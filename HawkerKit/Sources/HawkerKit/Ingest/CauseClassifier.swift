import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// Deterministic, inspectable classification of why a trial stopped.
///
/// No curation, no training, no model weights. A precedence-ordered lexicon runs first
/// and wins outright; only genuinely unmatched text falls through to a sentence
/// embedding against eight prototypes written in this file. Every verdict carries the
/// substring that produced it, so the Method sheet can show its own working.
///
/// Precedence matters more than it looks. A trial halted for both toxicity and slow
/// accrual is a safety death: the safety signal is the fact that constrains reuse, and
/// the accrual problem is downstream of it.
public struct CauseClassifier: Sendable {

    /// Vote-share floor for the nearest-neighbour fallback, forwarded from
    /// `ExemplarBank`. Below it, `unknown` is the honest answer and is scored
    /// neutrally rather than optimistically.
    public static var similarityThreshold: Double { ExemplarBank.voteShareGate }

    public init() {}

    // MARK: The lexicon

    /// Ordered by precedence, first match wins. Stems are matched case-insensitively
    /// against the whole string, so "hepatotox" catches hepatotoxic, hepatotoxicity
    /// and hepatotoxicities without three entries.
    /// Ordered by precedence, first match wins. Stems are matched case-insensitively
    /// against the whole string, so "hepatotox" catches hepatotoxic, hepatotoxicity and
    /// hepatotoxicities without three entries.
    ///
    /// Calibrated on 4,000 real halted studies pulled from ClinicalTrials.gov on
    /// 2026-08-28, which brought unknown down from 44.5% to 33.1% of all halted studies
    /// (24.7% of those that state a reason). Do not add a stem without re-running
    /// `CauseClassifierCalibrationTests`: two of the first draft's stems were substring
    /// collisions ("harm" matches "pharmaceutical") and both landed in safetyMechanistic,
    /// the class that costs an asset the most.
    public static let lexicon: [(cause: CauseOfDeath, stems: [String])] = [
        // Toxicity, adverse events and safety committee stops. First in precedence: a trial
        // halted for both toxicity and slow accrual is a safety death, because the safety
        // signal is the fact that constrains reuse.
        (.safetyMechanistic, [
            "hepatotox", "cardiotox", "nephrotox", "neurotox", "cardiac safety", "qt prolong",
            "qtc", "torsade", "adverse event", "adverse reaction", "serious ae", "sae", "dsmb",
            "data safety monitoring", "data and safety monitoring", "safety signal",
            "safety concern", "safety issue", "safety finding", "toxicity", "toxicities",
            "toxic effect", "unacceptable tox", "death", "deaths", "fatal", "mortality imbalance",
            "liver enzyme", "transaminase", "alt elevation", "ast elevation", "clinical hold",
            "risk-benefit", "risk/benefit", "benefit-risk", "tolerability", "not well tolerated",
            "poorly tolerated", "safety data", "safety reason", "safety of the",
            "overall profile of the", "efficacy and safety profile", "benefit/risk",
            "serious adverse", "safety monitoring", "toxicolog", "toxic effect", "toxic "
        ]),
        // The drug reached its target and the target did not deliver.
        (.efficacyFutility, [
            "futility", "futile", "lack of efficacy", "lack of effectiveness", "no efficacy",
            "insufficient efficacy", "did not meet", "failed to meet", "failed primary",
            "primary endpoint was not", "missed the primary", "interim analysis",
            "efficacy boundary", "unlikely to demonstrate", "no significant difference",
            "negative result", "did not demonstrate", "low probability of success",
            "pre-specified futility", "not effective", "ineffective", "no benefit",
            "lack of benefit", "primary objective was not", "did not show", "no improvement",
            "efficacy analysis", "unlikely to succeed", "stopping rule", "results of the interim"
        ]),
        // The molecule never got where it needed to be. Rare in the wild (0.3% of
        // classified halted trials) because sponsors rarely say so in public.
        (.pkAdmet, [
            "pharmacokinetic", "pharmacokinetics", " pk ", "exposure", "bioavailability",
            "half-life", "half life", "formulation", "solubility", "absorption", "metabolis",
            "drug-drug interaction", "drug interaction", "plasma concentration",
            "insufficient exposure", "did not achieve target concentration",
            "stability of the drug", "dosage form", "dose form", "bioequivalence",
            "drug stability", "impurity"
        ]),
        // The single largest cause in the real data (32.6% of studies with a stated
        // reason). Nothing to do with the biology.
        (.enrolment, [
            "enrolment", "enrollment", "accrual", "recruitment", "recruiting", "slow enrol",
            "slow enroll", "poor accrual", "low accrual", "insufficient participants",
            "insufficient patients", "insufficient subjects", "unable to enrol",
            "unable to enroll", "unable to recruit", "did not enrol", "did not enroll",
            "lack of eligible", "no eligible patients", "failure to control sufficient patients",
            "below protocol expectation", "no participants enrol", "no subjects enrol",
            "no patients enrol", "not enrolled", "never enrolled", "no participants were enrol",
            "not able to recruit", "unable to identify", "lack of patient", "lack of participant",
            "lack of subject", "lack of accrual", "lack of enrol", "recruit", "recrut",
            "inclusion period", "end of inclusion", "not enough patient", "no enough patient",
            "not enough subject", "insufficient enrol", "low enrol", "poor enrol", "slow accrual",
            "number of patients", "few patients", "few participants", "too few", "no eligible",
            "difficulty enrol", "difficulty in enrol", "screening failure",
            "participants are no longer"
        ]),
        // Portfolio decisions, mergers, and sponsors changing their minds.
        (.businessStrategic, [
            "business decision", "business reason", "strategic", "strategy", "portfolio",
            "prioriti", "deprioriti", "sponsor decision", "company decision", "merger",
            "acquisition", "acquired", "licensing", "licence", "license", "commercial", "market",
            "development was discontinued", "program was discontinued",
            "programme was discontinued", "development terminated", "no longer part of",
            "change in development plan", "management decision", "sponsor's decision",
            "sponsors decision", "terminated by sponsor", "terminated by the sponsor",
            "withdrawn by sponsor", "sponsor withdrew", "sponsor withdrawal", "business objective",
            "company shifted", "shifted focus", "change in focus", "discontinu",
            "withdrew support", "withdrew its support", "decided to terminate",
            "decided to discontinue", "decided to stop", "decided to end", "decided not to",
            "company decided", "sponsor decided", "no longer marketed", "ce mark", "not marketed",
            "development plan", "development was stopped", "study was cancelled",
            "study was canceled", "no longer of interest", "redundant", "internal decision",
            "ceased operations", "company ceased", "withdrawal of sponsor"
        ]),
        // "cost " carries a trailing space on purpose: bare "cost" matches
        // "costimulatory", which is a real immunology word and not a funding problem.
        (.funding, [
            "funding", "funded", "financial", "finance", "budget", "resources", "lack of resource",
            "sponsor closed", "grant", "insufficient funds", "money", "economic", "lack of funds",
            "lack of funding", "cost prohibitive", "cost ", "unfunded", "financial support",
            "loss of support", "no support", "costs", "cost of"
        ]),
        // Sites, staff, supply and paperwork.
        (.operational, [
            "investigator", "principal investigator", "pi left", "pi departed", "site closure",
            "site closed", "study site", "supply", "drug supply", "manufacturing",
            "administrative", "logistic", "covid", "pandemic", "sars-cov-2", "regulatory hold",
            "irb", "ethics committee", "protocol amendment", "staffing", "personnel", "relocation",
            "pi request", "investigator request", "insufficient staff", "lack of staff",
            "never initiated", "never activated", "never started", "was not initiated",
            "not activated", "on hold", "infeasible", "feasibility", "not feasible",
            "study design", "design of the study", "protocol was revised", "protocol issue",
            "institution", "equipment", "device", "no longer possible", "technical",
            "data quality", "competed with", "alternate study", "duplicate", "unavailability",
            "combined with nct"
        ])
    ]

    /// The plan specified eight hand-written prototype sentences with a 0.55 cosine
    /// gate. They are retained here only so the Method sheet can show what was tried
    /// and why it was dropped: measured against held-out text on 2026-08-28 the
    /// prototypes classified one sentence in five correctly, and a 0.55 gate on the
    /// rescaled similarity accepted 99.7% of everything. `ExemplarBank` replaced them
    /// with real sponsor sentences labelled by the lexicon above. See that type.
    public static let retiredPrototypes: [(cause: CauseOfDeath, sentence: String)] = [
        (.safetyMechanistic, "The study was stopped because patients experienced serious adverse events and unacceptable toxicity."),
        (.efficacyFutility,  "An interim analysis showed the treatment was unlikely to demonstrate benefit, so the trial was stopped for futility."),
        (.pkAdmet,           "The compound did not achieve adequate plasma exposure and the formulation gave poor bioavailability."),
        (.enrolment,         "The trial closed because too few eligible patients could be recruited within the planned period."),
        (.businessStrategic, "The sponsor made a strategic portfolio decision to discontinue development of this programme."),
        (.funding,           "The study ended because the funding was withdrawn and no further financial resources were available."),
        (.operational,       "The site closed after the principal investigator left and study drug supply could not be maintained.")
    ]

    // MARK: Classification

    /// Classify a `whyStopped` string with the deterministic lexicon only.
    ///
    /// This is the whole classifier for about 75% of the corpus and it never needs the
    /// Neural Engine. Callers wanting the embedding fallback use `classify(_:using:)`.
    public func classify(_ text: String?) -> CauseVerdict {
        guard let raw = text?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return .noStatement
        }
        return lexiconMatch(raw) ?? CauseVerdict(cause: .unknown, confidence: .none, evidence: "")
    }

    /// Classify with the on-device nearest-neighbour fallback for text the lexicon
    /// does not match.
    ///
    /// The lexicon always wins where it fires: it is auditable, and its evidence is a
    /// literal substring of what the sponsor wrote. The bank only ever rescues text
    /// that matched nothing, its verdicts are marked `.weak`, and it declines to answer
    /// below its gate rather than guessing.
    public func classify(_ text: String?, using bank: ExemplarBank) async -> CauseVerdict {
        guard let raw = text?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return .noStatement
        }
        if let hit = lexiconMatch(raw) {
            // Feed the lexicon's own verdicts back in, so the bank grows with the corpus.
            await bank.add(text: raw, cause: hit.cause)
            return hit
        }
        guard let neighbour = await bank.classify(raw) else {
            return CauseVerdict(cause: .unknown, confidence: .none, evidence: "")
        }
        return CauseVerdict(
            cause: neighbour.cause,
            confidence: .weak,
            evidence: "Nearest \(ExemplarBank.neighbourCount) labelled sponsor statements agreed \(Int(neighbour.voteShare * 100))%",
            evidenceRange: nil,
            similarity: neighbour.voteShare
        )
    }

    /// First lexicon stem that occurs in the text, with the matched substring and its
    /// offsets so the UI can highlight the sponsor's own words.
    func lexiconMatch(_ raw: String) -> CauseVerdict? {
        // Padded so a stem written as " pk " can match at the string boundaries too.
        let haystack = " " + raw.lowercased().replacingOccurrences(of: "\n", with: " ") + " "
        for entry in Self.lexicon {
            for stem in entry.stems {
                guard let range = haystack.range(of: stem) else { continue }
                let lower = haystack.distance(from: haystack.startIndex, to: range.lowerBound)
                let upper = haystack.distance(from: haystack.startIndex, to: range.upperBound)
                // Offsets shift by one for the leading pad character.
                let start = max(0, min(raw.count, lower - 1))
                let end = max(start, min(raw.count, upper - 1))
                let from = raw.index(raw.startIndex, offsetBy: start)
                let to = raw.index(raw.startIndex, offsetBy: end)
                return CauseVerdict(
                    cause: entry.cause,
                    confidence: .strong,
                    evidence: String(raw[from..<to]),
                    evidenceRange: start..<end
                )
            }
        }
        return nil
    }

    /// Total number of stems, printed in the Method sheet so the lexicon's size is
    /// visible rather than claimed.
    public static var stemCount: Int { lexicon.reduce(0) { $0 + $1.stems.count } }
}
