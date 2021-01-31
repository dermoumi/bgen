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

    # set a constant seed to have consistent builds
    RANDOM=42

    # used later to keep track of whether a file was imported or not
    # declared here to be on the biggest private scope it's needed in
    # shellcheck disable=2034
    local imported_files=()

    # shellcheck disable=2034
    local header_file=
    # shellcheck disable=2034
    local entrypoint_func=
    # shellcheck disable=2034
    local shebang_string=
    # shellcheck disable=2034
    local import_paths=
    local entrypoint_file=
    local is_library=
    local source_dir=
    local output_dir=
    read_project_meta

    if ((is_library)); then
        build_library
    else
        if ((print_source)); then
            build_project_to_stdout
        else
            build_project
        fi
    fi
}

build_library_file() {
    local file="$1"

    if [[ "${shebang_string:-}" ]]; then
        printf '%s\n\n' "$shebang_string"
    fi
    process_file "$file"
}

build_library() {
    if shopt -qs extglob; then
        local keep_extglob=1
    fi

    shopt -s extglob
    for file in "${source_dir%/}"/**/*.sh; do
        # If we have the same path as the query, then we got no file
        if [[ "$file" == "${source_dir%/}/**/*.sh" ]]; then
            break
        fi

        # ignore files that start with an underscore
        if [[ "$file" == _* ]]; then
            continue
        fi

        local output_file="${output_dir%/}/${file%%$source_dir}"
        mkdir -p "${output_file%/*}"

        build_library_file "$file" >"$output_file"
    done

    if ! ((keep_extglob)); then
        shopt -u extglob
    fi
}

build_project() {
    # save it in a temp file first
    local tmp_file
    tmp_file=$(mktemp /tmp/bgen.XXXXXXXXXX)
    # shellcheck disable=SC2064
    trap "rm '$tmp_file' >/dev/null || true" exit

    # build the project
    build_file "$entrypoint_file" >"$tmp_file"

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

build_file() {
    local entrypoint=$1

    echo_header
    process_file "$entrypoint"
    echo_entrypoint_call
}
