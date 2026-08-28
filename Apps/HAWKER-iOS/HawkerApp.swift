import SwiftUI
import HawkerKit

/// iOS and iPadOS. The app target holds the entry point and nothing else: every view,
/// model and client lives in HawkerKit so the five platforms share one codebase.
@main
struct HawkerApp: App {
    var body: some Scene {
        WindowGroup {
            HawkerRootView()
        }
    }
}
