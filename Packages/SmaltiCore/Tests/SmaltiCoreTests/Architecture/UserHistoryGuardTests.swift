import Foundation
import Testing

/// F4 C14: Smalti never reads the user's own zsh history. Only the benchmark (`scripts/measure-input.sh` and its
/// `scripts/input-bench`) names it, read-only. Pane histories (`<pane>.zsh_history`) are Smalti's own files.
@Suite("User history guard")
struct UserHistoryGuardTests {
    /// Built from pieces so this file does not name it.
    private static let fileName = "." + "zsh_history"
    private static var userFile: Regex<AnyRegexOutput>? {
        try? Regex("(~|/|\\$HOME|path: \")" + NSRegularExpression.escapedPattern(for: fileName))
    }
    private static let allowed = ["scripts/measure-input.sh", "scripts/input-bench/"]
    private static let skipped = ["/.build/", "/node_modules/", "/build/", "/.git/", "/vendor/", "/.superpowers/"]

    @Test func patternFindsTheUserHistory() throws {
        let pattern = try #require(Self.userFile)

        #expect("let file = home.appending(path: \"\(Self.fileName)\")".contains(pattern))
        #expect("cat ~/\(Self.fileName)".contains(pattern))
        #expect(!"history/\\(pane)\(Self.fileName)".contains(pattern))
    }

    @Test func onlyTheBenchmarkNamesTheUserHistory() throws {
        let pattern = try #require(Self.userFile)
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent()  // Architecture
            .deletingLastPathComponent()  // SmaltiCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // SmaltiCore
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // repo
        var offenders: [String] = []
        for folder in ["App", "Packages", "scripts"] {
            offenders += Self.files(under: root.appending(path: folder), root: root).filter { path in
                guard let text = try? String(contentsOf: root.appending(path: path), encoding: .utf8) else { return false }
                return text.split(separator: "\n").contains { $0.contains(pattern) }
            }
        }

        #expect(offenders.isEmpty, "these name the user's zsh history: \(offenders)")
    }

    private static func files(under folder: URL, root: URL) -> [String] {
        let rootPath = root.path(percentEncoded: false)
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        var found: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            let path = String(url.path(percentEncoded: false).dropFirst(rootPath.count))
            guard ["swift", "sh", "py", "zsh"].contains(url.pathExtension),
                !skipped.contains(where: { "/\(path)".contains($0) }),
                !allowed.contains(where: { path.hasPrefix($0) })
            else { continue }
            found.append(path)
        }
        return found
    }
}
