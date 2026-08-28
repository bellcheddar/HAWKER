import SwiftUI


// Not built for watchOS. The watch shows data and scores only (see WatchRootView):
// no 3D, no charts and no filter UI, so this view's platform-specific controls would
// only be a worse version of the phone app on a smaller screen.
#if !os(watchOS)

/// The Overlook, placed around the viewer on visionOS.
///
/// Same scene as the windowed console: the cloud at arm's length and the headline
/// panels in an arc beyond it, so the data is reachable and the findings are readable.
public struct OverlookImmersiveScene: View {
    @State private var store = HawkerStore()
    @State private var router = Router()
    @State private var selected: Asset?

    public init() {}

    public var body: some View {
        RealityViewContainer(store: store, selected: $selected)
            .environment(store)
            .environment(router)
            .task { store.load() }
    }
}

struct RealityViewContainer: View {
    let store: HawkerStore
    @Binding var selected: Asset?

    var body: some View {
        ZStack {
            #if canImport(RealityKit) && os(visionOS)
            GraveyardCloudView(assets: store.assets, selected: $selected, idleMotion: true)
                .frame(depth: 600)
            #else
            Color.clear
            #endif
        }
    }
}

#endif
