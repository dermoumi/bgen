#!/usr/bin/env bash

bgen:import barg

command_install() {
    local should_exit=
    local should_exit_err=0
    barg.parse "$@"
    if ((should_exit)); then
        return "$should_exit_err"
    fi

    if ! type -p bpkg >/dev/null 2>&1; then
        butl.fail "bpkg is not installed"
        return
    fi

    bpkg_cmd="bpkg"

    local build_deps=()
    read_project_meta

    for dep in "${build_deps[@]}"; do
        butl.log_info "Installing $dep"

        "$bpkg_cmd" install "$dep"
    done
}
