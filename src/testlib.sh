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
    local stack="${1:-0}"

    local bgen_line
    bgen_line=$((1 + ${BASH_LINENO[$((stack + 1))]}))

    local line_file=
    local line_nr=0
    while IFS= read -r line; do
        local current_line_nr
        current_line_nr=$(awk '$2 == "BGEN__BEGIN" {printf $1}' <<<"$line")

        [[ "$current_line_nr" ]] || continue
        ((bgen_line > current_line_nr)) || continue

        line_file="$(awk '{OFS=""; $1=""; $2=""; printf $0 }')"
        line_nr=$((current_line_nr + 1))
    done <<<"$__BGEN_LINEMAP__"

    printf '%b%s%b\n' "$__COL_DANGER" "${line_file/$PWD\//}:$((bgen_line - line_nr)):" "$__COL_RESET"
}
export -f __get_source_line

assert_status() {
    local status_code="$?"

    local expected_code="${1:-}"
    [[ "${2:-}" ]] && status_code="$2"

    [[ "$status_code" == "$expected_code" ]] && return 0

    __get_source_line >&2
    echo "Expected status code to be $expected_code, got: $status_code" >&2
    exit 1
}
export -f assert_status

assert_eq() {
    local left="$1"
    local right="$2"

    [[ "$left" == "$right" ]] && return 0

    (   
        __get_source_line
        echo "Expected left string to match right string."
        echo "Left:"
        echo "$left"
        echo
        echo "Right:"
        echo "$right"
    ) >&2
    exit 1
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

    local err=""
    (   
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

        "$test_func" >"$stdout_file" 2>"$stderr_file"
    ) || err="$?"

    if [[ ! "$err" ]]; then
        printf "%b.%b" "$__COL_SUCCESS" "$__COL_RESET"
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

    __test_failed+=("$test_func")

    printf "%bF%b" "$__COL_DANGER" "$__COL_RESET"
    return
}

for __test_func in $( declare -F | awk '$3 ~ /^ *test_/ {printf "%s\n", $3}'); do
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
