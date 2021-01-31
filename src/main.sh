#!/usr/bin/env bash

bgen:import build.sh
bgen:import run.sh
bgen:import tests.sh
bgen:import barg

# entrypoint
bgen() {
    barg.subcommand build command_build "builds the project"
    barg.subcommand run command_run "runs the project"
    barg.subcommand test command_test "runs tests"

    local subcommand=
    barg.parse "$@"

    "${subcommand[@]}"
}
