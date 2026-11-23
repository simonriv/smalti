import Foundation
import SmaltiCoreTestSupport
import Testing

/// Only DarwinMetricsAdapter imports the IOKit framework.
@Suite("Darwin metrics adapter guard")
struct DarwinMetricsGuardTests {
    private static let framework = "IOKit"
    private static let adapterPackage = "DarwinMetricsAdapter"
    private let scanner = ImportScanner.forbidding([framework])

    private let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()  // DarwinMetricsAdapterTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // DarwinMetricsAdapter
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repository root

    @Test func onlyThisAdapterImportsIOKit() throws {
        let packages = try FileManager.default.contentsOfDirectory(
            atPath: repositoryRoot.appending(path: "Packages").path(percentEncoded: false))
        let scanned =
            packages.filter { $0 != Self.adapterPackage }.map(sources(ofPackage:))
            + [repositoryRoot.appending(path: "App")]

        let violations = try scanned.filter(exists).flatMap(scanner.violations(inDirectory:))

        #expect(violations.isEmpty, "\(violations.map(\.description).joined(separator: "\n"))")
    }

    @Test func theAdapterImportsIOKit() throws {
        #expect(try !scanner.violations(inDirectory: sources(ofPackage: Self.adapterPackage)).isEmpty)
    }

    private func sources(ofPackage name: String) -> URL {
        repositoryRoot.appending(path: "Packages/\(name)/Sources")
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }
}
