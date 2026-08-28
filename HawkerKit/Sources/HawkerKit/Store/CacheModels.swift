import Foundation

/// On-disk cache of the working set.
///
/// The build plan called for SwiftData. A single JSON document turned out to be the
/// better fit and is what ships: the app reads and writes the whole working set at
/// once and never queries it relationally, so a store, a schema and a migration path
/// would all be cost with no matching benefit. `Asset` is already `Codable` because
/// it crosses to the watch over WatchConnectivity regardless.
public actor AssetCache {
    public static let ttl: TimeInterval = 7 * 24 * 60 * 60

    public struct Snapshot: Codable, Sendable {
        public let savedAt: Date
        public let assets: [Asset]
        public var isStale: Bool { Date().timeIntervalSince(savedAt) > AssetCache.ttl }

        public init(savedAt: Date, assets: [Asset]) {
            self.savedAt = savedAt
            self.assets = assets
        }
    }

    private let url: URL

    public init(filename: String = "hawker-assets.json") {
        let base = (try? FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? URL.temporaryDirectory
        self.url = base.appending(path: filename)
    }

    public func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? HawkerJSON.decoder.decode(Snapshot.self, from: data)
    }

    public func save(assets: [Asset]) {
        let snapshot = Snapshot(savedAt: Date(), assets: assets)
        guard let data = try? HawkerJSON.encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }

    public var fileURL: URL { url }
}
