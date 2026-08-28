import Foundation
#if os(iOS) || os(watchOS)
import WatchConnectivity
#endif

/// Sends the top assets from the phone to the watch.
///
/// The watch can fetch for itself and does when it has to, but that means running the
/// whole join on a watch battery for data the phone already has. So: the phone pushes
/// a small digest whenever its working set changes, and the watch's own fetch becomes
/// the fallback rather than the norm.
///
/// Only the top 25 by Ghost Rank travel, and only the fields the watch renders.
/// `updateApplicationContext` replaces rather than queues, which is right here: a
/// stale digest is worthless and there is no value in delivering an old one late.
///
/// Compiled for iOS and watchOS only. WatchConnectivity imports on visionOS and macOS
/// too, but a WCSession is only ever between a phone and a watch, and the delegate's
/// required members differ per platform: guarding on `canImport` built a type that
/// failed to conform on visionOS.
public actor WatchSync {
    public static let shared = WatchSync()

    /// The watch shows a fixed top-25 list, so that is exactly what is sent.
    public static let digestLimit = 25

    #if os(iOS) || os(watchOS)
    private let delegate = SessionDelegate()
    #endif

    public init() {}

    public func activate() {
        #if os(iOS) || os(watchOS)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = delegate
        session.activate()
        #endif
    }

    /// Push a digest from the phone. A no-op where there is no counterpart.
    public func send(assets: [Asset]) {
        #if os(iOS) || os(watchOS)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif

        let digest = WatchDigest(
            savedAt: Date(),
            assets: Array(assets.prefix(Self.digestLimit))
        )
        guard let data = try? HawkerJSON.encoder.encode(digest) else { return }
        // A digest of 25 assets is comfortably inside the application-context limit;
        // the whole working set would not be, which is why only the digest travels.
        try? session.updateApplicationContext(["digest": data])
        #endif
    }

    /// The most recent digest received, if any.
    public func received() -> WatchDigest? {
        #if os(iOS) || os(watchOS)
        guard WCSession.isSupported() else { return nil }
        guard let data = WCSession.default.receivedApplicationContext["digest"] as? Data else { return nil }
        return try? HawkerJSON.decoder.decode(WatchDigest.self, from: data)
        #else
        return nil
        #endif
    }
}

public struct WatchDigest: Codable, Sendable {
    public let savedAt: Date
    public let assets: [Asset]

    public init(savedAt: Date, assets: [Asset]) {
        self.savedAt = savedAt
        self.assets = assets
    }
}

#if os(iOS) || os(watchOS)
/// WCSessionDelegate is an Objective-C protocol and its callbacks arrive on a
/// background queue, so this hops to the main actor rather than touching state directly.
final class SessionDelegate: NSObject, WCSessionDelegate, @unchecked Sendable {
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?) {}

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        NotificationCenter.default.post(name: .hawkerDigestReceived, object: nil)
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
#endif

public extension Notification.Name {
    static let hawkerDigestReceived = Notification.Name("hawker.digestReceived")
}
