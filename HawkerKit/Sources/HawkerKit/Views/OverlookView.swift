import SwiftUI
import simd
#if canImport(RealityKit)
import RealityKit
#endif


// Not built for watchOS. The watch shows data and scores only (see WatchRootView):
// no 3D, no charts and no filter UI, so this view's platform-specific controls would
// only be a worse version of the phone app on a smaller screen.
#if !os(watchOS)

/// Tab 6. The whole graveyard as one spatial console.
///
/// One scene, three presentations: a volumetric window and an ImmersiveSpace on
/// visionOS, and the same RealityKit scene under a 2D glass HUD everywhere else.
public struct OverlookView: View {
    @Environment(HawkerStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: Asset?

    public init() {}

    public var body: some View {
        ZStack {
            HawkerBackground()
            if store.isLoading, case .loading(let p) = store.state {
                IngestProgressView(progress: p)
            } else if store.assets.isEmpty {
                HawkerEmptyState(
                    symbol: "sparkles.rectangle.stack",
                    title: "Nothing to look over yet",
                    message: "The Overlook plots the whole working set at once."
                )
            } else {
                console
            }
        }
        .navigationTitle(HawkerTab.overlook.title)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var console: some View {
        GeometryReader { geo in
            ZStack {
                #if canImport(RealityKit)
                GraveyardCloudView(
                    assets: store.assets,
                    selected: $selected,
                    idleMotion: !reduceMotion
                )
                #endif
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let selected {
                            selectedPanel(selected)
                        }
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 230, maximum: 340), spacing: 10)],
                            spacing: 10
                        ) {
                            ForEach(findings, id: \.title) { finding in
                                Button { finding.action(router) } label: {
                                    FindingPanel(finding: finding)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        axesLegend
                    }
                    .padding(14)
                    .frame(maxWidth: geo.size.width > 900 ? 900 : .infinity)
                }
            }
        }
    }

    private func selectedPanel(_ asset: Asset) -> some View {
        GlassPanel(tint: Palette.colour(for: asset.cause)) {
            HStack(alignment: .top, spacing: 12) {
                GhostRankRing(rank: asset.ghostRank, size: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text(asset.displayName).font(Typography.heading).foregroundStyle(.white)
                    if let target = asset.target {
                        Text(target.displayName).font(.caption).foregroundStyle(Palette.accent)
                    }
                    CauseBadge(asset.cause, confidence: asset.verdict.confidence, compact: true)
                }
                Spacer()
                Button("Post Mortem") { router.go(.asset(asset.chemblId)) }
                    .buttonStyle(.bordered)
                    .tint(Palette.neon)
            }
        }
    }

    private var axesLegend: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader("How to read the cloud")
                legendRow("x", "Year of death")
                legendRow("y", "Structural tractability")
                legendRow("z", "Ghost Rank")
                legendRow("colour", "Cause of death")
                legendRow("size", "Phase reached")
            }
        }
    }

    private func legendRow(_ axis: String, _ meaning: String) -> some View {
        HStack(spacing: 8) {
            Text(axis).hawkerNumber(Typography.numberSmall).foregroundStyle(Palette.neon).frame(width: 46, alignment: .leading)
            Text(meaning).font(.caption).foregroundStyle(Palette.ghost.opacity(0.8))
        }
    }

    // MARK: The six headline findings

    struct Finding: Sendable {
        let title: String
        let value: String
        let detail: String
        let tint: Color
        let action: @MainActor @Sendable (Router) -> Void
    }

    private var findings: [Finding] {
        let assets = store.assets
        let classified = assets.filter { $0.cause != .unknown }
        let business = classified.filter { !$0.cause.isMechanistic }

        var out: [Finding] = []

        out.append(Finding(
            title: "Business, not biology",
            value: classified.isEmpty ? "-" : String(format: "%.0f%%", 100 * Double(business.count) / Double(classified.count)),
            detail: "of \(classified.count) classified assets died for reasons that say nothing about the molecule",
            tint: Palette.magenta,
            action: { $0.go(.graveyard(.causeByYear)) }
        ))

        if let top = assets.filter({ !$0.cause.isMechanistic && $0.cause != .unknown }).max(by: { $0.ghostRank < $1.ghostRank }) {
            out.append(Finding(
                title: "Top reclaimable asset",
                value: top.displayName,
                detail: "Ghost Rank \(top.ghostRank), \(top.cause.label.lowercased())",
                tint: Palette.neon,
                action: { $0.go(.asset(top.chemblId)) }
            ))
        }

        let byTarget = Dictionary(grouping: assets.compactMap { a in a.target.map { ($0.chemblId, a) } }, by: \.0)
        if let (targetId, group) = byTarget.max(by: { $0.value.count < $1.value.count }),
           let target = group.first?.1.target {
            out.append(Finding(
                title: "Most reused pocket",
                value: target.displayName,
                detail: "\(group.count) dead clinical assets against one target",
                tint: Palette.accent,
                action: { $0.go(.target(targetId)) }
            ))
        }

        if let widest = assets.max(by: { $0.score.biologicalWhitespace < $1.score.biologicalWhitespace }),
           let association = widest.whitespaceAssociation {
            out.append(Finding(
                title: "Biggest whitespace",
                value: association.diseaseName,
                detail: "\(widest.displayName), genetic evidence \(String(format: "%.2f", association.geneticScore)), never tried there",
                tint: Palette.tealDeath,
                action: { $0.go(.asset(widest.chemblId)) }
            ))
        }

        if let oldest = assets.filter({ $0.ftoLapsedEstimate }).min(by: { ($0.estimatedFTOYear ?? 9999) < ($1.estimatedFTOYear ?? 9999) }) {
            out.append(Finding(
                title: "Oldest lapsed (estimate)",
                value: oldest.displayName,
                detail: "estimated horizon \(oldest.estimatedFTOYear.map(String.init) ?? "-"): an estimate from public dates, not a freedom-to-operate opinion",
                tint: Palette.amberDeath,
                action: { $0.go(.asset(oldest.chemblId)) }
            ))
        }

        let byFamily = Dictionary(grouping: classified.compactMap { a in a.target.map { ($0.family, a) } }, by: \.0)
        let deadliest = byFamily
            .filter { $0.value.count >= 3 }
            .max { lhs, rhs in
                let l = Double(lhs.value.filter { $0.1.cause.isMechanistic }.count) / Double(lhs.value.count)
                let r = Double(rhs.value.filter { $0.1.cause.isMechanistic }.count) / Double(rhs.value.count)
                return l < r
            }
        if let deadliest {
            let fraction = Double(deadliest.value.filter { $0.1.cause.isMechanistic }.count) / Double(deadliest.value.count)
            out.append(Finding(
                title: "Deadliest target class",
                value: deadliest.key.label,
                detail: String(format: "%.0f%% of its assets died on the biology, across %d", fraction * 100, deadliest.value.count),
                tint: Palette.hazard,
                action: { router in
                    var filter = StallFilter()
                    filter.families = [deadliest.key]
                    router.go(.stallFiltered(filter))
                }
            ))
        }

        return out
    }
}

struct FindingPanel: View {
    let finding: OverlookView.Finding

    var body: some View {
        GlassPanel(tint: finding.tint) {
            VStack(alignment: .leading, spacing: 5) {
                Text(finding.title)
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(finding.tint)
                Text(finding.value)
                    .font(Typography.heading)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(finding.detail)
                    .font(.caption2)
                    .foregroundStyle(Palette.ghost.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#if canImport(RealityKit)
import RealityKit

/// The whole graveyard as a point cloud of instanced emissive spheres.
public struct GraveyardCloudView: View {
    private let assets: [Asset]
    @Binding private var selected: Asset?
    private let idleMotion: Bool

    @State private var yaw: Float = 0
    @State private var dragStart: Float = 0

    public init(assets: [Asset], selected: Binding<Asset?>, idleMotion: Bool) {
        self.assets = assets
        _selected = selected
        self.idleMotion = idleMotion
    }

    public var body: some View {
        RealityView { content in
            let root = Entity()
            root.name = "cloud"

            // One sphere mesh, many transforms: the plan's instancing rule, and the
            // difference between a smooth cloud and one mesh per asset.
            let mesh = MeshResource.generateSphere(radius: 1)
            var materials: [CauseOfDeath: RealityKit.Material] = [:]
            for cause in CauseOfDeath.allCases {
                var m = PhysicallyBasedMaterial()
                let colour = PlatformColor(Palette.colour(for: cause))
                m.baseColor = .init(tint: colour)
                m.emissiveColor = .init(color: colour)
                m.emissiveIntensity = 2.0
                m.roughness = 0.9
                materials[cause] = m
            }

            let years = assets.compactMap(\.yearOfDeath)
            let minYear = Float(years.min() ?? 2000)
            let maxYear = Float(years.max() ?? 2025)
            let span = max(1, maxYear - minYear)

            for asset in assets {
                let node = ModelEntity(mesh: mesh, materials: [materials[asset.cause]!])
                let x = ((Float(asset.yearOfDeath ?? Int(minYear)) - minYear) / span - 0.5) * 0.6
                let y = (Float(asset.score.structuralTractability) - 0.5) * 0.4
                let z = (Float(asset.score.overall) - 0.5) * 0.4
                node.position = SIMD3(x, y, z)
                let phase = Float(asset.phaseReached?.rank ?? 1)
                node.scale = SIMD3(repeating: 0.0025 + 0.0009 * phase)
                node.name = asset.chemblId
                root.addChild(node)
            }
            content.add(root)
        } update: { content in
            content.entities.first { $0.name == "cloud" }?.orientation =
                simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
        }
        #if !os(visionOS)
        .gesture(
            DragGesture()
                .onChanged { yaw = dragStart + Float($0.translation.width) * 0.008 }
                .onEnded { _ in dragStart = yaw }
        )
        #endif
        .accessibilityLabel("Point cloud of \(assets.count) dead assets, positioned by year of death, structural tractability and Ghost Rank.")
    }
}
#endif

#endif
