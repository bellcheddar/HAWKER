import SwiftUI


// Not built for watchOS. The watch shows data and scores only (see WatchRootView):
// no 3D, no charts and no filter UI, so this view's platform-specific controls would
// only be a worse version of the phone app on a smaller screen.
#if !os(watchOS)

/// A single PDB entry: the 3D scene, with its pocket residues listed beside it.
///
/// Selection is two-way. Tapping a residue in the list highlights it in the scene,
/// and the plan asks for the reverse too.
public struct StructureDetailView: View {
    private let pdbId: String
    private let ccd: String?

    @State private var loaded: LoadedStructure?
    @State private var error: String?
    @State private var selected: PocketResidue?

    public init(pdbId: String, ccd: String?) {
        self.pdbId = pdbId
        self.ccd = ccd
    }

    public var body: some View {
        ZStack {
            HawkerBackground()
            if let loaded {
                content(loaded)
            } else if let error {
                HawkerEmptyState(
                    symbol: "cube.transparent",
                    title: "Could not load \(pdbId)",
                    message: error
                )
            } else {
                VStack(spacing: 10) {
                    ProgressView().tint(Palette.neon)
                    Text("Downloading \(pdbId) coordinates from the RCSB PDB")
                        .font(.caption)
                        .foregroundStyle(Palette.ghost.opacity(0.75))
                }
            }
        }
        .navigationTitle(pdbId)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: pdbId) { await load() }
    }

    @ViewBuilder
    private func content(_ loaded: LoadedStructure) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                #if canImport(RealityKit)
                GlassPanel(tint: Palette.neon, padding: 0) {
                    MolecularSceneView(loaded: loaded, selectedResidue: $selected)
                        .frame(height: 340)
                }
                #endif

                GlassPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(
                            "Pocket",
                            subtitle: loaded.ligand.map {
                                "\(loaded.pocket.count) residues within 5.0 Å of \($0.compId) (\($0.atoms.count) atoms)."
                            } ?? "No ligand identified in this entry."
                        )
                        ForEach(loaded.pocket) { residue in
                            Button { selected = (selected == residue) ? nil : residue } label: {
                                HStack {
                                    Text(residue.displayName)
                                        .hawkerNumber(Typography.numberSmall)
                                        .foregroundStyle(selected == residue ? Palette.neon : Palette.ghost)
                                    Text(residue.chainId)
                                        .font(.caption2)
                                        .foregroundStyle(Palette.ghost.opacity(0.5))
                                    Spacer()
                                    Text("\(residue.contactCount)")
                                        .hawkerNumber(Typography.numberSmall)
                                        .foregroundStyle(Palette.ghost.opacity(0.55))
                                    Text(residue.distanceText)
                                        .hawkerNumber(Typography.numberSmall)
                                        .foregroundStyle(Palette.accent)
                                        .frame(width: 68, alignment: .trailing)
                                }
                                .padding(.vertical, 2)
                                .background(selected == residue ? Palette.wash(for: .enrolment) : .clear)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    private func load() async {
        guard loaded == nil else { return }
        do {
            loaded = try await StructureLoader.shared.load(pdbId: pdbId, ccd: ccd)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#endif
