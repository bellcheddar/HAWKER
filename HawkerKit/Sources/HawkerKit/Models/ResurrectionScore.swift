import Foundation

/// Four components, each 0 to 1, each shown separately. The overall number is a
/// weighted sum and nothing else: there is no model here, and the UI must never
/// present the total without the parts that made it.
public struct ResurrectionScore: Codable, Sendable, Hashable {
    public let benignDeath: Double
    public let structuralTractability: Double
    public let biologicalWhitespace: Double
    /// A crude estimate from public approval dates. Not a freedom-to-operate
    /// opinion, and labelled as an estimate everywhere it is displayed.
    public let freedomToOperate: Double

    public static let weights = (
        benignDeath: 0.35,
        structuralTractability: 0.25,
        biologicalWhitespace: 0.25,
        freedomToOperate: 0.15
    )

    public init(
        benignDeath: Double,
        structuralTractability: Double,
        biologicalWhitespace: Double,
        freedomToOperate: Double
    ) {
        self.benignDeath = benignDeath.clamped01
        self.structuralTractability = structuralTractability.clamped01
        self.biologicalWhitespace = biologicalWhitespace.clamped01
        self.freedomToOperate = freedomToOperate.clamped01
    }

    public var overall: Double {
        benignDeath * Self.weights.benignDeath
        + structuralTractability * Self.weights.structuralTractability
        + biologicalWhitespace * Self.weights.biologicalWhitespace
        + freedomToOperate * Self.weights.freedomToOperate
    }

    /// The overall score rendered 0 to 100.
    public var ghostRank: Int { Int((overall * 100).rounded()) }

    public var components: [Component] {
        [
            Component(kind: .benignDeath, value: benignDeath),
            Component(kind: .structuralTractability, value: structuralTractability),
            Component(kind: .biologicalWhitespace, value: biologicalWhitespace),
            Component(kind: .freedomToOperate, value: freedomToOperate)
        ]
    }

    public struct Component: Identifiable, Sendable, Hashable {
        public var id: Kind { kind }
        public let kind: Kind
        public let value: Double
        public var weight: Double { kind.weight }
        public var contribution: Double { value * weight }
    }

    public enum Kind: String, Codable, Sendable, CaseIterable, Hashable {
        case benignDeath, structuralTractability, biologicalWhitespace, freedomToOperate

        public var label: String {
            switch self {
            case .benignDeath: "Benign death"
            case .structuralTractability: "Structural tractability"
            case .biologicalWhitespace: "Biological whitespace"
            case .freedomToOperate: "Freedom to operate (estimate)"
            }
        }

        public var weight: Double {
            switch self {
            case .benignDeath: ResurrectionScore.weights.benignDeath
            case .structuralTractability: ResurrectionScore.weights.structuralTractability
            case .biologicalWhitespace: ResurrectionScore.weights.biologicalWhitespace
            case .freedomToOperate: ResurrectionScore.weights.freedomToOperate
            }
        }

        public var explanation: String {
            switch self {
            case .benignDeath:
                "How far the recorded cause of death was a fact about the sponsor rather than about the molecule."
            case .structuralTractability:
                "Whether the exact ligand has been co-crystallised, whether the target has any structure at all, and what Open Targets says about small-molecule tractability."
            case .biologicalWhitespace:
                "The best genetically supported disease association for this target that is not the indication the asset failed in."
            case .freedomToOperate:
                "An estimate only: earliest public approval or registration date plus 20 years. It is not a freedom-to-operate opinion and must not be relied on as one."
            }
        }

        /// Shown wherever the FTO number appears, per the plan's guardrail.
        public var caveat: String? {
            self == .freedomToOperate
                ? "Estimate from public dates only. Not legal advice, and not a freedom-to-operate opinion."
                : nil
        }
    }
}

extension Double {
    var clamped01: Double { Swift.min(1, Swift.max(0, self)) }
}
