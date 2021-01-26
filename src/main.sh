#!/usr/bin/env bash

bgen:import build
bgen:import run
bgen:import test
bgen:import barg

# entrypoint
bgen() {
    barg.subcommand build build_project "builds the project"
    barg.subcommand run run_project "runs the project"
    barg.subcommand run-debug build_project_to_stdout "outputs the project code"
    barg.subcommand debug debug_project "runs the project in bash debug mode"
    barg.subcommand test run_project_tests "runs tests"
    barg.subcommand test-debug run_project_tests_debug "outputs the project's test code"

    local subcommand=
    barg.parse "$@"

    "${subcommand[@]}"
}
