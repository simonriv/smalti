import XCTest

extension XCUIApplication {
    /// Smalti launched with a shell that reads no startup files. The user's login shell may attach to a
    /// shared tmux session, and typed test input must never reach it.
    static func isolatedSmalti() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-SmaltiShellCommand", "/bin/zsh -f"]
        return app
    }
}
