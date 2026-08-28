import Foundation

/// Open Targets Platform GraphQL client.
///
/// Field notes from live introspection (2026-08-28):
/// - `Tractability` is `{ label: String, modality: String, value: Boolean }`. It is a
///   list of boolean flags, **not** the numbered bucket scheme the build plan assumed,
///   so the tractability score counts satisfied small-molecule labels instead.
/// - `SafetyLiability` has `{ event, eventId, datasource, effects, biosamples, studies }`.
/// - `AssociatedDisease` has `{ score, novelty, disease, datatypeScores, datasourceScores }`
///   where each score entry is a `ScoredComponent { id, score }`.
/// - The API keys on Ensembl gene id, so a UniProt accession has to be resolved first
///   via the `search` field. That mapping is cached: it is stable and costs a round trip.
public actor OpenTargetsClient {
    private let client: APIClient
    private let endpoint = URL(string: "https://api.platform.opentargets.org/api/v4/graphql")!
    private var ensemblByUniProt: [String: String?] = [:]

    public init(client: APIClient = .shared) { self.client = client }

    /// Resolve a UniProt accession to an Ensembl gene id.
    public func ensemblId(forUniProt accession: String) async throws -> String? {
        if let cached = ensemblByUniProt[accession] { return cached }
        let query = """
        query R($q: String!) { search(queryString: $q, entityNames: ["target"]) { hits { id entity } } }
        """
        let response: SearchResponse = try await run(query: query, variables: ["q": accession])
        let id = response.data?.search?.hits?.first(where: { $0.entity == "target" })?.id
        ensemblByUniProt[accession] = id
        return id
    }

    /// The single target query the ingest uses. One round trip per target.
    public func target(ensemblId: String, associationLimit: Int = 25) async throws -> TargetPayload? {
        let query = """
        query T($id: String!, $size: Int!) {
          target(ensemblId: $id) {
            id
            approvedSymbol
            approvedName
            targetClass { id label level }
            proteinIds { id source }
            tractability { label modality value }
            safetyLiabilities { event eventId datasource }
            associatedDiseases(page: { index: 0, size: $size }) {
              count
              rows { score disease { id name } datatypeScores { id score } }
            }
          }
        }
        """
        let response: TargetResponse = try await run(
            query: query,
            variables: ["id": .string(ensemblId), "size": .int(associationLimit)]
        )
        return response.data?.target
    }

    // MARK: Transport

    private func run<T: Decodable & Sendable>(query: String, variables: [String: String]) async throws -> T {
        try await run(query: query, variables: variables.mapValues { GraphQLValue.string($0) })
    }

    private func run<T: Decodable & Sendable>(query: String, variables: [String: GraphQLValue]) async throws -> T {
        let body = GraphQLRequest(query: query, variables: variables)
        let response: T = try await client.postJSON(T.self, to: endpoint, body: body)
        return response
    }

    struct GraphQLRequest: Encodable, Sendable {
        let query: String
        let variables: [String: GraphQLValue]
    }

    /// Open Targets takes both String and Int variables in the queries above, and
    /// `[String: Any]` is not Encodable, so the two cases are modelled explicitly.
    enum GraphQLValue: Encodable, Sendable {
        case string(String)
        case int(Int)

        func encode(to encoder: any Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .string(let s): try c.encode(s)
            case .int(let i): try c.encode(i)
            }
        }
    }

    // MARK: Wire types

    struct SearchResponse: Decodable, Sendable {
        let data: DataBlock?
        struct DataBlock: Decodable, Sendable { let search: Search? }
        struct Search: Decodable, Sendable { let hits: [Hit]? }
        struct Hit: Decodable, Sendable { let id: String?; let entity: String? }
    }

    struct TargetResponse: Decodable, Sendable {
        let data: DataBlock?
        struct DataBlock: Decodable, Sendable { let target: TargetPayload? }
    }

    public struct TargetPayload: Decodable, Sendable {
        public let id: String?
        public let approvedSymbol: String?
        public let approvedName: String?
        public let targetClass: [TargetClass]?
        public let proteinIds: [ProteinId]?
        public let tractability: [Tractability]?
        public let safetyLiabilities: [Safety]?
        public let associatedDiseases: AssociatedDiseases?

        public struct TargetClass: Decodable, Sendable {
            public let id: Int?
            public let label: String?
            public let level: String?
        }

        public struct ProteinId: Decodable, Sendable {
            public let id: String?
            public let source: String?
        }

        public struct Tractability: Decodable, Sendable {
            public let label: String?
            public let modality: String?
            public let value: Bool?
        }

        public struct Safety: Decodable, Sendable {
            public let event: String?
            public let eventId: String?
            public let datasource: String?
        }

        public struct AssociatedDiseases: Decodable, Sendable {
            public let count: Int?
            public let rows: [Row]?

            public struct Row: Decodable, Sendable {
                public let score: Double?
                public let disease: Disease?
                public let datatypeScores: [ScoredComponent]?
            }

            public struct Disease: Decodable, Sendable {
                public let id: String?
                public let name: String?
            }

            public struct ScoredComponent: Decodable, Sendable {
                public let id: String?
                public let score: Double?
            }
        }

        /// Small-molecule tractability labels that came back true.
        public var smallMoleculeLabels: [String] {
            (tractability ?? [])
                .filter { $0.modality == "SM" && $0.value == true }
                .compactMap(\.label)
        }
    }
}
