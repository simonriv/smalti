import SQLite3
import XCTest

/// F9: the timeline's fixture installed in this launch's temporary homes (`-SmaltiClaudeHome`, `-SmaltiCodexHome`):
/// F6's sanitized Claude transcripts and F9's Codex home, with the transcripts' directory set to `root`.
enum TimelineFixture {
    static let workB = "7b1f7b2a-0c81-4aa0-8229-85de52add2e8"
    static let workA = "401a63e1-c076-45fe-9f09-432da1c8cfa6"
    static let longPrompt = "5e1f0000-0000-4000-8000-000000000002"
    static let codex = "01a217ec-6769-7511-85da-e8c0c0fc852a"

    private struct Home: Decodable {
        let claude: [String: [String]]
        let codex: [String: String]
        let longPrompt: String
    }

    /// A folder the panes start in, by its real path (the project root the timeline searches is a real path).
    static func root(for app: XCUIApplication) throws -> String {
        let folder = app.configFile.deletingLastPathComponent().appending(path: "work")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.resolvingSymlinksInPath().path(percentEncoded: false)
    }

    /// Installs the fixture; returns the long prompt, to compare a whole copy with.
    @discardableResult
    /// `claude: false` leaves Claude's transcripts out (they hold Spanish text, which the English walk would flag).
    static func install(in app: XCUIApplication, root: String, from bundle: Bundle, claude: Bool = true) throws
        -> String
    {
        let url = try XCTUnwrap(bundle.url(forResource: "timeline-home", withExtension: "json"))
        let home = try JSONDecoder().decode(Home.self, from: Data(contentsOf: url))
        let folder = app.claudeHome.appending(path: "projects").appending(path: claudeFolder(for: root))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (path, lines) in claude ? home.claude : [:] {
            let text = lines.map { $0.replacingOccurrences(of: "{{root}}", with: root) + "\n" }.joined()
            try Data(text.utf8).write(to: folder.appending(path: URL(filePath: path).lastPathComponent))
        }
        for (path, base64) in home.codex {
            let target = app.codexHome.appending(path: path)
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try XCTUnwrap(Data(base64Encoded: base64)).write(to: target)
        }
        try moveCodexThreads(to: root, in: app.codexHome.appending(path: "state_5.sqlite"))
        return home.longPrompt
    }

    /// The Codex session's directory becomes `root`, so the project's search finds it.
    private static func moveCodexThreads(to root: String, in store: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open(store.path(percentEncoded: false), &database) == SQLITE_OK else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: store.path(percentEncoded: false)])
        }
        defer { sqlite3_close(database) }
        let sql = "update threads set cwd = '\(root.replacingOccurrences(of: "'", with: "''"))'"
        XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
    }

    /// Claude Code's folder name for a directory: every character that is not an ASCII letter or digit becomes `-`.
    static func claudeFolder(for directory: String) -> String {
        String(directory.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
    }
}

extension XCUIApplication {
    var codexHome: URL {
        guard let position = launchArguments.firstIndex(of: "-SmaltiCodexHome") else {
            preconditionFailure("not an isolated Smalti: no -SmaltiCodexHome")
        }
        return URL(filePath: launchArguments[position + 1])
    }
}
