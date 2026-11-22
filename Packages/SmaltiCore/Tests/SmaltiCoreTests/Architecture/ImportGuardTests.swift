import Foundation
import Testing

@Suite("Import guard")
struct ImportGuardTests {
    @Test func scannerFlagsForbiddenModule() {
        let violations = forbiddenImports(in: "import Foundation\nimport AppKit\n", file: "X.swift")

        #expect(violations == [ImportViolation(file: "X.swift", line: 2, module: "AppKit")])
    }

    @Test func scannerIgnoresCommentsAndAllowedModules() {
        let violations = forbiddenImports(in: "// import AppKit\nimport Foundation", file: "X.swift")

        #expect(violations.isEmpty)
    }

    @Test func scannerFlagsAttributedImports() {
        let violations = forbiddenImports(in: "@preconcurrency import GhosttyKit", file: "X.swift")

        #expect(violations.map(\.module) == ["GhosttyKit"])
    }

    @Test func scannerFlagsDeclarationKindImports() {
        let violations = forbiddenImports(in: "import struct CoreGraphics.CGRect", file: "X.swift")

        #expect(violations.map(\.module) == ["CoreGraphics"])
    }

    @Test func coreSourcesHaveNoForbiddenImports() throws {
        let violations = try forbiddenImports(inDirectory: coreSourcesDirectory())

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
