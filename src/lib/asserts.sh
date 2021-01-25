#!/usr/bin/env bash
# shellcheck disable=SC2034

assert_exits_with_code() {
    local expected_code="$1"
    shift

    local err
    ("$@") || err=$?

    if ((err == expected_code)); then
        return 0
    fi

    echo "assert_status: expected exit_code to be $expected_code", got "${err:-0}" >&2

    # save line at which this happened, used later for reporting
    __bgen_assert_line="${BASH_LINENO[0]-}"

    return 1
}

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
