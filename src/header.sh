#!/usr/bin/env bash

# Exit on error. Append "|| true" if you expect an error.
set -o errexit
# Exit on error inside any functions or subshells.
set -o errtrace
# Do not allow use of undefined vars. Use ${VAR:-} to use an undefined VAR
set -o nounset
# Catch the error in case mysqldump fails (but gzip succeeds) in $(mysqldump | gzip)
set -o pipefail
# Turn on traces, useful for debugging. Set _XTRACE to enable
[[ "${_XTRACE:-}" ]] && set -o xtrace

# check whether script is source or directly executed
if [[ "${__BGEN_PIPE_SOURCE__:-}" ]]; then
    __process__="$__BGEN_PIPE_SOURCE__"
elif [[ "${BASH_SOURCE+x}" ]]; then
    __process__="${BASH_SOURCE[0]}"
else
    __process__="$0"
fi

if [[ "${BASH_SOURCE+x}" && "${BASH_SOURCE[0]}" != "${0}" ]]; then
    __main__= # false
    # shellcheck disable=SC2154
    if [[ "${__usage__+x}" ]]; then
        if [[ "${BASH_SOURCE[1]}" = "${0}" ]]; then
            __main__=1 # true
        fi

        __process__="${BASH_SOURCE[1]}"
    fi
else
    # shellcheck disable=SC2034
    __main__=1 # true
    [[ "${__usage__+x}" ]] && unset -v __usage__
fi

# Set magic variables for current file, directory, os, etc.
__dir__="$(cd "$(dirname "${__process__}")" && pwd)"
__file__="${__dir__}/$(basename "${__process__}")"
# shellcheck disable=SC2034,SC2015
__base__="$(basename "${__file__}" .sh)"
# shellcheck disable=SC2034,SC2015
if [[ "${__BGEN_PIPE_SOURCE__:-}" ]]; then
    __invocation__="${__BGEN_PIPE_SOURCE__}"
else
    __invocation__="$(printf %q "${__file__}")"
fi

# Define the environment variables (and their defaults) that this script depends on
LOG_LEVEL="${LOG_LEVEL:-6}" # 7 = debug -> 0 = emergency
NO_COLOR="${NO_COLOR:-}"    # true = disable color. otherwise autodetected
