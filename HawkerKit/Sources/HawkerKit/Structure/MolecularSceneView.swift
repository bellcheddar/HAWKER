import SwiftUI
import simd
#if canImport(RealityKit)
import RealityKit
#endif


// Not built for watchOS. The watch shows data and scores only (see WatchRootView):
// no 3D, no charts and no filter UI, so this view's platform-specific controls would
// only be a worse version of the phone app on a smaller screen.
#if !os(watchOS)

/// A loaded structure with everything the views need, computed once.
public struct LoadedStructure: Sendable {
    public let pdbId: String
    public let structure: MMCIFParser.Structure
    public let ligand: MMCIFParser.LigandGroup?
    public let pocket: [PocketResidue]
    public let pocketAtoms: [MMCIFParser.Atom]

    public var centre: SIMD3<Float> { ligand?.centroid ?? .zero }
}

/// Loads and prepares structures off the main actor.
public actor StructureLoader {
    public static let shared = StructureLoader()

    private let rcsb = RCSBClient()
    private let parser = MMCIFParser()
    private let finder = PocketFinder()
    private var cache: [String: LoadedStructure] = [:]

    public init() {}

    public func load(pdbId: String, ccd: String?) async throws -> LoadedStructure {
        let key = "\(pdbId)|\(ccd ?? "-")"
        if let hit = cache[key] { return hit }

        let data = try await rcsb.coordinates(pdbId: pdbId)
        let structure = parser.parse(String(decoding: data, as: UTF8.self))

        // Prefer the ligand we came for; fall back to the largest non-solvent group.
        let ligand = ccd.flatMap { structure.ligand(ccd: $0) } ?? structure.ligandGroups().first
        let pocket = ligand.map { finder.pocket(ligand: $0.atoms, polymer: structure.polymerAtoms) } ?? []
        let atoms = finder.atoms(of: pocket, in: structure.polymerAtoms)

        let loaded = LoadedStructure(
            pdbId: pdbId, structure: structure, ligand: ligand,
            pocket: pocket, pocketAtoms: atoms
        )
        cache[key] = loaded
        return loaded
    }
}

#if canImport(RealityKit)
/// The one 3D scene, shared by every platform that has one.
///
/// iOS, iPadOS and macOS drive an orbit camera from drag and magnify gestures.
/// visionOS relies on the system's own manipulation, so the gestures are not attached
/// there: adding them fights the platform rather than helping it.
public struct MolecularSceneView: View {
    private let loaded: LoadedStructure
    @Binding private var selectedResidue: PocketResidue?
    private let showPocket: Bool

    @State private var geometry = MoleculeGeometry()
    @State private var yaw: Float = 0
    @State private var pitch: Float = 0
    @State private var zoom: Float = 1
    @State private var dragStart: (Float, Float) = (0, 0)
    @State private var zoomStart: Float = 1

    public init(
        loaded: LoadedStructure,
        selectedResidue: Binding<PocketResidue?> = .constant(nil),
        showPocket: Bool = true
    ) {
        self.loaded = loaded
        _selectedResidue = selectedResidue
        self.showPocket = showPocket
    }

    public var body: some View {
        RealityView { content in
            let root = Entity()
            root.name = "root"
            content.add(root)
            rebuild(root)

            // An explicit camera, placed from the content's own extent. Without one
            // the default camera sits wherever it likes and the molecule is a speck.
            #if !os(visionOS)
            let camera = Entity()
            camera.components.set(PerspectiveCameraComponent(near: 0.01, far: 100, fieldOfViewInDegrees: 60))
            camera.position = SIMD3(0, 0, framingDistance)
            camera.name = "camera"
            content.add(camera)
            #endif
        } update: { content in
            guard let root = content.entities.first(where: { $0.name == "root" }) else { return }
            root.orientation = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
                * simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0))
            root.scale = SIMD3(repeating: zoom)
        }
        #if !os(visionOS)
        .gesture(
            DragGesture()
                .onChanged { value in
                    yaw = dragStart.0 + Float(value.translation.width) * 0.01
                    pitch = dragStart.1 + Float(value.translation.height) * 0.01
                }
                .onEnded { _ in dragStart = (yaw, pitch) }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { zoom = max(0.3, min(4, zoomStart * Float($0.magnification))) }
                .onEnded { _ in zoomStart = zoom }
        )
        #endif
        .accessibilityLabel(accessibilityDescription)
    }

    /// Distance that frames the ligand and its pocket together.
    private var framingDistance: Float {
        var points = loaded.ligand?.atoms.map(\.position) ?? []
        if showPocket { points += loaded.pocketAtoms.map(\.position) }
        guard !points.isEmpty else { return 0.6 }
        let radius = MoleculeGeometry.boundingRadius(of: points, about: loaded.centre)
        return MoleculeGeometry.framingDistance(radius: radius)
    }

    private func rebuild(_ root: Entity) {
        root.children.removeAll()
        let centre = loaded.centre

        if let ligand = loaded.ligand {
            // mmCIF gives no connectivity, so ligand bonds are inferred by distance
            // exactly as the pocket's are.
            let atoms = ligand.atoms.map { SDFParser.Atom(element: $0.element, position: $0.position) }
            var bonds: [SDFParser.Bond] = []
            for i in 0..<atoms.count {
                for j in (i + 1)..<atoms.count {
                    let d = simd_distance(atoms[i].position, atoms[j].position)
                    if ChemistryTables.areBonded(atoms[i].element, atoms[j].element, distance: d) {
                        bonds.append(SDFParser.Bond(a: i, b: j, order: 1))
                    }
                }
            }
            root.addChild(geometry.ligandEntity(atoms: atoms, bonds: bonds, centre: centre))
        }

        if showPocket, !loaded.pocketAtoms.isEmpty {
            root.addChild(geometry.pocketEntity(atoms: loaded.pocketAtoms, centre: centre, ghosted: true))
        }
    }

    private var accessibilityDescription: String {
        let ligand = loaded.ligand.map { "\($0.compId), \($0.atoms.count) atoms" } ?? "no ligand"
        return "Three-dimensional structure \(loaded.pdbId): \(ligand), pocket of \(loaded.pocket.count) residues."
    }
}
#endif

#endif
