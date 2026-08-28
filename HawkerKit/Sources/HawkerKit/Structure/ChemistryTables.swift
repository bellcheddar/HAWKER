import Foundation
import SwiftUI

/// CPK colours and covalent radii, in Angstrom.
public enum ChemistryTables {

    /// Standard CPK, tuned slightly for a dark ground: carbon is a light grey rather
    /// than black, which is invisible against the void colour.
    public static func colour(for element: String) -> Color {
        switch element.uppercased() {
        case "H":  Color(hex: 0xE8EDF5)
        case "C":  Color(hex: 0x9AA7BF)
        case "N":  Color(hex: 0x4A7DFF)
        case "O":  Color(hex: 0xFF4D5E)
        case "S":  Color(hex: 0xFFD93D)
        case "P":  Color(hex: 0xFF9A3D)
        case "F":  Color(hex: 0x6BFFB8)
        case "CL": Color(hex: 0x4EF0A0)
        case "BR": Color(hex: 0xB5651D)
        case "I":  Color(hex: 0xB57BFF)
        case "SE": Color(hex: 0xFFA100)
        case "FE": Color(hex: 0xE06633)
        case "ZN": Color(hex: 0x7D80B0)
        case "MG": Color(hex: 0x8AFF00)
        case "CA": Color(hex: 0x3DFF00)
        case "NA": Color(hex: 0xAB5CF2)
        case "K":  Color(hex: 0x8F40D4)
        case "MN": Color(hex: 0x9C7AC7)
        case "CU": Color(hex: 0xC88033)
        default:   Color(hex: 0xFF6CF0)
        }
    }

    /// Covalent radius in Angstrom.
    public static func covalentRadius(_ element: String) -> Float {
        switch element.uppercased() {
        case "H": 0.31
        case "C": 0.76
        case "N": 0.71
        case "O": 0.66
        case "F": 0.57
        case "P": 1.07
        case "S": 1.05
        case "CL": 1.02
        case "BR": 1.20
        case "I": 1.39
        case "SE": 1.20
        case "FE": 1.32
        case "ZN": 1.22
        case "MG": 1.41
        case "CA": 1.76
        case "NA": 1.66
        case "K": 2.03
        case "MN": 1.39
        case "CU": 1.32
        default: 1.00
        }
    }

    /// Infer bonds from distance, for polymer atoms where mmCIF gives no connectivity.
    /// Two atoms are bonded when they are closer than the sum of their covalent radii
    /// plus a small tolerance.
    public static func areBonded(_ a: String, _ b: String, distance: Float) -> Bool {
        let limit = covalentRadius(a) + covalentRadius(b) + 0.45
        return distance > 0.4 && distance <= limit
    }
}
