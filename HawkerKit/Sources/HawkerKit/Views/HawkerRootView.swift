import SwiftUI


// Not built for watchOS. The watch shows data and scores only (see WatchRootView):
// no 3D, no charts and no filter UI, so this view's platform-specific controls would
// only be a worse version of the phone app on a smaller screen.
#if !os(watchOS)

/// The one root view, shared by iOS, iPadOS, macOS and visionOS.
///
/// The platforms differ only in their container: a TabView on iOS and visionOS, a
/// NavigationSplitView on macOS. The tab bodies below are identical everywhere, which
/// is what keeps four app targets down to one set of views.
public struct HawkerRootView: View {
    @State private var store = HawkerStore()
    @State private var router = Router()

    public init() {}

    public var body: some View {
        container
            .environment(store)
            .environment(router)
            .preferredColorScheme(.dark)
            .tint(Palette.neon)
            .task { store.load() }
            .onOpenURL { router.open(url: $0) }
            .sheet(isPresented: Binding(
                get: { router.presentingMethod },
                set: { router.presentingMethod = $0 }
            )) {
                MethodView()
                    .environment(store)
            }
    }

    @ViewBuilder
    private var container: some View {
        #if os(macOS)
        NavigationSplitView {
            List(HawkerTab.allCases, id: \.self, selection: Binding(
                get: { router.tab }, set: { router.tab = $0 ?? .stall }
            )) { tab in
                Label(tab.title, systemImage: tab.symbol).tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                Button { router.presentingMethod = true } label: {
                    Label("Method", systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(10)
            }
        } detail: {
            NavigationStack(path: Binding(get: { router.path }, set: { router.path = $0 })) {
                body(for: router.tab)
                    .navigationDestination(for: HawkerRoute.self, destination: destination)
            }
        }
        #else
        TabView(selection: Binding(get: { router.tab }, set: { router.tab = $0 })) {
            ForEach(HawkerTab.allCases, id: \.self) { tab in
                NavigationStack(path: Binding(get: { router.path }, set: { router.path = $0 })) {
                    body(for: tab)
                        .navigationDestination(for: HawkerRoute.self, destination: destination)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button { router.presentingMethod = true } label: {
                                    Label("Method", systemImage: "list.bullet.rectangle")
                                }
                            }
                        }
                }
                .tabItem { Label(tab.title, systemImage: tab.symbol) }
                .tag(tab)
            }
        }
        #endif
    }

    @ViewBuilder
    private func body(for tab: HawkerTab) -> some View {
        switch tab {
        case .stall:      StallView()
        case .postMortem: TopAssetRedirectView()
        case .graveyard:  GraveyardView()
        case .shelf:      SecondHandShelfView()
        case .pockets:    PocketReuseView()
        case .overlook:   OverlookView()
        }
    }

    @ViewBuilder
    private func destination(_ route: HawkerRoute) -> some View {
        switch route {
        case .asset(let id):
            PostMortemView(assetId: id)
        case .target(let id):
            PocketReuseView(targetId: id)
        case .pocket(let pdbId, let ccd):
            StructureDetailView(pdbId: pdbId, ccd: ccd)
        case .stallFiltered(let filter):
            StallView(filter: filter)
        case .graveyard:
            GraveyardView()
        case .method:
            MethodView()
        }
    }
}

/// The Post Mortem tab has no single subject until one is chosen, so it opens on the
/// highest-ranked asset rather than showing an empty frame.
struct TopAssetRedirectView: View {
    @Environment(HawkerStore.self) private var store

    var body: some View {
        if let top = store.assets.first {
            PostMortemView(assetId: top.chemblId)
        } else if store.isLoading, case .loading(let p) = store.state {
            ZStack { HawkerBackground(); IngestProgressView(progress: p) }
        } else {
            ZStack {
                HawkerBackground()
                HawkerEmptyState(
                    symbol: "stethoscope",
                    title: "No asset selected",
                    message: "Pick one from The Stall and it opens here."
                )
            }
        }
    }
}

#endif
