#!/usr/bin/env bash

bgen:import build

command_run() {
    barg.arg debug \
        --short=d \
        --long=debug \
        --desc "Run the project in debug mode."
    barg.arg args \
        --multi \
        --value=ARGUMENT \
        --desc="Arguments to pass to the project."

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
    local is_library=
    read_project_meta

    if ((is_library)); then
        butl.die "You cannot run library projects."
    elif ((debug)); then
        debug_project "${args[@]}"
    else
        run_project "${args[@]}"
    fi
}

run_project() {
    export __BGEN_PIPE_SOURCE__="${__base__:-$0} run"
    bash -c "$(build_file "$entrypoint_file")" "${__base__:-$0} run" "$@"
}

debug_project() {
    export __BGEN_PIPE_SOURCE__="${__base__:-$0} debug"
    bash -x -c "$(build_file "$entrypoint_file")" "${__base__:-$0} run" "$@"
}
