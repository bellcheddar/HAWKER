import Foundation

/// UniChem cross-references.
///
/// This is the highest-value call in the whole pipeline and it is worth saying why.
/// The build plan expected to reach ClinicalTrials.gov by matching drug names, and
/// listed the miss rate on code names and licensee renames as a known limitation.
/// It turns out UniChem's compound record already carries, in a single response:
///   - `rcsb_pdb` / `pdbe`: the PDB chemical component id, which finds co-crystals
///   - `pubchem`: the CID, which gets a ready-made 3D conformer
///   - `clinicaltrials`: every NCT id registered against the compound
/// So the trial join is done on curated identifiers, not on string similarity, and
/// the name-matching limitation does not apply to this build.
public struct UniChemClient: Sendable {
    private let client: APIClient
    private let endpoint = URL(string: "https://www.ebi.ac.uk/unichem/api/v1/compounds")!

    /// UniChem's numeric id for ChEMBL as a source.
    private static let chemblSourceID = 1

    public init(client: APIClient = .shared) { self.client = client }

    public func crossReferences(chemblId: String) async throws -> CrossReferences {
        let body = Request(type: "sourceID", compound: chemblId, sourceID: Self.chemblSourceID)
        let response = try await client.postJSON(Response.self, to: endpoint, body: body)
        let sources = response.compounds?.first?.sources ?? []

        var byName: [String: [String]] = [:]
        for source in sources {
            guard let name = source.shortName, let id = source.compoundId else { continue }
            byName[name, default: []].append(id)
        }

        return CrossReferences(
            chemblId: chemblId,
            // Prefer the RCSB spelling, fall back to PDBe: they agree in practice
            // but either may be absent.
            ccdCode: byName["rcsb_pdb"]?.first ?? byName["pdbe"]?.first,
            pubchemCID: byName["pubchem"]?.first,
            drugbankId: byName["drugbank"]?.first,
            nctIds: byName["clinicaltrials"] ?? [],
            all: byName
        )
    }

    public struct CrossReferences: Sendable, Hashable {
        public let chemblId: String
        public let ccdCode: String?
        public let pubchemCID: String?
        public let drugbankId: String?
        public let nctIds: [String]
        public let all: [String: [String]]

        public static func empty(_ chemblId: String) -> CrossReferences {
            CrossReferences(chemblId: chemblId, ccdCode: nil, pubchemCID: nil,
                            drugbankId: nil, nctIds: [], all: [:])
        }
    }

    struct Request: Encodable, Sendable {
        let type: String
        let compound: String
        let sourceID: Int
    }

    struct Response: Decodable, Sendable {
        let compounds: [Compound]?
        /// A String on the wire ("1"), despite being a count.
        let totalCompounds: String?

        struct Compound: Decodable, Sendable {
            let sources: [Source]?
        }

        struct Source: Decodable, Sendable {
            let shortName: String?
            let compoundId: String?

            enum CodingKeys: String, CodingKey {
                case shortName
                case compoundId
            }

            init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                shortName = try c.decodeIfPresent(String.self, forKey: .shortName)
                // compoundId is a String for most sources but an Int for a few
                // (gtopdb, brenda), which fails a plain String decode.
                if let s = try? c.decodeIfPresent(String.self, forKey: .compoundId) {
                    compoundId = s
                } else if let i = try? c.decodeIfPresent(Int.self, forKey: .compoundId) {
                    compoundId = String(i)
                } else {
                    compoundId = nil
                }
            }
        }
    }
}
