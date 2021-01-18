#!/bin/bash

bgen:import utils

build_project() {
    # save it in a temp file first
    local tmp_file
    tmp_file=$(mktemp /tmp/bgen.XXXXXXXXXX)
    # shellcheck disable=SC2064
    trap "rm '$tmp_file' >/dev/null || true" exit

    # build the project
    build_project_to_stdout >"$tmp_file"

    # shellcheck disable=SC1007
    local output_file=
    read_project_meta

    # make sure the output's directory exists
    local output_dir
    output_dir=$(dirname "$output_file")
    if [[ "$output_dir" && "$output_dir" != "." ]]; then
        mkdir -p "$output_dir"
    fi

    # copy it to the real output dir and make it executable
    cp "$tmp_file" "$output_file"
    chmod +x "$output_file"
}

build_project_to_stdout() {
    local imported_files=()

    # shellcheck disable=SC1007
    local project_name= header_file= entrypoint_file= entrypoint_func= shebang_string=
    read_project_meta

    # build the project
    output=$(
        echo_header
        process_file "$entrypoint_file"
        echo_entrypoint_call
    )

    echo "$output"
}

read_project_meta() {
    local meta_filename="meta.sh"
    local meta_file_path=""

    # shellcheck disable=SC2154
    if [[ -f "$PWD/$meta_filename" ]]; then
        meta_file_path="$PWD/$meta_filename"
    elif [[ -f "$__dir__/$meta_filename" ]]; then
        meta_file_path="$__dir__/$meta_filename"
    fi

    local meta_dir
    if [[ -e "$meta_file_path" ]]; then
        meta_dir=$(dirname "$meta_file_path")

        # shellcheck disable=SC1090
        source "$meta_file_path"
    else
        meta_dir="$PWD"
    fi

    # get project name
    local bgen_project_name
    if [[ "${bgen_project_name:-}" ]]; then
        bgen_project_name="$bgen_project_name"
    else
        bgen_project_name=$(basename "$meta_dir")
    fi
    if [[ "${project_name+x}" ]]; then
        project_name="$bgen_project_name"
    fi

    # get header file
    if [[ "${header_file+x}" ]]; then
        header_file="${bgen_header_file:-}"
    fi

    # get entrypoint file
    if [[ "${entrypoint_file+x}" ]]; then
        entrypoint_file="${bgen_entrypoint_file:-"$meta_dir/src/main.sh"}"
    fi

    # get entrypoint func
    if [[ "${entrypoint_func+x}" ]]; then
        entrypoint_func="${bgen_entrypoint_func:-}"
    fi

    # get shebang string
    if is_declared shebang_string; then
        shebang_string="${bgen_shebang_string:-"#!/usr/bin/env bash"}"
    fi

    # get output file
    if [[ "${output_file+x}" ]]; then
        output_file="${bgen_output_file:-"$meta_dir/bin/$bgen_project_name"}"
    fi
}

echo_header() {
    if [[ -f "$header_file" ]]; then
        printf '%s\n\n' "$shebang_string"

        process_file "$header_file"
    else
        local default_header
        bgen:include_str default_header header.sh

        echo "$default_header"
    fi

    # Add some spacing
    printf '\n\n'
}

process_file() {
    local file="$1"

    file=$(realpath "$file")

    local src_dir
    src_dir=$(dirname "$file")
    pushd "$src_dir" >/dev/null || exit

    local found_first_line=
    while IFS= read -r line; do
        # process source directives that point ot static files
        process_directive "$line" || { check && continue; }

        # remove first shebang in the file
        if ! [[ "$found_first_line" ]]; then
            process_shebang "$line" || { check && continue; }
        fi

        if [[ ! "$found_first_line" ]]; then
            if echo "$line" | grep -E "^[[:space:]]*$" >/dev/null; then
                continue
            else
                found_first_line=1
            fi
        fi

        # Otherwise echo the line as is
        echo "$line"
    done <"$file"

    # Add some spacing
    printf '\n\n'

    popd >/dev/null || exit
}

echo_entrypoint_call() {
    if [[ "$entrypoint_func" ]]; then
        # shellcheck disable=SC2016
        printf '[[ "$__main__" ]] && %s "$@"\n\n' "$entrypoint_func"
    fi
}

check() {
    local ret="$?"

    if [[ "$ret" == 200 ]]; then
        return 0
    fi

    if [[ "$ret" ]] && ((ret != 0 && ret != 200)); then
        exit "$ret"
    fi

    return 1
}

process_shebang() {
    local line="$1"
    line=$(trim_str "$line")

    if [[ "$line" =~ ^\#\! ]]; then
        return 200
    fi
}

process_directive() {
    local line="$1"

    local trimmed_line
    trimmed_line=$(trim_str "$line")

    if ! [[ "$trimmed_line" =~ ^bgen\: ]]; then
        return 0
    fi

    local indent_size
    indent_size=$(echo "" | awk -v l="$line" -v t="$trimmed_line" '{print index(l, t) - 1}')

    # shellcheck disable=2001
    declare -a "args=( $(echo "$trimmed_line" | sed -e 's/\([`$\(\)]\)/\\\1/g') )"

    if (("${#args[@]}" == 0)); then
        return 0
    fi

    local directive="${args[0]}"
    args=("${args[@]:1}")

    case "$directive" in
    "bgen:import") bgen_import "${args[@]}" ;;
    "bgen:include_str") bgen_include_str "${args[@]}" ;;
    "bgen:"*) bail "unknown bgen directive: $directive" ;;
    *) ;;
    esac
}

bgen_import() {
    local file="${1:-}"
    if [[ ! "$file" ]]; then
        bail "bgen:import requires 1 parameter (filename)"
    fi

    # Check if there exists a file with `.sh` appended to it
    [[ -f "${file}.sh" ]] && file="${file}.sh"

    # Raise error if file does not exit
    if [[ ! -f "$file" ]]; then
        bail "bgen:import error: cannot import $file"
    fi

    # Don't re-import file if it was already imported
    if ! is_file_marked_imported "$file"; then
        # Mark file as imported
        mark_file_imported "$file"

        # Do normal file processing
        process_file "$file"
    fi

    # Return 200 to tell check() that we've processed something
    return 200
}

bgen_include_str() {
    local variable="${1:-}"
    local file="${2:-}"
    if [[ ! "$variable" || ! "$file" ]]; then
        bail "bgen:include_str requires 2 parameters (variable name and filename)"
    fi

    local indent_size="${indent_size:-0}"
    local tabs=$((indent_size / 4))
    local indent
    indent=$(printf "%${indent_size}s")
    indent_plus=$(printf '\t%.0s' $(seq $((tabs + 1))))

    # Raise error if file does not exit
    if [[ ! -f "$file" ]]; then
        bail "bgen:include_str error: cannot import $file"
    fi

    echo "${indent}${variable}=\$("
    echo "${indent}cat <<-\"EOF\""
    while IFS= read -r line; do
        echo "$indent_plus$line"
    done <"$file"
    echo "${indent_plus}EOF"
    echo "${indent})"

    # Return 200 to tell check() that we've processed something
    return 200
}

mark_file_imported() {
    local file="$1"
    file=$(realpath "$file")

    imported_files+=("$file")
}

is_file_marked_imported() {
    local file="$1"
    file=$(realpath "$file")

    for imported_file in "${imported_files[@]}"; do
        if [[ "$imported_file" == "$file" ]]; then
            return 0
        fi
    done

    return 1
}
