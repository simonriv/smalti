import Foundation
import SmaltiCore
import Testing

@testable import GhosttyAdapter

@Suite("Restore launcher")
struct RestoreLauncherTests {
    private let banner = "── restaurado · 22 nov 23:48 ──"

    @Test func launcherPrintsTheFileThenTheBannerThenExecsTheShell() {
        let command = RestoreLauncher.command(shell: .custom("/bin/zsh -f"), banner: banner)

        #expect(command.hasPrefix("/bin/sh -c '"))
        #expect(command.contains(#"cat "$SMALTI_RESTORE_FILE""#))
        #expect(command.contains(#"rm -f "$SMALTI_RESTORE_FILE""#))
        #expect(command.contains(banner))
        #expect(command.hasSuffix("exec /bin/zsh -f'"))
    }

    @Test func loginShellStaysALoginShell() {
        let command = RestoreLauncher.command(shell: .loginShell, banner: banner)

        #expect(command.hasSuffix(#"exec -l "${SHELL:-/bin/zsh}"'"#))
    }

    @Test func singleQuotesInTheShellCommandAreEscaped() {
        let command = RestoreLauncher.command(shell: .custom("/bin/zsh -f -c 'echo hi'"), banner: banner)

        #expect(command.contains(#"exec /bin/zsh -f -c '\''echo hi'\'''"#))
    }

    @Test func bannerIsPrintedInTheSecondaryGrey() {
        let command = RestoreLauncher.command(shell: .loginShell, banner: banner)

        #expect(command.contains(#"\033[38;2;139;145;156m"#))
    }
}
