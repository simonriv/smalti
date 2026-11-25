import Foundation
import OSLog
import SmaltiCore
import Sparkle

/// `AppUpdates` on Sparkle 2 (F7.6). Sparkle checks `SUFeedURL` (or the test override), shows its standard windows
/// and installs only an update whose EdDSA signature matches `SUPublicEDKey`. Nothing starts until `start()`.
@MainActor
public final class SparkleUpdates: AppUpdates {
    private static let feedKey = "SUFeedURL"

    /// The feed the updater reads: the override when there is one, else the bundle's.
    public let feed: URL
    private let updater: SPUUpdater
    private let feedDelegate: FeedOverride

    private init(bundle: Bundle, feed: URL, override: URL?) {
        self.feed = feed
        feedDelegate = FeedOverride(feed: override)
        let driver = SPUStandardUserDriver(hostBundle: bundle, delegate: nil)
        updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: feedDelegate)
    }

    /// An updater for `bundle`, or nil when it has no feed (Smalti Dev) and no override (UI tests, Debug only).
    public static func make(bundle: Bundle, feedOverride: URL?) -> SparkleUpdates? {
        let bundleFeed = (bundle.object(forInfoDictionaryKey: feedKey) as? String).flatMap {
            $0.isEmpty ? nil : URL(string: $0)
        }
        guard let feed = feedOverride ?? bundleFeed else { return nil }
        return SparkleUpdates(bundle: bundle, feed: feed, override: feedOverride)
    }

    /// Starts the scheduled checks; Sparkle's own error says why it could not (a missing key, a bad feed).
    public func start() throws(AppUpdatesError) {
        do {
            try updater.start()
        } catch {
            throw .couldNotStart(reason: error.localizedDescription)
        }
    }

    public func checkNow() {
        updater.checkForUpdates()
    }

    public var isAutomatic: Bool { updater.automaticallyChecksForUpdates }

    public func setAutomatic(_ isOn: Bool) {
        updater.automaticallyChecksForUpdates = isOn
    }
}

/// Why the updater did not start.
public enum AppUpdatesError: Error, Equatable {
    case couldNotStart(reason: String)
}

/// Hands Sparkle the test feed (without one, Sparkle reads `SUFeedURL`) and logs why an update did not install:
/// "Mostrar registros…" and the update tests read it (4005 is a signature that does not match `SUPublicEDKey`).
private final class FeedOverride: NSObject, SPUUpdaterDelegate {
    private let feed: URL?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "dev.simonriv.smalti", category: "updates")

    init(feed: URL?) {
        self.feed = feed
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        feed?.absoluteString
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let error = error as NSError
        // 1001 is "you are up to date", not a failure.
        guard error.code != 1001 else { return }
        logger.error("update aborted: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
    }
}
