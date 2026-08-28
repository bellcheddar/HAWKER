import SwiftUI

/// Tab 1. Every dead asset, as a grid of glass cards.
public struct StallView: View {
    @Environment(HawkerStore.self) private var store
    @Environment(Router.self) private var router
    @State private var filter: StallFilter
    @State private var showingFilters = false

    public init(filter: StallFilter = StallFilter()) {
        _filter = State(initialValue: filter)
    }

    private var results: [Asset] { store.filtered(filter) }

    public var body: some View {
        ZStack {
            HawkerBackground()
            content
        }
        .navigationTitle(HawkerTab.stall.title)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(text: $filter.query, prompt: "Drug, target, indication, PDB or ChEMBL id")
        // watchOS has no Menu and no filter sheet: the watch shows a fixed top-25
        // list, so this whole toolbar is iOS, iPadOS, macOS and visionOS only.
        #if !os(watchOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Sort by", selection: $filter.sort) {
                        ForEach(StallSort.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showingFilters.toggle() } label: {
                    Label("Filter", systemImage: filter.isActive
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
            }
        }
        #endif
        #if !os(watchOS)
        .sheet(isPresented: $showingFilters) {
            StallFilterSheet(filter: $filter)
        }
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .idle:
            HawkerEmptyState(
                symbol: "arrow.down.circle",
                title: "Nothing loaded yet",
                message: "HAWKER builds its working set from ChEMBL, ClinicalTrials.gov, Open Targets and the PDB.",
                retry: nil
            )
        case .loading(let progress):
            IngestProgressView(progress: progress)
        case .failed(let message):
            HawkerEmptyState(
                symbol: "wifi.exclamationmark",
                title: "Could not reach the data sources",
                message: message
            )
        case .loaded:
            if results.isEmpty {
                HawkerEmptyState(
                    symbol: "magnifyingglass",
                    title: "No assets match",
                    message: filter.isActive
                        ? "\(filter.summary). Loosen a filter, or clear them all."
                        : "The working set is empty."
                )
            } else {
                grid
            }
        }
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(filter.summary)
                        .font(.caption)
                        .foregroundStyle(Palette.ghost.opacity(0.8))
                    Spacer()
                    Text("\(results.count)")
                        .hawkerNumber(Typography.numberSmall)
                        .foregroundStyle(Palette.neon)
                    Text(results.count == 1 ? "asset" : "assets")
                        .font(.caption)
                        .foregroundStyle(Palette.ghost.opacity(0.8))
                }
                .padding(.horizontal, 4)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 12)], spacing: 12) {
                    ForEach(results) { asset in
                        Button { router.go(.asset(asset.chemblId)) } label: {
                            AssetCard(asset: asset)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
        }
    }
}

/// One dead asset, as a card. Everything on it is a link.
public struct AssetCard: View {
    private let asset: Asset

    public init(asset: Asset) { self.asset = asset }

    public var body: some View {
        GlassPanel(tint: Palette.colour(for: asset.cause)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(asset.displayName)
                            .font(Typography.heading)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        if let target = asset.target {
                            Text(target.displayName)
                                .font(.caption)
                                .foregroundStyle(Palette.accent)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    GhostRankRing(rank: asset.ghostRank, size: 46)
                }

                if let moa = asset.mechanismOfAction {
                    Text(moa)
                        .font(.caption)
                        .foregroundStyle(Palette.ghost.opacity(0.85))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    CauseBadge(asset.cause, confidence: asset.verdict.confidence, compact: true)
                    if let phase = asset.phaseReached {
                        Chip(text: phase.shortLabel, colour: Palette.accent)
                    }
                    if asset.hasCoCrystal, let pdb = asset.structures.first?.pdbId {
                        Chip(text: pdb, colour: Palette.neon, symbol: "cube")
                    }
                    if asset.withdrawnFlag {
                        Chip(text: "Withdrawn", colour: Palette.hazard, symbol: "xmark.octagon")
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct Chip: View {
    let text: String
    let colour: Color
    var symbol: String?

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9)) }
            Text(text).font(.caption2).fontWeight(.medium)
        }
        .foregroundStyle(colour)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(colour.opacity(0.15)))
    }
}

/// Real numbers while the ingest runs. Never a spinner on a blank screen.
public struct IngestProgressView: View {
    private let progress: IngestPipeline.Progress

    public init(progress: IngestPipeline.Progress) { self.progress = progress }

    public var body: some View {
        VStack(spacing: 14) {
            Text(progress.stage)
                .font(Typography.heading)
                .foregroundStyle(Palette.ghost)
                .multilineTextAlignment(.center)
            if progress.total > 0 {
                ProgressView(value: progress.fraction)
                    .tint(Palette.neon)
                    .frame(maxWidth: 320)
                HStack(spacing: 14) {
                    Label("\(progress.completed) of \(progress.total)", systemImage: "arrow.down.circle")
                    Label("\(progress.kept) kept", systemImage: "tray.full")
                }
                .hawkerNumber(Typography.numberSmall)
                .foregroundStyle(Palette.ghost.opacity(0.8))
            } else {
                ProgressView().tint(Palette.neon)
            }
            Text("The first run joins several public databases and takes a few minutes. Later launches read a local cache.")
                .font(.caption)
                .foregroundStyle(Palette.ghost.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .padding(30)
    }
}

#if !os(watchOS)
struct StallFilterSheet: View {
    @Binding var filter: StallFilter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Cause of death") {
                    ForEach(CauseOfDeath.allCases, id: \.self) { cause in
                        Toggle(isOn: binding(for: cause)) {
                            Label {
                                Text(cause.label)
                            } icon: {
                                Image(systemName: cause.symbolName)
                                    .foregroundStyle(Palette.colour(for: cause))
                            }
                        }
                    }
                }
                Section("Phase reached") {
                    ForEach(TrialPhase.allCases.sorted { $0.rank > $1.rank }, id: \.self) { phase in
                        Toggle(phase.label, isOn: binding(for: phase))
                    }
                }
                Section("Target class") {
                    ForEach(TargetFamily.allCases, id: \.self) { family in
                        Toggle(family.label, isOn: binding(for: family))
                    }
                }
                Section {
                    Toggle("Has a co-crystal of the exact ligand", isOn: $filter.requiresStructure)
                    Toggle("Estimated patent horizon has passed", isOn: $filter.requiresLapsedFTO)
                } footer: {
                    Text("The patent horizon is an estimate from public dates, not a freedom-to-operate opinion.")
                }
                Section {
                    Button("Clear all filters", role: .destructive) {
                        let query = filter.query
                        let sort = filter.sort
                        filter = StallFilter()
                        filter.query = query
                        filter.sort = sort
                    }
                }
            }
            .navigationTitle("Filter")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func binding(for cause: CauseOfDeath) -> Binding<Bool> {
        Binding(
            get: { filter.causes.contains(cause) },
            set: { if $0 { filter.causes.insert(cause) } else { filter.causes.remove(cause) } }
        )
    }
    private func binding(for phase: TrialPhase) -> Binding<Bool> {
        Binding(
            get: { filter.phases.contains(phase) },
            set: { if $0 { filter.phases.insert(phase) } else { filter.phases.remove(phase) } }
        )
    }
    private func binding(for family: TargetFamily) -> Binding<Bool> {
        Binding(
            get: { filter.families.contains(family) },
            set: { if $0 { filter.families.insert(family) } else { filter.families.remove(family) } }
        )
    }
}
#endif
