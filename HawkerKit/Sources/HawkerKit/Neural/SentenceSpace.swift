import Foundation
import Accelerate
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// Shared sentence-embedding space, backed by Apple's on-device model.
///
/// `NLEmbedding.sentenceEmbedding` runs on the Neural Engine, offline, with no model
/// to ship and nothing to train, which is the only kind of ML that fits this app's
/// "no hand curation" rule. Three parts of HAWKER use it: the classifier's fallback,
/// the whitespace check, and search.
///
/// Why this type exists rather than calling `NLEmbedding` directly: the obvious API,
/// `distance(between:and:)`, re-embeds **both** strings on every call, so comparing one
/// string to eight prototypes embeds it eight times and the prototypes 8n times.
/// Measured on this M1 Max: 12 strings/s that way against 165 strings/s when each
/// string is embedded once and compared with vDSP, a 14.1x difference. At the naive
/// rate the classifier fallback alone would have taken about twelve minutes and blown
/// the cold-ingest budget.
public actor SentenceSpace {
    public static let shared = SentenceSpace()

    /// 512 on current OS versions. Read from the model, never assumed.
    public private(set) var dimension: Int = 0

    #if canImport(NaturalLanguage)
    private let embedding: NLEmbedding?
    #endif

    /// Vectors are pure functions of their text and the model is fixed for the life of
    /// the process, so caching is always safe and the ingest re-sees a lot of boilerplate
    /// ("Terminated by sponsor", "Slow accrual") across thousands of trials.
    private var cache: [String: [Float]] = [:]
    private var cacheOrder: [String] = []
    private let cacheLimit = 20_000

    public init() {
        #if canImport(NaturalLanguage)
        let model = NLEmbedding.sentenceEmbedding(for: .english)
        self.embedding = model
        self.dimension = model?.dimension ?? 0
        #endif
    }

    /// True when the on-device model loaded. When it has not, every caller must fall
    /// back to a deterministic answer rather than guessing: an unavailable model is
    /// not permission to invent a classification.
    public var isAvailable: Bool {
        #if canImport(NaturalLanguage)
        embedding != nil
        #else
        false
        #endif
    }

    /// L2-normalised embedding, so a comparison is a single dot product.
    public func vector(for text: String) -> [Float]? {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        if let hit = cache[key] { return hit }

        #if canImport(NaturalLanguage)
        guard let embedding, let raw = embedding.vector(for: key) else { return nil }
        var v = raw.map(Float.init)
        normalise(&v)
        store(key: key, vector: v)
        return v
        #else
        return nil
        #endif
    }

    /// Embed many strings, reusing the cache. Sequential on purpose: `NLEmbedding` is
    /// not documented as thread-safe, and the ANE is already the bottleneck, so
    /// fanning out buys nothing and risks a data race.
    public func vectors(for texts: [String]) -> [String: [Float]] {
        var out: [String: [Float]] = [:]
        out.reserveCapacity(texts.count)
        for text in texts {
            if let v = vector(for: text) { out[text] = v }
        }
        return out
    }

    /// Cosine similarity in 0...1 for two already-normalised vectors.
    /// Raw cosine is -1...1; sentence embeddings rarely go negative, but the rescale
    /// keeps every threshold in this app on one comparable scale.
    public nonisolated func similarity(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        return (Double(dot) + 1.0) / 2.0
    }

    /// Raw cosine in -1...1 for two already-normalised vectors.
    ///
    /// Prefer this to `similarity(_:_:)` for any threshold: the 0...1 rescale maps a
    /// cosine of 0.1 to 0.55, which silently turned the plan's 0.55 gate into "accept
    /// everything" and produced a 99.7% match rate that looked like success.
    public nonisolated func rawCosine(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        return Double(dot)
    }

    /// Best match among candidates, with its similarity.
    public func nearest(
        to text: String,
        among candidates: [(id: String, vector: [Float])]
    ) -> (id: String, similarity: Double)? {
        guard let v = vector(for: text) else { return nil }
        var best: (String, Double)?
        for candidate in candidates {
            let s = similarity(v, candidate.vector)
            if best == nil || s > best!.1 { best = (candidate.id, s) }
        }
        return best.map { (id: $0.0, similarity: $0.1) }
    }

    /// Similarity between two strings, both embedded through the cache.
    public func similarity(between a: String, and b: String) -> Double? {
        guard let va = vector(for: a), let vb = vector(for: b) else { return nil }
        return similarity(va, vb)
    }

    // MARK: Internals

    private func normalise(_ v: inout [Float]) {
        var sumsq: Float = 0
        vDSP_svesq(v, 1, &sumsq, vDSP_Length(v.count))
        let norm = sqrt(sumsq)
        guard norm > 1e-9 else { return }
        var inv = 1 / norm
        vDSP_vsmul(v, 1, &inv, &v, 1, vDSP_Length(v.count))
    }

    private func store(key: String, vector: [Float]) {
        if cache[key] == nil {
            cacheOrder.append(key)
            if cacheOrder.count > cacheLimit {
                // Simple FIFO eviction: access order does not matter much here because
                // the ingest sweeps once and the UI re-queries a small working set.
                let evict = cacheOrder.removeFirst()
                cache.removeValue(forKey: evict)
            }
        }
        cache[key] = vector
    }

    public func clearCache() {
        cache.removeAll(keepingCapacity: false)
        cacheOrder.removeAll(keepingCapacity: false)
    }

    public var cacheCount: Int { cache.count }
}
