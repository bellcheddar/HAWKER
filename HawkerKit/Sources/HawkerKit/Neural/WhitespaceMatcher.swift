import Foundation

/// Decides whether a disease association is genuinely *other* than the indication
/// the asset already failed in.
///
/// This is a correctness fix, not a speed one. The whitespace component asks for the
/// best association "for a disease other than the failed indication", and comparing
/// EFO ids only catches an exact repeat. Open Targets and ChEMBL routinely name the
/// same biology differently: "atherosclerosis" against "coronary artery disease",
/// "type 2 diabetes mellitus" against "non-insulin-dependent diabetes". Scoring those
/// as whitespace credits an asset for a second shot at the disease that just killed
/// it, which is precisely the claim the app must not make.
///
/// The obvious fix was on-device sentence similarity between the disease names, and
/// it was tried and **rejected on measurement** (2026-08-28). The general-English
/// sentence model does not encode disease synonymy at all: "myocardial infarction"
/// against "asthma" scored 0.671 while "atherosclerosis" against "atherosclerotic
/// disease" scored 0.657, and "chronic obstructive pulmonary disease" against its own
/// abbreviation "COPD" scored 0.287. Same-pairs and different-pairs overlap completely
/// and in the wrong order, so no threshold exists that separates them. Tuning one
/// would have produced confident, wrong whitespace claims.
///
/// What remains is deterministic and honest: exact identifier match, exact name match,
/// and a conservative token-overlap rule for the shared-stem cases the ids miss.
/// Anything it cannot rule out stays a candidate, and the Method sheet says so.
public struct WhitespaceMatcher: Sendable {

    public init() {}

    /// Words too generic to imply two diseases are the same.
    static let genericTerms: Set<String> = [
        "disease", "diseases", "disorder", "disorders", "syndrome", "syndromes",
        "chronic", "acute", "primary", "secondary", "severe", "cancer", "carcinoma",
        "neoplasm", "infection", "failure", "deficiency", "injury", "malignant"
    ]

    /// The longest stem of six or more characters shared by the candidate name and any
    /// failed indication, ignoring generic clinical vocabulary.
    static func sharedDistinctiveStem(_ name: String, _ failed: [String]) -> String? {
        let tokens = distinctiveTokens(name)
        guard !tokens.isEmpty else { return nil }
        var best: String?
        for other in failed {
            for a in tokens {
                for b in distinctiveTokens(other) {
                    // Prefix agreement of six characters catches the -osis/-otic and
                    // -aemia/-aemic families without matching unrelated words.
                    let shared = String(zip(a, b).prefix { $0 == $1 }.map(\.0))
                    if shared.count >= 6, shared.count > (best?.count ?? 0) { best = shared }
                }
            }
        }
        return best
    }

    static func distinctiveTokens(_ s: String) -> [String] {
        s.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
            .filter { $0.count >= 6 && !genericTerms.contains($0) }
    }

    /// The best genetically supported association that is not one of the failed
    /// indications, together with the ones that were rejected and why.
    public func bestWhitespace(
        associations: [DiseaseAssociation],
        failedIndications: [Indication]
    ) -> Result {
        let failedIds = Set(failedIndications.map(\.efoId))
        let failedNames = failedIndications.map(\.term).filter { !$0.isEmpty }

        var excluded: [Exclusion] = []
        var candidates: [DiseaseAssociation] = []

        for association in associations {
            // 1. Exact identifier match: certain, and free.
            if failedIds.contains(association.diseaseId) {
                excluded.append(Exclusion(association: association, reason: .exactIdentifier, similarity: nil))
                continue
            }
            // 2. Exact name match, case-insensitively.
            if failedNames.contains(where: { $0.caseInsensitiveCompare(association.diseaseName) == .orderedSame }) {
                excluded.append(Exclusion(association: association, reason: .exactName, similarity: nil))
                continue
            }
            // 3. Shared distinctive token: "atherosclerosis" against "atherosclerotic
            //    disease" is caught by a common stem where an embedding was not.
            //    Deliberately narrow: a stem must be at least six characters, so
            //    "disease", "chronic" and "syndrome" cannot trigger it on their own.
            if let stem = Self.sharedDistinctiveStem(association.diseaseName, failedNames) {
                excluded.append(Exclusion(association: association, reason: .sharedStem, similarity: nil, matched: stem))
            } else {
                candidates.append(association)
            }
        }

        let best = candidates.max(by: { $0.geneticScore < $1.geneticScore })
        return Result(best: best, considered: candidates, excluded: excluded)
    }

    public struct Result: Sendable {
        public let best: DiseaseAssociation?
        public let considered: [DiseaseAssociation]
        public let excluded: [Exclusion]
    }

    public struct Exclusion: Sendable, Hashable {
        public let association: DiseaseAssociation
        public let reason: Reason
        public let similarity: Double?
        public let matched: String?

        public init(association: DiseaseAssociation, reason: Reason, similarity: Double?, matched: String? = nil) {
            self.association = association
            self.reason = reason
            self.similarity = similarity
            self.matched = matched
        }

        public enum Reason: String, Sendable, Hashable {
            case exactIdentifier, exactName, sharedStem

            public var label: String {
                switch self {
                case .exactIdentifier: "Same EFO identifier as the failed indication"
                case .exactName: "Same name as the failed indication"
                case .sharedStem: "Shares a distinctive stem with the failed indication"
                }
            }
        }
    }
}
