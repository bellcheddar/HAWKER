import SwiftUI
import HawkerKit

/// visionOS: the main console in a window, plus an ImmersiveSpace for the Overlook.
@main
struct HawkerApp: App {
    @State private var immersion: ImmersionStyle = .mixed

    var body: some Scene {
        WindowGroup(id: "console") {
            HawkerRootView()
        }
        .windowStyle(.plain)

        // The Overlook's point cloud, placed around the viewer rather than in a pane.
        ImmersiveSpace(id: "overlook") {
            OverlookImmersiveScene()
        }
        .immersionStyle(selection: $immersion, in: .mixed)
    }
}
