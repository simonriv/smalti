import Foundation
import SmaltiCore
import Testing

@testable import GhosttyAdapter

/// F2 C8: each pane keeps its own history next to the shared one. A real interactive zsh runs with the chain
/// libghostty sets up: `ZDOTDIR` at Ghostty's integration, whose `.zshenv` loads Smalti's from `GHOSTTY_ZSH_ZDOTDIR`,
/// which restores the user's `ZDOTDIR` (here a temporary one with `SHARE_HISTORY`).
@Suite("Pane history")
struct PaneHistoryTests {
    private let work = FileManager.default.temporaryDirectory.appending(path: "smalti-history-\(UUID())")
    private var userDirectory: URL { work.appending(path: "user") }
    private var shared: URL { work.appending(path: "shared") }
    private var paneFile: URL { work.appending(path: "history/pane.zsh_history") }

    init() throws {
        try FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        let zshrc = """
            HISTFILE=\(shared.path(percentEncoded: false))
            SAVEHIST=100
            HISTSIZE=100
            setopt SHARE_HISTORY INC_APPEND_HISTORY
            """
        try Data(zshrc.utf8).write(to: userDirectory.appending(path: ".zshrc"))
    }

    /// Runs an interactive zsh reading `input` and returns its output.
    private func runZsh(_ input: String, restoresHistory: Bool) throws -> String {
        let smalti = try SmaltiZshEnv.install(in: work.appending(path: "zsh"))
        var environment = [
            "HOME": work.path(percentEncoded: false), "TERM": "xterm", "TMUX": "smalti-tests",
            "ZDOTDIR": TestGhostty.resources.appending(path: "shell-integration/zsh").path(percentEncoded: false),
            "GHOSTTY_ZSH_ZDOTDIR": smalti.path(percentEncoded: false),
            "SMALTI_USER_ZDOTDIR": userDirectory.path(percentEncoded: false),
            "SMALTI_HISTORY_FILE": paneFile.path(percentEncoded: false),
        ]
        if restoresHistory { environment["SMALTI_RESTORE_HISTORY"] = "1" }
        let process = Process()
        process.executableURL = URL(filePath: "/bin/zsh")
        process.arguments = ["-i"]
        process.environment = environment
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stdout
        try process.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: output, as: UTF8.self)
    }

    private func lines(of file: URL) -> [String] {
        ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    @Test func commandsGoToThePaneFileAndTheSharedOne() throws {
        _ = try runZsh("echo uno\necho dos\n", restoresHistory: false)

        #expect((try? String(contentsOf: paneFile, encoding: .utf8)) == "echo uno\necho dos\n")
        #expect(lines(of: shared).contains("echo dos"))
    }

    @Test func restoredPaneSeesItsOwnLastCommandFirst() throws {
        _ = try runZsh("echo uno\necho dos\n", restoresHistory: false)
        try Data("echo compartido\n".utf8).write(to: shared, options: .atomic)

        let output = try runZsh("print -r -- ULTIMO=$history[$((HISTCMD-1))]\n", restoresHistory: true)

        #expect(output.contains("ULTIMO=echo dos"))
    }

    @Test func notRestoredPaneKeepsTheSharedHistory() throws {
        _ = try runZsh("echo uno\necho dos\n", restoresHistory: false)
        try Data("echo compartido\n".utf8).write(to: shared, options: .atomic)

        let output = try runZsh("print -r -- ULTIMO=$history[$((HISTCMD-1))]\n", restoresHistory: false)

        #expect(output.contains("ULTIMO=echo compartido"))
    }

    @Test func spaceIgnoredCommandsStayOutOfThePaneFile() throws {
        try Data("setopt HIST_IGNORE_SPACE\n".utf8).write(to: userDirectory.appending(path: ".zshenv"))

        _ = try runZsh(" export TOKEN=secreto\necho visible\n", restoresHistory: false)

        #expect(lines(of: paneFile) == ["echo visible"])
    }

    @Test func noClobberStillRecordsThePaneHistory() throws {
        try Data("setopt NO_CLOBBER\n".utf8).write(to: userDirectory.appending(path: ".zshenv"))

        _ = try runZsh("echo uno\n", restoresHistory: false)

        #expect(lines(of: paneFile) == ["echo uno"])
    }

    @Test func historyIgnorePatternIsRespected() throws {
        try Data("HISTORY_IGNORE='(ls|pwd)'\n".utf8).write(to: userDirectory.appending(path: ".zshenv"))

        _ = try runZsh("pwd\necho visible\n", restoresHistory: false)

        #expect(lines(of: paneFile) == ["echo visible"])
    }

    @Test func multiLineCommandComesBackAsOneEntry() throws {
        _ = try runZsh("for i in 1 2; do\necho $i\ndone\n", restoresHistory: false)

        let output = try runZsh("print -r -- \"<${history[$((HISTCMD-1))]}>\"\n", restoresHistory: true)

        #expect(output.replacingOccurrences(of: "\r", with: "").contains("<for i in 1 2; do\necho $i\ndone>"))
    }

    @Test func zshrcThatResetsPrecmdStillRecordsHistory() throws {
        let zshrc = try String(contentsOf: userDirectory.appending(path: ".zshrc"), encoding: .utf8)
        try Data((zshrc + "\nprecmd_functions=()\n").utf8).write(to: userDirectory.appending(path: ".zshrc"))

        _ = try runZsh("echo uno\n", restoresHistory: false)

        #expect(lines(of: paneFile) == ["echo uno"])
    }

    @Test func userZshrcStillLoads() throws {
        let output = try runZsh("print -r -- HF=$HISTFILE\n", restoresHistory: false)

        #expect(output.contains("HF=\(shared.path(percentEncoded: false))"))
    }

    @Test func ghosttyIntegrationStillLoads() throws {
        let output = try runZsh("print -r -- STATE=${+_ghostty_state}\n", restoresHistory: false)

        #expect(output.contains("STATE=1"))
    }

    @Test func historyNeedsAPaneFile() {
        let spec = TerminalSessionSpec(workingDirectory: .root, command: .loginShell)

        #expect(GhosttyTerminalEngine.zshChain(for: spec, zshDirectory: work, userZdotdir: nil).isEmpty)
    }

    @Test func chainPointsGhosttyAtSmaltiAndKeepsTheUserDirectory() {
        let spec = TerminalSessionSpec(
            workingDirectory: .root, command: .loginShell, environment: ["SMALTI_HISTORY_FILE": "/h"])

        let chain = GhosttyTerminalEngine.zshChain(for: spec, zshDirectory: work, userZdotdir: "/Users/s/.zsh")

        #expect(chain["GHOSTTY_ZSH_ZDOTDIR"] == work.path(percentEncoded: false))
        #expect(chain["SMALTI_USER_ZDOTDIR"] == "/Users/s/.zsh")
        #expect(chain["ZDOTDIR"] == nil)
    }
}

extension WorkingDirectory {
    // Safe: "/" is absolute.
    fileprivate static let root = (try? WorkingDirectory(path: "/")) ?? { preconditionFailure("/ is absolute") }()
}
