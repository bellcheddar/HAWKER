import Foundation

/// Search over the asset set that understands what was asked, not just what was typed.
///
/// Substring search fails the question this app exists to answer. "Heart drugs that
/// were shelved for money reasons" matches nothing literally, while the assets that
/// answer it are all present. So: a literal pass first, because an exact drug name,
/// ChEMBL id or PDB code must always win and must never be reordered by a model, then
/// an on-device semantic pass over a short profile of each asset.
///
/// The semantic pass is opt-in per query and only runs once the literal pass has been
/// exhausted, so typing a ChEMBL id stays instant.
public struct SemanticSearch: Sendable {

    /// Floor for a semantic hit. Below this the result is noise dressed as an answer.
    public static let relevanceThreshold = 0.62

    private let space: SentenceSpace

    public init(space: SentenceSpace = .shared) { self.space = space }

    /// One sentence per asset, built from the fields a person would actually search on.
    /// Kept short on purpose: the embedding is a sentence model, and burying the drug
    /// name in a paragraph of trial metadata dilutes it.
    public func profile(for asset: Asset) -> String {
        var parts: [String] = [asset.displayName]
        if let moa = asset.mechanismOfAction { parts.append(moa) }
        if let target = asset.target { parts.append(target.displayName) }
        if let indication = asset.failedIndications.first { parts.append("failed in \(indication.term)") }
        parts.append("stopped because of \(asset.cause.label.lowercased())")
        if let phase = asset.phaseReached { parts.append("reached \(phase.label)") }
        return parts.joined(separator: ", ")
    }

    /// Literal matches: exact identifiers and substring hits on the fields a user types.
    public func literalMatches(_ query: String, in assets: [Asset]) -> [Asset] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return assets.filter { asset in
            if asset.chemblId.lowercased() == q { return true }
            if asset.displayName.lowercased().contains(q) { return true }
            if asset.synonyms.contains(where: { $0.lowercased().contains(q) }) { return true }
            if asset.ccdCode?.lowercased() == q { return true }
            if asset.target?.displayName.lowercased().contains(q) == true { return true }
            if asset.mechanismOfAction?.lowercased().contains(q) == true { return true }
            if asset.failedIndications.contains(where: { $0.term.lowercased().contains(q) }) { return true }
            if asset.structures.contains(where: { $0.pdbId.lowercased() == q }) { return true }
            return false
        }
    }

    /// Literal hits first (in Ghost Rank order), then semantic hits above the
    /// threshold, never duplicating an asset already matched literally.
    public func search(_ query: String, in assets: [Asset], limit: Int = 100) async -> [Hit] {
        let literal = literalMatches(query, in: assets)
            .sorted { $0.ghostRank > $1.ghostRank }
            .map { Hit(asset: $0, kind: .literal, relevance: 1.0) }

        guard literal.count < limit, await space.isAvailable,
              let queryVector = await space.vector(for: query)
        else { return Array(literal.prefix(limit)) }

        let already = Set(literal.map(\.asset.chemblId))
        var semantic: [Hit] = []
        for asset in assets where !already.contains(asset.chemblId) {
            guard let v = await space.vector(for: profile(for: asset)) else { continue }
            let relevance = space.similarity(queryVector, v)
            if relevance >= Self.relevanceThreshold {
                semantic.append(Hit(asset: asset, kind: .semantic, relevance: relevance))
            }
        }
        semantic.sort { $0.relevance > $1.relevance }
        return Array((literal + semantic).prefix(limit))
    }

    public struct Hit: Sendable, Identifiable, Hashable {
        public var id: String { asset.chemblId }
        public let asset: Asset
        public let kind: Kind
        /// 1.0 for a literal match, cosine similarity for a semantic one.
        public let relevance: Double

        public enum Kind: String, Sendable, Hashable {
            case literal, semantic
            /// Shown next to semantic hits so a fuzzy match never masquerades as exact.
            public var label: String {
                switch self {
                case .literal: "Match"
                case .semantic: "Related"
                }
            }
        }
    }
}
