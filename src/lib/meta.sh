#!/usr/bin/env bash

bgen:import butl/vars

# shellcheck disable=SC2034
read_project_meta() {
    butl.is_declared import_paths || local import_paths

    # make sure some vars are local if not declared on a parent scope
    butl.is_declared project_root || local project_root=
    butl.is_declared project_name || local project_name=
    butl.is_declared header_file || local header_file=
    butl.is_declared entrypoint_file || local entrypoint_file=
    butl.is_declared entrypoint_func || local entrypoint_func=
    butl.is_declared source_dir || local source_dir=
    butl.is_declared shebang_string || local shebang_string=
    butl.is_declared tests_dir || local tests_dir=
    butl.is_declared output_file || local output_file=
    butl.is_declared output_dir || local output_dir=
    butl.is_declared is_library || local is_library=

    # set some defaults
    shebang_string="#!/usr/bin/env bash"
    tests_dir="tests"
    output_dir="dist"

    local import_paths_extra=()
    import_paths=()
    import_paths=("deps/*/lib")

    # source config file
    project_root="$PWD"
    while true; do
        # shellcheck disable=SC1091
        if [[ -f ".bgenrc" ]]; then
            project_root="$PWD"
            source ".bgenrc"
            break
        elif [[ -f "bgenrc.sh" ]]; then
            project_root="$PWD"
            source "bgenrc.sh"
            break
        fi

        if [[ "$PWD" == "/" ]]; then
            cd "$project_root" || return
            break
        fi

        cd ..
    done

    # If there's a lib/ directory, but no src/ directory, assume it's a library
    if [[ ! "$is_library" && -d "lib" && ! -d "src" ]]; then
        is_library=1
    fi

    # source directory is lib for libraries and src for single script files
    if [[ ! "$source_dir" ]]; then
        if ((is_library)); then
            source_dir="lib"
        else
            source_dir="src"
        fi
    fi

    # set the default entrypoint file
    if [[ ! "$entrypoint_file" ]]; then
        if ((is_library)); then
            entrypoint_file=""
        else
            entrypoint_file="${source_dir%/}/main.sh"
        fi
    fi

    # set default project name
    if [[ ! "${project_name:-}" ]]; then
        # ${file##*/} keeps only what's after the last slash (aka the basename)
        project_name="${PWD##*/}"
    fi

    # set default output file
    if [[ ! "${output_file:-}" ]]; then
        if ((is_library)); then
            output_file=""
        else
            output_file="${output_dir%/}/${project_name#/}"
        fi
    fi

    # set default entrypoint function
    if [[ ! "${entrypoint_func:-}" ]]; then
        if ((is_library)); then
            entrypoint_func=""
        else
            entrypoint_func="$project_name"
        fi
    fi

    # add the extra import paths
    if ((${#import_paths_extra[@]})); then
        import_paths=("${import_paths_extra[@]}" "${import_paths[@]}")
    fi

    # add env paths, give them more priority
    if [[ "${BGEN_IMPORT_PATHS:-}" ]]; then
        local env_paths=()
        while read -rd ':' path; do
            env_paths+=("$path")
        done <<<"${BGEN_IMPORT_PATHS}:"
        import_paths=("${env_paths[@]}" "${import_paths[@]}")
    fi
}
