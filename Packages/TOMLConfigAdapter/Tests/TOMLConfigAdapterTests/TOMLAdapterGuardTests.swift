import Foundation
import SmaltiCoreTestSupport
import Testing

/// R10: TOMLConfigAdapter is the only code that imports the TOML library.
@Suite("TOML adapter guard")
struct TOMLAdapterGuardTests {
    private static let tomlLibrary = "TOMLDecoder"
    private static let adapterPackage = "TOMLConfigAdapter"
    private let scanner = ImportScanner.forbidding([tomlLibrary])

    private let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()  // TOMLConfigAdapterTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // TOMLConfigAdapter
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repository root

    @Test func onlyThisAdapterImportsTheTOMLLibrary() throws {
        let packages = try packageNames()
        let otherSources = packages.filter { $0 != Self.adapterPackage }.map(sources(ofPackage:))
        let scanned = otherSources + [repositoryRoot.appending(path: "App")]

        let violations = try scanned.flatMap(scanner.violations(inDirectory:))

        #expect(packages.contains(Self.adapterPackage) && packages.contains("SmaltiCore"))
        #expect(
            violations.isEmpty,
            "\(Self.tomlLibrary) imported outside \(Self.adapterPackage):\n\(violations.map(\.description).joined(separator: "\n"))"
        )
    }

    @Test func theAdapterIsWhereTheTOMLLibraryIsImported() throws {
        let imports = try scanner.violations(inDirectory: sources(ofPackage: Self.adapterPackage))

        #expect(!imports.isEmpty)
    }

    private func sources(ofPackage name: String) -> URL {
        repositoryRoot.appending(path: "Packages/\(name)/Sources")
    }

    /// Every directory under `Packages/` that has a `Sources` folder.
    private func packageNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            atPath: repositoryRoot.appending(path: "Packages").path(percentEncoded: false)
        )
        .filter { FileManager.default.fileExists(atPath: sources(ofPackage: $0).path(percentEncoded: false)) }
    }
}
