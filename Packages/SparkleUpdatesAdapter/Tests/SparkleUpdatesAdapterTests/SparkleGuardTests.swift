import Foundation
import SmaltiCoreTestSupport
import Testing

/// Only SparkleUpdatesAdapter imports Sparkle.
@Suite("Sparkle adapter guard")
struct SparkleGuardTests {
    private static let framework = "Sparkle"
    private static let adapterPackage = "SparkleUpdatesAdapter"
    private let scanner = ImportScanner.forbidding([framework])
    private let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    @Test func onlyThisAdapterImportsSparkle() throws {
        let packages = try FileManager.default.contentsOfDirectory(
            atPath: repositoryRoot.appending(path: "Packages").path(percentEncoded: false))
        let scanned =
            packages.filter { $0 != Self.adapterPackage }.map {
                repositoryRoot.appending(path: "Packages/\($0)/Sources")
            }
            + [repositoryRoot.appending(path: "App")]

        let violations = try scanned.filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
            .flatMap(scanner.violations(inDirectory:))

        #expect(violations.isEmpty, "\(violations.map(\.description).joined(separator: "\n"))")
    }

    @Test func theAdapterImportsSparkle() throws {
        let sources = repositoryRoot.appending(path: "Packages/\(Self.adapterPackage)/Sources")

        #expect(try !scanner.violations(inDirectory: sources).isEmpty)
    }
}
