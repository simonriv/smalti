import Foundation
import SmaltiCoreTestSupport
import Testing

@Suite("Import guard")
struct ImportGuardTests {
    /// SmaltiCore stays pure Swift: Foundation value types are the only allowed import.
    private let scanner = ImportScanner.allowing(["Foundation"])

    @Test func scannerFlagsForbiddenModule() {
        let violations = scanner.violations(in: "import Foundation\nimport AppKit\n", file: "X.swift")

        #expect(violations == [ImportViolation(file: "X.swift", line: 2, module: "AppKit")])
    }

    @Test func scannerIgnoresCommentsAndAllowedModules() {
        let violations = scanner.violations(in: "// import AppKit\nimport Foundation", file: "X.swift")

        #expect(violations.isEmpty)
    }

    @Test func scannerFlagsAttributedImports() {
        let violations = scanner.violations(in: "@preconcurrency import GhosttyKit", file: "X.swift")

        #expect(violations.map(\.module) == ["GhosttyKit"])
    }

    @Test func scannerFlagsDeclarationKindImports() {
        let violations = scanner.violations(in: "import struct CoreGraphics.CGRect", file: "X.swift")

        #expect(violations.map(\.module) == ["CoreGraphics"])
    }

    @Test func forbiddingScannerFlagsOnlyTheListedModules() {
        let scanner = ImportScanner.forbidding(["TOMLDecoder"])

        let violations = scanner.violations(in: "import AppKit\nimport TOMLDecoder\n", file: "X.swift")

        #expect(violations == [ImportViolation(file: "X.swift", line: 2, module: "TOMLDecoder")])
    }

    @Test func coreSourcesHaveNoForbiddenImports() throws {
        let violations = try scanner.violations(inDirectory: coreSourcesDirectory())

        #expect(
            violations.isEmpty,
            "Forbidden imports in SmaltiCore:\n\(violations.map(\.description).joined(separator: "\n"))")
    }

    private func coreSourcesDirectory() -> URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()  // Architecture
            .deletingLastPathComponent()  // SmaltiCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
            .appending(path: "Sources/SmaltiCore")
    }
}

@Suite("Locale guard")
struct LocaleGuardTests {
    @Test func scannerFlagsSystemLanguageLookups() {
        let source = "let a = Locale.current\n// Bundle.main\nlet b = String(localized: \"x\")\nlet c = 1\n"

        #expect(LocaleScanner.violations(in: source, file: "X.swift").map(\.line) == [1, 3])
    }

    @Test func coreSourcesNeverReadTheSystemLanguage() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appending(path: "Sources/SmaltiCore")
        let violations = try LocaleScanner.violations(inDirectory: root)

        #expect(violations.isEmpty, "\(violations.map(\.description).joined(separator: "\n"))")
    }
}
