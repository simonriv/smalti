import Foundation
import XCTest

extension XCUIApplication {
    /// The only shell UI tests may run: it reads no startup files.
    static let isolatedShell = "/bin/zsh -f"
    /// Non-empty `$TMUX` for every shell the tests start; it names no real tmux socket.
    static let tmuxGuard = "smalti-ui-tests-isolation"

    /// Smalti launched with a config file of its own, in a per-launch temporary directory, so tests never read or
    /// write the user's `~/.config/smalti/config.toml`. Without `config` the file does not exist and the defaults
    /// apply. `shell` overrides the shell (`-SmaltiShellCommand`); pass `nil` only with a valid `config` whose
    /// `[shell] command` is the isolated shell, because the user's login shell attaches to a shared tmux session.
    static func isolatedSmalti(shell: String? = isolatedShell, config: String? = nil) -> XCUIApplication {
        precondition(
            shell != nil || config?.contains("command = \"\(isolatedShell)\"") == true,
            "a launch without -SmaltiShellCommand needs a config whose shell is \(isolatedShell)")
        let app = XCUIApplication()
        // Fail closed: if a login shell ever started (a fixture that stops parsing falls back to it), a `.zshrc`
        // that attaches to tmux only when `$TMUX` is empty, as the user's does, stays out of `tmux main`.
        app.launchEnvironment["TMUX"] = tmuxGuard
        let file = isolatedConfigFile
        app.launchArguments += ["-SmaltiConfigPath", file.path(percentEncoded: false)]
        if let shell { app.launchArguments += ["-SmaltiShellCommand", shell] }
        app.launchArguments += [
            "-SmaltiStatePath", file.deletingLastPathComponent().appending(path: "state").path(percentEncoded: false),
            // F3: never the user's Claude data nor their Ollama; tests that need transcripts copy a fixture here.
            "-SmaltiClaudeHome", file.deletingLastPathComponent().appending(path: "claude").path(percentEncoded: false),
            "-SmaltiOllamaURL", "http://127.0.0.1:1",
            // F5.6: the app asks `claude plugin list` at launch; tests never run the real `claude`.
            "-SmaltiClaudeCommand",
            file.deletingLastPathComponent().appending(path: "no-claude").path(percentEncoded: false),
            // F7: never the machine's managed Claude settings; tests that need them write this file.
            "-SmaltiManagedSettings",
            file.deletingLastPathComponent().appending(path: "managed-settings.json").path(percentEncoded: false),
        ]
        app.launchArguments += isolatedHarnessArguments(next: file.deletingLastPathComponent())
        if let config { app.writeConfig(config) }
        return app
    }

    /// F6: empty homes for Codex, Antigravity and OpenCode, an empty Neovim config, `nvim --clean` for the editor
    /// panes and a short socket folder (`sun_path` holds 104 bytes): never the user's own.
    private static func isolatedHarnessArguments(next folder: URL) -> [String] {
        let path = { (name: String) in folder.appending(path: name).path(percentEncoded: false) }
        let sockets = "/private/tmp/smalti-ui-\(UUID().uuidString.prefix(8))"
        return [
            "-SmaltiCodexHome", path("codex"), "-SmaltiAntigravityHome", path("antigravity-cli"),
            "-SmaltiOpenCodeDB", path("opencode/opencode.db"), "-SmaltiNvimConfigHome", path("nvim-config/nvim"),
            // The pane's `zsh -f` has no Homebrew in its PATH (InputTests does the same).
            "-SmaltiNvimCommand", "/opt/homebrew/bin/nvim --clean", "-SmaltiEditorSocketDir", sockets,
        ]
    }

    /// F4: zsh with Ghostty's integration and Smalti's input script, which `zsh -f` would skip. `-d` skips the
    /// global rc files and `-SmaltiUserZdotdir` points the user's ZDOTDIR at an empty temporary folder, so neither
    /// the user's `.zshrc` (tmux, plugins) nor their history is ever read.
    static let integratedShell = "/bin/zsh -d"

    /// F5: the shell keeps the `.zshrc`'s `p% ` prompt (`[prompt] source = "shell"`) unless `smaltiPrompt` is true,
    /// so F4's tests read the prompt they were written for; PromptTests turn Smalti's on.
    static func isolatedSmaltiWithIntegration(smaltiPrompt: Bool = false) -> XCUIApplication {
        let app = isolatedSmalti(shell: integratedShell)
        if !smaltiPrompt { app.writeTheme("[prompt]\nsource = \"shell\"\n") }
        let zdotdir = app.configFile.deletingLastPathComponent().appending(path: "zdotdir")
        try? FileManager.default.createDirectory(at: zdotdir, withIntermediateDirectories: true)
        try? Data("PS1='p%% '\n".utf8).write(to: zdotdir.appending(path: ".zshrc"))
        app.launchArguments += ["-SmaltiUserZdotdir", zdotdir.path(percentEncoded: false)]
        return app
    }

    /// F5.6: a fake `claude` (a script the app runs with `/bin/sh`) next to the config that answers `plugin list` from a state file and installs or
    /// uninstalls by touching it; `installed` sets the starting state. Returns the state file.
    @discardableResult
    func useFakeClaude(installed: Bool) -> URL {
        let folder = configFile.deletingLastPathComponent()
        let script = folder.appending(path: "fake-claude")
        let state = folder.appending(path: "claude-state")
        let text = """
            #!/bin/sh
            state="$(dirname "$0")/claude-state"
            echo "$*" >> "$(dirname "$0")/claude-calls"
            case "$*" in
              "plugin list") [ -f "$state" ] && echo "  ❯ smalti@smalti"; exit 0 ;;
              "plugin install smalti@smalti") touch "$state" ;;
              "plugin uninstall smalti@smalti") rm -f "$state" ;;
            esac
            exit 0
            """
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try text.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: script.path(percentEncoded: false))
            if installed { try Data().write(to: state) }
        } catch {
            XCTFail("could not write the fake claude: \(error)")
        }
        if let position = launchArguments.firstIndex(of: "-SmaltiClaudeCommand") {
            launchArguments[position + 1] = script.path(percentEncoded: false)
        }
        // Every ⌘K asks again, so a test sees an external change on its next opening.
        launchArguments += ["-SmaltiIntegrationRecheckSeconds", "0"]
        return state
    }

    /// The temporary config file this launch reads; tests rewrite it before "Recargar configuración".
    var configFile: URL {
        // isolatedSmalti always passes the argument followed by its value.
        guard let position = launchArguments.firstIndex(of: "-SmaltiConfigPath") else {
            preconditionFailure("not an isolated Smalti: no -SmaltiConfigPath")
        }
        return URL(filePath: launchArguments[position + 1])
    }

    /// The temporary state directory (sessions, layouts, socket) of this launch, next to its config file.
    var stateDirectory: URL {
        guard let position = launchArguments.firstIndex(of: "-SmaltiStatePath") else {
            preconditionFailure("not an isolated Smalti: no -SmaltiStatePath")
        }
        return URL(filePath: launchArguments[position + 1])
    }

    func writeConfig(_ text: String) {
        let file = configFile
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            XCTFail("could not write the fixture config at \(file.path(percentEncoded: false)): \(error)")
        }
    }

    /// F5: `theme.toml` next to the config file, as the app looks for it.
    func writeTheme(_ text: String) {
        let file = configFile.deletingLastPathComponent().appending(path: "theme.toml")
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            XCTFail("could not write the fixture theme at \(file.path(percentEncoded: false)): \(error)")
        }
    }

    /// Named `config.toml`, as the user's file, so the status bar shows the same name. Created only on write.
    private static var isolatedConfigFile: URL {
        FileManager.default.temporaryDirectory.appending(path: "smalti-ui-tests-\(UUID().uuidString)/config.toml")
    }

    /// The Claude home this launch reads (`-SmaltiClaudeHome`): empty unless a test installs transcripts.
    var claudeHome: URL {
        guard let position = launchArguments.firstIndex(of: "-SmaltiClaudeHome") else {
            preconditionFailure("not an isolated Smalti: no -SmaltiClaudeHome")
        }
        return URL(filePath: launchArguments[position + 1])
    }

    /// Writes the bundled observatory fixture into `claudeHome`, each transcript moved so its newest line is a few
    /// minutes ago (the first file newest), so every session falls in "today" whenever the suite runs.
    func installObservatoryFixture(from bundle: Bundle, newestFirst: [String] = []) throws {
        let url = try XCTUnwrap(bundle.url(forResource: "observatory-claude-home", withExtension: "json"))
        let fixture = try JSONDecoder().decode([String: [String: [String]]].self, from: Data(contentsOf: url))
        let files = fixture["files"] ?? [:]
        let order = newestFirst + files.keys.sorted().filter { !newestFirst.contains($0) }
        for (rank, path) in order.enumerated() {
            let newest = Date().addingTimeInterval(-Double(5 + rank) * 60)
            let target = claudeHome.appending(path: path)
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let lines = TranscriptShift.lines(files[path] ?? [], newest: newest)
            try Data(lines.map { $0 + "\n" }.joined().utf8).write(to: target)
        }
    }
}

/// Moves every `timestamp` of a transcript by the same amount, so its last one lands on `newest`.
enum TranscriptShift {
    static func lines(_ lines: [String], newest: Date) -> [String] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parse = { (text: String) in formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text) }
        let records = lines.map { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] }
        let latest = records.compactMap { ($0?["timestamp"] as? String).flatMap(parse) }.max() ?? newest
        let delta = newest.timeIntervalSince(latest)
        return zip(lines, records).map { line, record in
            guard var record, let text = record["timestamp"] as? String, let date = parse(text) else { return line }
            record["timestamp"] = formatter.string(from: date.addingTimeInterval(delta))
            return (try? JSONSerialization.data(withJSONObject: record)).flatMap { String(data: $0, encoding: .utf8) }
                ?? line
        }
    }
}
