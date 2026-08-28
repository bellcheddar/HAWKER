import SwiftUI
import Charts


// Not built for watchOS. The watch shows data and scores only (see WatchRootView):
// no 3D, no charts and no filter UI, so this view's platform-specific controls would
// only be a worse version of the phone app on a smaller screen.
#if !os(watchOS)

/// Tab 3. The analytics, and the tab that carries the app's headline claim.
///
/// Every mark drills through to a filtered Stall, so a bar is a question and the list
/// behind it is the answer.
public struct GraveyardView: View {
    @Environment(HawkerStore.self) private var store
    @Environment(Router.self) private var router
    @State private var facet: GraveyardFacet = .causeByYear

    public init(facet: GraveyardFacet = .causeByYear) {
        _facet = State(initialValue: facet)
    }

    private var assets: [Asset] { store.assets }

    public var body: some View {
        ZStack {
            HawkerBackground()
            if store.isLoading, case .loading(let p) = store.state {
                IngestProgressView(progress: p)
            } else if assets.isEmpty {
                HawkerEmptyState(
                    symbol: "chart.bar",
                    title: "Nothing to chart yet",
                    message: "The Graveyard draws from the loaded working set."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        headline
                        picker
                        chart
                        perClass
                    }
                    .padding(14)
                }
            }
        }
        .navigationTitle(HawkerTab.graveyard.title)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: Headline

    private var classified: [Asset] { assets.filter { $0.cause != .unknown } }
    private var businessCount: Int { classified.filter { !$0.cause.isMechanistic }.count }
    private var businessFraction: Double {
        classified.isEmpty ? 0 : Double(businessCount) / Double(classified.count)
    }

    private var headline: some View {
        GlassPanel(tint: Palette.magenta) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Died of business, not biology")
                    .font(Typography.heading)
                    .foregroundStyle(Palette.ghost)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(format: "%.0f%%", businessFraction * 100))
                        .hawkerNumber(.system(size: 46, weight: .bold, design: .monospaced))
                        .foregroundStyle(Palette.magenta)
                    Text("of \(classified.count) assets with a stated, classifiable reason")
                        .font(.caption)
                        .foregroundStyle(Palette.ghost.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Enrolment, funding, operations and portfolio decisions tell us nothing about the molecule or the pocket. Those assets are the ones worth a second look.")
                    .font(.caption)
                    .foregroundStyle(Palette.ghost.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                let unknown = assets.count - classified.count
                if unknown > 0 {
                    Text("\(unknown) more filed no usable reason and are excluded from this percentage rather than assumed either way.")
                        .font(.caption2)
                        .foregroundStyle(Palette.slate)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var picker: some View {
        Picker("Facet", selection: $facet) {
            ForEach(GraveyardFacet.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    // MARK: Charts

    @ViewBuilder
    private var chart: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(facet.label, subtitle: "Tap any mark to open the matching assets.")
                switch facet {
                case .causeByYear: causeByYear
                case .causeByTargetClass: causeByTargetClass
                case .rankVsPhase: rankVsPhase
                case .phaseToCause: phaseToCause
                }
            }
        }
    }

    private var causeByYear: some View {
        Chart(yearRows, id: \.id) { row in
            AreaMark(
                x: .value("Year", row.year),
                y: .value("Assets", row.count),
                stacking: .standard
            )
            .foregroundStyle(by: .value("Cause", row.cause.label))
        }
        .chartForegroundStyleScale(causeScale)
        // Without an explicit domain Swift Charts treats the Int year as an ordinary
        // continuous value and scales from zero, so two millennia of empty axis squash
        // every data point into a spike at the right-hand edge.
        .chartXScale(domain: yearDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisValueLabel {
                    if let year = value.as(Int.self) {
                        Text(String(year)).font(.caption2).monospacedDigit()
                    }
                }
                AxisGridLine().foregroundStyle(Palette.navy)
            }
        }
        .frame(height: 230)
    }

    /// The real span of the data, padded by a year so the edges are not clipped.
    private var yearDomain: ClosedRange<Int> {
        let years = yearRows.map(\.year)
        guard let lo = years.min(), let hi = years.max(), lo < hi else {
            return 2000...2026
        }
        return (lo - 1)...(hi + 1)
    }

    private var causeByTargetClass: some View {
        Chart(familyRows, id: \.id) { row in
            BarMark(
                x: .value("Assets", row.count),
                y: .value("Class", row.family.label)
            )
            .foregroundStyle(by: .value("Cause", row.cause.label))
            .cornerRadius(2)
        }
        .chartForegroundStyleScale(causeScale)
        .frame(height: 260)
    }

    private var rankVsPhase: some View {
        Chart(assets.filter { $0.phaseReached != nil }) { asset in
            PointMark(
                x: .value("Phase", asset.phaseReached?.rank ?? 0),
                y: .value("Ghost Rank", asset.ghostRank)
            )
            .foregroundStyle(by: .value("Cause", asset.cause.label))
            .symbolSize(by: .value("Enrolment", max(20, min(300, Double(asset.trials.compactMap(\.enrolment).max() ?? 30)))))
            .opacity(0.75)
        }
        .chartForegroundStyleScale(causeScale)
        .chartXAxis {
            AxisMarks(values: [1, 2, 3, 4, 5]) { value in
                AxisValueLabel {
                    if let rank = value.as(Int.self),
                       let phase = TrialPhase.allCases.first(where: { $0.rank == rank }) {
                        Text(phase.shortLabel).font(.caption2)
                    }
                }
                AxisGridLine().foregroundStyle(Palette.navy)
            }
        }
        .frame(height: 260)
    }

    /// A flow from phase reached to cause of death, drawn as paired stacked bars.
    /// Swift Charts has no Sankey mark, and a pair of stacks reads more honestly at
    /// this data size than hand-drawn ribbons would.
    private var phaseToCause: some View {
        Chart(phaseRows, id: \.id) { row in
            BarMark(
                x: .value("Phase", row.phase.shortLabel),
                y: .value("Assets", row.count)
            )
            .foregroundStyle(by: .value("Cause", row.cause.label))
            .cornerRadius(2)
        }
        .chartForegroundStyleScale(causeScale)
        .frame(height: 240)
    }

    private var causeScale: KeyValuePairs<String, Color> {
        [
            "Safety (mechanistic)": Palette.hazard,
            "Efficacy / futility": Palette.amberDeath,
            "PK / ADMET": Palette.violetDeath,
            "Enrolment": Palette.tealDeath,
            "Business / strategic": Palette.magenta,
            "Funding": Palette.magenta.opacity(0.7),
            "Operational": Palette.slate,
            "Unknown": Palette.slate.opacity(0.5)
        ]
    }

    // MARK: Drill-through

    private var perClass: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Business against biology, per target class")
                ForEach(TargetFamily.allCases, id: \.self) { family in
                    let inFamily = classified.filter { $0.target?.family == family }
                    if !inFamily.isEmpty {
                        let business = inFamily.filter { !$0.cause.isMechanistic }.count
                        Button {
                            var filter = StallFilter()
                            filter.families = [family]
                            router.go(.stallFiltered(filter))
                        } label: {
                            HStack {
                                Text(family.label).font(.caption)
                                    .foregroundStyle(Palette.ghost)
                                Spacer()
                                Text("\(inFamily.count)")
                                    .hawkerNumber(Typography.numberSmall)
                                    .foregroundStyle(Palette.ghost.opacity(0.6))
                                Text(String(format: "%.0f%%", 100 * Double(business) / Double(inFamily.count)))
                                    .hawkerNumber(Typography.numberSmall)
                                    .foregroundStyle(Palette.magenta)
                                    .frame(width: 46, alignment: .trailing)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Row types

    struct YearRow: Identifiable { let id = UUID(); let year: Int; let cause: CauseOfDeath; let count: Int }
    struct FamilyRow: Identifiable { let id = UUID(); let family: TargetFamily; let cause: CauseOfDeath; let count: Int }
    struct PhaseRow: Identifiable { let id = UUID(); let phase: TrialPhase; let cause: CauseOfDeath; let count: Int }

    private var yearRows: [YearRow] {
        var buckets: [Int: [CauseOfDeath: Int]] = [:]
        for asset in assets {
            guard let year = asset.yearOfDeath, year > 1990, year <= 2030 else { continue }
            buckets[year, default: [:]][asset.cause, default: 0] += 1
        }
        return buckets.flatMap { year, causes in
            causes.map { YearRow(year: year, cause: $0.key, count: $0.value) }
        }.sorted { $0.year < $1.year }
    }

    private var familyRows: [FamilyRow] {
        var buckets: [TargetFamily: [CauseOfDeath: Int]] = [:]
        for asset in assets {
            guard let family = asset.target?.family else { continue }
            buckets[family, default: [:]][asset.cause, default: 0] += 1
        }
        return buckets.flatMap { family, causes in
            causes.map { FamilyRow(family: family, cause: $0.key, count: $0.value) }
        }
    }

    private var phaseRows: [PhaseRow] {
        var buckets: [TrialPhase: [CauseOfDeath: Int]] = [:]
        for asset in assets {
            guard let phase = asset.phaseReached else { continue }
            buckets[phase, default: [:]][asset.cause, default: 0] += 1
        }
        return buckets.flatMap { phase, causes in
            causes.map { PhaseRow(phase: phase, cause: $0.key, count: $0.value) }
        }.sorted { $0.phase.rank < $1.phase.rank }
    }
}

#endif
