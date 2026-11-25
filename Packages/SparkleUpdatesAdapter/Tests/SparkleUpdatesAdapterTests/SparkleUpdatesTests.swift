import Foundation
import SmaltiCore
import SparkleUpdatesAdapter
import Testing

/// F7.6: the updater exists only in a build with a feed (Release) or with the test override; it never starts here,
/// so these tests make no request.
@MainActor
@Suite("SparkleUpdates")
final class SparkleUpdatesTests {
    nonisolated private static let bundleID = "dev.simonriv.smalti.sparkleadaptertest"
    nonisolated private let directory = FileManager.default.temporaryDirectory.appending(
        path: "smalti-sparkle-\(UUID())")

    /// Review 1 (M4): every test leaves no folder nor defaults domain behind.
    deinit {
        try? FileManager.default.removeItem(at: directory)
        UserDefaults.standard.removePersistentDomain(forName: Self.bundleID)
    }

    /// A bundle on disk with `keys` in its Info.plist, so Sparkle keeps its defaults in a test domain.
    private func bundle(_ keys: [String: String]) throws -> Bundle {
        let root = directory.appending(path: "Test.app")
        let contents = root.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] =
            [
                "CFBundleIdentifier": Self.bundleID, "CFBundleVersion": "1", "CFBundleShortVersionString": "0.0.1",
                "CFBundlePackageType": "APPL", "CFBundleName": "Test",
            ].merging(keys) { _, new in new }
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appending(path: "Info.plist"))
        return try #require(Bundle(url: root))
    }

    @Test func noFeedMeansNoUpdater() throws {
        #expect(SparkleUpdates.make(bundle: try bundle([:]), feedOverride: nil) == nil)
    }

    @Test func emptyFeedMeansNoUpdater() throws {
        #expect(SparkleUpdates.make(bundle: try bundle(["SUFeedURL": ""]), feedOverride: nil) == nil)
    }

    @Test func bundleFeedMakesAnUpdater() throws {
        let updates = SparkleUpdates.make(
            bundle: try bundle(["SUFeedURL": "https://smalti.sh/appcast.xml"]), feedOverride: nil)

        #expect(updates != nil)
    }

    @Test func overrideMakesAnUpdaterWithoutABundleFeed() throws {
        let override = try #require(URL(string: "http://127.0.0.1:9/appcast.xml"))

        #expect(SparkleUpdates.make(bundle: try bundle(["SUFeedURL": ""]), feedOverride: override) != nil)
    }

    @Test func overrideIsTheFeedTheUpdaterUses() throws {
        let override = try #require(URL(string: "http://127.0.0.1:9/appcast.xml"))
        let updates = try #require(
            SparkleUpdates.make(
                bundle: try bundle(["SUFeedURL": "https://smalti.sh/appcast.xml"]), feedOverride: override))

        #expect(updates.feed == override)
    }

    @Test func automaticCheckFollowsTheSetting() throws {
        let updates = try #require(
            SparkleUpdates.make(bundle: try bundle(["SUFeedURL": "https://smalti.sh/appcast.xml"]), feedOverride: nil))

        updates.setAutomatic(false)
        #expect(!updates.isAutomatic)
        updates.setAutomatic(true)
        #expect(updates.isAutomatic)
    }
}
