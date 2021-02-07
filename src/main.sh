#!/usr/bin/env bash

bgen:import barg

bgen:import build.sh
bgen:import run.sh
bgen:import tests.sh
bgen:import install.sh

# entrypoint
bgen() {
    barg.subcommand build command_build "builds the project"
    barg.subcommand run command_run "runs the project"
    barg.subcommand test command_test "runs tests"
    barg.subcommand install command_install "install project dependencies"

    local subcommand=
    local subcommand_args=()

    local should_exit=
    local should_exit_err=0
    barg.parse "$@"
    if ((should_exit)); then
        return "$should_exit_err"
    fi

    if ((${#subcommand_args[@]})); then
        "$subcommand" "${subcommand_args[@]}"
    else
        "$subcommand"
    fi
}
