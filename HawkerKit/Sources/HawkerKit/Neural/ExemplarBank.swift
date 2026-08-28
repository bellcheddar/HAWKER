import Foundation

/// Nearest-neighbour classification of `whyStopped` text, over real sponsor sentences
/// that the deterministic lexicon has already labelled.
///
/// ## Why this rather than the prototype sentences the plan specified
///
/// The plan called for eight hand-written prototype sentences and a 0.55 cosine
/// threshold. That was measured on 2026-08-28 and it does not work: against five
/// held-out sentences with obvious classes it got **one** right, the "PK" prototype
/// acted as an attractor for enrolment, funding and efficacy text alike, and the
/// string "Study closed." scored 0.569, higher than four of the five. A 0.55 gate on
/// that scale accepted 99.7% of everything, which is the tell that the number meant
/// nothing.
///
/// The failure is not the Neural Engine's: it is that a general-English sentence model
/// is being asked to match invented sentences against a register it has never seen.
/// Real `whyStopped` text is terse, passive and full of trial jargon ("Slow accrual",
/// "PI left institution", "Sponsor's decision"), and nothing written by hand sounds
/// like it.
///
/// So the exemplars are real sentences instead, and their labels come from the lexicon
/// rather than from a person: still no hand curation, and the bank grows as the app
/// ingests. Measured on a held-out 20% of 2,674 labelled strings:
///
/// | Vote-share gate | Coverage | Precision |
/// |---|---|---|
/// | 0.50 | 68.6% | 89.6% |
/// | 0.70 | 49.2% | 95.8% |
/// | **0.80** | **42.6%** | **97.8%** |
/// | 0.90 | 32.3% | 98.8% |
///
/// 0.80 is the chosen gate: per-class precision there is 95.8% to 100%, and the point
/// of the fallback is to be right about the text it does claim, not to claim all of it.
public actor ExemplarBank {
    public static let shared = ExemplarBank()

    /// Neighbours consulted. Swept over 1, 5, 15 and 25: accuracy peaks flat around
    /// 5 to 15, and 15 gives a smoother vote share, which is what the gate reads.
    public static let neighbourCount = 15

    /// Minimum similarity-weighted vote share for the winning class. See the table above.
    public static let voteShareGate = 0.80

    private let space: SentenceSpace
    private var exemplars: [(cause: CauseOfDeath, vector: [Float])] = []
    private var isPrepared = false

    public init(space: SentenceSpace = .shared) { self.space = space }

    public var count: Int { exemplars.count }
    public var prepared: Bool { isPrepared }

    /// Embed the shipped seed bank. Costs about nine seconds on an M1 Max for 1,458
    /// sentences, once, so callers run it off the main actor during ingest and the UI
    /// falls back to the lexicon alone until it finishes.
    public func prepare() async {
        guard !isPrepared, await space.isAvailable else { return }
        for seed in Self.loadSeeds() {
            guard let cause = CauseOfDeath(rawValue: seed.c),
                  let v = await space.vector(for: seed.t) else { continue }
            exemplars.append((cause, v))
        }
        isPrepared = true
    }

    /// Add a sentence the lexicon has just classified. The bank improves as the app
    /// ingests, and nothing here was written by a person.
    public func add(text: String, cause: CauseOfDeath) async {
        guard isPrepared, let v = await space.vector(for: text) else { return }
        exemplars.append((cause, v))
    }

    /// Similarity-weighted k-NN vote. Returns nil below the gate, which is the honest
    /// answer far more often than not.
    public func classify(_ text: String) async -> (cause: CauseOfDeath, voteShare: Double, nearest: Double)? {
        guard isPrepared, !exemplars.isEmpty, let v = await space.vector(for: text) else { return nil }

        // Partial selection of the k best, rather than sorting 1,458 every call.
        var top: [(CauseOfDeath, Double)] = []
        top.reserveCapacity(Self.neighbourCount)
        for exemplar in exemplars {
            let s = space.rawCosine(v, exemplar.vector)
            if top.count < Self.neighbourCount {
                top.append((exemplar.cause, s))
                top.sort { $0.1 > $1.1 }
            } else if s > top[Self.neighbourCount - 1].1 {
                top[Self.neighbourCount - 1] = (exemplar.cause, s)
                top.sort { $0.1 > $1.1 }
            }
        }
        guard let nearest = top.first?.1 else { return nil }

        var weights: [CauseOfDeath: Double] = [:]
        for (cause, s) in top { weights[cause, default: 0] += max(0, s) }
        let total = weights.values.reduce(0, +)
        guard total > 0, let winner = weights.max(by: { $0.value < $1.value }) else { return nil }

        let share = winner.value / total
        guard share >= Self.voteShareGate else { return nil }
        return (winner.key, share, Double(nearest))
    }

    // MARK: Seed bank

    struct Seed: Decodable, Sendable {
        let c: String
        let t: String
    }

    struct SeedFile: Decodable, Sendable {
        let version: Int
        let captured: String
        let source: String
        let exemplars: [Seed]
    }

    static func loadSeeds() -> [Seed] {
        guard let url = Bundle.module.url(forResource: "exemplar_bank", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? HawkerJSON.decoder.decode(SeedFile.self, from: data)
        else { return [] }
        return file.exemplars
    }

    /// Provenance, printed in the Method sheet.
    public static func seedProvenance() -> (captured: String, source: String, count: Int)? {
        guard let url = Bundle.module.url(forResource: "exemplar_bank", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? HawkerJSON.decoder.decode(SeedFile.self, from: data)
        else { return nil }
        return (file.captured, file.source, file.exemplars.count)
    }
}
