import Foundation
import HawkerKit

// A headless run of the ingest, so the pipeline can be validated and timed without
// the app. Reports real numbers: counts per class, join hit rates and wall clock.

let limit = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 200

print("HAWKER ingest: seeding with up to \(limit) ChEMBL molecules\n")
let pipeline = IngestPipeline()

/// The progress callback is called from the pipeline's actor, so the last-seen stage
/// has to live somewhere Sendable rather than in a local var.
final class StageTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var last = ""
    func changed(to stage: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard stage != last else { return false }
        last = stage
        return true
    }
}
let tracker = StageTracker()

let (assets, summary) = try await pipeline.run(limit: limit) { progress in
    if tracker.changed(to: progress.stage) {
        print("  [\(progress.stage)]")
    }
    if progress.total > 0, progress.completed % 40 == 0, progress.completed > 0 {
        print(String(format: "    %d/%d considered, %d kept", progress.completed, progress.total, progress.kept))
    }
}

print("""

=== Summary ===
considered      \(summary.considered)
kept            \(summary.kept)  (\(pct(summary.kept, summary.considered)))
with a target   \(summary.withTarget)  (\(pct(summary.withTarget, summary.kept)))
with co-crystal \(summary.withCoCrystal)  (\(pct(summary.withCoCrystal, summary.kept)))
elapsed         \(summary.elapsed)

=== Cause of death ===
""")
for (cause, count) in summary.byCause.sorted(by: { $0.value > $1.value }) {
    print(String(format: "  %-22@ %4d  %@", cause.rawValue as NSString, count, pct(count, summary.kept)))
}
print(String(format: "\n  died of business rather than biology: %.1f%% of classified",
             summary.businessFraction * 100))

print("\n=== Top 15 by Ghost Rank ===")
for asset in assets.prefix(15) {
    let target = asset.target?.displayName ?? "-"
    let struc = asset.hasCoCrystal ? (asset.structures.first?.pdbId ?? "-") : "-"
    print(String(format: "  %3d  %-26@ %-14@ %-20@ %-6@ %@",
                 asset.ghostRank,
                 asset.displayName as NSString,
                 target as NSString,
                 asset.cause.shortLabel as NSString,
                 struc as NSString,
                 asset.verdict.confidence.label))
}

print("\n=== Score component means ===")
for kind in ResurrectionScore.Kind.allCases {
    let values = assets.map { a -> Double in
        switch kind {
        case .benignDeath: a.score.benignDeath
        case .structuralTractability: a.score.structuralTractability
        case .biologicalWhitespace: a.score.biologicalWhitespace
        case .freedomToOperate: a.score.freedomToOperate
        }
    }
    let mean = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    print(String(format: "  %-32@ %.3f", kind.label as NSString, mean))
}

func pct(_ n: Int, _ d: Int) -> String {
    d > 0 ? String(format: "%.1f%%", 100 * Double(n) / Double(d)) : "-"
}
