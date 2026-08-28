import Foundation
import Testing
import simd
@testable import HawkerKit

@Suite("Structure parsing and geometry, against a real PDB entry")
struct StructureTests {

    /// 5I9I: Lp-PLA2 with darapladib bound, 2.7 Å. The exact co-crystal the ingest
    /// finds for CHEMBL204021, so the whole join is exercised on one real case.
    func loadStructure() throws -> MMCIFParser.Structure {
        MMCIFParser().parse(try Fixture.text("5I9I.cif"))
    }

    @Test("mmCIF atom_site parses, with ATOM and HETATM both present")
    func parsesAtoms() throws {
        let s = try loadStructure()
        #expect(s.entryId == "5I9I")
        // The file holds 5,649 atom_site rows; alternate conformers beyond A are dropped.
        #expect(s.atoms.count > 5_000)
        // The trap this guards: slicing the record type by fixed column drops every
        // ATOM while HETATM matches by luck, so both counts must be non-trivial.
        #expect(s.polymerAtoms.count > 4_000)
        #expect(s.hetatmAtoms.count > 50)
        #expect(s.atoms.allSatisfy { !$0.element.isEmpty })
    }

    @Test("Darapladib is found as the ligand, by its chemical component id")
    func findsLigand() throws {
        let s = try loadStructure()
        let ligand = try #require(s.ligand(ccd: "5HV"))
        #expect(ligand.compId == "5HV")
        // Darapladib is C36H38F4N3O2S: 46 non-hydrogen atoms, and crystal structures
        // at 2.7 Å do not resolve hydrogens.
        #expect(ligand.atoms.count >= 40)
        #expect(ligand.atoms.count <= 60)
    }

    @Test("Waters and buffer components are not mistaken for the ligand")
    func ignoresSolvent() throws {
        let s = try loadStructure()
        let groups = s.ligandGroups()
        #expect(!groups.contains { MMCIFParser.ignoredComponents.contains($0.compId) })
        // The largest group should be the real ligand, not a cluster of waters.
        #expect(groups.first?.compId == "5HV")
    }

    @Test("The 5 Å pocket around darapladib is a sensible size and sorted by distance")
    func findsPocket() throws {
        let s = try loadStructure()
        let ligand = try #require(s.ligand(ccd: "5HV"))
        let pocket = PocketFinder().pocket(ligand: ligand.atoms, polymer: s.polymerAtoms)

        // A 46-atom ligand in a real pocket lines up roughly 20 to 45 residues at 5 Å.
        #expect(pocket.count >= 15)
        #expect(pocket.count <= 60)
        // Every reported residue must actually be inside the cutoff.
        #expect(pocket.allSatisfy { $0.minDistance <= Double(PocketFinder.defaultCutoff) + 0.001 })
        #expect(pocket.allSatisfy { $0.contactCount >= 1 })
        // Sorted nearest first, because that ordering drives the UI list.
        #expect(pocket == pocket.sorted { $0.minDistance < $1.minDistance })
        // Lp-PLA2's catalytic serine should line a pocket that holds its own inhibitor.
        #expect(pocket.contains { $0.compId == "SER" })
    }

    @Test("The grid finds exactly what a brute-force scan finds")
    func gridMatchesBruteForce() throws {
        let s = try loadStructure()
        let ligand = try #require(s.ligand(ccd: "5HV"))
        let polymer = s.polymerAtoms
        let cutoff = PocketFinder.defaultCutoff

        let fromGrid = Set(PocketFinder().pocket(ligand: ligand.atoms, polymer: polymer).map(\.id))

        // The scan the grid exists to avoid, run once here so the optimisation is
        // checked against ground truth rather than trusted.
        var brute = Set<String>()
        for l in ligand.atoms {
            for p in polymer where simd_distance(l.position, p.position) <= cutoff {
                brute.insert(PocketResidue(chainId: p.chainId, seqId: p.residueNumber,
                                           compId: p.compId, minDistance: 0, contactCount: 1).id)
            }
        }
        #expect(fromGrid == brute)
    }

    @Test("Kabsch recovers a known rotation exactly")
    func kabschRecoversRotation() throws {
        let s = try loadStructure()
        let ca = s.polymerAtoms.filter { $0.atomName == "CA" }.prefix(120).map(\.position)
        #expect(ca.count == 120)

        // Rotate 37 degrees about a tilted axis and translate, then recover it.
        let axis = simd_normalize(SIMD3<Float>(0.3, 0.8, 0.5))
        let q = simd_quatf(angle: .pi * 37 / 180, axis: axis)
        let shift = SIMD3<Float>(12, -5, 3)
        let moved = ca.map { q.act($0) + shift }

        let alignment = try #require(Kabsch.superpose(mobile: moved, reference: Array(ca)))
        // A pure rigid transform must come back at essentially zero RMSD.
        #expect(alignment.rmsd < 0.001)
        #expect(alignment.pairCount == 120)

        let restored = alignment.transform(moved)
        for (a, b) in zip(restored, ca) {
            #expect(simd_distance(a, b) < 0.01)
        }
    }

    @Test("Kabsch does not accept a mirror image as a fit")
    func kabschRejectsReflection() throws {
        let s = try loadStructure()
        let ca = s.polymerAtoms.filter { $0.atomName == "CA" }.prefix(80).map(\.position)
        // Reflect through the xy plane. A reflection is not a rotation, so a correct
        // implementation must NOT report a near-zero RMSD here.
        let mirrored = ca.map { SIMD3<Float>($0.x, $0.y, -$0.z) }
        let alignment = try #require(Kabsch.superpose(mobile: mirrored, reference: Array(ca)))
        #expect(alignment.rmsd > 1.0)
    }

    @Test("PubChem 3D SDF parses with its bonds")
    func parsesSDF() throws {
        let molecule = try #require(SDFParser().parse(try Fixture.text("pubchem_3d.sdf")))
        // The counts line says 85 atoms, 89 bonds.
        #expect(molecule.atoms.count == 85)
        #expect(molecule.bonds.count == 89)
        #expect(molecule.bonds.allSatisfy { $0.a >= 0 && $0.a < 85 && $0.b >= 0 && $0.b < 85 })
        #expect(molecule.bonds.contains { $0.order == 2 })
        // Darapladib carries four fluorines and one sulfur.
        #expect(molecule.atoms.filter { $0.element == "F" }.count == 4)
        #expect(molecule.atoms.filter { $0.element == "S" }.count == 1)
        // Real 3D coordinates, not a flat 2D depiction.
        let zs = molecule.atoms.map(\.position.z)
        #expect((zs.max()! - zs.min()!) > 1.0)
    }
}
