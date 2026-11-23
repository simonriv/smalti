import Foundation
import SmaltiCoreTestSupport
import Testing

/// Only FigCompletionAdapter imports JavaScriptCore.
@Suite("Fig adapter guard")
struct FigAdapterGuardTests {
    private static let framework = "JavaScriptCore"
    private static let adapterPackage = "FigCompletionAdapter"
    private let scanner = ImportScanner.forbidding([framework])

    private let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()  // FigCompletionAdapterTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // FigCompletionAdapter
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repository root

    @Test func onlyThisAdapterImportsJavaScriptCore() throws {
        let packages = try FileManager.default.contentsOfDirectory(
            atPath: repositoryRoot.appending(path: "Packages").path(percentEncoded: false))
        let scanned =
            packages.filter { $0 != Self.adapterPackage }.map(sources(ofPackage:))
            + [repositoryRoot.appending(path: "App")]

        let violations = try scanned.filter(exists).flatMap(scanner.violations(inDirectory:))

        #expect(violations.isEmpty, "\(violations.map(\.description).joined(separator: "\n"))")
    }

    @Test func theAdapterImportsJavaScriptCore() throws {
        #expect(try !scanner.violations(inDirectory: sources(ofPackage: Self.adapterPackage)).isEmpty)
    }

    private func sources(ofPackage name: String) -> URL {
        repositoryRoot.appending(path: "Packages/\(name)/Sources")
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }
}
