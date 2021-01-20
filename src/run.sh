#!/usr/bin/env bash

bgen:import build

run_project() {
    export __BGEN_PIPE_SOURCE__="${__base__:-$0} run"
    bash -c "$(build_project_to_stdout)" "${__base__:-$0} run" "$@"
}

debug_project() {
    export __BGEN_PIPE_SOURCE__="${__base__:-$0} debug"
    bash -x -c "$(build_project_to_stdout)" "${__base__:-$0} run" "$@"
}
