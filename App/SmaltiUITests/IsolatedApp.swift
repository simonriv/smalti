import Foundation
import XCTest

extension XCUIApplication {
    /// Smalti launched with a shell that reads no startup files and a config file that does not exist (so the
    /// defaults apply). The user's login shell may attach to a shared tmux session, and tests must never read or
    /// write the user's own `~/.config/smalti/config.toml`.
    static func isolatedSmalti(shell: String = "/bin/zsh -f") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-SmaltiShellCommand", shell, "-SmaltiConfigPath", isolatedConfigPath]
        return app
    }

    /// Never created: a missing file means "use the defaults".
    private static var isolatedConfigPath: String {
        FileManager.default.temporaryDirectory.appending(path: "smalti-ui-tests-\(UUID().uuidString).toml")
            .path(percentEncoded: false)
    }
}
