import Foundation

/// PubChem PUG-REST, used only for ready-made 3D conformers.
///
/// Generating conformers is a project in itself, so the app fetches coordinates that
/// already exist rather than computing them. Not every CID has a 3D record: PubChem
/// returns 404 for those, which is an honest miss and is surfaced as an empty state.
public struct PubChemClient: Sendable {
    private let client: APIClient
    private let base = URL(string: "https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/")!

    public init(client: APIClient = .shared) { self.client = client }

    /// A 3D SDF conformer for a CID, or nil when PubChem has no 3D record.
    public func conformerSDF(cid: String) async throws -> String? {
        let url = base.appending(path: "cid/\(cid)/SDF").appending(queryItems: [
            .init(name: "record_type", value: "3d")
        ])
        do {
            let data = try await client.get(url, accept: "chemical/x-mdl-sdfile")
            return String(data: data, encoding: .utf8)
        } catch let error as APIError where error.isMiss {
            return nil
        }
    }
}
