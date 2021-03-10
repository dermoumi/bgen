#!/usr/bin/env bash

bgen:import build

command_run() {
    barg.arg input \
        --short=i \
        --long=input \
        --value=FILE \
        --desc "File or directory to run, if any"
    barg.arg debug \
        --short=d \
        --long=debug \
        --desc "Run the project in debug mode."
    barg.arg args \
        --multi \
        --value=ARGUMENT \
        --desc="Arguments to pass to the project."

    local input=
    local debug=
    local args=()

    local should_exit=
    local should_exit_err=0
    barg.parse "$@"
    if ((should_exit)); then
        return "$should_exit_err"
    fi

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
    # shellcheck disable=2034
    local entrypoint_file=
    # shellcheck disable=2034
    local project_root=
    local is_library=
    read_project_meta

    if [[ "$input" == "" ]]; then
        input=$entrypoint_file
    fi

    if ((is_library)); then
        butl.die "You cannot run library projects."
    elif ((debug)); then
        debug_project "$input" "${args[@]}"
    else
        run_project "$input" "${args[@]}"
    fi
}

run_project() {
    local input=$1

    local tmp_file
    tmp_file=$(mktemp)
    build_file "$input" >"$tmp_file"

    export __BGEN_PIPE_SOURCE__="${__base__:-$0} run"

    local err=0
    bash "$tmp_file" "$@" || err=$?

    rm -f "$tmp_file"

    return "$err"
}

debug_project() {
    local input=$1

    local tmp_file
    tmp_file=$(mktemp)
    build_file "$input" >"$tmp_file"

    export __BGEN_PIPE_SOURCE__="${__base__:-$0} run"

    local err=0
    bash -x "$tmp_file" "$@" || err=$?

    rm -f "$tmp_file"

    return "$err"
}
