#!/usr/bin/env bash

bgen:import build

test_debug_project() {
    export __BGEN_PIPE_SOURCE__="${__base__:-$0} test"
    build_tests_to_stdout
}

test_project() {
    # TODO: Check awk exists

    local test_code linemap
    test_code="$(build_tests_to_stdout)"
    linemap="$(awk '$0 ~ /^# BGEN__/ {OFS=""; $1=""; $2=$2 " "; print NR " " $0}' <<<"$test_code")"

    export __BGEN_PIPE_SOURCE__="${__base__:-$0} test"
    export __BGEN_LINEMAP__="$linemap"
    bash -c "$test_code" "${__base__:-$0} test" "$@"
}
