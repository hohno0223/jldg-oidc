#!/usr/bin/env bash
# Shared implementation. Use jldg-agent.sh or jldg-agent.csh, not this file.
# start/stop stdout is reserved for commands to evaluate in the calling shell.
# status prints human-readable information and must be run without eval.
shell_format=${1:-}
if [[ $shell_format != bash && $shell_format != tcsh ]]; then
    printf '%s\n' 'Use jldg-agent.sh or jldg-agent.csh start|stop|status.' >&2
    printf '/bin/false;\n'
    exit 2
fi
shift
if [[ $# != 1 || ( $1 != start && $1 != stop && $1 != status ) ]]; then
    printf '%s\n' 'Expected exactly one action: start, stop, or status.' >&2
    printf '/bin/false;\n'
    exit 2
fi

emit_unset() {
    if [[ $shell_format == bash ]]; then
        printf 'unset %s;\n' "$1"
    else
        printf 'unsetenv %s;\n' "$1"
    fi
}

emit_set() {
    local name=$1 value=$2 quoted='' char i
    local LC_ALL=C
    if [[ $shell_format == bash ]]; then
        printf 'export %s=%q;\n' "$name" "$value"
    else
        # Escape metacharacters, including ! for interactive history expansion.
        # Escaping each space preserves repeated spaces through eval `...`.
        for ((i=0; i<${#value}; i++)); do
            char=${value:i:1}
            case $char in
                [a-zA-Z0-9_./:@%+=,-]) quoted+=$char ;;
                *) quoted+="\\$char" ;;
            esac
        done
        printf 'setenv %s %s;\n' "$name" "${quoted:-\'\'}"
    fi
}

show_status() {
    local cmd agent_status accounts account jldg_loaded=0
    for cmd in oidc-agent oidc-add; do
        command -v "$cmd" >/dev/null || {
            printf 'Required command not found: %s\n' "$cmd" >&2
            return 1
        }
    done

    # Query before printing details so an unavailable agent needs only one line.
    # Do not use oidc-agent-service use, load accounts, or get tokens.
    if ! agent_status=$(oidc-agent --status 2>&1); then
        printf '%s\n' 'JLDG agent is not running or not connected.'
        return 1
    fi

    case ${JWT_USER_PATH-} in
        '!oidc-token --time=60 jldg')
            printf '%s\n' 'JWT_USER_PATH: configured for JLDG' ;;
        '') printf '%s\n' 'JWT_USER_PATH: not configured; run start in this shell' ;;
        *) printf '%s\n' 'JWT_USER_PATH: different setting; run start to configure JLDG' ;;
    esac
    if [[ -n ${OIDC_SOCK:-} ]]; then
        printf 'Connection: OIDC_SOCK=%s\n' "$OIDC_SOCK"
    else
        printf '%s\n' 'Connection: default oidc-agent socket (OIDC_SOCK is unset or empty)'
    fi

    printf '%s\n' 'Agent: reachable'
    if ! accounts=$(oidc-add --loaded); then
        printf '%s\n' 'JLDG account: unknown (could not list loaded accounts)'
        return 1
    fi
    while IFS= read -r account; do
        if [[ $account == jldg ]]; then
            jldg_loaded=1
            break
        fi
    done <<<"$accounts"
    if ((jldg_loaded)); then
        printf '%s\n' 'JLDG account: loaded'
    else
        printf '%s\n' 'JLDG account: not loaded; run start'
    fi
    printf '\n%s\n%s\n' 'Agent details:' "$agent_status"
    printf '%s\n' 'Token validity: not checked; start verifies refresh-token use.'
}

# Dispatch before the start/stop EXIT trap so status never emits environment
# changes, including when the agent is stopped or an inspection command fails.
if [[ $1 == status ]]; then
    show_status
    exit $?
fi

terminal_state=''
started_agent=0
on_exit() {
    local rc=$?
    # oidc-gen/oidc-add disable terminal echo while asking for passwords.
    # Restore the original settings even if a prompt is interrupted.
    if [[ -n $terminal_state ]]; then
        stty "$terminal_state" || printf '%s\n' 'Could not restore terminal settings; run stty echo.' >&2
    fi
    if ((rc != 0 && started_agent)); then
        if oidc-agent-service stop >/dev/null; then
            printf '%s\n' 'Start failed; stopped the agent started by this command.' >&2
        else
            printf '%s\n' 'Could not stop the newly started agent; run oidc-agent-service stop.' >&2
        fi
    fi
    if ((rc != 0)); then
        emit_unset JWT_USER_PATH
        # Preserve failure through eval without exiting the calling shell.
        printf '/bin/false;\n'
    fi
    return "$rc"
}
trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
umask 077

show_forward_options() {
    local line port
    # Only the localhost redirect URIs configured for JLDG are supported.
    local pattern='[?&]redirect_uri=http%3[Aa]%2[Ff]%2[Ff]localhost%3[Aa]([0-9]+)(&|[[:space:]]|$)'
    while IFS= read -r line; do
        [[ $line =~ $pattern ]] || continue
        port=${BASH_REMATCH[1]}
        printf '\nBrowser authentication:
Use a browser with the JLDG certificate installed in either case.

Browser on the same machine as oidc-agent:
  Open the authorization URL directly. No SSH forwarding is needed.

Browser on a different PC:
  In another terminal on that PC, add these options before the destination
  in your usual SSH command to the machine running oidc-agent:

    -N -o ExitOnForwardFailure=yes -L %s:localhost:%s -D 1080

  Set the browser SOCKS5 proxy to localhost:1080 to reach the OP through SSH.
  Keep SSH connected, then open the authorization URL in that browser.
  When authentication and the original terminal command finish, restore
  the previous browser proxy settings and stop forwarding with Ctrl-C.

If polling stops and asks for Enter, complete browser authentication first,
then press Enter in this terminal. Keep SSH connected while it waits.
' "$port" "$port"
    done >&2
}

filter_gen_stdout() {
    local line
    while IFS= read -r line || [[ -n $line ]]; do
        case $line in
            'No account exists with this short name. Creating new configuration ...'|\
            'Generating account configuration ...'|accepted) ;;
            *) printf '%s\n' "$line" ;;
        esac
    done
}

filter_gen_output() {
    local char pending='' passthrough=0 suppress=0
    local header='Please try state lookup again by using:'
    local command='oidc-gen --state='
    # Forward ordinary text as soon as it differs from the two hidden lines.
    # In particular, do not wait for a newline before displaying a prompt.
    while IFS= read -r -N 1 char; do
        if [[ $char == $'\n' ]]; then
            if (( !suppress )) && [[ $pending != "$header" ]]; then
                printf '%s\n' "$pending"
            fi
            pending='' passthrough=0 suppress=0
        elif ((suppress)); then
            continue
        elif ((passthrough)); then
            printf '%s' "$char"
        else
            pending+=$char
            if [[ $pending == "$command" ]]; then
                suppress=1
                pending=''
            elif [[ $header != "$pending"* && $command != "$pending"* ]]; then
                printf '%s' "$pending"
                pending='' passthrough=1
            fi
        fi
    done
    if (( !suppress )) && [[ $pending != "$header" ]]; then
        printf '%s' "$pending"
    fi
    return 0
}

run_gen() {
    (
        set -o pipefail
        # Filter stdout first, then handle the merged stream in one filter
        # so concurrent stdout writes cannot split stderr text into characters.
        OIDC_AGENT_NOCOLOR=1 oidc-gen "${gen_options[@]}" "$@" \
            2>&1 > >(filter_gen_stdout) |
            filter_gen_output | tee >(cat >&2) | show_forward_options
    )
}

main() {
    local action=$1 agent_env accounts token_error cmd value
    local reauth_required=0
    local client_config=${JLDG_CLIENT_CONFIG:-/etc/oidc-agent/jldg-client.json}
    local -a gen_options=(
        --pub --prompt=none --pw-prompt=cli --confirm-default
        --flow=code --no-scheme --no-url-call
    )

    if [[ $action == stop ]]; then
        if [[ -z ${OIDC_SOCK:-} ]]; then
            printf '%s\n' 'Not connected to a JLDG agent.' >&2
        else
            for cmd in oidc-agent oidc-agent-service; do
                command -v "$cmd" >/dev/null || {
                    printf 'Required command not found: %s\n' "$cmd" >&2
                    return 1
                }
            done
            if ! oidc-agent --status >/dev/null 2>&1; then
                printf '%s\n' 'JLDG agent is not running or not connected.' >&2
            else
                oidc-agent-service stop >/dev/null || {
                    printf '%s\n' 'Could not stop the JLDG agent.' >&2
                    return 1
                }
                printf '%s\n' 'JLDG agent stopped.' >&2
            fi
        fi
        for cmd in JWT_USER_PATH OIDC_SOCK OIDCD_PID OIDCD_PID_FILE; do
            emit_unset "$cmd"
        done
        printf '/bin/true;\n'
        return 0
    fi

    for cmd in oidc-agent-service oidc-gen oidc-add oidc-token grep tee cat stty; do
        command -v "$cmd" >/dev/null || {
            printf 'Required command not found: %s\n' "$cmd" >&2
            return 1
        }
    done

    # eval/backticks may supply EOF on stdin. Use the controlling terminal
    # for password prompts and oidc-gen's Enter wait when it is available.
    if [[ ! -t 0 ]] && { true </dev/tty; } 2>/dev/null; then
        exec </dev/tty || return 1
    fi
    if [[ -t 0 ]]; then
        terminal_state=$(stty -g) || return 1
    fi

    # start succeeds only for a new service agent; otherwise reuse it.
    # Track ownership so failed startup does not stop an existing shared agent.
    if agent_env=$(oidc-agent-service start 2>/dev/null); then
        started_agent=1
    else
        agent_env=$(oidc-agent-service use) || return 1
    fi
    # oidc-agent-service emits Bash commands; evaluate these only internally.
    eval "$agent_env" >/dev/null || return 1
    # On reuse, oidc-agent-service can emit an empty or inherited OIDCD_PID.
    # Its PID file is authoritative and remains available after logout.
    if [[ -n ${OIDCD_PID_FILE:-} ]]; then
        if ! { [[ -r $OIDCD_PID_FILE ]] &&
            { IFS= read -r OIDCD_PID < "$OIDCD_PID_FILE" || [[ -n $OIDCD_PID ]]; }; }; then
            printf 'Cannot read agent PID from: %s\n' "$OIDCD_PID_FILE" >&2
            return 1
        fi
    fi
    [[ -n ${OIDC_SOCK:-} && ${OIDCD_PID:-} =~ ^[1-9][0-9]*$ ]] || {
        printf '%s\n' 'oidc-agent-service did not provide agent connection variables.' >&2
        return 1
    }

    accounts=$(oidc-gen --accounts) || return 1
    if ! grep -Fxq -- jldg <<<"$accounts"; then
        [[ -r $client_config ]] || {
            printf 'Cannot read client configuration: %s\n' "$client_config" >&2
            return 1
        }
        printf '%s\n' 'Creating the JLDG account. Complete browser authentication.' >&2
        run_gen --file="$client_config" jldg || return 1
    else
        # Loading also refreshes tokens. Keep password prompts visible while
        # capturing errors so an expired refresh token reaches reauthentication.
        if ! token_error=$(
            set -o pipefail
            oidc-add --pw-prompt=cli --pw-store jldg 2>&1 |
                tee >(cat >&2)
        ); then
            [[ $token_error == *--reauthenticate* ]] || return 1
            reauth_required=1
        fi
    fi

    # Force refresh even when a cached access token is still valid.
    # Discard the token; only capture stderr for error classification.
    if ((reauth_required)) || ! token_error=$(oidc-token --force-new jldg 2>&1 >/dev/null); then
        case $token_error in
            *--reauthenticate*)
                printf '%s\n' 'JLDG reauthentication required. Complete browser authentication.' >&2
                run_gen --reauthenticate jldg || return 1
                oidc-token --force-new jldg >/dev/null || return 1
                ;;
            *)
                printf '%s\n' "$token_error" >&2
                return 1
                ;;
        esac
    fi

    # Validate all values before emitting any partial connection setup.
    for value in "$OIDC_SOCK" "$OIDCD_PID" "${OIDCD_PID_FILE:-}"; do
        case $value in
            *$'\n'*|*$'\r'*)
                printf '%s\n' 'Agent environment values must not contain newlines.' >&2
                return 1
                ;;
        esac
    done
    printf '%s\n' 'JLDG authentication is ready for Gfarm.' >&2
    emit_set OIDC_SOCK "$OIDC_SOCK"
    emit_set OIDCD_PID "$OIDCD_PID"
    if [[ -n ${OIDCD_PID_FILE:-} ]]; then
        emit_set OIDCD_PID_FILE "$OIDCD_PID_FILE"
    else
        emit_unset OIDCD_PID_FILE
    fi
    emit_set JWT_USER_PATH '!oidc-token --time=60 jldg'
    printf '/bin/true;\n'
}

# No shell detection, locks, or startup-file modifications.
main "$@"
exit $?
