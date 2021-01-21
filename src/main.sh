#!/usr/bin/env bash

bgen:import build
bgen:import run
bgen:import test

# entrypoint
main() {
    local cmd="${1:-}"

    if [[ "$cmd" == "build" ]]; then
        build_project
        return
    fi

    if [[ "$cmd" == "run" ]]; then
        shift
        run_project "$@"
        return
    fi

    if [[ "$cmd" == "debug" ]]; then
        shift
        debug_project "$@"
        return
    fi

    if [[ "$cmd" == "test" ]]; then
        test_project
        return
    fi

    if [[ "$cmd" == "test-debug" ]]; then
        test_debug_project
        return
    fi

    build_project_to_stdout
}
