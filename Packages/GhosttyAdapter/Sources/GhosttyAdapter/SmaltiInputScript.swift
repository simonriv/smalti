/// F4's zsh side of the input channel (spec "Canal zsh ↔ Smalti"), appended to Smalti's `.zshenv`.
///
/// It installs at the first prompt, after the user's `.zshrc`, only in interactive shells with
/// `SMALTI_INPUT_SOCKET`. zsh keeps editing the line; this script reports the line and each command to Smalti and
/// paints the ghost text Smalti answers with (`POSTDISPLAY`). It never waits for Smalti: answers arrive through
/// `zle -F -w`, and the only writer checks the socket is writable and ignores SIGPIPE just while writing, so a
/// slow, stuck or vanished Smalti leaves a plain zsh behind. Every answer whose `seq` is not the last one sent is
/// dropped.
enum SmaltiInputScript {
    static let text = #"""
        # Smalti F4: suggestions over $SMALTI_INPUT_SOCKET. zsh edits the line; Smalti only suggests.
        if [[ -o interactive && -n "$SMALTI_INPUT_SOCKET" ]]; then
            typeset -g _smalti_input_fd= _smalti_input_seq=0 _smalti_input_state= _smalti_input_ghost=
            typeset -g _smalti_input_exec=0 _smalti_input_have_specs=0
            typeset -ga _smalti_input_specs
            typeset -g _smalti_input_right=forward-char _smalti_input_end=end-of-line
            typeset -g _smalti_input_tab=expand-or-complete

            _smalti_input_escape() {
                local text=${1//\\/\\\\}
                text=${text//$'\t'/\\t}
                REPLY=${text//$'\n'/\\n}
            }

            _smalti_input_unescape() {
                local text=${1//\\\\/$'\0'}
                text=${text//\\t/$'\t'}
                text=${text//\\n/$'\n'}
                REPLY=${text//$'\0'/\\}
            }

            # The only writer. Never blocks and never dies of SIGPIPE. `zselect -w` only promises room for the
            # socket's low-water mark (2048 bytes on Darwin), so messages are kept under 2000 bytes; a longer one
            # (a huge paste) is not sent.
            _smalti_input_send() {
                setopt localoptions localtraps
                trap '' PIPE
                [[ -n $_smalti_input_fd ]] || return 1
                _smalti_input_fits "$1" || return 1
                zselect -t 0 -w $_smalti_input_fd 2>/dev/null || return 0
                print -r -u $_smalti_input_fd -- "$1" 2>/dev/null || { _smalti_input_disable; return 1 }
            }

            # Turns the channel off for this shell, quietly: zsh stays as if Smalti were not there.
            _smalti_input_disable() {
                if [[ -n $_smalti_input_fd ]]; then
                    zle -F $_smalti_input_fd 2>/dev/null
                    exec {_smalti_input_fd}>&- 2>/dev/null
                fi
                _smalti_input_fd=
                _smalti_input_ghost=
                if zle; then
                    POSTDISPLAY=
                    region_highlight=("${(@)region_highlight:#*memo=smalti}")
                fi
            }

            _smalti_input_paint() {
                _smalti_input_ghost=$1
                POSTDISPLAY=$1
                region_highlight=("${(@)region_highlight:#*memo=smalti}")
                [[ -n $1 ]] && region_highlight+=("${#BUFFER} $(( ${#BUFFER} + ${#1} )) fg=#5f6672 memo=smalti")
            }

            _smalti_input_fits() {
                setopt localoptions nomultibyte
                (( ${#1} < 2000 ))
            }

            # Before every redraw: when the line changed, keep the part of the ghost still ahead of the cursor and
            # tell Smalti the new line.
            _smalti_input_redraw() {
                [[ -n $_smalti_input_fd ]] || return 0
                local state="$CURSOR:$BUFFER"
                [[ $state == "$_smalti_input_state" ]] && return 0
                local previous=${_smalti_input_state#*:}
                _smalti_input_state=$state
                local expected=$previous$_smalti_input_ghost
                if (( CURSOR == ${#BUFFER} )) && [[ -n $_smalti_input_ghost && $expected == "$BUFFER"?* ]]; then
                    _smalti_input_paint "${expected#"$BUFFER"}"
                else
                    _smalti_input_paint ""
                fi
                _smalti_input_escape "$BUFFER"
                local message="line"$'\t'$(( _smalti_input_seq + 1 ))$'\t'$CURSOR$'\t'$REPLY
                _smalti_input_fits "$message" || { _smalti_input_paint ""; return 0 }
                (( _smalti_input_seq++ ))
                _smalti_input_send "$message"
            }

            _smalti_input_line_init() {
                _smalti_input_state=
                _smalti_input_ghost=
            }

            # An accepted line keeps no ghost on screen.
            _smalti_input_line_finish() {
                _smalti_input_paint ""
            }

            _smalti_input_apply() {
                local -a fields
                fields=("${(@ps:\t:)1}")
                case $fields[1] in
                    specs)
                        _smalti_input_specs=(${=fields[2]})
                        _smalti_input_have_specs=1
                        ;;
                    suggest)
                        (( fields[2] == _smalti_input_seq )) || return 0
                        _smalti_input_unescape "$fields[3]"
                        (( CURSOR == ${#BUFFER} )) && _smalti_input_paint "$REPLY"
                        ;;
                    edit)
                        (( fields[2] == _smalti_input_seq )) || return 0
                        _smalti_input_unescape "${(pj:\t:)fields[4,-1]}"
                        BUFFER=$REPLY
                        CURSOR=$fields[3]
                        _smalti_input_paint ""
                        ;;
                    run)
                        (( fields[2] == _smalti_input_seq )) || return 0
                        _smalti_input_paint ""
                        zle accept-line
                        ;;
                    fallback)
                        (( fields[2] == _smalti_input_seq )) || return 0
                        zle $_smalti_input_tab
                        ;;
                esac
            }

            # `zle -F -w` handler: reads every answer waiting on the socket; an error or EOF disables the channel.
            _smalti_input_receive() {
                local fd=$1 line
                if [[ -n $2 ]]; then
                    _smalti_input_disable
                    return 0
                fi
                while :; do
                    if ! IFS= read -r -u $fd line; then
                        _smalti_input_disable
                        return 0
                    fi
                    _smalti_input_apply "$line"
                    zselect -t 0 -r $fd 2>/dev/null || break
                done
                zle -R
            }

            # → and ⌃E accept the ghost at the end of the line; otherwise they do what they did before.
            smalti-accept() {
                if [[ -n $_smalti_input_ghost ]] && (( CURSOR == ${#BUFFER} )); then
                    BUFFER+=$_smalti_input_ghost
                    CURSOR=${#BUFFER}
                    _smalti_input_paint ""
                else
                    zle $_smalti_input_right
                fi
            }

            smalti-accept-end() {
                if [[ -n $_smalti_input_ghost ]] && (( CURSOR == ${#BUFFER} )); then
                    zle smalti-accept
                else
                    zle $_smalti_input_end
                fi
            }

            _smalti_input_preexec() {
                _smalti_input_exec=0
                [[ -o histignorespace && $1 == ' '* ]] && return 0
                [[ -n $HISTORY_IGNORE && $1 == ${~HISTORY_IGNORE} ]] && return 0
                _smalti_input_escape "${1%$'\n'}"
                _smalti_input_send "exec"$'\t'$(( ++_smalti_input_seq ))$'\t'$REPLY && _smalti_input_exec=1
            }

            _smalti_input_precmd() {
                local code=$?
                (( _smalti_input_exec )) || return 0
                _smalti_input_exec=0
                _smalti_input_send "done"$'\t'$(( ++_smalti_input_seq ))$'\t'$code
            }

            # The widget a key had before Smalti took it, for when Smalti has nothing to do.
            _smalti_input_previous() {
                local binding=${${(z)"$(bindkey -M emacs -- $1)"}[2]}
                REPLY=${binding:-$2}
                [[ $REPLY == undefined-key ]] && REPLY=$2
            }

            _smalti_input_install() {
                precmd_functions=(${precmd_functions:#_smalti_input_install})
                zmodload zsh/net/socket zsh/zselect 2>/dev/null || return 0
                zsocket "$SMALTI_INPUT_SOCKET" 2>/dev/null || return 0
                _smalti_input_fd=$REPLY
                zle -N _smalti_input_receive
                zle -N smalti-accept
                zle -N smalti-accept-end
                zle -N _smalti_input_redraw
                zle -N _smalti_input_line_init
                zle -N _smalti_input_line_finish
                zle -F -w $_smalti_input_fd _smalti_input_receive
                autoload -Uz add-zle-hook-widget
                add-zle-hook-widget line-pre-redraw _smalti_input_redraw
                add-zle-hook-widget line-init _smalti_input_line_init
                add-zle-hook-widget line-finish _smalti_input_line_finish
                _smalti_input_previous '^[[C' forward-char; _smalti_input_right=$REPLY
                _smalti_input_previous '^E' end-of-line; _smalti_input_end=$REPLY
                _smalti_input_previous '^I' expand-or-complete; _smalti_input_tab=$REPLY
                local keymap
                for keymap in emacs viins; do
                    bindkey -M $keymap '^[[C' smalti-accept
                    bindkey -M $keymap '^[OC' smalti-accept
                    bindkey -M $keymap '^E' smalti-accept-end
                done
                preexec_functions+=(_smalti_input_preexec)
                precmd_functions+=(_smalti_input_precmd)
                _smalti_input_send "hello"$'\t'"$SMALTI_PANE_ID"
            }
            typeset -ag precmd_functions preexec_functions
            precmd_functions+=(_smalti_input_install)
        fi
        """#
}
