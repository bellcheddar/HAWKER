import Foundation
import simd

/// Residues lining a ligand, found with a uniform grid.
///
/// A full pairwise scan over a 5,600-atom entry against an 85-atom ligand is about
/// half a million distance tests per structure, and Pocket Reuse does this for every
/// co-crystal of a target at once. The grid makes it linear in the ligand's size:
/// bucket the polymer once, then look only in the 27 cells around each ligand atom.
public struct PocketFinder: Sendable {

    /// The plan's definition: a 5.0 Å ligand-proximity shell. This is a shell, not a
    /// computed cavity, which is fine for comparing reuse across entries and is not a
    /// druggability calculation.
    public static let defaultCutoff: Float = 5.0

    public init() {}

    public func pocket(
        ligand: [MMCIFParser.Atom],
        polymer: [MMCIFParser.Atom],
        cutoff: Float = PocketFinder.defaultCutoff
    ) -> [PocketResidue] {
        guard !ligand.isEmpty, !polymer.isEmpty else { return [] }

        let grid = SpatialGrid(atoms: polymer, cellSize: cutoff)
        // Keyed by residue, carrying the closest approach and how many atoms are in range.
        var best: [String: (residue: MMCIFParser.Atom, minSquared: Float, contacts: Int)] = [:]
        let cutoffSquared = cutoff * cutoff

        for atom in ligand {
            for candidate in grid.neighbours(of: atom.position) {
                let d2 = simd_distance_squared(atom.position, candidate.position)
                guard d2 <= cutoffSquared else { continue }
                let key = "\(candidate.chainId)|\(candidate.residueNumber)|\(candidate.compId)"
                if var existing = best[key] {
                    existing.contacts += 1
                    if d2 < existing.minSquared { existing.minSquared = d2 }
                    best[key] = existing
                } else {
                    best[key] = (candidate, d2, 1)
                }
            }
        }

        return best.values
            .map {
                PocketResidue(
                    chainId: $0.residue.chainId,
                    seqId: $0.residue.residueNumber,
                    compId: $0.residue.compId,
                    minDistance: Double(sqrt($0.minSquared)),
                    contactCount: $0.contacts
                )
            }
            .sorted { $0.minDistance < $1.minDistance }
    }

    /// Every polymer atom belonging to the given residues, for rendering.
    public func atoms(
        of residues: [PocketResidue],
        in polymer: [MMCIFParser.Atom]
    ) -> [MMCIFParser.Atom] {
        let keys = Set(residues.map { "\($0.chainId)|\($0.seqId)" })
        return polymer.filter { keys.contains("\($0.chainId)|\($0.residueNumber)") }
    }
}

/// A uniform grid over atom positions. Cell size equals the search radius, so every
/// neighbour within the radius is in one of the 27 surrounding cells.
struct SpatialGrid: Sendable {
    private let cellSize: Float
    private var cells: [SIMD3<Int32>: [MMCIFParser.Atom]] = [:]

    init(atoms: [MMCIFParser.Atom], cellSize: Float) {
        self.cellSize = max(0.5, cellSize)
        for atom in atoms {
            cells[Self.index(atom.position, self.cellSize), default: []].append(atom)
        }
    }

    static func index(_ p: SIMD3<Float>, _ size: Float) -> SIMD3<Int32> {
        SIMD3<Int32>(
            Int32(floor(p.x / size)),
            Int32(floor(p.y / size)),
            Int32(floor(p.z / size))
        )
    }

    func neighbours(of position: SIMD3<Float>) -> [MMCIFParser.Atom] {
        let centre = Self.index(position, cellSize)
        var out: [MMCIFParser.Atom] = []
        for dx in -1...1 {
            for dy in -1...1 {
                for dz in -1...1 {
                    let key = SIMD3<Int32>(centre.x + Int32(dx), centre.y + Int32(dy), centre.z + Int32(dz))
                    if let bucket = cells[key] { out.append(contentsOf: bucket) }
                }
            }
        }
        return out
    }
}
