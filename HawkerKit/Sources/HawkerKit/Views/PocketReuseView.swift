import SwiftUI
import simd


// Not built for watchOS. The watch shows data and scores only (see WatchRootView):
// no 3D, no charts and no filter UI, so this view's platform-specific controls would
// only be a worse version of the phone app on a smaller screen.
#if !os(watchOS)

/// Tab 5. Target-centric: every clinical ligand that ever bound this target, in one
/// superposed frame, coloured by how each one died.
///
/// This is where an abandoned chemotype sitting next to a successful one stops being
/// two rows in a table and becomes one picture.
public struct PocketReuseView: View {
    @Environment(HawkerStore.self) private var store
    @Environment(Router.self) private var router

    private let fixedTargetId: String?
    @State private var selectedTargetId: String?
    @State private var superposition: Superposition?
    @State private var loading = false
    @State private var note: String?

    public init(targetId: String? = nil) {
        self.fixedTargetId = targetId
        _selectedTargetId = State(initialValue: targetId)
    }

    /// Targets with more than one dead asset are the only ones this view can say
    /// anything about, so they are what it offers.
    private var candidates: [(target: TargetRecord, assets: [Asset])] {
        Dictionary(grouping: store.assets.compactMap { asset -> (String, Asset)? in
            guard let id = asset.target?.chemblId else { return nil }
            return (id, asset)
        }, by: \.0)
        .compactMap { _, pairs in
            guard let target = pairs.first?.1.target else { return nil }
            return (target, pairs.map(\.1).sorted { $0.ghostRank > $1.ghostRank })
        }
        .filter { $0.assets.count >= 2 }
        .sorted { $0.assets.count > $1.assets.count }
    }

    private var active: (target: TargetRecord, assets: [Asset])? {
        guard let id = selectedTargetId else { return candidates.first }
        return candidates.first { $0.target.chemblId == id }
            ?? store.assets.first { $0.target?.chemblId == id }.flatMap { asset in
                asset.target.map { ($0, store.assets(forTarget: id)) }
            }
    }

    public var body: some View {
        ZStack {
            HawkerBackground()
            if store.isLoading, case .loading(let p) = store.state {
                IngestProgressView(progress: p)
            } else if candidates.isEmpty && active == nil {
                HawkerEmptyState(
                    symbol: "cube.transparent",
                    title: "No target has two dead assets yet",
                    message: "Pocket Reuse compares clinical ligands that bound the same target. It needs at least two, and the working set does not have a target with two yet."
                )
            } else if let active {
                content(active)
            }
        }
        .navigationTitle(HawkerTab.pockets.title)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private func content(_ active: (target: TargetRecord, assets: [Asset])) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if fixedTargetId == nil { picker }
                header(active)
                superposedScene(active)
                ligandTable(active)
                heatmap(active)
            }
            .padding(14)
        }
        .task(id: active.target.chemblId) { await superpose(active) }
    }

    private var picker: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader("Targets with more than one dead asset")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(candidates.prefix(24), id: \.target.chemblId) { entry in
                            Button { selectedTargetId = entry.target.chemblId } label: {
                                VStack(spacing: 2) {
                                    Text(entry.target.displayName)
                                        .font(.caption).fontWeight(.medium)
                                    Text("\(entry.assets.count)")
                                        .hawkerNumber(Typography.numberSmall)
                                }
                                .foregroundStyle(selectedTargetId == entry.target.chemblId ? Palette.void : Palette.neon)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Capsule().fill(
                                    selectedTargetId == entry.target.chemblId ? Palette.neon : Palette.neon.opacity(0.14)
                                ))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func header(_ active: (target: TargetRecord, assets: [Asset])) -> some View {
        GlassPanel(tint: Palette.accent) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(active.target.displayName, subtitle: active.target.prefName)
                HStack(spacing: 6) {
                    Chip(text: active.target.family.label, colour: Palette.accent)
                    if let accession = active.target.uniprotAccession {
                        Chip(text: accession, colour: Palette.neon, symbol: "link")
                    }
                    Chip(text: "\(active.assets.count) dead assets", colour: Palette.magenta)
                }
                if !active.target.tractabilitySM.isEmpty {
                    Text(active.target.tractabilitySM.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(Palette.ghost.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func superposedScene(_ active: (target: TargetRecord, assets: [Asset])) -> some View {
        GlassPanel(tint: Palette.neon) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(
                    "Superposed pockets",
                    subtitle: superposition.map { s in
                        "\(s.entries.count) co-crystals aligned on \(s.pairCount) pocket CA atoms. Ligands coloured by how each asset died."
                    } ?? "Aligning co-crystals on their shared pocket residues."
                )
                if loading {
                    HStack(spacing: 8) {
                        ProgressView().tint(Palette.neon)
                        Text("Downloading and superposing structures").font(.caption)
                            .foregroundStyle(Palette.ghost.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                } else if let superposition, !superposition.entries.isEmpty {
                    #if canImport(RealityKit)
                    SuperposedSceneView(superposition: superposition)
                        .frame(height: 340)
                    #endif
                    ForEach(superposition.entries, id: \.pdbId) { entry in
                        HStack(spacing: 8) {
                            Circle().fill(Palette.colour(for: entry.cause)).frame(width: 8, height: 8)
                            Text(entry.pdbId).hawkerNumber(Typography.numberSmall)
                                .foregroundStyle(Palette.neon)
                            Text(entry.assetName).font(.caption)
                                .foregroundStyle(Palette.ghost)
                            Spacer()
                            if let rmsd = entry.rmsdText {
                                Text(rmsd).hawkerNumber(Typography.numberSmall)
                                    .foregroundStyle(Palette.ghost.opacity(0.7))
                            } else {
                                Text("reference").font(.caption2)
                                    .foregroundStyle(Palette.ghost.opacity(0.5))
                            }
                        }
                    }
                } else {
                    Text(note ?? "No two entries share enough pocket residues to superpose.")
                        .font(.callout)
                        .foregroundStyle(Palette.ghost.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func ligandTable(_ active: (target: TargetRecord, assets: [Asset])) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Every clinical ligand against this target")
                ForEach(active.assets) { asset in
                    Button { router.go(.asset(asset.chemblId)) } label: {
                        HStack(spacing: 8) {
                            Circle().fill(Palette.colour(for: asset.cause)).frame(width: 8, height: 8)
                            Text(asset.displayName).font(.caption)
                                .foregroundStyle(Palette.ghost).lineLimit(1)
                            Spacer(minLength: 6)
                            if let ccd = asset.ccdCode {
                                Text(ccd).hawkerNumber(Typography.numberSmall)
                                    .foregroundStyle(Palette.neon.opacity(0.9))
                            }
                            Text(asset.cause.shortLabel).font(.caption2)
                                .foregroundStyle(Palette.colour(for: asset.cause))
                                .frame(width: 74, alignment: .trailing)
                            Text("\(asset.ghostRank)").hawkerNumber(Typography.numberSmall)
                                .foregroundStyle(Palette.rankColour(asset.ghostRank))
                                .frame(width: 30, alignment: .trailing)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Ligand by pocket residue, from the parsed structures.
    @ViewBuilder
    private func heatmap(_ active: (target: TargetRecord, assets: [Asset])) -> some View {
        if let superposition, superposition.entries.count >= 2 {
            let residues = superposition.sharedResidues
            GlassPanel {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(
                        "Contact map",
                        subtitle: "Closest approach in Å between each ligand and each shared pocket residue. Darker is closer."
                    )
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 2) {
                                Text("").frame(width: 62)
                                ForEach(residues, id: \.self) { residue in
                                    Text(residue)
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundStyle(Palette.ghost.opacity(0.7))
                                        .frame(width: 26)
                                }
                            }
                            ForEach(superposition.entries, id: \.pdbId) { entry in
                                HStack(spacing: 2) {
                                    Text(entry.pdbId)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(Palette.colour(for: entry.cause))
                                        .frame(width: 62, alignment: .leading)
                                    ForEach(residues, id: \.self) { residue in
                                        let d = entry.contacts[residue]
                                        Rectangle()
                                            .fill(cellColour(d))
                                            .frame(width: 26, height: 16)
                                            .overlay(
                                                Text(d.map { String(format: "%.1f", $0) } ?? "")
                                                    .font(.system(size: 7, design: .monospaced))
                                                    .foregroundStyle(.white.opacity(0.9))
                                            )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func cellColour(_ distance: Double?) -> Color {
        guard let distance else { return Palette.navy.opacity(0.35) }
        // 3.0 Å is a close contact, 5.0 Å is the shell edge.
        let t = max(0, min(1, (5.0 - distance) / 2.0))
        return Palette.neon.opacity(0.15 + 0.75 * t)
    }

    // MARK: Superposition

    private func superpose(_ active: (target: TargetRecord, assets: [Asset])) async {
        guard superposition?.targetId != active.target.chemblId else { return }
        loading = true
        note = nil
        defer { loading = false }

        // At most six entries: each is a coordinate download, and six colours is
        // already the limit of what can be told apart in one frame.
        var jobs: [(asset: Asset, pdbId: String, ccd: String?)] = []
        for asset in active.assets where asset.hasCoCrystal {
            if let ref = asset.structures.first(where: { !$0.title.isEmpty }) ?? asset.structures.first {
                jobs.append((asset, ref.pdbId, asset.ccdCode))
            }
            if jobs.count >= 6 { break }
        }
        guard jobs.count >= 1 else {
            note = "None of these assets has a co-crystal of its own ligand, so there is nothing to superpose."
            superposition = Superposition(targetId: active.target.chemblId, entries: [], pairCount: 0)
            return
        }

        var loadedStructures: [(Asset, LoadedStructure)] = []
        for job in jobs {
            if let s = try? await StructureLoader.shared.load(pdbId: job.pdbId, ccd: job.ccd) {
                loadedStructures.append((job.asset, s))
            }
        }
        guard let (refAsset, reference) = loadedStructures.first else {
            note = "Could not download coordinates for any of these entries."
            superposition = Superposition(targetId: active.target.chemblId, entries: [], pairCount: 0)
            return
        }

        var entries: [Superposition.Entry] = [Superposition.Entry(
            pdbId: reference.pdbId,
            assetName: refAsset.displayName,
            cause: refAsset.cause,
            rmsd: nil,
            ligandPositions: reference.ligand?.atoms.map(\.position) ?? [],
            ligandElements: reference.ligand?.atoms.map(\.element) ?? [],
            contacts: contactMap(reference)
        )]
        var pairCount = 0

        for (asset, mobile) in loadedStructures.dropFirst() {
            // Correspondence by residue number on CA atoms: the same target solved
            // twice shares its numbering, and matching on it avoids needing an
            // alignment algorithm here.
            let refCA = caByResidue(reference)
            let mobCA = caByResidue(mobile)
            let shared = Set(refCA.keys).intersection(mobCA.keys).sorted()
            guard shared.count >= 4 else { continue }

            let p = shared.compactMap { mobCA[$0] }
            let q = shared.compactMap { refCA[$0] }
            guard let alignment = Kabsch.superpose(mobile: p, reference: q) else { continue }
            pairCount = max(pairCount, alignment.pairCount)

            let moved = (mobile.ligand?.atoms.map(\.position) ?? []).map(alignment.transform)
            entries.append(Superposition.Entry(
                pdbId: mobile.pdbId,
                assetName: asset.displayName,
                cause: asset.cause,
                rmsd: alignment.rmsd,
                ligandPositions: moved,
                ligandElements: mobile.ligand?.atoms.map(\.element) ?? [],
                contacts: contactMap(mobile)
            ))
        }

        superposition = Superposition(
            targetId: active.target.chemblId,
            entries: entries,
            pairCount: pairCount,
            centre: reference.centre
        )
    }

    private func caByResidue(_ s: LoadedStructure) -> [Int: SIMD3<Float>] {
        var out: [Int: SIMD3<Float>] = [:]
        for atom in s.structure.polymerAtoms where atom.atomName == "CA" {
            out[atom.residueNumber] = atom.position
        }
        return out
    }

    private func contactMap(_ s: LoadedStructure) -> [String: Double] {
        Dictionary(s.pocket.map { ($0.displayName, $0.minDistance) }, uniquingKeysWith: min)
    }
}

/// Several co-crystals brought into one frame.
public struct Superposition: Sendable {
    public struct Entry: Sendable {
        public let pdbId: String
        public let assetName: String
        public let cause: CauseOfDeath
        /// Nil for the reference entry.
        public let rmsd: Double?
        public let ligandPositions: [SIMD3<Float>]
        public let ligandElements: [String]
        public let contacts: [String: Double]

        public var rmsdText: String? { rmsd.map { String(format: "%.2f Å", $0) } }
    }

    public let targetId: String
    public let entries: [Entry]
    public let pairCount: Int
    public var centre: SIMD3<Float> = .zero

    /// Residues lined by at least two of the ligands: the columns worth showing.
    public var sharedResidues: [String] {
        var counts: [String: Int] = [:]
        for entry in entries {
            for key in entry.contacts.keys { counts[key, default: 0] += 1 }
        }
        return counts.filter { $0.value >= max(2, entries.count / 2) }
            .keys.sorted { lhs, rhs in
                (Int(lhs.dropFirst().prefix(while: \.isNumber)) ?? 0)
                    < (Int(rhs.dropFirst().prefix(while: \.isNumber)) ?? 0)
            }
            .prefix(30).map { $0 }
    }
}

#if canImport(RealityKit)
import RealityKit

/// Every superposed ligand in one scene, each coloured by how its asset died.
public struct SuperposedSceneView: View {
    private let superposition: Superposition
    @State private var geometry = MoleculeGeometry()
    @State private var yaw: Float = 0
    @State private var pitch: Float = 0
    @State private var dragStart: (Float, Float) = (0, 0)

    public init(superposition: Superposition) { self.superposition = superposition }

    public var body: some View {
        RealityView { content in
            let root = Entity()
            root.name = "superposed"
            for entry in superposition.entries {
                let atoms = zip(entry.ligandElements, entry.ligandPositions).map {
                    SDFParser.Atom(element: $0.0, position: $0.1)
                }
                var bonds: [SDFParser.Bond] = []
                for i in 0..<atoms.count {
                    for j in (i + 1)..<atoms.count
                    where ChemistryTables.areBonded(
                        atoms[i].element, atoms[j].element,
                        distance: simd_distance(atoms[i].position, atoms[j].position)
                    ) {
                        bonds.append(SDFParser.Bond(a: i, b: j, order: 1))
                    }
                }
                // Tinted by cause, so the semantic colour survives into 3D exactly as
                // the design language requires.
                root.addChild(geometry.ligandEntity(
                    atoms: atoms, bonds: bonds,
                    centre: superposition.centre,
                    tint: Palette.colour(for: entry.cause)
                ))
            }
            content.add(root)

            #if !os(visionOS)
            let all = superposition.entries.flatMap(\.ligandPositions)
            let radius = MoleculeGeometry.boundingRadius(of: all, about: superposition.centre)
            let camera = Entity()
            camera.components.set(PerspectiveCameraComponent(near: 0.01, far: 100, fieldOfViewInDegrees: 60))
            camera.position = SIMD3(0, 0, MoleculeGeometry.framingDistance(radius: radius))
            content.add(camera)
            #endif
        } update: { content in
            content.entities.first { $0.name == "superposed" }?.orientation =
                simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0))
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
        #endif
        .accessibilityLabel("\(superposition.entries.count) superposed ligands, coloured by cause of death.")
    }
}
#endif

#endif
