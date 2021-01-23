#!/usr/bin/env bash

bgen:import build

test_debug_project() {
    export __BGEN_PIPE_SOURCE__="${__base__:-$0} test"
    build_tests_to_stdout "$@"
}

test_project() {
    export __BGEN_PIPE_SOURCE__="${__base__:-$0} test"
    bash -c "$(build_tests_to_stdout "$@")" "${__base__:-$0} test" "$@"
}
