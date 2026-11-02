#!/usr/bin/env bash
# Bash interface. Use eval for start/stop; run status directly.
if [[ ${BASH_SOURCE[0]} != "$0" ]]; then
    printf '%s\n' 'Do not source this file. Use eval for start|stop, or run status directly.' >&2
    return 2
fi
script_dir=$(cd -- "$(dirname -- "$0")" && pwd) || {
    printf '/bin/false;\n'
    exit 1
}
if [[ ! -r $script_dir/jldg-agent-core.sh ]]; then
    printf '%s\n' 'Cannot read jldg-agent-core.sh beside this interface.' >&2
    printf '/bin/false;\n'
    exit 1
fi
exec bash "$script_dir/jldg-agent-core.sh" bash "$@"
