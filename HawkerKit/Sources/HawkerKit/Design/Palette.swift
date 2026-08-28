import SwiftUI

/// "Neon Autopsy": dark, glassy, thin neon strokes, monospaced numerals.
///
/// The cause-of-death colours are the app's semantic constant. The same magenta means
/// "died of business" in a chart, a chip, a table row and a glowing molecule, on every
/// platform. Nothing else in the app may use them.
public enum Palette {
    // Ground and chrome.
    public static let void        = Color(hex: 0x05070F)
    public static let slab        = Color(hex: 0x0E1428)
    public static let navy        = Color(hex: 0x1C244B)
    public static let accent      = Color(hex: 0x467FF7)
    public static let neon        = Color(hex: 0x4EF0FF)
    public static let ghost       = Color(hex: 0xB6C6E8)

    // Cause-of-death scale.
    public static let hazard      = Color(hex: 0xFF4D5E)
    public static let amberDeath  = Color(hex: 0xFFAE43)
    public static let violetDeath = Color(hex: 0xB57BFF)
    public static let tealDeath   = Color(hex: 0x2FE0C0)
    public static let magenta     = Color(hex: 0xFF5CD8)
    public static let slate       = Color(hex: 0x64748B)

    public static func colour(for cause: CauseOfDeath) -> Color {
        switch cause {
        case .safetyMechanistic: hazard
        case .efficacyFutility:  amberDeath
        case .pkAdmet:           violetDeath
        case .enrolment:         tealDeath
        case .businessStrategic: magenta
        case .funding:           magenta
        case .operational:       slate
        case .unknown:           slate
        }
    }

    /// Ghost Rank ramp: cold at the bottom, neon at the top. Deliberately not the
    /// cause scale, so a high rank never reads as a cause.
    public static func rankColour(_ rank: Int) -> Color {
        switch rank {
        case ..<25: slate
        case ..<45: accent.opacity(0.75)
        case ..<65: accent
        case ..<80: neon.opacity(0.85)
        default:    neon
        }
    }

    /// Same hue as `colour(for:)` but legible as a fill behind text.
    public static func wash(for cause: CauseOfDeath) -> Color {
        colour(for: cause).opacity(0.16)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >>  8) & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: 1
        )
    }
}
