import SwiftUI
import Charts

/// Tab 4. Assets whose estimated composition-of-matter horizon has passed.
///
/// The caveat is in the header, not a footnote, because the whole tab is built on an
/// estimate and presenting it as anything firmer would be misleading.
public struct SecondHandShelfView: View {
    @Environment(HawkerStore.self) private var store
    @Environment(Router.self) private var router

    public init() {}

    private var lapsed: [Asset] {
        store.assets
            .filter { $0.ftoLapsedEstimate }
            .sorted { $0.ghostRank > $1.ghostRank }
    }

    public var body: some View {
        ZStack {
            HawkerBackground()
            if store.isLoading {
                if case .loading(let p) = store.state { IngestProgressView(progress: p) }
            } else if lapsed.isEmpty {
                HawkerEmptyState(
                    symbol: "clock.badge.questionmark",
                    title: "Nothing on the shelf yet",
                    message: "No asset in the working set has an estimated horizon that has passed. The estimate needs a public approval or trial start date, and many shelved compounds have neither."
                )
            } else {
                content
            }
        }
        .navigationTitle(HawkerTab.shelf.title)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GlassPanel(tint: Palette.amberDeath) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("These dates are estimates", systemImage: "exclamationmark.triangle")
                            .font(Typography.heading)
                            .foregroundStyle(Palette.amberDeath)
                        Text("""
                        Each horizon is the earliest public approval or trial start date plus \
                        \(Scorer.estimatedPatentTermYears) years. Real composition-of-matter expiry depends on Orange Book \
                        patent listings, term extensions and paediatric exclusivity, none of which \
                        are used here. This is not a freedom-to-operate opinion and must not be \
                        relied on as legal guidance.
                        """)
                        .font(.caption)
                        .foregroundStyle(Palette.ghost.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                GlassPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader("Estimated lapse by year", subtitle: "\(lapsed.count) assets past their estimated horizon.")
                        Chart(byYear, id: \.year) { row in
                            BarMark(
                                x: .value("Year", String(row.year)),
                                y: .value("Assets", row.count)
                            )
                            .foregroundStyle(Palette.amberDeath.gradient)
                            .cornerRadius(3)
                        }
                        .frame(height: 150)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 12)], spacing: 12) {
                    ForEach(lapsed) { asset in
                        Button { router.go(.asset(asset.chemblId)) } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                AssetCard(asset: asset)
                                if let year = asset.estimatedFTOYear {
                                    Text("Estimated horizon \(String(year))")
                                        .font(.caption2)
                                        .foregroundStyle(Palette.amberDeath.opacity(0.9))
                                        .padding(.top, 4)
                                        .padding(.leading, 6)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
        }
    }

    private var byYear: [(year: Int, count: Int)] {
        Dictionary(grouping: lapsed.compactMap(\.estimatedFTOYear), by: { $0 })
            .map { (year: $0.key, count: $0.value.count) }
            .sorted { $0.year < $1.year }
    }
}
