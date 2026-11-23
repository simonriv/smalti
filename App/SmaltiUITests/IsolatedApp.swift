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
        if let config { app.writeConfig(config) }
        return app
    }

    /// The temporary config file this launch reads; tests rewrite it before "Recargar configuración".
    var configFile: URL {
        // isolatedSmalti always passes the argument followed by its value.
        guard let position = launchArguments.firstIndex(of: "-SmaltiConfigPath") else {
            preconditionFailure("not an isolated Smalti: no -SmaltiConfigPath")
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

    /// Named `config.toml`, as the user's file, so the status bar shows the same name. Created only on write.
    private static var isolatedConfigFile: URL {
        FileManager.default.temporaryDirectory.appending(path: "smalti-ui-tests-\(UUID().uuidString)/config.toml")
    }
}
