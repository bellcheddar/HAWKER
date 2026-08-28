import Foundation

/// RCSB search, data and coordinate download.
///
/// Field notes from the live responses (2026-08-28):
/// - The search service returns HTTP 204 with an empty body when nothing matches,
///   not a 200 with an empty `result_set`. A plain JSON decode of a 204 throws, so
///   an empty body is treated as "no hits" rather than an error.
/// - `rcsb_entry_info.resolution_combined` is an **array** of Doubles.
/// - Dates are ISO 8601 with milliseconds ("2016-06-15T00:00:00.000+00:00").
public struct RCSBClient: Sendable {
    private let client: APIClient
    private let searchURL = URL(string: "https://search.rcsb.org/rcsbsearch/v2/query")!
    private let dataBase = URL(string: "https://data.rcsb.org/rest/v1/core/")!

    public init(client: APIClient = .shared) { self.client = client }

    /// PDB entries containing a given chemical component. This is the join that
    /// turns a dead ligand into a real pocket.
    public func entries(containingCCD ccd: String, limit: Int = 25) async throws -> [String] {
        let query = SearchQuery(
            query: .init(
                type: "terminal",
                service: "text_chem",
                parameters: .init(
                    attribute: "rcsb_chem_comp_container_identifiers.comp_id",
                    operator: "exact_match",
                    value: ccd.uppercased()
                )
            ),
            returnType: "entry",
            requestOptions: .bestResolutionFirst(rows: limit)
        )
        return try await runSearch(query)
    }

    /// PDB entries for a UniProt accession, used when the exact ligand has no
    /// co-crystal but the target has been solved.
    public func entries(forUniProt accession: String, limit: Int = 25) async throws -> [String] {
        let query = SearchQuery(
            query: .init(
                type: "terminal",
                service: "text",
                parameters: .init(
                    attribute: "rcsb_polymer_entity_container_identifiers.reference_sequence_identifiers.database_accession",
                    operator: "exact_match",
                    value: accession
                )
            ),
            returnType: "entry",
            requestOptions: .bestResolutionFirst(rows: limit)
        )
        return try await runSearch(query)
    }

    public func entry(_ pdbId: String) async throws -> StructureRef {
        let url = dataBase.appending(path: "entry/\(pdbId.uppercased())")
        let payload = try await client.getJSON(EntryPayload.self, from: url)
        return StructureRef(
            pdbId: pdbId.uppercased(),
            title: payload.structBlock?.title ?? pdbId.uppercased(),
            resolution: payload.entryInfo?.resolutionCombined?.first,
            experimentalMethod: payload.exptl?.first?.method,
            releaseDate: payload.accessionInfo?.initialReleaseDate.flatMap(Self.parseDate),
            ligandCCD: nil,
            uniprotAccessions: []
        )
    }

    /// Raw mmCIF coordinates.
    public func coordinates(pdbId: String) async throws -> Data {
        guard let url = URL(string: "https://files.rcsb.org/download/\(pdbId.uppercased()).cif") else {
            throw APIError.malformed("bad PDB id \(pdbId)")
        }
        return try await client.get(url, accept: "text/plain")
    }

    // MARK: Search plumbing

    private func runSearch(_ query: SearchQuery) async throws -> [String] {
        let data = try await client.postRaw(searchURL, body: try HawkerJSON.encoder.encode(query))
        // 204 No Content is how the search service says "no hits".
        guard !data.isEmpty else { return [] }
        let response = try HawkerJSON.decoder.decode(SearchResponse.self, from: data)
        return (response.resultSet ?? []).map(\.identifier)
    }

    static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    // MARK: Wire types

    struct SearchQuery: Encodable, Sendable {
        let query: Node
        let returnType: String
        let requestOptions: RequestOptions

        enum CodingKeys: String, CodingKey {
            case query
            case returnType = "return_type"
            case requestOptions = "request_options"
        }

        struct Node: Encodable, Sendable {
            let type: String
            let service: String
            let parameters: Parameters
        }

        struct Parameters: Encodable, Sendable {
            let attribute: String
            let `operator`: String
            let value: String
        }

        struct RequestOptions: Encodable, Sendable {
            let paginate: Paginate
            let sort: [Sort]?

            /// Ask the search service to order by resolution rather than sorting
            /// locally. Sorting locally would need the entry metadata, and fetching
            /// that for every hit is exactly the per-asset cost that was removed from
            /// the ingest. This costs nothing and puts the best structure first.
            static func bestResolutionFirst(rows: Int) -> RequestOptions {
                RequestOptions(
                    paginate: Paginate(start: 0, rows: rows),
                    sort: [Sort(sortBy: "rcsb_entry_info.resolution_combined", direction: "asc")]
                )
            }
        }

        struct Sort: Encodable, Sendable {
            let sortBy: String
            let direction: String

            enum CodingKeys: String, CodingKey {
                case sortBy = "sort_by"
                case direction
            }
        }

        struct Paginate: Encodable, Sendable {
            let start: Int
            let rows: Int
        }
    }

    struct SearchResponse: Decodable, Sendable {
        let totalCount: Int?
        let resultSet: [Hit]?

        enum CodingKeys: String, CodingKey {
            case totalCount = "total_count"
            case resultSet = "result_set"
        }

        struct Hit: Decodable, Sendable {
            let identifier: String
            let score: Double?
        }
    }

    struct EntryPayload: Decodable, Sendable {
        let structBlock: StructBlock?
        let entryInfo: EntryInfo?
        let exptl: [Exptl]?
        let accessionInfo: AccessionInfo?

        enum CodingKeys: String, CodingKey {
            case structBlock = "struct"
            case entryInfo = "rcsb_entry_info"
            case exptl
            case accessionInfo = "rcsb_accession_info"
        }

        struct StructBlock: Decodable, Sendable { let title: String? }
        struct Exptl: Decodable, Sendable { let method: String? }

        struct EntryInfo: Decodable, Sendable {
            /// An array, even when there is exactly one value.
            let resolutionCombined: [Double]?

            enum CodingKeys: String, CodingKey {
                case resolutionCombined = "resolution_combined"
            }
        }

        struct AccessionInfo: Decodable, Sendable {
            let initialReleaseDate: String?

            enum CodingKeys: String, CodingKey {
                case initialReleaseDate = "initial_release_date"
            }
        }
    }
}
