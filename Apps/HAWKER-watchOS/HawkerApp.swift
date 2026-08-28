import SwiftUI
import HawkerKit

/// watchOS: data and scores, no 3D. Molecular rendering on a watch is not worth the
/// battery or the hours, and the plan says so explicitly.
@main
struct HawkerApp: App {
    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}
