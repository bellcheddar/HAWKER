import Foundation

/// Why a clinical asset stopped. The ordering of the cases is also the precedence
/// order used by `CauseClassifier`: a trial halted for both toxicity and slow accrual
/// is a safety death, because the safety signal is the fact that constrains reuse.
public enum CauseOfDeath: String, Codable, Sendable, CaseIterable, Hashable {
    case safetyMechanistic
    case efficacyFutility
    case pkAdmet
    case enrolment
    case businessStrategic
    case funding
    case operational
    case unknown

    /// The spine of the app: did the biology fail, or did the business?
    ///
    /// Only these three classes tell us something about the molecule or the target.
    /// Everything else is a fact about a sponsor, and leaves the science untouched.
    public var isMechanistic: Bool {
        switch self {
        case .safetyMechanistic, .efficacyFutility, .pkAdmet: true
        default: false
        }
    }

    public var label: String {
        switch self {
        case .safetyMechanistic: "Safety (mechanistic)"
        case .efficacyFutility:  "Efficacy / futility"
        case .pkAdmet:           "PK / ADMET"
        case .enrolment:         "Enrolment"
        case .businessStrategic: "Business / strategic"
        case .funding:           "Funding"
        case .operational:       "Operational"
        case .unknown:           "Unknown"
        }
    }

    /// Short form for chips and watch rows, where the full label will not fit.
    public var shortLabel: String {
        switch self {
        case .safetyMechanistic: "Safety"
        case .efficacyFutility:  "Efficacy"
        case .pkAdmet:           "PK"
        case .enrolment:         "Enrolment"
        case .businessStrategic: "Business"
        case .funding:           "Funding"
        case .operational:       "Operational"
        case .unknown:           "Unknown"
        }
    }

    /// An SF Symbol so the classification is never carried by colour alone.
    public var symbolName: String {
        switch self {
        case .safetyMechanistic: "exclamationmark.triangle.fill"
        case .efficacyFutility:  "target"
        case .pkAdmet:           "drop.fill"
        case .enrolment:         "person.2.slash.fill"
        case .businessStrategic: "briefcase.fill"
        case .funding:           "banknote.fill"
        case .operational:       "wrench.and.screwdriver.fill"
        case .unknown:           "questionmark.circle.fill"
        }
    }
}

/// How much weight to put on a classification, so the UI can show the user
/// whether a label came from an explicit phrase or from a sentence embedding.
public enum ClassificationConfidence: String, Codable, Sendable, Hashable {
    case strong   // an explicit lexicon phrase matched
    case weak     // nearest prototype sentence, above the similarity threshold
    case none     // no text to classify

    public var label: String {
        switch self {
        case .strong: "Explicit"
        case .weak:   "Inferred"
        case .none:   "No statement"
        }
    }
}

/// A classification plus the evidence for it. Every cause shown in the app can be
/// audited back to the substring that produced it.
public struct CauseVerdict: Codable, Sendable, Hashable {
    public let cause: CauseOfDeath
    public let confidence: ClassificationConfidence
    /// The matched substring of `whyStopped`, or the prototype that won on cosine
    /// similarity. Empty when there was no text at all.
    public let evidence: String
    /// Character range of `evidence` within the source text, for highlighting.
    public let evidenceRange: Range<Int>?
    /// Cosine similarity, only set for `.weak` verdicts.
    public let similarity: Double?

    public init(
        cause: CauseOfDeath,
        confidence: ClassificationConfidence,
        evidence: String,
        evidenceRange: Range<Int>? = nil,
        similarity: Double? = nil
    ) {
        self.cause = cause
        self.confidence = confidence
        self.evidence = evidence
        self.evidenceRange = evidenceRange
        self.similarity = similarity
    }

    public static let noStatement = CauseVerdict(
        cause: .unknown,
        confidence: .none,
        evidence: ""
    )
}
