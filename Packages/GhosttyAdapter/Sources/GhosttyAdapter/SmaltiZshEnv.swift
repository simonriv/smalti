import Foundation

/// Smalti's zsh startup file, for per-pane history next to the shared one (F2, Terminal.app's model).
///
/// libghostty enables its zsh integration by pointing `ZDOTDIR` at it and, from its `.zshenv`, sources the
/// `.zshenv` of `GHOSTTY_ZSH_ZDOTDIR`: Smalti puts its own directory there. This file restores the user's
/// `ZDOTDIR` (`SMALTI_USER_ZDOTDIR`, else the home directory), so zsh then reads the user's files as always, and
/// after them (first `precmd`) loads the pane's history when restoring and starts copying each command to
/// `SMALTI_HISTORY_FILE`. The user's own `HISTFILE` and `SHARE_HISTORY` stay untouched.
enum SmaltiZshEnv {
    static let text = #"""
        # Smalti: per-pane history (F2). Sourced by Ghostty's zsh integration through GHOSTTY_ZSH_ZDOTDIR.
        if [[ -n "${SMALTI_USER_ZDOTDIR+X}" ]]; then
            'builtin' 'export' ZDOTDIR="$SMALTI_USER_ZDOTDIR"
        else
            'builtin' 'unset' 'ZDOTDIR'
        fi
        'builtin' 'unset' 'SMALTI_USER_ZDOTDIR'
        'builtin' 'typeset' _smalti_file=${ZDOTDIR-$HOME}"/.zshenv"
        [[ ! -r "$_smalti_file" ]] || 'builtin' 'source' '--' "$_smalti_file"
        'builtin' 'unset' '_smalti_file'

        if [[ -o interactive && -n "$SMALTI_HISTORY_FILE" ]]; then
            _smalti_history_init() {
                builtin emulate -L zsh
                precmd_functions=(${precmd_functions:#_smalti_history_init})
                if [[ -n "$SMALTI_RESTORE_HISTORY" && -r "$SMALTI_HISTORY_FILE" ]]; then
                    builtin fc -R "$SMALTI_HISTORY_FILE"
                fi
                builtin unset SMALTI_RESTORE_HISTORY
                zshaddhistory_functions+=(_smalti_add_history)
            }
            _smalti_add_history() {
                builtin emulate -L zsh
                [[ -d "${SMALTI_HISTORY_FILE:h}" ]] || command mkdir -p -m 700 "${SMALTI_HISTORY_FILE:h}"
                builtin print -r -- "${1%%$'\n'}" >> "$SMALTI_HISTORY_FILE"
                builtin return 0
            }
            builtin typeset -ag precmd_functions zshaddhistory_functions
            precmd_functions+=(_smalti_history_init)
        fi
        """#

    /// Writes `.zshenv` into `directory` (created owner-only) and returns the directory.
    static func install(in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Data(text.utf8).write(to: directory.appending(path: ".zshenv"), options: .atomic)
        return directory
    }
}
