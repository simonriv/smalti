import Foundation

@testable import GhosttyAdapter

/// Every suite initialises libghostty the same way (the first call wins for the whole process), with the bundled
/// resources so its shell integration is available, as in the app.
enum TestGhostty {
    static let resources = URL(filePath: #filePath)
        .deletingLastPathComponent()  // GhosttyAdapterTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // GhosttyAdapter
        .appending(path: "Frameworks/ghostty-resources/ghostty")

    @MainActor
    static func initialize() throws {
        try GhosttyProcess.ensureInitialized(resourcesDirectory: resources)
    }
}
