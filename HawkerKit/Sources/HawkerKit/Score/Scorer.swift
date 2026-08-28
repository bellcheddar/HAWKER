import Foundation

/// The Resurrection Score, computed from facts already on the `Asset`.
///
/// There is no model here and nothing is fitted. Every number below traces to a
/// public field, and the four components are always displayed separately, because a
/// single number would hide the fact that they measure entirely different things.
public struct Scorer: Sendable {

    /// Estimated composition-of-matter term, in years, added to the earliest public
    /// date. A crude proxy: real expiry needs Orange Book listings and term
    /// extensions. Labelled as an estimate wherever it is shown.
    public static let estimatedPatentTermYears = 20

    public init() {}

    // MARK: Components

    /// How far the death was a fact about the sponsor rather than about the molecule.
    ///
    /// `unknown` sits at 0.5 deliberately: it is neutral, not optimistic. Two thirds
    /// of the corpus would otherwise be flattered by its own silence.
    public func benignDeath(cause: CauseOfDeath) -> Double {
        switch cause {
        case .businessStrategic, .funding, .operational: 1.0
        case .enrolment: 1.0
        case .unknown: 0.5
        case .pkAdmet: 0.15
        case .efficacyFutility: 0.05
        case .safetyMechanistic: 0.0
        }
    }

    /// Whether there is something to design against.
    ///
    /// The build plan assumed Open Targets returned numbered tractability buckets. It
    /// does not: it returns a list of boolean labels. So the third term counts the
    /// small-molecule labels that came back true, against the number that exist.
    public func structuralTractability(
        hasExactCoCrystal: Bool,
        hasAnyTargetStructure: Bool,
        smallMoleculeLabels: [String]
    ) -> Double {
        var score = 0.0
        // A co-crystal of this exact ligand is the strongest possible statement:
        // the pocket is real, the pose is known, and the SAR is already in the file.
        if hasExactCoCrystal { score += 0.6 }
        if hasAnyTargetStructure { score += 0.2 }
        score += 0.2 * tractabilityFraction(smallMoleculeLabels)
        return score
    }

    /// Open Targets' small-molecule tractability labels, ranked. The higher labels
    /// subsume the lower ones in practice, so the best label present sets the score.
    static let smallMoleculeLadder: [String] = [
        "Approved Drug",
        "Advanced Clinical",
        "Phase 1 Clinical",
        "Structure with Ligand",
        "High-Quality Ligand",
        "High-Quality Pocket",
        "Med-Quality Pocket",
        "Druggable Family"
    ]

    func tractabilityFraction(_ labels: [String]) -> Double {
        guard !labels.isEmpty else { return 0 }
        let present = Set(labels)
        for (index, label) in Self.smallMoleculeLadder.enumerated() where present.contains(label) {
            // Best label wins; earlier in the ladder is stronger.
            return 1.0 - (Double(index) / Double(Self.smallMoleculeLadder.count))
        }
        return 0.25 // an unrecognised label is still evidence of something
    }

    /// The best genetically supported disease association that is **not** the
    /// indication the asset failed in.
    ///
    /// Weighted by genetic evidence on purpose: a high overall association score is
    /// often driven by literature co-mention, which is a fact about publishing rather
    /// than about causality, and would make every well-studied target look like
    /// whitespace.
    public func biologicalWhitespace(association: DiseaseAssociation?) -> Double {
        guard let association else { return 0 }
        let genetic = association.geneticScore
        // Half the credit for the association existing, half for it being genetic.
        return (association.score * 0.5) + (genetic * 0.5)
    }

    /// Estimate only. Not a freedom-to-operate opinion, and the UI must say so
    /// wherever this number appears.
    ///
    /// Ramps from 0 at the estimated horizon to 1 ten years past it, rather than
    /// stepping, because the estimate is too crude to justify a cliff edge.
    public func freedomToOperate(estimatedHorizonYear: Int?, now: Date = Date()) -> Double {
        guard let horizon = estimatedHorizonYear else { return 0.35 } // no date: mildly unknown
        let year = Calendar(identifier: .gregorian).component(.year, from: now)
        let elapsed = year - horizon
        if elapsed >= 10 { return 1.0 }
        if elapsed <= -10 { return 0.0 }
        return (Double(elapsed) + 10) / 20.0
    }

    /// Earliest public date + the estimated term. Uses ChEMBL's first approval where
    /// there is one, else the earliest trial start, which is the earliest public
    /// evidence the compound existed.
    public func estimatedHorizonYear(firstApproval: Int?, trials: [TrialRecord]) -> Int? {
        let calendar = Calendar(identifier: .gregorian)
        let trialYears = trials.compactMap { $0.startDate.map { calendar.component(.year, from: $0) } }
        guard let earliest = ([firstApproval].compactMap { $0 } + trialYears).min() else { return nil }
        return earliest + Self.estimatedPatentTermYears
    }

    // MARK: Assembly

    public func score(
        cause: CauseOfDeath,
        hasExactCoCrystal: Bool,
        hasAnyTargetStructure: Bool,
        smallMoleculeLabels: [String],
        whitespace: DiseaseAssociation?,
        estimatedHorizonYear: Int?,
        now: Date = Date()
    ) -> ResurrectionScore {
        ResurrectionScore(
            benignDeath: benignDeath(cause: cause),
            structuralTractability: structuralTractability(
                hasExactCoCrystal: hasExactCoCrystal,
                hasAnyTargetStructure: hasAnyTargetStructure,
                smallMoleculeLabels: smallMoleculeLabels
            ),
            biologicalWhitespace: biologicalWhitespace(association: whitespace),
            freedomToOperate: freedomToOperate(estimatedHorizonYear: estimatedHorizonYear, now: now)
        )
    }
}
