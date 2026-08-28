import SwiftUI

/// The single navigation path, shared by every platform.
///
/// iOS and visionOS push onto it inside a TabView; macOS pushes onto it inside a
/// NavigationSplitView's detail column. The view bodies do not know the difference,
/// which is what keeps five targets down to one set of views.
@Observable
public final class Router {
    public var path = NavigationPath()
    public var tab: HawkerTab = .stall
    public var presentingMethod = false

    public init() {
        #if DEBUG
        applyLaunchArguments()
        #endif
    }

    #if DEBUG
    /// Drive the app from outside, for screenshots and UI verification.
    ///
    /// Without these there is no way to reach a particular screen from a script: a
    /// `hawker://` deep link makes the simulator raise an "Open in HAWKER?" dialog that
    /// needs a tap, and `simctl` cannot tap. UserDefaults reads the arguments for free.
    ///
    ///     xcrun simctl launch <udid> com.mdeller.hawker -AppTab graveyard
    ///     xcrun simctl launch <udid> com.mdeller.hawker -AppAsset CHEMBL276711
    ///     open -a HAWKER.app --args -AppTab pockets
    private func applyLaunchArguments() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "AppTab"),
           let match = HawkerTab.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(raw) == .orderedSame }) {
            tab = match
        }
        if let id = defaults.string(forKey: "AppAsset"), !id.isEmpty {
            path.append(HawkerRoute.asset(id.uppercased()))
        }
        if let pdb = defaults.string(forKey: "AppPocket"), !pdb.isEmpty {
            let parts = pdb.split(separator: ":").map(String.init)
            path.append(HawkerRoute.pocket(pdbId: parts[0].uppercased(),
                                           ccd: parts.count > 1 ? parts[1].uppercased() : nil))
        }
        if defaults.bool(forKey: "AppMethod") {
            presentingMethod = true
        }
    }
    #endif

    public func go(_ route: HawkerRoute) {
        if case .method = route {
            presentingMethod = true
            return
        }
        path.append(route)
    }

    public func replaceStack(with route: HawkerRoute) {
        path = NavigationPath()
        path.append(route)
    }

    public func popToRoot() {
        path = NavigationPath()
    }

    /// Deep links. A filtered Stall switches tab rather than pushing, because the
    /// Stall is a tab root and pushing a second copy of it reads as a bug.
    @discardableResult
    public func open(url: URL) -> Bool {
        guard let route = HawkerRoute(url: url) else { return false }
        switch route {
        case .stallFiltered:
            tab = .stall
            path = NavigationPath()
            path.append(route)
        case .graveyard:
            tab = .graveyard
            path = NavigationPath()
        case .method:
            presentingMethod = true
        default:
            path.append(route)
        }
        return true
    }
}

public enum HawkerTab: String, CaseIterable, Hashable, Sendable {
    case stall, postMortem, graveyard, shelf, pockets, overlook

    public var title: String {
        switch self {
        case .stall: "The Stall"
        case .postMortem: "Post Mortem"
        case .graveyard: "The Graveyard"
        case .shelf: "Second-hand Shelf"
        case .pockets: "Pocket Reuse"
        case .overlook: "The Overlook"
        }
    }

    /// Six tabs do not fit on an iPhone at full length: "The Stall" and "Post Mortem"
    /// overlapped on an iPhone 17 Pro. The tab bar uses these; every other place the
    /// tab is named uses the full title.
    public var shortTitle: String {
        switch self {
        case .stall: "Stall"
        case .postMortem: "Mortem"
        case .graveyard: "Graveyard"
        case .shelf: "Shelf"
        case .pockets: "Pockets"
        case .overlook: "Overlook"
        }
    }

    public var symbol: String {
        switch self {
        case .stall: "square.grid.2x2"
        case .postMortem: "stethoscope"
        case .graveyard: "chart.bar.xaxis"
        case .shelf: "clock.arrow.circlepath"
        case .pockets: "cube.transparent"
        case .overlook: "sparkles.rectangle.stack"
        }
    }

    /// The watch carries data and scores only: no 3D, and no analytics that need a
    /// chart bigger than the screen.
    public var availableOnWatch: Bool {
        switch self {
        case .stall, .postMortem, .shelf: true
        default: false
        }
    }
}
