/// F4's zsh side of the input channel (spec "Canal zsh ↔ Smalti"), appended to Smalti's `.zshenv`.
///
/// It installs at the first prompt, after the user's `.zshrc`, only in interactive shells with
/// `SMALTI_INPUT_SOCKET`. zsh keeps editing the line; this script reports the line and each command to Smalti and
/// paints the ghost text Smalti answers with (`POSTDISPLAY`). It never waits for Smalti:
/// - answers arrive through `zle -F -w` and are read with `sysread` into a buffer, applying only complete lines;
/// - the only writer checks the socket is writable, keeps messages under 2000 bytes and ignores SIGPIPE just while
///   writing.
/// A slow, stuck or vanished Smalti leaves a plain zsh behind. Every function runs under `emulate -L zsh`, so the
/// user's options never change its behavior, and it uses its own variables (never `REPLY`). Only the shell
/// prompt takes part (between `precmd` and `preexec`), never `vared` or `select`, which run inside a command.
enum SmaltiInputScript {
    static let text = #"""
        # Smalti F4: suggestions over $SMALTI_INPUT_SOCKET. zsh edits the line; Smalti only suggests.
        if [[ -o interactive && -n "$SMALTI_INPUT_SOCKET" ]]; then
            typeset -g _smalti_input_fd= _smalti_input_seq=0 _smalti_input_state= _smalti_input_ghost=
            typeset -g _smalti_input_exec=0 _smalti_input_have_specs=0 _smalti_input_inbox= _smalti_input_text=
            typeset -g _smalti_input_prompt=0 _smalti_input_refuse_enter=0 _smalti_input_pwd=
            typeset -ga _smalti_input_specs
            # F5.6: role → color of the highlight (empty: off), the last spans (`start,end,role`) and their line.
            typeset -gA _smalti_hl_style
            typeset -ga _smalti_hl_spans
            typeset -g _smalti_hl_buffer=
            # The `seq` and text of the last `line` sent: a `complete` or `history` moves `seq` without changing the
            # line, and that line's highlight still applies to it.
            typeset -g _smalti_input_line_seq= _smalti_input_line_text=
            typeset -gA _smalti_input_previous

            _smalti_input_escape() {
                emulate -L zsh
                local text=${1//\\/\\\\}
                text=${text//$'\t'/\\t}
                _smalti_input_text=${text//$'\n'/\\n}
            }

            _smalti_input_unescape() {
                emulate -L zsh
                local text=${1//\\\\/$'\0'}
                text=${text//\\t/$'\t'}
                text=${text//\\n/$'\n'}
                _smalti_input_text=${text//$'\0'/\\}
            }

            # The shell's own directory, escaped, for every message that depends on it: OSC 7 may arrive later.
            _smalti_input_where() {
                emulate -L zsh
                _smalti_input_escape "$PWD"
                _smalti_input_pwd=$_smalti_input_text
            }

            _smalti_input_fits() {
                emulate -L zsh
                setopt nomultibyte
                (( ${#1} < 2000 ))
            }

            # The only writer. Returns 0 when sent, 2 when dropped (socket full or message too long), 1 when the
            # channel is off. `zselect -w` only promises room for the socket's low-water mark (2048 bytes on
            # Darwin), hence the 2000-byte limit.
            _smalti_input_send() {
                emulate -L zsh
                setopt localtraps
                trap '' PIPE
                # `zselect` answers in `reply`: kept local so the user's own `reply` survives.
                local -a reply
                [[ -n $_smalti_input_fd ]] || return 1
                _smalti_input_fits "$1" || return 2
                zselect -t 0 -w $_smalti_input_fd 2>/dev/null || return 2
                print -r -u $_smalti_input_fd -- "$1" 2>/dev/null || { _smalti_input_disable; return 1 }
            }

            # Turns the channel off for this shell, quietly: zsh stays as if Smalti were not there.
            _smalti_input_disable() {
                emulate -L zsh
                if [[ -n $_smalti_input_fd ]]; then
                    zle -F $_smalti_input_fd 2>/dev/null
                    # Braces: a bare `exec … 2>/dev/null` would redirect the shell's own stderr for good.
                    { exec {_smalti_input_fd}>&- } 2>/dev/null
                fi
                _smalti_input_fd=
                _smalti_input_ghost=
                _smalti_input_inbox=
                _smalti_hl_spans=()
                if zle; then
                    POSTDISPLAY=
                    region_highlight=("${(@)region_highlight:#*memo=smalti}")
                    region_highlight=("${(@)region_highlight:#*memo=smaltihl}")
                fi
            }

            # F5.6: whether a word names something the shell can run. Only lookups and file tests on the literal
            # word: never `eval`, globbing or expansion, so `$(…)` or backticks in it are just text.
            _smalti_hl_known() {
                emulate -L zsh
                local word=$1
                [[ -n $word ]] || return 1
                (( $+aliases[$word] || $+functions[$word] || $+builtins[$word] || $+commands[$word] )) && return 0
                (( ${reswords[(Ie)$word]} )) && return 0
                # A binary installed after the table was filled: `whence -p` only searches `PATH`.
                [[ $word != */* ]] && { whence -p -- "$word" >/dev/null 2>&1; return }
                [[ $word == '~/'* ]] && word=$HOME${word#\~}
                [[ -x $word && ! -d $word ]]
            }

            # F5.6: paints the spans Smalti gave for this line. A command that does not exist turns red only once
            # the cursor has left it; a path is underlined over the color it already has.
            _smalti_hl_paint() {
                emulate -L zsh
                region_highlight=("${(@)region_highlight:#*memo=smaltihl}")
                (( ${#_smalti_hl_style} )) || return 0
                local span start end role rest attr
                for span in $_smalti_hl_spans; do
                    start=${span%%,*}
                    rest=${span#*,}
                    end=${rest%%,*}
                    role=${rest#*,}
                    [[ $start == <-> && $end == <-> ]] && (( start < end && end <= ${#BUFFER} )) || continue
                    case $role in
                        p) attr=underline ;;
                        c)
                            if _smalti_hl_known "${(Q)BUFFER[start+1,end]}"; then
                                attr="fg=$_smalti_hl_style[c]"
                            elif (( CURSOR >= start && CURSOR <= end )); then
                                continue
                            else
                                attr="fg=$_smalti_hl_style[u]"
                            fi
                            ;;
                        v) attr="fg=$_smalti_hl_style[o]" ;;
                        s|o|q|x) attr="fg=$_smalti_hl_style[$role]" ;;
                        *) continue ;;
                    esac
                    region_highlight+=("$start $end $attr memo=smaltihl")
                done
            }

            # F5.6: before the answer for a new line arrives, keep only the spans that end before the first changed
            # character (or at it, when the change starts with a separator), so no color ever sits on text that is no
            # longer its own; a cursor move only repaints.
            _smalti_hl_keep_prefix() {
                emulate -L zsh
                (( ${#_smalti_hl_spans} )) || { region_highlight=("${(@)region_highlight:#*memo=smaltihl}"); return 0 }
                if [[ $BUFFER != "$_smalti_hl_buffer" ]]; then
                    local old=$_smalti_hl_buffer first i span rest
                    if [[ $BUFFER == "$old"* ]]; then
                        first=${#old}
                    else
                        i=1
                        while (( i <= ${#old} && i <= ${#BUFFER} )) && [[ ${BUFFER[i]} == "${old[i]}" ]]; do (( i++ )); done
                        first=$(( i - 1 ))
                    fi
                    # A span touching the change survives only when the change starts with a separator: the
                    # word just finished keeps its color, the one being typed loses it.
                    local -i reach=first
                    [[ ${BUFFER[first+1]} == [[:space:]\;\|\&\(\)\<\>] ]] && (( reach++ ))
                    local -a kept
                    for span in $_smalti_hl_spans; do
                        rest=${span#*,}
                        (( ${rest%%,*} < reach )) && kept+=($span)
                    done
                    _smalti_hl_spans=($kept)
                    _smalti_hl_buffer=$BUFFER
                fi
                _smalti_hl_paint
            }

            _smalti_input_paint() {
                emulate -L zsh
                _smalti_input_ghost=$1
                POSTDISPLAY=$1
                region_highlight=("${(@)region_highlight:#*memo=smalti}")
                [[ -n $1 ]] && region_highlight+=("${#BUFFER} $(( ${#BUFFER} + ${#1} )) fg=${_smalti_ghost_color:-${SMALTI_GHOST_COLOR:-#5f6672}} memo=smalti")
            }

            # Only the shell's own prompt takes part: from `precmd` to `preexec`. `vared` and `select` read lines
            # inside a running command, so they never do.
            _smalti_input_at_prompt() {
                [[ -n $_smalti_input_fd ]] && (( _smalti_input_prompt ))
            }

            # Before every redraw: when the line changed, keep the part of the ghost still ahead of the cursor and
            # tell Smalti the new line. A line too long to send still moves `seq`, so late answers are dropped.
            _smalti_input_redraw() {
                emulate -L zsh
                _smalti_input_at_prompt || return 0
                local state="$CURSOR:$BUFFER"
                [[ $state == "$_smalti_input_state" ]] && return 0
                local previous=${_smalti_input_state#*:}
                _smalti_input_state=$state
                _smalti_hl_keep_prefix
                local expected=$previous$_smalti_input_ghost
                if (( CURSOR == ${#BUFFER} )) && [[ -n $_smalti_input_ghost && $expected == "$BUFFER"?* ]]; then
                    _smalti_input_paint "${expected#"$BUFFER"}"
                else
                    _smalti_input_paint ""
                fi
                (( _smalti_input_seq++ ))
                _smalti_input_line_seq=$_smalti_input_seq
                _smalti_input_line_text=$BUFFER
                _smalti_input_where
                _smalti_input_escape "$BUFFER"
                local message="line"$'\t'$_smalti_input_seq$'\t'$_smalti_input_pwd$'\t'$CURSOR$'\t'$_smalti_input_text
                _smalti_input_send "$message" || _smalti_input_paint ""
                return 0
            }

            _smalti_input_line_init() {
                _smalti_input_state=
                _smalti_input_ghost=
                _smalti_hl_spans=()
                _smalti_hl_buffer=
                _smalti_input_refuse_enter=0
            }

            # An accepted line keeps no ghost on screen.
            _smalti_input_line_finish() {
                emulate -L zsh
                _smalti_input_paint ""
            }

            # A field that must be a number is checked before zsh does arithmetic with it.
            _smalti_input_is_current() {
                [[ $1 == <-> ]] && (( $1 == _smalti_input_seq ))
            }

            _smalti_input_apply() {
                emulate -L zsh
                local -a fields
                fields=("${(@ps:\t:)1}")
                case $fields[1] in
                    specs)
                        # A long list comes in several answers: they add up.
                        _smalti_input_specs+=(${(s: :)fields[2]})
                        _smalti_input_have_specs=1
                        ;;
                    suggest)
                        _smalti_input_is_current "$fields[2]" || return 0
                        _smalti_input_unescape "$fields[3]"
                        (( CURSOR == ${#BUFFER} )) && _smalti_input_paint "$_smalti_input_text"
                        ;;
                    edit|editrun)
                        # ⌘↩'s edit comes with Return right behind it: if the edit is dropped, so is that Return.
                        if ! _smalti_input_is_current "$fields[2]" || [[ $fields[3] != <-> ]]; then
                            [[ $fields[1] == editrun ]] && _smalti_input_refuse_enter=1
                            return 0
                        fi
                        _smalti_input_unescape "${(pj:\t:)fields[4,-1]}"
                        BUFFER=$_smalti_input_text
                        CURSOR=$fields[3]
                        _smalti_input_paint ""
                        ;;
                    fallback)
                        _smalti_input_is_current "$fields[2]" || return 0
                        _smalti_input_widget '^I' expand-or-complete
                        ;;
                    prompt|promptstyle)
                        _smalti_prompt_apply "$1"
                        ;;
                    highlight)
                        if ! _smalti_input_is_current "$fields[2]"; then
                            [[ $fields[2] == "$_smalti_input_line_seq" && $BUFFER == "$_smalti_input_line_text" ]] \
                                || return 0
                        fi
                        _smalti_hl_spans=(${(s: :)fields[3]})
                        _smalti_hl_buffer=$BUFFER
                        _smalti_hl_paint
                        ;;
                    highlightstyle)
                        if [[ $fields[2] == off ]]; then
                            _smalti_hl_style=()
                        else
                            _smalti_hl_style=(c "$fields[2]" u "$fields[3]" s "$fields[4]" o "$fields[5]" q "$fields[6]" x "$fields[7]")
                        fi
                        zle && _smalti_hl_paint
                        ;;
                esac
                return 0
            }

            # Reads what is waiting on the socket without blocking and applies every complete line; a partial
            # answer stays in the inbox until its newline arrives. EOF disables the channel.
            _smalti_input_drain() {
                emulate -L zsh
                local chunk lines line closed=0
                local -a reply
                while [[ -n $_smalti_input_fd ]] && zselect -t 0 -r $_smalti_input_fd 2>/dev/null; do
                    chunk=
                    if ! sysread -i $_smalti_input_fd -s 4096 chunk 2>/dev/null || [[ -z $chunk ]]; then
                        closed=1
                        break
                    fi
                    _smalti_input_inbox+=$chunk
                done
                # The last answers can arrive together with the end of the channel: they still count (F5).
                if [[ $_smalti_input_inbox == *$'\n'* ]]; then
                    lines=${_smalti_input_inbox%$'\n'*}
                    _smalti_input_inbox=${_smalti_input_inbox##*$'\n'}
                    for line in "${(@f)lines}"; do
                        # Away from the prompt (vared, select) only a new style still counts (block 3 review, M4).
                        [[ $1 == discard && $line != promptstyle$'\t'* && $line != highlightstyle$'\t'* ]] && continue
                        _smalti_input_apply "$line"
                    done
                fi
                (( closed )) && _smalti_input_disable
            }

            # `zle -F -w` handler (widget handlers get no error argument: a failed read tells instead). It always
            # reads, or zle would call it again at once; away from the prompt (`vared`) the answers are dropped.
            _smalti_input_receive() {
                emulate -L zsh
                if _smalti_input_at_prompt; then
                    _smalti_input_drain
                else
                    _smalti_input_drain discard
                fi
                zle -R
            }

            # Runs the widget a key had before Smalti took it, in the current keymap.
            _smalti_input_widget() {
                emulate -L zsh
                zle ${_smalti_input_previous[$KEYMAP:$1]:-${_smalti_input_previous[main:$1]:-$2}}
            }

            # → and ⌃E accept the ghost at the end of the line; otherwise they do what they did before.
            smalti-accept() {
                emulate -L zsh
                if [[ -n $_smalti_input_ghost ]] && (( CURSOR == ${#BUFFER} )); then
                    BUFFER+=$_smalti_input_ghost
                    CURSOR=${#BUFFER}
                    _smalti_input_paint ""
                elif [[ $KEYS == $'\eOC' ]]; then
                    _smalti_input_widget '^[OC' forward-char
                else
                    _smalti_input_widget '^[[C' forward-char
                fi
            }

            smalti-accept-end() {
                emulate -L zsh
                if [[ -n $_smalti_input_ghost ]] && (( CURSOR == ${#BUFFER} )); then
                    zle smalti-accept
                else
                    _smalti_input_widget '^E' end-of-line
                fi
            }

            # The command of the word being completed: the first word after the last separator before the cursor;
            # empty while the cursor is still on that command's name.
            _smalti_input_command() {
                emulate -L zsh
                local -a words
                words=(${(z)LBUFFER})
                local index=${#words} start=1
                while (( index > 0 )); do
                    if [[ $words[index] == (';'|'|'|'||'|'&'|'&&'|'|&'|'&|'|'&!'|';|'|'('|'{'|then|do|else|elif) ]]; then
                        start=$(( index + 1 ))
                        break
                    fi
                    (( index-- ))
                done
                _smalti_input_text=
                (( ${#words} >= start )) || return 0
                [[ ${#words} -gt $start || $LBUFFER == *[[:space:]] ]] && _smalti_input_text=$words[start]
                return 0
            }

            # Tab: Smalti's menu when it has a spec for the command; the user's own Tab otherwise, right away.
            smalti-complete() {
                emulate -L zsh
                _smalti_input_command
                local command=$_smalti_input_text
                if ! _smalti_input_at_prompt || [[ -z $command ]] || (( ! _smalti_input_have_specs )) \
                    || (( ! ${_smalti_input_specs[(Ie)$command]} )); then
                    _smalti_input_widget '^I' expand-or-complete
                    return
                fi
                _smalti_input_where
                _smalti_input_escape "$BUFFER"
                # A request that cannot go out (too long, socket full, channel off) leaves Tab to what it did before.
                _smalti_input_send "complete"$'\t'$(( ++_smalti_input_seq ))$'\t'"$_smalti_input_pwd"$'\t'$CURSOR$'\t'"$_smalti_input_text" \
                    || _smalti_input_widget '^I' expand-or-complete
                return 0
            }

            # ⌃R: Smalti's history palette, searching for what is on the line; the previous ⌃R when it is off.
            smalti-history() {
                emulate -L zsh
                if ! _smalti_input_at_prompt; then
                    _smalti_input_widget '^R' history-incremental-search-backward
                    return
                fi
                _smalti_input_where
                _smalti_input_escape "$BUFFER"
                _smalti_input_send "history"$'\t'$(( ++_smalti_input_seq ))$'\t'"$_smalti_input_pwd"$'\t'"$_smalti_input_text" \
                    || _smalti_input_widget '^R' history-incremental-search-backward
                return 0
            }

            # Enter: first the answers already waiting (⌘↩ in Smalti's palette sends `edit` and then Return, and
            # Return may be read first), then whatever Enter did before.
            smalti-accept-line() {
                emulate -L zsh
                _smalti_input_at_prompt && _smalti_input_drain
                if (( _smalti_input_refuse_enter )); then
                    _smalti_input_refuse_enter=0
                    return 0
                fi
                _smalti_input_widget '^M' accept-line
            }

            _smalti_input_preexec() {
                emulate -L zsh
                _smalti_input_prompt=0
                _smalti_input_exec=0
                [[ -n $_smalti_input_fd ]] || return 0
                [[ -o histignorespace && $1 == ' '* ]] && return 0
                [[ -n ${HISTORY_IGNORE-} && $1 == ${~HISTORY_IGNORE} ]] && return 0
                _smalti_input_where
                _smalti_input_escape "${1%$'\n'}"
                _smalti_input_send "exec"$'\t'$(( ++_smalti_input_seq ))$'\t'"$_smalti_input_pwd"$'\t'"$_smalti_input_text" \
                    && _smalti_input_exec=1
                return 0
            }

            _smalti_input_precmd() {
                local code=$?
                emulate -L zsh
                _smalti_input_prompt=1
                (( _smalti_input_exec )) || return 0
                _smalti_input_exec=0
                _smalti_input_send "done"$'\t'$(( ++_smalti_input_seq ))$'\t'$code
                return 0
            }

            _smalti_input_bye() {
                emulate -L zsh
                _smalti_input_send "bye"
                return 0
            }

            # Remembers, for every keymap, the widget each key had before Smalti took it.
            _smalti_input_remember() {
                emulate -L zsh
                local keymap key binding
                for keymap in main emacs viins vicmd; do
                    for key in '^I' '^R' '^M' '^E' '^[[C' '^[OC'; do
                        binding=${${(z)"$(bindkey -M $keymap -- "$key" 2>/dev/null)"}[2]}
                        [[ -n $binding && $binding != undefined-key ]] && _smalti_input_previous[$keymap:$key]=$binding
                    done
                done
                return 0
            }

        \#(SmaltiPromptScript.functions)

            _smalti_input_install() {
                local code=$?
                emulate -L zsh
                precmd_functions=(${precmd_functions:#_smalti_input_install})
                zmodload zsh/net/socket zsh/zselect zsh/system zsh/datetime zsh/parameter 2>/dev/null || return 0
                zsocket "$SMALTI_INPUT_SOCKET" 2>/dev/null || return 0
                # Moved to a descriptor of ten or more: the user's `exec 3>file` must never receive Smalti's lines.
                local low=$REPLY
                { exec {_smalti_input_fd}>&$low } 2>/dev/null || { { exec {low}>&- } 2>/dev/null; return 0 }
                { exec {low}>&- } 2>/dev/null
                zle -N _smalti_input_receive
                zle -F -w $_smalti_input_fd _smalti_input_receive
                # `SMALTI_INPUT_FEATURES=0`: Smalti's prompt only (spec F5); ghost, Tab, ⌃R and history stay off.
                if [[ ${SMALTI_INPUT_FEATURES:-1} != 0 ]]; then
                    _smalti_input_widgets
                fi
                preexec_functions+=(_smalti_prompt_preexec)
                zshexit_functions+=(_smalti_input_bye)
                _smalti_input_prompt=1
                _smalti_input_send "hello"$'\t'"$SMALTI_PANE_ID"
                # The first prompt is on screen already: its context goes now, with the startup files' last status
                # (block 3 review, M3); it also puts the precmd hook in place for the later ones.
                _smalti_prompt_context $code
                return 0
            }

            _smalti_input_widgets() {
                emulate -L zsh
                _smalti_input_remember
                zle -N smalti-accept
                zle -N smalti-accept-end
                zle -N smalti-complete
                zle -N smalti-history
                zle -N smalti-accept-line
                zle -N _smalti_input_redraw
                zle -N _smalti_input_line_init
                zle -N _smalti_input_line_finish
                autoload -Uz add-zle-hook-widget
                add-zle-hook-widget line-pre-redraw _smalti_input_redraw
                add-zle-hook-widget line-init _smalti_input_line_init
                add-zle-hook-widget line-finish _smalti_input_line_finish
                local keymap
                for keymap in emacs viins; do
                    bindkey -M $keymap '^[[C' smalti-accept
                    bindkey -M $keymap '^[OC' smalti-accept
                    bindkey -M $keymap '^E' smalti-accept-end
                    bindkey -M $keymap '^I' smalti-complete
                    bindkey -M $keymap '^R' smalti-history
                done
                # vi's command mode keeps ⌃R as redo; Enter goes through Smalti everywhere.
                for keymap in emacs viins vicmd; do
                    bindkey -M $keymap '^M' smalti-accept-line
                done
                preexec_functions+=(_smalti_input_preexec)
                precmd_functions+=(_smalti_input_precmd)
                return 0
            }
            typeset -ag precmd_functions preexec_functions zshexit_functions
            precmd_functions+=(_smalti_input_install)
        fi
        """#
}
