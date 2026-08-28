import Foundation

/// Menu-bar commands on macOS post these; the root view listens.
public extension Notification.Name {
    static let hawkerRefresh = Notification.Name("hawker.refresh")
    static let hawkerSelectTab = Notification.Name("hawker.selectTab")
}
