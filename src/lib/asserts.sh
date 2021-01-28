#!/usr/bin/env bash
# shellcheck disable=SC2034

assert_eq() {
    local left="$1"
    local right="$2"

    if [[ "$left" == "$right" ]]; then
        return 0
    fi

    printf 'assert_eq sides do not match\nleft:\n%s\n\nright:\n%s\n' "$left" "$right" >&2

    # save line at which this happened, used later for reporting
    __bgen_assert_line="${BASH_LINENO[0]-}"

    return 1
}
export -f assert_eq

assert_exits_with() {
    local args=()

    unset __bgen_assert_code
    unset __bgen_assert_stdout
    unset __bgen_assert_stderr

    while (($#)); do
        case "$1" in
        --code)
            local __bgen_assert_code=$2
            shift 2
            ;;
        --code=*)
            local __bgen_assert_code=${1#--code=}
            shift
            ;;
        --stdout)
            local __bgen_assert_stdout=$2
            shift 2
            ;;
        --stdout=*)
            local __bgen_assert_stdout=${1#--stdout=}
            shift
            ;;
        --stderr)
            local __bgen_assert_stderr=$2
            shift 2
            ;;
        --stderr=*)
            local __bgen_assert_stderr=${1#--stderr=}
            shift
            ;;
        --)
            shift
            args+=("$@")
            shift $#
            ;;
        *)
            args+=("$1")
            shift
            ;;
        esac
    done

    local err=0

    local stderr_file
    stderr_file=$(mktemp)

    if ((BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 2 && BASH_VERSINFO[1] <= 3)); then
        local stdout_file
        stdout_file=$(mktemp)

        # Working around bash 4.2 and 4.3 not returning the correct exit code of subprocesses
        err=$(
            "${args[@]}" 1>"$stdout_file" 2>"$stderr_file"
            echo $?
        )

        local stdout
        stdout=$(<"$stdout_file")
        rm "$stdout_file"
    else
        local stdout
        stdout=$("${args[@]}" 2>"$stderr_file") || err=$?
    fi

    local stderr
    stderr=$(<"$stderr_file")
    rm "$stderr_file"

    local report=()

    if [[ "${__bgen_assert_code+x}" ]] && ((__bgen_assert_code != err)); then
        report+=("$(printf "expected exit code: %s\nreturned exit code: %s\n" "$__bgen_assert_code" "$err")")
    fi

    if [[ "${__bgen_assert_stdout+x}" ]] && [[ "$__bgen_assert_stdout" != "$stdout" ]]; then
        report+=("$(printf "expected stdout: %s\nreturned stdout: %s\n" "$__bgen_assert_stdout" "$stdout")")
    fi

    if [[ "${__bgen_assert_stderr+x}" ]] && [[ "$__bgen_assert_stderr" != "$stderr" ]]; then
        report+=("$(printf "expected stderr: %s\nreturned stderr: %s\n" "$__bgen_assert_stderr" "$stderr")")
    fi

    if ((${#report[@]})); then
        printf 'assert_exits_with failed:\n' >&2
        printf '%s\n' "${report[@]}" >&2

        # save line at which this happened, used later for reporting
        __bgen_assert_line="${BASH_LINENO[0]-}"

        return 1
    fi

    return 0
}
export -f assert_exits_with
