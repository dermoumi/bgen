#!/usr/bin/env bash

bgen:import build
bgen:import run
bgen:import tests
bgen:import barg

# entrypoint
bgen() {
    barg.subcommand build build_project "builds the project"
    barg.subcommand run run_project "runs the project"
    barg.subcommand debug debug_project "runs the project in bash debug mode"
    barg.subcommand test run_project_tests "runs tests"

    local subcommand=
    barg.parse "$@"

    "${subcommand[@]}"
}
