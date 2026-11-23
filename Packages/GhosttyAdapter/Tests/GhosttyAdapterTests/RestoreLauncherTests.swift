import Foundation
import SmaltiCore
import Testing

@testable import GhosttyAdapter

@Suite("Restore launcher")
struct RestoreLauncherTests {
    private let banner = "── restaurado · 22 nov 23:48 ──"

    @Test func launcherPrintsTheFileThenTheBannerThenExecsTheShell() {
        let command = RestoreLauncher.command(shell: .custom("/bin/zsh -f"))

        #expect(command.hasPrefix("/bin/sh -c '"))
        #expect(command.contains(#"cat "$SMALTI_RESTORE_FILE""#))
        #expect(command.contains(#"rm -f "$SMALTI_RESTORE_FILE""#))
        #expect(command.contains(#""$SMALTI_RESTORE_BANNER""#))
        #expect(!command.contains(banner))
        #expect(command.hasSuffix("exec /bin/zsh -f'"))
    }

    @Test func loginShellStaysALoginShell() {
        let command = RestoreLauncher.command(shell: .loginShell)

        #expect(command.hasSuffix(#"exec "${SHELL:-/bin/zsh}" -l'"#))
    }

    @Test func singleQuotesInTheShellCommandAreEscaped() {
        let command = RestoreLauncher.command(shell: .custom("/bin/zsh -f -c 'echo hi'"))

        #expect(command.contains(#"exec /bin/zsh -f -c '\''echo hi'\'''"#))
    }

    /// Runs the launcher for real, as libghostty would: file, banner, then a login zsh.
    @Test func launcherRunsWithALoginShell() throws {
        let work = FileManager.default.temporaryDirectory.appending(path: "smalti-launcher-\(UUID())")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let file = work.appending(path: "restore.txt")
        try Data("salida-previa\n".utf8).write(to: file)
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = [
            "-c",
            String(RestoreLauncher.command(shell: .loginShell).dropFirst("/bin/sh -c ".count).dropFirst().dropLast()),
        ]
        process.environment = [
            "HOME": work.path(percentEncoded: false), "ZDOTDIR": work.path(percentEncoded: false), "SHELL": "/bin/zsh",
            "TERM": "xterm", "TMUX": "smalti-tests", RestoreLauncher.fileVariable: file.path(percentEncoded: false),
            RestoreLauncher.bannerVariable: banner,
        ]
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        try process.run()
        stdin.fileHandleForWriting.write(Data("print -r -- LOGIN=$options[login]\nexit\n".utf8))
        try stdin.fileHandleForWriting.close()
        let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()

        #expect(output.contains("salida-previa"))
        #expect(output.contains(banner))
        #expect(output.contains("LOGIN=on"))
        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }

    @Test func bannerIsPrintedInTheSecondaryGrey() {
        let command = RestoreLauncher.command(shell: .loginShell)

        #expect(command.contains(#"\033[38;2;139;145;156m"#))
    }
}
