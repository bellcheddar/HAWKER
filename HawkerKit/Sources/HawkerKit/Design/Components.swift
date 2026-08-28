import SwiftUI

// MARK: Glass panel

/// The app's one container. `.glassBackgroundEffect()` on visionOS, an ultra-thin
/// material over the void colour everywhere else, with a soft neon rim.
public struct GlassPanel<Content: View>: View {
    private let content: Content
    private let tint: Color
    private let padding: CGFloat

    public init(tint: Color = Palette.neon, padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                #if os(visionOS)
                Color.clear
                #else
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Palette.slab.opacity(0.65))
                    )
                #endif
            }
            .overlay {
                #if !os(visionOS)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1)
                #endif
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            #if os(visionOS)
            .glassBackgroundEffect()
            #endif
    }
}

// MARK: Cause badge

/// The cause of death, as a chip. Always carries a symbol and a word, never colour
/// alone: the whole classification must survive being read in greyscale.
public struct CauseBadge: View {
    private let cause: CauseOfDeath
    private let confidence: ClassificationConfidence?
    private let compact: Bool

    public init(_ cause: CauseOfDeath, confidence: ClassificationConfidence? = nil, compact: Bool = false) {
        self.cause = cause
        self.confidence = confidence
        self.compact = compact
    }

    public var body: some View {
        HStack(spacing: 5) {
            Image(systemName: cause.symbolName)
                .font(.caption2)
            Text(compact ? cause.shortLabel : cause.label)
                .font(.caption)
                .fontWeight(.medium)
            if confidence == .weak {
                // An inferred verdict must never look like a stated one.
                Image(systemName: "sparkle")
                    .font(.system(size: 8))
                    .opacity(0.8)
            }
        }
        .foregroundStyle(Palette.colour(for: cause))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Palette.wash(for: cause)))
        .overlay(Capsule().strokeBorder(Palette.colour(for: cause).opacity(0.45), lineWidth: 0.75))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var s = "Cause of death: \(cause.label)"
        if confidence == .weak { s += ", inferred" }
        if confidence == ClassificationConfidence.none { s += ", no reason stated" }
        return s
    }
}

// MARK: Score bar

/// One component of the Resurrection Score. Shows its own weight, because a bar at
/// 0.9 carrying a weight of 0.15 contributes less than one at 0.5 carrying 0.35.
public struct ScoreBar: View {
    private let kind: ResurrectionScore.Kind
    private let value: Double
    private let showCaveat: Bool

    public init(kind: ResurrectionScore.Kind, value: Double, showCaveat: Bool = true) {
        self.kind = kind
        self.value = value
        self.showCaveat = showCaveat
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(kind.label)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ghost)
                Spacer(minLength: 8)
                Text(String(format: "%.2f", value))
                    .hawkerNumber(Typography.numberSmall)
                    .foregroundStyle(Palette.neon)
                Text("x\(String(format: "%.2f", kind.weight))")
                    .hawkerNumber(Typography.numberSmall)
                    .foregroundStyle(Palette.ghost.opacity(0.6))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.navy.opacity(0.6))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Palette.accent, Palette.neon],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: max(2, geo.size.width * value))
                }
            }
            .frame(height: 7)

            // The plan's guardrail: this sentence appears wherever the number does.
            if showCaveat, let caveat = kind.caveat {
                Text(caveat)
                    .font(.caption2)
                    .foregroundStyle(Palette.amberDeath.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kind.label): \(String(format: "%.2f", value)) of 1, weight \(String(format: "%.2f", kind.weight))")
    }
}

// MARK: Ghost Rank ring

public struct GhostRankRing: View {
    private let rank: Int
    private let size: CGFloat

    public init(rank: Int, size: CGFloat = 52) {
        self.rank = rank
        self.size = size
    }

    public var body: some View {
        ZStack {
            Circle().stroke(Palette.navy.opacity(0.7), lineWidth: size * 0.09)
            Circle()
                .trim(from: 0, to: max(0.001, Double(rank) / 100))
                .stroke(
                    Palette.rankColour(rank),
                    style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text("\(rank)")
                .hawkerNumber(.system(size: size * 0.34, weight: .bold, design: .monospaced))
                .foregroundStyle(Palette.rankColour(rank))
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ghost Rank \(rank) of 100")
    }
}

// MARK: Section header

public struct SectionHeader: View {
    private let title: String
    private let subtitle: String?

    public init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Typography.heading)
                .foregroundStyle(.white)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Palette.ghost.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Empty and error states

/// Honest empty states. The plan is explicit: if an API returns nothing, say so.
/// Never a spinner on a blank screen, and never a fabricated placeholder record.
public struct HawkerEmptyState: View {
    private let symbol: String
    private let title: String
    private let message: String
    private let retry: (@Sendable () -> Void)?

    public init(symbol: String = "tray", title: String, message: String, retry: (@Sendable () -> Void)? = nil) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.retry = retry
    }

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.ghost.opacity(0.5))
            Text(title)
                .font(Typography.heading)
                .foregroundStyle(Palette.ghost)
            Text(message)
                .font(.callout)
                .foregroundStyle(Palette.ghost.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let retry {
                Button("Try again") { retry() }
                    .buttonStyle(.bordered)
                    .tint(Palette.accent)
            }
        }
        .padding(28)
        .frame(maxWidth: 420)
    }
}

// MARK: Background

public struct HawkerBackground: View {
    public init() {}
    public var body: some View {
        #if os(visionOS)
        Color.clear
        #else
        Palette.void.ignoresSafeArea()
        #endif
    }
}
