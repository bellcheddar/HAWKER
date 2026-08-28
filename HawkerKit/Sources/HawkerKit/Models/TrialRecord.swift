import Foundation

/// A single ClinicalTrials.gov study, reduced to the fields that bear on
/// why an asset stopped.
public struct TrialRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: String { nctId }

    public let nctId: String
    public let briefTitle: String
    public let overallStatus: TrialStatus
    /// The sponsor's own free text. Often absent: about two thirds of terminated
    /// studies leave it blank, which is why `unknown` is scored neutrally.
    public let whyStopped: String?
    public let phases: [TrialPhase]
    public let enrolment: Int?
    public let startDate: Date?
    public let completionDate: Date?
    public let leadSponsor: String?
    public let conditions: [String]

    public init(
        nctId: String,
        briefTitle: String,
        overallStatus: TrialStatus,
        whyStopped: String?,
        phases: [TrialPhase],
        enrolment: Int?,
        startDate: Date?,
        completionDate: Date?,
        leadSponsor: String?,
        conditions: [String]
    ) {
        self.nctId = nctId
        self.briefTitle = briefTitle
        self.overallStatus = overallStatus
        self.whyStopped = whyStopped
        self.phases = phases
        self.enrolment = enrolment
        self.startDate = startDate
        self.completionDate = completionDate
        self.leadSponsor = leadSponsor
        self.conditions = conditions
    }

    /// The three statuses that mean the study stopped before its planned end.
    public var isHalted: Bool { overallStatus.isHalted }

    /// The best available date for "when this died", used by the Graveyard's
    /// year axis and the Overlook point cloud.
    public var deathDate: Date? { completionDate ?? startDate }

    public var highestPhase: TrialPhase? {
        phases.max(by: { $0.rank < $1.rank })
    }
}

public enum TrialStatus: String, Codable, Sendable, Hashable, CaseIterable {
    case terminated       = "TERMINATED"
    case withdrawn        = "WITHDRAWN"
    case suspended        = "SUSPENDED"
    case completed        = "COMPLETED"
    case recruiting       = "RECRUITING"
    case activeNotRecruiting = "ACTIVE_NOT_RECRUITING"
    case notYetRecruiting = "NOT_YET_RECRUITING"
    case enrollingByInvitation = "ENROLLING_BY_INVITATION"
    case unknownStatus    = "UNKNOWN"
    case other            = "OTHER"

    public init(apiValue: String) {
        self = TrialStatus(rawValue: apiValue.uppercased()) ?? .other
    }

    public var isHalted: Bool {
        switch self {
        case .terminated, .withdrawn, .suspended: true
        default: false
        }
    }

    public var label: String {
        switch self {
        case .terminated: "Terminated"
        case .withdrawn: "Withdrawn"
        case .suspended: "Suspended"
        case .completed: "Completed"
        case .recruiting: "Recruiting"
        case .activeNotRecruiting: "Active, not recruiting"
        case .notYetRecruiting: "Not yet recruiting"
        case .enrollingByInvitation: "Enrolling by invitation"
        case .unknownStatus: "Unknown"
        case .other: "Other"
        }
    }
}

public enum TrialPhase: String, Codable, Sendable, Hashable, CaseIterable {
    case earlyPhase1 = "EARLY_PHASE1"
    case phase1      = "PHASE1"
    case phase2      = "PHASE2"
    case phase3      = "PHASE3"
    case phase4      = "PHASE4"
    case notApplicable = "NA"

    public init(apiValue: String) {
        self = TrialPhase(rawValue: apiValue.uppercased()) ?? .notApplicable
    }

    /// Ordering for "how far did it get". `notApplicable` sorts below everything.
    public var rank: Int {
        switch self {
        case .notApplicable: 0
        case .earlyPhase1: 1
        case .phase1: 2
        case .phase2: 3
        case .phase3: 4
        case .phase4: 5
        }
    }

    public var label: String {
        switch self {
        case .earlyPhase1: "Early phase 1"
        case .phase1: "Phase 1"
        case .phase2: "Phase 2"
        case .phase3: "Phase 3"
        case .phase4: "Phase 4"
        case .notApplicable: "N/A"
        }
    }

    public var shortLabel: String {
        switch self {
        case .earlyPhase1: "EP1"
        case .phase1: "P1"
        case .phase2: "P2"
        case .phase3: "P3"
        case .phase4: "P4"
        case .notApplicable: "NA"
        }
    }
}
