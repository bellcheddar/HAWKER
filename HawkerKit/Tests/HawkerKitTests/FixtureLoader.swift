import Foundation
import Testing

/// Every fixture in this directory is a real API response captured on 2026-08-28,
/// not a hand-written sample. That is the point: the decoders are tested against
/// what the services actually return, including the parts that are surprising.
enum Fixture {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil) else {
            throw FixtureError.missing(name)
        }
        return try Data(contentsOf: url)
    }

    static func text(_ name: String) throws -> String {
        String(decoding: try data(name), as: UTF8.self)
    }

    enum FixtureError: Error, CustomStringConvertible {
        case missing(String)
        var description: String {
            switch self {
            case .missing(let n): "Fixture not found: \(n)"
            }
        }
    }
}
