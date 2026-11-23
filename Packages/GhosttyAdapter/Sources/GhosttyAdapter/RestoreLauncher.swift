import SmaltiCore

/// The command a restored pane starts with: it prints the saved scrollback (from `$SMALTI_RESTORE_FILE`), removes
/// that file, prints the "restaurado" banner in the secondary grey and replaces itself with the pane's shell.
/// It runs through `/bin/sh`, so it works with any shell, also `zsh -f` in tests; libghostty's zsh integration
/// still reaches the final shell through `ZDOTDIR`, which it exports to the whole process tree.
enum RestoreLauncher {
    static let fileVariable = "SMALTI_RESTORE_FILE"
    /// The banner travels in the environment, so no character in it is ever read as shell syntax.
    static let bannerVariable = "SMALTI_RESTORE_BANNER"
    /// `#8b919c` (secondary text) as a true-colour SGR.
    private static let bannerColor = #"\033[38;2;139;145;156m"#

    /// The banner is not part of the command: pass it as `bannerVariable` in the pane's environment.
    static func command(shell: TerminalCommand) -> String {
        let script = [
            #"cat "$\#(fileVariable)""#,
            #"rm -f "$\#(fileVariable)""#,
            #"printf "\#(bannerColor)%s\033[0m\n" "$\#(bannerVariable)""#,
            exec(shell),
        ].joined(separator: "; ")
        return "/bin/sh -c " + singleQuoted(script)
    }

    private static func exec(_ shell: TerminalCommand) -> String {
        switch shell {
        // POSIX `exec` has no -l; zsh, bash and fish all take -l for a login shell.
        case .loginShell: #"exec "${SHELL:-/bin/zsh}" -l"#
        case .custom(let command): "exec \(command)"
        }
    }

    private static func singleQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
