#!/usr/bin/env bash

bgen:import barg

command_install() {
    local should_exit=
    local should_exit_err=0
    barg.parse "$@"
    if ((should_exit)); then
        return "$should_exit_err"
    fi

    echo hi
}
