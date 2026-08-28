import Foundation

/// ChEMBL REST client.
///
/// Field notes from the live responses (2026-08-28), all of which contradict the
/// obvious guess and none of which should be "corrected" from memory:
/// - `molecule.max_phase` is a **String** ("3.0"), and so is `max_phase_for_ind`.
/// - `mechanism.max_phase` is an **Int**. The two endpoints genuinely disagree.
/// - `withdrawn_reason` is not present on the molecule resource at all, despite
///   appearing in older documentation. Only `withdrawn_flag` is.
public struct ChEMBLClient: Sendable {
    private let client: APIClient
    private let base = URL(string: "https://www.ebi.ac.uk/chembl/api/data/")!

    public init(client: APIClient = .shared) { self.client = client }

    // MARK: Molecules

    /// One page of molecules at a given max_phase.
    /// - Note: `maxPhase` is sent as an integer even though it comes back as "3.0".
    public func molecules(maxPhase: Int, limit: Int = 100, offset: Int = 0) async throws -> MoleculePage {
        let url = base.appending(path: "molecule.json").appending(queryItems: [
            .init(name: "max_phase", value: String(maxPhase)),
            .init(name: "limit", value: String(limit)),
            .init(name: "offset", value: String(offset))
        ])
        return try await client.getJSON(MoleculePage.self, from: url)
    }

    public func withdrawnMolecules(limit: Int = 100, offset: Int = 0) async throws -> MoleculePage {
        let url = base.appending(path: "molecule.json").appending(queryItems: [
            .init(name: "withdrawn_flag", value: "true"),
            .init(name: "limit", value: String(limit)),
            .init(name: "offset", value: String(offset))
        ])
        return try await client.getJSON(MoleculePage.self, from: url)
    }

    // MARK: Mechanism and indication

    public func mechanisms(moleculeId: String) async throws -> [Mechanism] {
        let url = base.appending(path: "mechanism.json").appending(queryItems: [
            .init(name: "molecule_chembl_id", value: moleculeId),
            .init(name: "limit", value: "20")
        ])
        return try await client.getJSON(MechanismPage.self, from: url).mechanisms
    }

    public func indications(moleculeId: String) async throws -> [DrugIndication] {
        let url = base.appending(path: "drug_indication.json").appending(queryItems: [
            .init(name: "molecule_chembl_id", value: moleculeId),
            .init(name: "limit", value: "50")
        ])
        return try await client.getJSON(IndicationPage.self, from: url).drugIndications
    }

    /// Mechanisms for many molecules in one request.
    ///
    /// ChEMBL supports `__in` filters, which is the difference between two round trips
    /// per molecule and two per batch. At the 200 ms per-host spacing this client
    /// keeps, that is the difference between a twenty-minute ingest and a two-minute
    /// one, so the batch form is the default and the single-molecule call above is
    /// only for detail views.
    public func mechanisms(moleculeIds: [String]) async throws -> [String: [Mechanism]] {
        var out: [String: [Mechanism]] = [:]
        for batch in moleculeIds.chunked(into: 40) {
            let url = base.appending(path: "mechanism.json").appending(queryItems: [
                .init(name: "molecule_chembl_id__in", value: batch.joined(separator: ",")),
                .init(name: "limit", value: "1000")
            ])
            guard let page = try? await client.getJSON(MechanismPage.self, from: url) else { continue }
            for mechanism in page.mechanisms {
                guard let id = mechanism.moleculeChemblId else { continue }
                out[id, default: []].append(mechanism)
            }
        }
        return out
    }

    /// Indications for many molecules in one request.
    ///
    /// Indications are far more numerous than mechanisms (aspirin alone has 47), so
    /// this paginates where a batch overflows rather than silently truncating.
    public func indications(moleculeIds: [String]) async throws -> [String: [DrugIndication]] {
        var out: [String: [DrugIndication]] = [:]
        for batch in moleculeIds.chunked(into: 25) {
            var offset = 0
            while true {
                let url = base.appending(path: "drug_indication.json").appending(queryItems: [
                    .init(name: "molecule_chembl_id__in", value: batch.joined(separator: ",")),
                    .init(name: "limit", value: "1000"),
                    .init(name: "offset", value: String(offset))
                ])
                guard let page = try? await client.getJSON(IndicationPage.self, from: url),
                      !page.drugIndications.isEmpty else { break }
                for indication in page.drugIndications {
                    guard let id = indication.moleculeChemblId else { continue }
                    out[id, default: []].append(indication)
                }
                offset += page.drugIndications.count
                if page.drugIndications.count < 1000 { break }
            }
        }
        return out
    }

    public func target(id: String) async throws -> Target {
        let url = base.appending(path: "target/\(id).json")
        return try await client.getJSON(Target.self, from: url)
    }

    // MARK: Wire types

    public struct MoleculePage: Decodable, Sendable {
        public let molecules: [Molecule]
        public let pageMeta: PageMeta

        enum CodingKeys: String, CodingKey {
            case molecules
            case pageMeta = "page_meta"
        }
    }

    public struct PageMeta: Decodable, Sendable {
        public let limit: Int
        public let offset: Int
        public let totalCount: Int?
        public let next: String?

        enum CodingKeys: String, CodingKey {
            case limit, offset, next
            case totalCount = "total_count"
        }
    }

    public struct Molecule: Decodable, Sendable {
        public let moleculeChemblId: String
        public let prefName: String?
        /// Arrives as a String. See the note at the top of this file.
        public let maxPhase: Double?
        public let withdrawnFlag: Bool?
        public let firstApproval: Int?
        public let moleculeType: String?
        public let structures: Structures?
        public let synonyms: [Synonym]?

        enum CodingKeys: String, CodingKey {
            case moleculeChemblId = "molecule_chembl_id"
            case prefName = "pref_name"
            case maxPhase = "max_phase"
            case withdrawnFlag = "withdrawn_flag"
            case firstApproval = "first_approval"
            case moleculeType = "molecule_type"
            case structures = "molecule_structures"
            case synonyms = "molecule_synonyms"
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            moleculeChemblId = try c.decode(String.self, forKey: .moleculeChemblId)
            prefName = try c.decodeIfPresent(String.self, forKey: .prefName)
            maxPhase = try c.decodeLenientDouble(forKey: .maxPhase)
            withdrawnFlag = try c.decodeIfPresent(Bool.self, forKey: .withdrawnFlag)
            firstApproval = try c.decodeIfPresent(Int.self, forKey: .firstApproval)
            moleculeType = try c.decodeIfPresent(String.self, forKey: .moleculeType)
            structures = try c.decodeIfPresent(Structures.self, forKey: .structures)
            synonyms = try c.decodeIfPresent([Synonym].self, forKey: .synonyms)
        }

        public struct Structures: Decodable, Sendable {
            public let canonicalSmiles: String?
            public let standardInchiKey: String?

            enum CodingKeys: String, CodingKey {
                case canonicalSmiles = "canonical_smiles"
                case standardInchiKey = "standard_inchi_key"
            }
        }

        public struct Synonym: Decodable, Sendable {
            public let moleculeSynonym: String?
            public let synType: String?

            enum CodingKeys: String, CodingKey {
                case moleculeSynonym = "molecule_synonym"
                case synType = "syn_type"
            }
        }
    }

    public struct MechanismPage: Decodable, Sendable {
        public let mechanisms: [Mechanism]
    }

    public struct Mechanism: Decodable, Sendable {
        public let moleculeChemblId: String?
        public let targetChemblId: String?
        public let mechanismOfAction: String?
        public let actionType: String?
        /// Int here, String on the molecule resource. Both are decoded leniently.
        public let maxPhase: Double?

        enum CodingKeys: String, CodingKey {
            case moleculeChemblId = "molecule_chembl_id"
            case targetChemblId = "target_chembl_id"
            case mechanismOfAction = "mechanism_of_action"
            case actionType = "action_type"
            case maxPhase = "max_phase"
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            moleculeChemblId = try c.decodeIfPresent(String.self, forKey: .moleculeChemblId)
            targetChemblId = try c.decodeIfPresent(String.self, forKey: .targetChemblId)
            mechanismOfAction = try c.decodeIfPresent(String.self, forKey: .mechanismOfAction)
            actionType = try c.decodeIfPresent(String.self, forKey: .actionType)
            maxPhase = try c.decodeLenientDouble(forKey: .maxPhase)
        }
    }

    public struct IndicationPage: Decodable, Sendable {
        public let drugIndications: [DrugIndication]

        enum CodingKeys: String, CodingKey {
            case drugIndications = "drug_indications"
        }
    }

    public struct DrugIndication: Decodable, Sendable {
        /// Needed to demultiplex a batched `__in` response back to its molecule.
        public let moleculeChemblId: String?
        public let efoId: String?
        public let efoTerm: String?
        public let maxPhaseForInd: Double?
        public let indicationRefs: [IndicationRef]?

        enum CodingKeys: String, CodingKey {
            case moleculeChemblId = "molecule_chembl_id"
            case efoId = "efo_id"
            case efoTerm = "efo_term"
            case maxPhaseForInd = "max_phase_for_ind"
            case indicationRefs = "indication_refs"
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            moleculeChemblId = try c.decodeIfPresent(String.self, forKey: .moleculeChemblId)
            efoId = try c.decodeIfPresent(String.self, forKey: .efoId)
            efoTerm = try c.decodeIfPresent(String.self, forKey: .efoTerm)
            maxPhaseForInd = try c.decodeLenientDouble(forKey: .maxPhaseForInd)
            indicationRefs = try c.decodeIfPresent([IndicationRef].self, forKey: .indicationRefs)
        }

        /// ChEMBL packs every NCT id for an indication into one comma-separated
        /// `ref_id` string, which is why this is split rather than mapped.
        public var nctIds: [String] {
            (indicationRefs ?? [])
                .filter { $0.refType == "ClinicalTrials" }
                .flatMap { ($0.refId ?? "").split(separator: ",") }
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("NCT") }
        }

        public struct IndicationRef: Decodable, Sendable {
            public let refType: String?
            public let refId: String?

            enum CodingKeys: String, CodingKey {
                case refType = "ref_type"
                case refId = "ref_id"
            }
        }
    }

    public struct Target: Decodable, Sendable {
        public let targetChemblId: String
        public let prefName: String?
        public let targetType: String?
        public let organism: String?
        public let targetComponents: [Component]?

        enum CodingKeys: String, CodingKey {
            case targetChemblId = "target_chembl_id"
            case prefName = "pref_name"
            case targetType = "target_type"
            case organism
            case targetComponents = "target_components"
        }

        /// Swiss-Prot accession of the first protein component.
        public var uniprotAccession: String? {
            targetComponents?.first(where: { $0.componentType == "PROTEIN" })?.accession
                ?? targetComponents?.first?.accession
        }

        public struct Component: Decodable, Sendable {
            public let accession: String?
            public let componentType: String?

            enum CodingKeys: String, CodingKey {
                case accession
                case componentType = "component_type"
            }
        }
    }
}

extension KeyedDecodingContainer {
    /// ChEMBL is inconsistent about whether a phase is a number or a string, and
    /// which it uses depends on the endpoint. Accept either rather than guessing.
    func decodeLenientDouble(forKey key: Key) throws -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Double(s) }
        return nil
    }
}
