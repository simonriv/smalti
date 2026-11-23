import Foundation
import SmaltiCoreTestSupport
import Testing

/// Only FileSessionAdapter imports the Compression framework.
@Suite("File session adapter guard")
struct FileAdapterGuardTests {
    private static let framework = "Compression"
    private static let adapterPackage = "FileSessionAdapter"
    private let scanner = ImportScanner.forbidding([framework])

    private let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()  // FileSessionAdapterTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // FileSessionAdapter
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repository root

    @Test func onlyThisAdapterImportsCompression() throws {
        let packages = try FileManager.default.contentsOfDirectory(
            atPath: repositoryRoot.appending(path: "Packages").path(percentEncoded: false))
        let scanned =
            packages.filter { $0 != Self.adapterPackage }.map(sources(ofPackage:))
            + [repositoryRoot.appending(path: "App")]

        let violations = try scanned.filter(exists).flatMap(scanner.violations(inDirectory:))

        #expect(violations.isEmpty, "\(violations.map(\.description).joined(separator: "\n"))")
    }

    @Test func theAdapterImportsCompression() throws {
        #expect(try !scanner.violations(inDirectory: sources(ofPackage: Self.adapterPackage)).isEmpty)
    }

    private func sources(ofPackage name: String) -> URL {
        repositoryRoot.appending(path: "Packages/\(name)/Sources")
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }
}
