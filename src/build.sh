#!/usr/bin/env bash

bgen:import utils
bgen:import lib/meta
bgen:import lib/build
bgen:import barg

command_build() {
    barg.arg print_source \
        --short=p \
        --long=print-source \
        --desc "Print test script's source code instead of executing it."

    local print_source=
    barg.parse "$@"

    if ((print_source)); then
        build_project_to_stdout
    else
        build_project
    fi
}

build_project() {
    # save it in a temp file first
    local tmp_file
    tmp_file=$(mktemp /tmp/bgen.XXXXXXXXXX)
    # shellcheck disable=SC2064
    trap "rm '$tmp_file' >/dev/null || true" exit

    # build the project
    build_project_to_stdout >"$tmp_file"

    # shellcheck disable=SC1007
    local output_file=""
    read_project_meta

    # get output_file's directory
    : "${output_file%/*}"
    local output_dir="${_:-/}"

    # make sure the output's directory exists
    if [[ "$output_dir" && "$output_dir" != "." ]]; then
        mkdir -p "$output_dir"
    fi

    # copy it to the real output dir and make it executable
    cp "$tmp_file" "$output_file"
    chmod +x "$output_file"
}

build_project_to_stdout() {
    # set a constant seed to have consistent builds
    RANDOM=42

    # used later to keep track of whether a file was imported or not
    # declared here to be on the biggest private scope it's needed in
    # shellcheck disable=2034
    local imported_files=()

    # shellcheck disable=2034
    local project_root=
    # shellcheck disable=2034
    local header_file=
    # shellcheck disable=2034
    local entrypoint_func=
    # shellcheck disable=2034
    local shebang_string=
    # shellcheck disable=2034
    local import_paths=
    local entrypoint_file=
    read_project_meta

    # build the project
    echo_header
    process_file "$entrypoint_file"
    echo_entrypoint_call
}
