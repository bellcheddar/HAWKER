import Foundation
import Testing
@testable import HawkerKit

@Suite("The keep rule: what counts as a dead clinical asset")
struct KeepRuleTests {

    let now = Date(timeIntervalSince1970: 1_787_000_000) // 2026-08

    func trial(
        _ id: String,
        status: TrialStatus = .completed,
        yearsAgo: Int = 1,
        why: String? = nil
    ) -> TrialRecord {
        let date = Calendar(identifier: .gregorian)
            .date(byAdding: .year, value: -yearsAgo, to: now)!
        return TrialRecord(
            nctId: id, briefTitle: id, overallStatus: status, whyStopped: why,
            phases: [.phase2], enrolment: 100, startDate: date, completionDate: date,
            leadSponsor: "Sponsor", conditions: []
        )
    }

    @Test("A withdrawn drug is kept whatever else is true")
    func withdrawnIsKept() {
        #expect(KeepRule.keeps(withdrawn: true, maxPhase: 4, firstApproval: 1998,
                               trials: [trial("NCT1")], now: now))
    }

    @Test("Any halted trial keeps the asset")
    func haltedIsKept() {
        for status in [TrialStatus.terminated, .withdrawn, .suspended] {
            #expect(KeepRule.keeps(withdrawn: false, maxPhase: 2, firstApproval: nil,
                                   trials: [trial("NCT1", status: status)], now: now),
                    "\(status.label) should keep the asset")
        }
    }

    @Test("A molecule with NO trial data is not a dead asset")
    func noTrialsIsNotDead() {
        // The bug this suite exists for. A clinical-phase molecule with no approval
        // and no trial cross-references trivially has "no recent activity", and the
        // first version of this rule therefore kept 95% of everything.
        #expect(!KeepRule.keeps(withdrawn: false, maxPhase: 3, firstApproval: nil,
                                trials: [], now: now))
        #expect(!KeepRule.keeps(withdrawn: false, maxPhase: 2, firstApproval: nil,
                                trials: [], now: now))
    }

    @Test("Known trials that went quiet years ago do keep the asset")
    func quietTrialsAreKept() {
        #expect(KeepRule.keeps(withdrawn: false, maxPhase: 3, firstApproval: nil,
                               trials: [trial("NCT1", yearsAgo: 9)], now: now))
    }

    @Test("Recent activity means it is not dead")
    func recentActivityIsNotDead() {
        #expect(!KeepRule.keeps(withdrawn: false, maxPhase: 3, firstApproval: nil,
                                trials: [trial("NCT1", yearsAgo: 1)], now: now))
        // One live trial is enough, even alongside old ones.
        #expect(!KeepRule.keeps(withdrawn: false, maxPhase: 3, firstApproval: nil,
                                trials: [trial("NCT1", yearsAgo: 9), trial("NCT2", yearsAgo: 2)],
                                now: now))
    }

    @Test("An approved drug that simply went quiet is not a dead asset")
    func approvedIsNotDead() {
        #expect(!KeepRule.keeps(withdrawn: false, maxPhase: 4, firstApproval: 2001,
                                trials: [trial("NCT1", yearsAgo: 9)], now: now))
    }

    @Test("Preclinical compounds never reached the clinic, so they are out of scope")
    func preclinicalIsExcluded() {
        #expect(!KeepRule.keeps(withdrawn: false, maxPhase: 1, firstApproval: nil,
                                trials: [trial("NCT1", yearsAgo: 9)], now: now))
        #expect(!KeepRule.keeps(withdrawn: false, maxPhase: nil, firstApproval: nil,
                                trials: [trial("NCT1", yearsAgo: 9)], now: now))
    }

    @Test("The quiet boundary sits where it says it does")
    func quietBoundary() {
        // 4 years ago is inside the window, 6 is outside it.
        #expect(KeepRule.hasRecentActivity([trial("NCT1", yearsAgo: 4)], now: now))
        #expect(!KeepRule.hasRecentActivity([trial("NCT1", yearsAgo: 6)], now: now))
    }
}
