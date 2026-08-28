import Foundation
import Observation

/// The app's state. One store, shared by all five targets.
@Observable
@MainActor
public final class HawkerStore {
    public enum LoadState: Equatable, Sendable {
        case idle
        case loading(IngestPipeline.Progress)
        case loaded(Date)
        case failed(String)

        public static func == (a: LoadState, b: LoadState) -> Bool {
            switch (a, b) {
            case (.idle, .idle): true
            case (.loading(let x), .loading(let y)): x == y
            case (.loaded(let x), .loaded(let y)): x == y
            case (.failed(let x), .failed(let y)): x == y
            default: false
            }
        }
    }

    public private(set) var assets: [Asset] = []
    public private(set) var state: LoadState = .idle
    public private(set) var summary: IngestPipeline.Summary?
    public var filter = StallFilter()

    private let pipeline = IngestPipeline()
    private let cache = AssetCache()
    private let rcsb = RCSBClient()
    private var loadTask: Task<Void, Never>?
    /// Entry metadata resolved on demand, keyed by PDB id. The ingest deliberately
    /// does not fetch these: it was the largest single cost there, for a list most
    /// users never open.
    private var resolvedEntries: [String: StructureRef] = [:]
    private var resolving: Set<String> = []

    public init() {}

    public var isLoading: Bool { if case .loading = state { true } else { false } }

    /// A structure reference with its title and resolution, if they have been fetched.
    public func resolved(_ ref: StructureRef) -> StructureRef {
        resolvedEntries[ref.pdbId] ?? ref
    }

    /// Fetch entry metadata for the handful of structures a view is about to show.
    public func resolveEntries(_ refs: [StructureRef], limit: Int = 8) {
        let wanted = refs.prefix(limit)
            .map(\.pdbId)
            .filter { resolvedEntries[$0] == nil && !resolving.contains($0) }
        guard !wanted.isEmpty else { return }
        resolving.formUnion(wanted)

        Task { [weak self] in
            guard let self else { return }
            for pdbId in wanted {
                guard let entry = try? await self.rcsb.entry(pdbId) else {
                    self.resolving.remove(pdbId)
                    continue
                }
                // Keep the ligand id the search matched on: the entry endpoint does
                // not report which component we searched for.
                let existing = self.assets
                    .flatMap(\.structures)
                    .first { $0.pdbId == pdbId }
                self.resolvedEntries[pdbId] = StructureRef(
                    pdbId: entry.pdbId,
                    title: entry.title,
                    resolution: entry.resolution,
                    experimentalMethod: entry.experimentalMethod,
                    releaseDate: entry.releaseDate,
                    ligandCCD: existing?.ligandCCD,
                    uniprotAccessions: entry.uniprotAccessions
                )
                self.resolving.remove(pdbId)
            }
        }
    }

    public func asset(id: String) -> Asset? {
        assets.first { $0.chemblId.caseInsensitiveCompare(id) == .orderedSame }
    }

    public func assets(forTarget targetId: String) -> [Asset] {
        assets.filter { $0.target?.chemblId == targetId }
    }

    /// Filtered and sorted, which is what every list in the app actually shows.
    public func filtered(_ filter: StallFilter) -> [Asset] {
        assets.filter(filter.matches).sorted(by: filter.sort.areInIncreasingOrder)
    }

    /// Load from cache if it is fresh, otherwise ingest. The 7-day TTL is what makes
    /// a second launch instant and the app usable offline.
    public func load(force: Bool = false, limit: Int = 2_000) {
        guard loadTask == nil || force else { return }
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            if !force, let cached = await cache.load(), !cached.assets.isEmpty {
                self.assets = cached.assets
                self.state = .loaded(cached.savedAt)
                await WatchSync.shared.send(assets: cached.assets)
                // Still refresh in the background when the cache is stale.
                if cached.isStale { self.refreshInBackground(limit: limit) }
                return
            }
            await self.ingest(limit: limit)
        }
    }

    private func refreshInBackground(limit: Int) {
        Task { [weak self] in await self?.ingest(limit: limit, keepingExisting: true) }
    }

    private func ingest(limit: Int, keepingExisting: Bool = false) async {
        if !keepingExisting { state = .loading(IngestPipeline.Progress()) }
        do {
            let (assets, summary) = try await pipeline.run(limit: limit) { [weak self] progress in
                Task { @MainActor in
                    guard let self, !keepingExisting else { return }
                    self.state = .loading(progress)
                }
            }
            self.assets = assets
            self.summary = summary
            self.state = .loaded(Date())
            await cache.save(assets: assets)
            // The watch takes this rather than repeating the join on its own battery.
            await WatchSync.shared.send(assets: assets)
        } catch {
            // Keep whatever is already on screen rather than blanking it.
            if assets.isEmpty {
                state = .failed(error.localizedDescription)
            } else {
                state = .loaded(Date())
            }
        }
    }
}
