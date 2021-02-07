#!/usr/bin/env bash

bgen:import barg

command_install() {
    local should_exit=
    local should_exit_err=0
    barg.parse "$@"
    if ((should_exit)); then
        return "$should_exit_err"
    fi

    PATH="$HOME/.cache/bpkg/bin:$PATH"
    if ! type -p bpkg >/dev/null 2>&1; then
        install_bpkg || return
    fi

    local build_deps=()
    read_project_meta

    for dep in "${build_deps[@]}"; do
        butl.log_info "Installing $dep"

        bpkg-install "$dep"
    done
}

install_bpkg() (
    export PREFIX="$HOME/.cache/bpkg/"

    mkdir -p "$PREFIX"
    curl -Lo- "https://raw.githubusercontent.com/bpkg/bpkg/master/setup.sh" | bash
)
