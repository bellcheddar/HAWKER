import Foundation
import simd
#if canImport(RealityKit)
import RealityKit
#endif
import SwiftUI

/// Builds RealityKit entities for ligands and pockets.
///
/// Two rules from the build plan drive the whole design and both are about not
/// generating a mesh per atom: one sphere mesh and one cylinder mesh are created once
/// and reused with many transforms, and materials are cached per element. A 3,000-atom
/// pocket built the naive way generates 3,000 meshes and drops frames on a phone; this
/// way it is two meshes and 3,000 transforms.
#if canImport(RealityKit)
@MainActor
public final class MoleculeGeometry {

    /// World scale. Structures are in Angstrom; RealityKit wants metres, and 0.02 puts
    /// a typical drug-sized ligand at a comfortable size on a desk or in a window.
    public static let scale: Float = 0.02

    private var sphere: MeshResource
    private var cylinder: MeshResource
    private var materials: [String: RealityKit.Material] = [:]

    public init() {
        sphere = .generateSphere(radius: 1)
        cylinder = .generateCylinder(height: 1, radius: 1)
    }

    // MARK: Ligand, ball and stick

    public func ligandEntity(
        atoms: [SDFParser.Atom],
        bonds: [SDFParser.Bond],
        centre: SIMD3<Float>? = nil,
        tint: Color? = nil
    ) -> Entity {
        let root = Entity()
        let origin = centre ?? centroid(atoms.map(\.position))

        for atom in atoms {
            let node = ModelEntity(mesh: sphere, materials: [material(for: atom.element, tint: tint)])
            // Ball and stick: a quarter of the covalent radius, so bonds read clearly.
            let r = ChemistryTables.covalentRadius(atom.element) * 0.25 * Self.scale
            node.scale = SIMD3(repeating: r)
            node.position = (atom.position - origin) * Self.scale
            root.addChild(node)
        }

        for bond in bonds {
            guard bond.a < atoms.count, bond.b < atoms.count else { continue }
            let a = (atoms[bond.a].position - origin) * Self.scale
            let b = (atoms[bond.b].position - origin) * Self.scale
            let element = atoms[bond.a].element
            if bond.order >= 2 {
                // Offset pair for a double bond, in a plane perpendicular to the bond.
                let offset = perpendicular(b - a) * (0.035 * Self.scale * 10)
                root.addChild(bondEntity(a - offset, b - offset, element: element, tint: tint))
                root.addChild(bondEntity(a + offset, b + offset, element: element, tint: tint))
            } else {
                root.addChild(bondEntity(a, b, element: element, tint: tint))
            }
        }
        return root
    }

    // MARK: Pocket, licorice plus backbone tube

    public func pocketEntity(
        atoms: [MMCIFParser.Atom],
        centre: SIMD3<Float>,
        ghosted: Bool = false
    ) -> Entity {
        let root = Entity()
        let opacity: Float = ghosted ? 0.28 : 1.0

        // Side-chain atoms as licorice: small spheres plus inferred bonds.
        let sideChain = atoms.filter { !["N", "C", "O"].contains($0.atomName) || $0.atomName == "CA" }
        for atom in sideChain {
            let node = ModelEntity(mesh: sphere, materials: [material(for: atom.element, opacity: opacity)])
            node.scale = SIMD3(repeating: 0.18 * Self.scale)
            node.position = (atom.position - centre) * Self.scale
            root.addChild(node)
        }

        // Connectivity is not in the atom_site loop, so bonds are inferred by distance.
        // A grid keeps this linear rather than quadratic over the pocket.
        let grid = SpatialGrid(atoms: sideChain, cellSize: 2.0)
        var drawn = Set<Int64>()
        for atom in sideChain {
            for other in grid.neighbours(of: atom.position) where other.serial != atom.serial {
                let key = Int64(min(atom.serial, other.serial)) << 32 | Int64(max(atom.serial, other.serial))
                guard !drawn.contains(key) else { continue }
                let d = simd_distance(atom.position, other.position)
                guard ChemistryTables.areBonded(atom.element, other.element, distance: d) else { continue }
                drawn.insert(key)
                root.addChild(bondEntity(
                    (atom.position - centre) * Self.scale,
                    (other.position - centre) * Self.scale,
                    element: atom.element, radius: 0.09, opacity: opacity
                ))
            }
        }

        // Backbone tube through the CA trace.
        let ca = atoms.filter { $0.atomName == "CA" }.sorted {
            ($0.chainId, $0.residueNumber) < ($1.chainId, $1.residueNumber)
        }
        if ca.count >= 4 {
            let spline = TubeBuilder.catmullRom(ca.map(\.position), segmentsPerSpan: 8)
            for i in 0..<(spline.count - 1) {
                root.addChild(bondEntity(
                    (spline[i] - centre) * Self.scale,
                    (spline[i + 1] - centre) * Self.scale,
                    element: "TUBE", radius: 0.22, opacity: opacity
                ))
            }
        }
        return root
    }

    // MARK: Primitives

    private func bondEntity(
        _ a: SIMD3<Float>, _ b: SIMD3<Float>,
        element: String, radius: Float = 0.11, tint: Color? = nil, opacity: Float = 1
    ) -> Entity {
        let node = ModelEntity(mesh: cylinder, materials: [material(for: element, tint: tint, opacity: opacity)])
        let delta = b - a
        let length = simd_length(delta)
        guard length > 1e-6 else { return node }
        node.scale = SIMD3(radius * Self.scale, length, radius * Self.scale)
        node.position = (a + b) / 2
        // generateCylinder points along +Y, so rotate that onto the bond vector.
        node.orientation = simd_quatf(from: SIMD3(0, 1, 0), to: delta / length)
        return node
    }

    private func material(for element: String, tint: Color? = nil, opacity: Float = 1) -> RealityKit.Material {
        let key = "\(element)|\(tint.map { "\($0)" } ?? "-")|\(opacity)"
        if let cached = materials[key] { return cached }

        let base: Color = tint ?? (element == "TUBE" ? Palette.accent : ChemistryTables.colour(for: element))
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: PlatformColor(base))
        material.roughness = 0.35
        material.metallic = 0.1
        // The neon rim the design language asks for, without a custom shader.
        material.emissiveColor = .init(color: PlatformColor(base))
        material.emissiveIntensity = element == "TUBE" ? 0.15 : 0.35
        if opacity < 1 {
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        }
        let resolved: RealityKit.Material = material
        materials[key] = resolved
        return resolved
    }

    private func centroid(_ points: [SIMD3<Float>]) -> SIMD3<Float> {
        guard !points.isEmpty else { return .zero }
        return points.reduce(SIMD3<Float>.zero, +) / Float(points.count)
    }

    private func perpendicular(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let reference = abs(v.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
        return simd_normalize(simd_cross(v, reference))
    }
}

#if canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
typealias PlatformColor = NSColor
#endif
#endif

/// Catmull-Rom spline through the CA trace.
public enum TubeBuilder {
    /// Interpolates a smooth curve through every control point, which is what makes a
    /// backbone read as a backbone rather than a polyline of straight segments.
    public static func catmullRom(_ points: [SIMD3<Float>], segmentsPerSpan: Int = 8) -> [SIMD3<Float>] {
        guard points.count >= 2 else { return points }
        guard points.count >= 4 else { return points }

        var out: [SIMD3<Float>] = []
        out.reserveCapacity((points.count - 1) * segmentsPerSpan)

        for i in 0..<(points.count - 1) {
            let p0 = points[max(0, i - 1)]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = points[min(points.count - 1, i + 2)]

            // A long gap means a chain break, not a bond. Drawing through it would
            // paint a tube across empty space.
            if simd_distance(p1, p2) > 5.0 {
                out.append(p1)
                continue
            }

            for s in 0..<segmentsPerSpan {
                let t = Float(s) / Float(segmentsPerSpan)
                let t2 = t * t
                let t3 = t2 * t
                // Broken out term by term: as one expression the type checker gives up.
                let a: SIMD3<Float> = p1 * 2
                let b: SIMD3<Float> = (p2 - p0) * t
                let c: SIMD3<Float> = (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2
                let d: SIMD3<Float> = (p1 * 3 - p0 - p2 * 3 + p3) * t3
                out.append((a + b + c + d) * 0.5)
            }
        }
        out.append(points[points.count - 1])
        return out
    }
}
