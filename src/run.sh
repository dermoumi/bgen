#!/usr/bin/env bash

bgen:import build

command_run() {
    barg.arg debug \
        --short=d \
        --long=debug \
        --desc "Run the project in debug mode."
    barg.arg args \
        --multi \
        --value=ARGUMENT \
        --desc="Arguments to pass to the project."

    local debug=
    local args=()
    barg.parse "$@"

    if ((debug)); then
        debug_project "${args[@]}"
    else
        run_project "${args[@]}"
    fi
}

run_project() {
    export __BGEN_PIPE_SOURCE__="${__base__:-$0} run"
    bash -c "$(build_project_to_stdout)" "${__base__:-$0} run" "$@"
}

debug_project() {
    export __BGEN_PIPE_SOURCE__="${__base__:-$0} debug"
    bash -x -c "$(build_project_to_stdout)" "${__base__:-$0} run" "$@"
}
