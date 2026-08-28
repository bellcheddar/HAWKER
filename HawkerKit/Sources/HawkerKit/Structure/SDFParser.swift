import Foundation
import simd

/// PubChem 3D conformer SDF, V2000 connection table.
///
/// V2000 is a fixed-width format and, unlike mmCIF, genuinely is column-oriented: the
/// counts line packs the atom and bond counts into three-character fields with no
/// separator, so "85 89" and "100999" both have to parse. Splitting on whitespace
/// breaks on entries with 100 or more atoms, which is exactly the size of molecule
/// this app cares about.
public struct SDFParser: Sendable {

    public struct Molecule: Sendable {
        public let title: String
        public let atoms: [Atom]
        public let bonds: [Bond]

        public var centroid: SIMD3<Float> {
            guard !atoms.isEmpty else { return .zero }
            return atoms.reduce(SIMD3<Float>.zero) { $0 + $1.position } / Float(atoms.count)
        }
    }

    public struct Atom: Sendable, Hashable {
        public let element: String
        public let position: SIMD3<Float>
    }

    public struct Bond: Sendable, Hashable {
        public let a: Int
        public let b: Int
        /// 1 single, 2 double, 3 triple, 4 aromatic.
        public let order: Int
    }

    public init() {}

    public func parse(_ text: String) -> Molecule? {
        let lines = text.components(separatedBy: .newlines)
        guard lines.count > 4 else { return nil }

        let title = lines[0].trimmingCharacters(in: .whitespaces)
        let counts = lines[3]
        guard counts.count >= 6 else { return nil }

        // Fixed width: atoms in columns 0-2, bonds in 3-5.
        let atomCount = Int(counts.slice(0, 3).trimmingCharacters(in: .whitespaces)) ?? 0
        let bondCount = Int(counts.slice(3, 6).trimmingCharacters(in: .whitespaces)) ?? 0
        guard atomCount > 0, lines.count >= 4 + atomCount + bondCount else { return nil }

        var atoms: [Atom] = []
        atoms.reserveCapacity(atomCount)
        for i in 0..<atomCount {
            let line = lines[4 + i]
            guard line.count >= 34 else { continue }
            guard let x = Float(line.slice(0, 10).trimmingCharacters(in: .whitespaces)),
                  let y = Float(line.slice(10, 20).trimmingCharacters(in: .whitespaces)),
                  let z = Float(line.slice(20, 30).trimmingCharacters(in: .whitespaces))
            else { continue }
            let element = line.slice(31, 34).trimmingCharacters(in: .whitespaces)
            atoms.append(Atom(element: element.isEmpty ? "C" : element, position: SIMD3(x, y, z)))
        }

        var bonds: [Bond] = []
        bonds.reserveCapacity(bondCount)
        for i in 0..<bondCount {
            let line = lines[4 + atomCount + i]
            guard line.count >= 9 else { continue }
            guard let a = Int(line.slice(0, 3).trimmingCharacters(in: .whitespaces)),
                  let b = Int(line.slice(3, 6).trimmingCharacters(in: .whitespaces)),
                  let order = Int(line.slice(6, 9).trimmingCharacters(in: .whitespaces))
            else { continue }
            // SDF indices are 1-based.
            bonds.append(Bond(a: a - 1, b: b - 1, order: order))
        }

        return Molecule(title: title, atoms: atoms, bonds: bonds)
    }
}

extension String {
    /// Half-open character slice, clamped, for fixed-width formats.
    func slice(_ from: Int, _ to: Int) -> String {
        guard from < count else { return "" }
        let start = index(startIndex, offsetBy: from)
        let end = index(startIndex, offsetBy: Swift.min(to, count))
        return String(self[start..<end])
    }
}
