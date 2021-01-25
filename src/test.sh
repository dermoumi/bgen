#!/usr/bin/env bash

bgen:import build

run_project_tests_debug() {
    export __BGEN_PIPE_SOURCE__="${__base__:-$0} test"
    build_tests_to_stdout "$@"
}

run_project_tests() {
    export __BGEN_PIPE_SOURCE__="${__base__:-$0} test"
    bash -c "$(build_tests_to_stdout "$@")" "${__base__:-$0} test" "$@"
}
