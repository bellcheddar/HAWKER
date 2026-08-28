import Foundation

/// ClinicalTrials.gov API v2.
///
/// Field notes from the live responses (2026-08-28):
/// - `filter.ids` takes a comma-separated list of NCT ids and is the fastest way in
///   once UniChem has given us the ids. Batches of 50 are comfortable.
/// - `countTotal=true` is required or `totalCount` is simply absent from the payload.
/// - `whyStopped` sits in `protocolSection.statusModule`, and is present on roughly
///   a third of terminated studies. A blank one is a real answer, not a fetch failure.
/// - Dates arrive as "2014-04-24" or "2009-12" (month precision), so both are parsed.
/// - **Always send `fields`.** A full study record is about 200 kB, and this client uses
///   perhaps 1 kB of it: eligibility criteria, arm descriptions, outcome measures,
///   locations and the results section all come down otherwise. Requesting only the five
///   modules below took a three-study response from 593,763 bytes to 3,582, a 166x
///   reduction, and turned the ingest from network-bound into something that finishes.
public struct ClinicalTrialsClient: Sendable {
    private let client: APIClient
    private let base = URL(string: "https://clinicaltrials.gov/api/v2/studies")!

    /// Exactly the modules `TrialRecord` reads, and nothing else.
    static let fields = [
        "protocolSection.identificationModule.nctId",
        "protocolSection.identificationModule.briefTitle",
        "protocolSection.statusModule",
        "protocolSection.designModule.phases",
        "protocolSection.designModule.enrollmentInfo",
        "protocolSection.sponsorCollaboratorsModule.leadSponsor",
        "protocolSection.conditionsModule"
    ].joined(separator: ",")

    public init(client: APIClient = .shared) { self.client = client }

    /// Fetch studies by NCT id. Batches internally to keep URLs a sane length.
    public func studies(nctIds: [String]) async throws -> [TrialRecord] {
        guard !nctIds.isEmpty else { return [] }
        var out: [TrialRecord] = []
        for batch in nctIds.chunked(into: 50) {
            let url = base.appending(queryItems: [
                .init(name: "filter.ids", value: batch.joined(separator: ",")),
                .init(name: "pageSize", value: String(batch.count)),
                .init(name: "fields", value: Self.fields)
            ])
            let page = try await client.getJSON(StudyPage.self, from: url)
            out.append(contentsOf: page.studies.compactMap(\.trialRecord))
        }
        return out
    }

    /// A page of halted studies, used to widen the working set beyond the assets
    /// ChEMBL already knows about.
    public func haltedStudies(pageSize: Int = 100, pageToken: String? = nil) async throws -> (records: [TrialRecord], nextToken: String?) {
        var items: [URLQueryItem] = [
            .init(name: "filter.overallStatus", value: "TERMINATED|WITHDRAWN|SUSPENDED"),
            .init(name: "pageSize", value: String(pageSize)),
            .init(name: "countTotal", value: "true"),
            .init(name: "fields", value: Self.fields)
        ]
        if let pageToken { items.append(.init(name: "pageToken", value: pageToken)) }
        let page = try await client.getJSON(StudyPage.self, from: base.appending(queryItems: items))
        return (page.studies.compactMap(\.trialRecord), page.nextPageToken)
    }

    // MARK: Wire types

    struct StudyPage: Decodable, Sendable {
        let studies: [Study]
        let nextPageToken: String?
        let totalCount: Int?
    }

    struct Study: Decodable, Sendable {
        let protocolSection: ProtocolSection?

        var trialRecord: TrialRecord? {
            guard let p = protocolSection, let id = p.identificationModule?.nctId else { return nil }
            let status = p.statusModule
            let design = p.designModule
            return TrialRecord(
                nctId: id,
                briefTitle: p.identificationModule?.briefTitle ?? id,
                overallStatus: TrialStatus(apiValue: status?.overallStatus ?? "OTHER"),
                whyStopped: status?.whyStopped?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                phases: (design?.phases ?? []).map(TrialPhase.init(apiValue:)),
                enrolment: design?.enrollmentInfo?.count,
                startDate: status?.startDateStruct?.parsedDate,
                completionDate: status?.completionDateStruct?.parsedDate
                    ?? status?.primaryCompletionDateStruct?.parsedDate,
                leadSponsor: p.sponsorCollaboratorsModule?.leadSponsor?.name,
                conditions: p.conditionsModule?.conditions ?? []
            )
        }
    }

    struct ProtocolSection: Decodable, Sendable {
        let identificationModule: IdentificationModule?
        let statusModule: StatusModule?
        let designModule: DesignModule?
        let sponsorCollaboratorsModule: SponsorModule?
        let conditionsModule: ConditionsModule?
    }

    struct IdentificationModule: Decodable, Sendable {
        let nctId: String?
        let briefTitle: String?
    }

    struct StatusModule: Decodable, Sendable {
        let overallStatus: String?
        let whyStopped: String?
        let startDateStruct: DateStruct?
        let completionDateStruct: DateStruct?
        let primaryCompletionDateStruct: DateStruct?
    }

    struct DateStruct: Decodable, Sendable {
        let date: String?
        let type: String?

        /// Accepts both "2014-04-24" and the month-only "2009-12" form.
        var parsedDate: Date? {
            guard let date else { return nil }
            return DateStruct.full.date(from: date) ?? DateStruct.monthOnly.date(from: date)
        }

        static let full: DateFormatter = {
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyy-MM-dd"
            return f
        }()

        static let monthOnly: DateFormatter = {
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyy-MM"
            return f
        }()
    }

    struct DesignModule: Decodable, Sendable {
        let phases: [String]?
        let enrollmentInfo: EnrollmentInfo?

        struct EnrollmentInfo: Decodable, Sendable {
            let count: Int?
            let type: String?
        }
    }

    struct SponsorModule: Decodable, Sendable {
        let leadSponsor: Sponsor?
        struct Sponsor: Decodable, Sendable { let name: String? }
    }

    struct ConditionsModule: Decodable, Sendable {
        let conditions: [String]?
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
