import SwiftUI

/// SF Pro for prose, SF Mono for every number.
///
/// Numerals are monospaced throughout, not for style but because a table of Ghost
/// Ranks and Angstrom distances that reflows as values animate is unreadable.
public enum Typography {
    public static let display = Font.system(.largeTitle, design: .default, weight: .semibold)
    public static let title   = Font.system(.title2, design: .default, weight: .semibold)
    public static let heading = Font.system(.headline, design: .default, weight: .semibold)
    public static let body    = Font.system(.body, design: .default)
    public static let caption = Font.system(.caption, design: .default)

    /// Every number in the app.
    public static let number      = Font.system(.body, design: .monospaced).monospacedDigit()
    public static let numberSmall = Font.system(.caption, design: .monospaced).monospacedDigit()
    public static let numberLarge = Font.system(.title, design: .monospaced, weight: .semibold).monospacedDigit()
    /// Ghost Rank in a ring.
    public static let rank        = Font.system(.title3, design: .monospaced, weight: .bold).monospacedDigit()
}

public extension View {
    /// Anything that animates must not reflow while it does.
    func hawkerNumber(_ font: Font = Typography.number) -> some View {
        self.font(font).monospacedDigit()
    }
}
