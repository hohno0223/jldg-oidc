#!/usr/bin/env bash
# tcsh interface. This program runs in Bash and EMITS tcsh commands.
# Run with: eval `/path/to/jldg-agent.csh start`
# Run status directly, without eval.
script_dir=$(cd -- "$(dirname -- "$0")" && pwd) || {
    printf '/bin/false;\n'
    exit 1
}
if [[ ! -r $script_dir/jldg-agent-core.sh ]]; then
    printf '%s\n' 'Cannot read jldg-agent-core.sh beside this interface.' >&2
    printf '/bin/false;\n'
    exit 1
fi
exec bash "$script_dir/jldg-agent-core.sh" tcsh "$@"
