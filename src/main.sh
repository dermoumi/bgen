#!/bin/bash

bgen:import build
bgen:import run

# entrypoint
main() {
    local cmd="${1:-}"

    if [[ "$cmd" == "build" ]]; then
        shift
        build_project
        return
    elif [[ "$cmd" == "run" ]]; then
        shift
        run_project "$@"
        return
    fi

    build_project_to_stdout
}
