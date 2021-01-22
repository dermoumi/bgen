#!/usr/bin/env bash

__test_failed=()
__test_report=()

if [[ "$NO_COLOR" ]]; then
    __COL_DANGER=""
    __COL_SUCCESS=""
    __COL_TITLE=""
    __COL_FILENAME=""
    __COL_RESET=""
else
    __COL_DANGER="\e[31m"
    __COL_SUCCESS="\e[32m"
    __COL_TITLE="\e[36m"
    __COL_FILENAME="\e[33m"
    __COL_RESET="\e[0m"
fi

# shellcheck disable=SC2120
__get_source_line() {
    local bgen_line="$1"

    local line_file=("UNKNOWN_FILE")
    local line_nr=(0)
    local line_offset=(0)
    while IFS= read -r line; do
        local current_line_nr current_line_type
        current_line_nr="$(awk '{printf $1}' <<<"$line")"
        current_line_type="$(awk '{printf $2}' <<<"$line")"

        if ((current_line_nr > bgen_line)); then
            break
        fi

        # keep it as ifs, bash 3.2 seems to complain when i use a case here
        if [[ "$current_line_type" == "BGEN__BEGIN" ]]; then
            local file
            file="$(awk '{OFS=""; $1=""; $2=""; printf $0 }' <<<"$line")"
            line_file=("$file" "${line_file[@]}")
            line_nr=("$current_line_nr" "${line_nr[@]}")
            line_offset=(0 "${line_offset[@]}")
        elif [[ "$current_line_type" == "BGEN__END" ]]; then
            local file_start_line_nr="${line_nr[0]}"
            local file_lines=$((current_line_nr - file_start_line_nr))
            line_file=("${line_file[@]:1}")
            line_nr=("${line_nr[@]:1}")
            line_offset=("${line_offset[@]:1}")
            line_offset[0]=$((line_offset[0] + file_lines))
        fi
    done <<<"$__BGEN_LINEMAP__"

    echo "${line_file[0]/$PWD\//}:$((bgen_line - line_nr[0] - line_offset[0]))"
}
export -f __get_source_line

__handle_error() {
    local rc="$__bgen_current_rc"

    # if we have two successive return commands, use the previous one's line
    if [[ "$__bgen_current_cmd" == "$__bgen_previous_cmd" ]]; then
        local line="$__bgen_previous_cmd_line"
    else
        local line="$__bgen_current_cmd_line"

        if ((BASH_VERSINFO[0] < 4)); then
            line=$((line + 1))
        fi
    fi

    __error_handled=1

    local source_line
    source_line="$(__get_source_line "$line")"
    printf '%b%s (rc=%s)%b\n' "$__COL_DANGER" "$source_line" "$rc" "$__COL_RESET" >&2

    exit "$rc"
}
export -f __handle_error

__handle_exit() {
    local rc="$__bgen_current_rc"

    if [[ "${__error_handled:-}" ]]; then
        exit "$rc"
    fi

    local line="$__bgen_previous_cmd_line"

    # workaround for bash <4.0 returning 0 on nounset errors
    if [[ "$rc" == 0 ]]; then
        [[ "${__func_finished_successfully:-}" ]] && exit 0

        # this is the same code bash returns on version 4+ in these cases
        rc=127

        if [[ "${__bgen_previous_cmd_line:-}" ]]; then
            line=$((__bgen_previous_cmd_line))
        fi
    elif [[ "${__bgen_previous_cmd_line:-}" ]]; then
        line="$__bgen_previous_cmd_line"
    fi

    local source_line
    source_line="$(__get_source_line "$line")"
    printf '%b%s (rc=%s)%b\n' "$__COL_DANGER" "$source_line" "$rc" "$__COL_RESET" >&2

    exit "$rc"
}
export -f __handle_exit

__handle_debug() {
    local rc="$1"
    local line="$2"
    local cmd="$3"

    if ((BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 1))); then
        line=$((line + 1))
    fi

    if ((__bgen_previous_rc == 0)); then
        __bgen_previous_rc="$__bgen_current_rc"
        __bgen_previous_cmd="$__bgen_current_cmd"
        __bgen_previous_cmd_line="$__bgen_current_cmd_line"
    fi

    __bgen_current_rc="$rc"
    __bgen_current_cmd="$cmd"
    __bgen_current_cmd_line="$line"
}
export -f __handle_debug

assert_status() {
    local status_code="$?"

    local expected_code="${1:-}"
    [[ "${2:-}" ]] && status_code="$2"

    [[ "$status_code" == "$expected_code" ]] && return 0

    echo "assert_status: expected $expected_code, got $status_code" >&2
    return 1
}
export -f assert_status

assert_eq() {
    local left="$1"
    local right="$2"

    [[ "$left" == "$right" ]] && return 0

    (
        echo "assert_eq expected:"
        echo "$left"
        echo
        echo "assert_eq got:"
        echo "$right"
    ) >&2
    return 1
}
export -f assert_eq

__run_test() {
    local test_func="$1"
    local stdout_file stderr_file

    stdout_file="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm '$stdout_file'" EXIT

    stderr_file="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm '$stderr_file'" EXIT

    # we don't want this subshell to cause the entire test to fail
    # so we relax bash options until we get a status code
    set +o errexit +o errtrace +o nounset +o pipefail
    (
        # set up some hooks to print original error lines and files
        trap '__handle_debug "$?" "$LINENO" "$BASH_COMMAND"' DEBUG
        trap 'trap - DEBUG; __handle_error "$LINENO"' ERR
        trap 'trap - DEBUG; __handle_exit "$LINENO"' EXIT

        # enable some bash options to allow error checking
        set -o errexit -o errtrace -o nounset -o pipefail -o functrace

        # call our test function
        "$test_func"

        # workaround to check if function didn't end prematurely
        # bash 3.2 exists with rc=0 on unset variables :/
        __func_finished_successfully=1
    ) >"$stdout_file" 2>"$stderr_file"
    local err=$?
    set -o errexit -o errtrace -o nounset -o pipefail

    # print a dot or F depending on test status
    if ((err)); then
        printf "%bF%b" "$__COL_DANGER" "$__COL_RESET"
        __test_failed+=("$test_func")
    else
        printf "%b.%b" "$__COL_SUCCESS" "$__COL_RESET"
    fi

    : "${BGEN_NO_CAPTURE:=}"
    if ! ((err || BGEN_NO_CAPTURE)); then
        return
    fi

    if [[ -s "$stdout_file" || -s "$stderr_file" ]]; then
        local report
        report=$(
            printf '\n%b----- %s ----- %b\n' "$__COL_FILENAME" "$test_func" "$__COL_RESET"

            if [[ -s "$stdout_file" ]]; then
                printf "%bstdout:%b\n" "$__COL_TITLE" "$__COL_RESET"
                cat "$stdout_file"
                echo
            fi

            if [[ -s "$stderr_file" ]]; then
                printf "%bstderr:%b\n" "$__COL_TITLE" "$__COL_RESET"
                cat "$stderr_file"
                echo
            fi
        )
        __test_report+=("$report")
    fi
}

# look over test functions
for __test_func in "${__BGEN_TEST_FUNCS__[@]}"; do
    __run_test "$__test_func"
done
echo

if (("${#__test_failed[@]}")); then
    printf "\n%bFailed tests:%b\n" "$__COL_TITLE" "$__COL_RESET"
    for test_func in "${__test_failed[@]}"; do
        echo "    $test_func"
    done
fi

if (("${#__test_report[@]}")); then
    for test_report in "${__test_report[@]}"; do
        echo "$test_report"
    done
fi
