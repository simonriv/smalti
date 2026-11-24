import Foundation

@testable import GhosttyAdapter

/// A real interactive zsh with ZLE, in a pseudo-terminal made by `/usr/bin/script`, with the same chain libghostty
/// sets up (Ghostty's integration → Smalti's `.zshenv` → a temporary user ZDOTDIR). Never the user's own files.
/// `dump()` reads ZLE's state through a widget bound to ⌃X⌃D in the test `.zshrc`.
final class ZshHarness: @unchecked Sendable {
    struct State: Equatable {
        let buffer: String
        let cursor: Int
        let ghost: String
        let highlight: String
    }

    let work = FileManager.default.temporaryDirectory.appending(path: "smalti-zsh-\(UUID())")
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let lock = NSLock()
    private var transcript = Data()

    /// `socket` nil leaves `SMALTI_INPUT_SOCKET` unset; `zshrc` is appended to the test `.zshrc`; `extra` adds
    /// variables to the shell's environment (F5: `SMALTI_INPUT_FEATURES`, `AWS_PROFILE`).
    init(socket: String?, zshrc: String = "", extra: [String: String] = [:]) throws {
        let user = work.appending(path: "user")
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        let dump = work.appending(path: "dump").path(percentEncoded: false)
        let rc = """
            PS1='p%% '
            HISTFILE=\(work.path(percentEncoded: false))/hist
            _test_dump() { print -r -- "$BUFFER"$'\\x1f'"$CURSOR"$'\\x1f'"$POSTDISPLAY"$'\\x1f'"${region_highlight[*]}" >| \(dump) }
            zle -N _test_dump
            bindkey '^X^D' _test_dump
            bindkey -M viins '^X^D' _test_dump
            _test_prompt() { print -r -- "$(print -rP -- "$PROMPT")"$'\\x1f'"$PROMPT"$'\\x1f'"${precmd_functions[-1]}"$'\\x1f'"$BUFFER"$'\\x1f'"$(bindkey '^I')" >| \(dump)-prompt }
            zle -N _test_prompt
            bindkey '^X^P' _test_prompt
            \(zshrc)
            """
        try rc.write(to: user.appending(path: ".zshrc"), atomically: true, encoding: .utf8)
        let smalti = try SmaltiZshEnv.install(in: work.appending(path: "smalti"))
        var environment = [
            "HOME": work.path(percentEncoded: false), "TERM": "xterm-256color", "TMUX": "smalti-tests",
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "COLORTERM": "truecolor",
            // libghostty fills LANG from macOS preferences at init (os/locale.zig), so panes always have one.
            "LANG": "en_US.UTF-8",
            "ZDOTDIR": TestGhostty.resources.appending(path: "shell-integration/zsh").path(percentEncoded: false),
            "GHOSTTY_ZSH_ZDOTDIR": smalti.path(percentEncoded: false),
            "SMALTI_USER_ZDOTDIR": user.path(percentEncoded: false),
            "SMALTI_PANE_ID": "6F2B4E1C-0A3D-4C5E-9F11-2233445566AA",
        ]
        if let socket { environment["SMALTI_INPUT_SOCKET"] = socket }
        environment.merge(extra) { _, new in new }
        process.executableURL = URL(filePath: "/usr/bin/script")
        process.arguments = ["-q", "/dev/null", "/bin/zsh", "-d", "-i"]
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            self?.lock.withLock { self?.transcript.append(data) }
        }
        try process.run()
        Thread.sleep(forTimeInterval: 0.8)
    }

    deinit { close() }

    func close() {
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        try? FileManager.default.removeItem(at: work)
    }

    var isRunning: Bool { process.isRunning }

    /// Everything the shell printed so far.
    var printed: String { lock.withLock { String(decoding: transcript, as: UTF8.self) } }

    /// Sends keys and gives zsh `settle` seconds to handle them.
    func type(_ keys: String, settle: TimeInterval = 0.25) {
        input.fileHandleForWriting.write(Data(keys.utf8))
        Thread.sleep(forTimeInterval: settle)
    }

    /// F5: what zsh shows as the prompt (prompt-expanded, escapes removed), the raw `PROMPT`, the last precmd hook,
    /// the line being edited and what Tab is bound to.
    struct PromptState: Equatable {
        let shown: String
        let raw: String
        let lastPrecmd: String
        let buffer: String
        let tab: String
    }

    func dumpPrompt() -> PromptState? {
        let file = work.appending(path: "dump-prompt")
        try? FileManager.default.removeItem(at: file)
        type("\u{18}\u{10}")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let parts = text.trimmingCharacters(in: .newlines).components(separatedBy: "\u{1f}")
        guard parts.count == 5 else { return nil }
        let shown = parts[0].replacingOccurrences(of: "\u{1b}\\[[0-9;]*m", with: "", options: .regularExpression)
        return PromptState(shown: shown, raw: parts[1], lastPrecmd: parts[2], buffer: parts[3], tab: parts[4])
    }

    func dump() -> State? {
        let file = work.appending(path: "dump")
        try? FileManager.default.removeItem(at: file)
        type("\u{18}\u{04}")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let parts = text.trimmingCharacters(in: .newlines).components(separatedBy: "\u{1f}")
        guard parts.count == 4 else { return nil }
        return State(buffer: parts[0], cursor: Int(parts[1]) ?? -1, ghost: parts[2], highlight: parts[3])
    }
}
