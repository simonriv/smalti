/// F5's zsh side of Smalti's prompt (spec "Del dominio a zsh"), inside the input script's block so it shares its
/// channel. zsh paints an immediate prompt at once from what it knows (directory, duration, exit) and the full one
/// when Smalti answers; it never waits. Text from outside lives in `psvar` slots that the prompt shows with `%Nv`:
/// zsh inserts it as it is, with no expansion and no option of the user's mattering. Slots: 1 symbol, 2 directory,
/// 3 duration, 4 onward the full prompt's values. With an empty immediate prompt (`source = "shell"`) the user's own
/// prompt comes back.
enum SmaltiPromptScript {
    static let functions = #"""
                typeset -g _smalti_prompt_on=0 _smalti_prompt_seq=-1 _smalti_prompt_immediate= _smalti_prompt_started=
                typeset -g _smalti_prompt_saved=0 _smalti_prompt_user= _smalti_prompt_user_right=
                typeset -g _smalti_dir= _smalti_duration= _smalti_ghost_color=
                typeset -gA _smalti_prompt_labels

                # Milliseconds as the prompt shows them, like DurationModule: nothing under 2 s, "4.2s", then "2m 5s".
                _smalti_prompt_format() {
                    emulate -L zsh
                    local ms=$1
                    if (( ms < 2000 )); then
                        _smalti_duration=
                    elif (( ms < 60000 )); then
                        _smalti_duration="$(( ms / 1000 )).$(( ms / 100 % 10 ))s"
                    else
                        _smalti_duration="$(( ms / 60000 ))m $(( ms / 1000 % 60 ))s"
                    fi
                }

                # The directory label: what Smalti last said for this directory, else zsh's last two levels.
                _smalti_prompt_where() {
                    emulate -L zsh
                    _smalti_dir=${_smalti_prompt_labels[$PWD]:-${(%):-%2~}}
                }

                # `slot=text` pairs separated by U+001F into psvar; anything that is not a slot from 1 to 64 is ignored.
                _smalti_prompt_assign() {
                    emulate -L zsh
                    local pair slot
                    local -a pairs
                    pairs=("${(@ps:\x1f:)1}")
                    for pair in $pairs; do
                        slot=${pair%%=*}
                        [[ $slot == <1-64> ]] || continue
                        psvar[$slot]=${pair#*=}
                    done
                }

                _smalti_prompt_show() {
                    emulate -L zsh
                    psvar[2]=$_smalti_dir
                    psvar[3]=$_smalti_duration
                    PROMPT=$1
                    RPROMPT=
                }

                # A prompt set outside precmd (Smalti's answer, a new style) carries Ghostty's OSC 133 marks itself, as
                # Ghostty would add them, so the terminal keeps knowing where the prompt is; and Ghostty's next precmd sees
                # it as its own marked prompt and starts again from the clean one.
                _smalti_prompt_mark() {
                    emulate -L zsh
                    PROMPT=$1
                    RPROMPT=
                    (( ${+functions[_ghostty_precmd]} )) || return 0
                    local mark1=$'%{\e]133;A;cl=line\a%}' mark2=$'%{\e]133;P;k=s\a%}' markB=$'%{\e]133;B\a%}'
                    typeset -g _ghostty_saved_ps1=$1
                    PROMPT=${mark1}${1//$'\n'/$'\n'${mark2}}${markB}
                    typeset -g _ghostty_marked_ps1=$PROMPT
                }

                # The user's prompt is kept the first time Smalti's takes over, and given back when asked.
                _smalti_prompt_save() {
                    (( _smalti_prompt_saved )) && return 0
                    _smalti_prompt_user=$PROMPT
                    _smalti_prompt_user_right=$RPROMPT
                    _smalti_prompt_saved=1
                }

                _smalti_prompt_restore() {
                    _smalti_prompt_on=0
                    (( _smalti_prompt_saved )) || return 0
                    PROMPT=$_smalti_prompt_user
                    RPROMPT=$_smalti_prompt_user_right
                    _smalti_prompt_saved=0
                }

                # `promptstyle <immediate> <#ghost> <values>` and `prompt <seq> <label> <immediate> <full> <values>`. A
                # `prompt` counts only for the last `context` of this prompt: after a command it is stale.
                _smalti_prompt_apply() {
                    emulate -L zsh
                    local -a fields
                    fields=("${(@ps:\t:)1}")
                    case $fields[1] in
                        promptstyle)
                            [[ $fields[3] == '#'[[:xdigit:]][[:xdigit:]][[:xdigit:]][[:xdigit:]][[:xdigit:]][[:xdigit:]] ]] \
                                && _smalti_ghost_color=$fields[3]
                            _smalti_input_unescape "$fields[2]"
                            if [[ -z $_smalti_input_text ]]; then
                                _smalti_prompt_restore
                            else
                                _smalti_prompt_immediate=$_smalti_input_text
                                _smalti_input_unescape "$fields[4]"
                                _smalti_prompt_assign "$_smalti_input_text"
                                _smalti_prompt_save
                                _smalti_prompt_on=1
                                psvar[2]=$_smalti_dir
                                psvar[3]=$_smalti_duration
                                _smalti_prompt_mark "$_smalti_prompt_immediate"
                            fi
                            ;;
                        prompt)
                            (( _smalti_prompt_on )) || return 0
                            [[ $fields[2] == <-> ]] && (( fields[2] == _smalti_prompt_seq )) || return 0
                            _smalti_input_unescape "$fields[3]"
                            [[ -n $_smalti_input_text ]] && _smalti_prompt_labels[$PWD]=$_smalti_input_text
                            _smalti_input_unescape "$fields[6]"
                            _smalti_prompt_assign "$_smalti_input_text"
                            _smalti_input_unescape "$fields[5]"
                            _smalti_prompt_mark "$_smalti_input_text"
                            ;;
                        *) return 0 ;;
                    esac
                    zle && zle reset-prompt
                    return 0
                }

                _smalti_prompt_preexec() {
                    emulate -L zsh
                    _smalti_input_prompt=0
                    _smalti_prompt_seq=-1
                    _smalti_prompt_started=$EPOCHREALTIME
                }

                # The last precmd hook but Ghostty's (it moves itself there each time), so a framework's prompt set
                # earlier is replaced and Ghostty, last, adds its OSC 133 marks to Smalti's prompt.
                _smalti_prompt_precmd() {
                    local code=$?
                    emulate -L zsh
                    local -a hooks
                    hooks=(${precmd_functions:#(_smalti_prompt_precmd|_ghostty_precmd)} _smalti_prompt_precmd)
                    (( ${precmd_functions[(Ie)_ghostty_precmd]} )) && hooks+=(_ghostty_precmd)
                    precmd_functions=($hooks)
                    _smalti_input_prompt=1
                    local ms=0
                    if [[ -n $_smalti_prompt_started ]]; then
                        ms=$(( (EPOCHREALTIME - _smalti_prompt_started) * 1000 ))
                        ms=${ms%.*}
                    fi
                    _smalti_prompt_started=
                    _smalti_prompt_format $ms
                    _smalti_prompt_where
                    (( _smalti_prompt_on )) && _smalti_prompt_show "$_smalti_prompt_immediate"
                    local runtimes= kind executable
                    for kind executable in node "${commands[node]}" bun "${commands[bun]}" python "${commands[python3]}" \
                        go "${commands[go]}"; do
                        [[ -n $executable ]] && runtimes+="${runtimes:+;}$kind=$executable"
                    done
                    local -a parts
                    local field
                    for field in "$PWD" "${AWS_PROFILE-}" "${KUBECONFIG-}" "$runtimes"; do
                        _smalti_input_escape "$field"
                        parts+=("$_smalti_input_text")
                    done
                    _smalti_prompt_seq=$(( ++_smalti_input_seq ))
                    _smalti_input_send "context"$'\t'$_smalti_prompt_seq$'\t'$parts[1]$'\t'$code$'\t'$ms$'\t'$parts[2]$'\t'$parts[3]$'\t'$parts[4]
                    return 0
                }
        """#
}
