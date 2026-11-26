import Foundation
import Testing

/// F7.7: no UI test depends on the Mac's language. Every launch goes through `isolatedSmalti`, which passes
/// `-AppleLanguages` explicitly; an `XCUIApplication(…)` elsewhere would inherit the system's language.
@Suite("UI test language guard")
struct UITestLanguageGuardTests {
    private static let uiTests = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "App/SmaltiUITests")
    private static var isInRepository: Bool { FileManager.default.fileExists(atPath: uiTests.path) }

    static func bareLaunches(in source: String) -> [Int] {
        source.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { index, line in
            let code = line.trimmingCharacters(in: .whitespaces)
            return !code.hasPrefix("//") && code.contains("XCUIApplication(") ? index + 1 : nil
        }
    }

    @Test func scannerFindsBareLaunches() {
        #expect(Self.bareLaunches(in: "let a = XCUIApplication()\n// XCUIApplication()\nlet b = 1") == [1])
    }

    @Test func scannerFindsLaunchesWithArguments() {
        #expect(Self.bareLaunches(in: "let a = XCUIApplication(bundleIdentifier: id)\nlet b = 1") == [1])
    }

    @Test(.enabled(if: isInRepository))
    func onlyTheHelperCreatesTheApp() throws {
        let files = try FileManager.default.contentsOfDirectory(at: Self.uiTests, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "IsolatedApp.swift" }
        let offenders = try files.flatMap { file in
            Self.bareLaunches(in: try String(contentsOf: file, encoding: .utf8)).map {
                "\(file.lastPathComponent):\($0)"
            }
        }

        #expect(offenders.isEmpty, "bare XCUIApplication(): \(offenders)")
    }

    @Test(.enabled(if: isInRepository))
    func theHelperForcesALanguage() throws {
        let helper = try String(contentsOf: Self.uiTests.appending(path: "IsolatedApp.swift"), encoding: .utf8)

        #expect(helper.contains(#""-AppleLanguages""#))
    }
}
