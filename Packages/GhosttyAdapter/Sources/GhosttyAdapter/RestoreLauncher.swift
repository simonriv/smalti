import SmaltiCore

/// The command a restored pane starts with: it prints the saved scrollback (from `$SMALTI_RESTORE_FILE`), removes
/// that file, prints the "restaurado" banner in the secondary grey and replaces itself with the pane's shell.
/// It runs through `/bin/sh`, so it works with any shell, also `zsh -f` in tests; libghostty's zsh integration
/// still reaches the final shell through `ZDOTDIR`, which it exports to the whole process tree.
enum RestoreLauncher {
    static let fileVariable = "SMALTI_RESTORE_FILE"
    /// `#8b919c` (secondary text) as a true-colour SGR.
    private static let bannerColor = #"\033[38;2;139;145;156m"#

    static func command(shell: TerminalCommand, banner: String) -> String {
        let script = [
            #"cat "$\#(fileVariable)""#,
            #"rm -f "$\#(fileVariable)""#,
            #"printf "\#(bannerColor)%s\033[0m\n" "\#(banner)""#,
            exec(shell),
        ].joined(separator: "; ")
        return "/bin/sh -c " + singleQuoted(script)
    }

    private static func exec(_ shell: TerminalCommand) -> String {
        switch shell {
        case .loginShell: #"exec -l "${SHELL:-/bin/zsh}""#
        case .custom(let command): "exec \(command)"
        }
    }

    private static func singleQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
