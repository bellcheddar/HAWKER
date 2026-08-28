import SwiftUI
import HawkerKit

@main
struct HawkerApp: App {
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            HawkerRootView()
                .frame(minWidth: 980, minHeight: 660)
        }
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Graveyard") {
                Button("Refresh working set") {
                    NotificationCenter.default.post(name: .hawkerRefresh, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])

                Divider()

                ForEach(HawkerTab.allCases, id: \.self) { tab in
                    Button(tab.title) {
                        NotificationCenter.default.post(name: .hawkerSelectTab, object: tab)
                    }
                }
            }
        }
    }
}
