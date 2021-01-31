#!/usr/bin/env bash

bgen:import butl/vars
bgen:import butl/arrays

echo_header() {
    local header_file=${header_file:-}
    if [[ -f "$header_file" ]]; then
        if [[ "${shebang_string:-}" ]]; then
            printf '%s\n\n' "$shebang_string"
        fi

        process_file "$header_file"
    else
        local default_header
        bgen:include_str default_header ../header.sh

        echo "$default_header"
    fi

    # Add some spacing
    printf '\n\n'
}

process_file() {
    local file
    file=$(find_file "$1")

    # get directory name
    : "${file%/*}"
    local src_dir=${_:-/}

    pushd "$src_dir" >/dev/null || return
    process_input <"$file"
    popd >/dev/null || return
}

process_input() {
    local found_first_line=
    while IFS= read -r line; do
        local err=0

        # Process source directives that point ot static files
        process_directive "$line" || err=$?
        if ((err == 200)); then
            continue
        elif ((err)); then
            return $err
        fi

        # Remove first shebang in the file
        if ! [[ "$found_first_line" ]]; then
            process_shebang "$line" || err=$?
            if ((err == 200)); then
                continue
            elif ((err)); then
                return $err
            fi
        fi

        if [[ ! "$found_first_line" ]]; then
            if ! echo "$line" | grep -E "^[[:space:]]*$" >/dev/null; then
                found_first_line=1
            fi
        fi

        # Otherwise echo the line as is
        echo "$line"
    done
}

echo_entrypoint_call() {
    local entrypoint_func=${entrypoint_func:-}

    if [[ "$entrypoint_func" ]]; then
        # shellcheck disable=SC2016
        printf '\n[[ "$__main__" ]] && %s "$@"\n' "$entrypoint_func"
    fi
}

process_shebang() {
    local line
    line=$(trim_str "$1")

    if [[ "$line" =~ ^\#\! ]]; then
        found_first_line=1
        echo "# BGEN__SHEBANG_REMOVED"
        return 200
    fi
}

process_directive() {
    local line=$1
    if ! [[ "$line" =~ ^[[:space:]]*bgen\: ]]; then
        return 0
    fi

    : "${line%%[![:space:]]*}"
    local indent_size=${#_}

    # escape `` and $()
    : "${line//\`/\\\`}"
    : "${_//\$/\\\$}"
    : "${_//\(/\\\(}"
    : "${_//\)/\\/)}"
    declare -a "args=( $_ )"

    # parse arguments
    if (("${#args[@]}" == 0)); then
        return 0
    fi

    local directive=${args[0]}
    args=("${args[@]:1}")

    case "$directive" in
    "bgen:import") bgen_import "${args[@]}" ;;
    "bgen:include") bgen_include "${args[@]}" ;;
    "bgen:include_str") bgen_include_str "${args[@]}" ;;
    "bgen:"*) butl.fail "unknown bgen directive: $directive" ;;
    *) ;;
    esac
}

find_file() {
    local file=$1

    # check if the file exists
    if [[ -r "$file" && -f "$file" ]]; then
        realpath "$file"
        return
    fi

    # check in import directories
    # shellcheck disable=SC2154
    for unexpanded_dir in "${import_paths[@]}"; do
        for dir in $unexpanded_dir; do
            # make sure external files are always imported relative to project dir
            if [[ "$dir" != /* ]]; then
                dir="${project_root:-$PWD}/$dir"
            fi

            if [[ -r "$dir/$file" && -f "$dir/$file" ]]; then
                realpath "$dir/$file"
                return
            fi
        done
    done

    # nothing found :(
    echo "file does not exist or is not readable: $file" >&2
    return 1
}

find_source_file() {
    local file=$1

    find_file "${file}.sh" 2>/dev/null || find_file "$file"
}

bgen_import() {
    local file
    file=$(find_source_file "$1")

    # Don't re-import file if it was already imported
    if butl.index_of "$file" "${imported_files[@]-}"; then
        echo "# BGEN__ALREADY_IMPORTED $file"
    else
        # Mark file as imported
        imported_files+=("$file")

        # Add a comment indicating where the processing starts
        echo "# BGEN__BEGIN $file"

        # Do normal file processing
        process_file "$file"

        # Add a comment indicating where the processing starts
        echo "# BGEN__END $file"
    fi

    # Return 200 to tell check() that we've processed something
    return 200
}

bgen_include() {
    local file
    file=$(find_source_file "$1")

    # Add a comment indicating where the processing starts
    echo "# BGEN__BEGIN $file"

    # Do normal file processing
    process_file "$file"

    # Add a comment indicating where the processing starts
    echo "# BGEN__END $file"

    return 200
}

bgen_include_str() {
    local variable=$1
    local file
    file=$(find_file "$2")

    local TAB_SIZE=4
    local indent_size=${indent_size:-0}
    local tabs=$((indent_size / TAB_SIZE))
    local indent
    indent=$(printf "%${indent_size}s")
    indent_plus=$(printf '\t%.0s' $(seq $((tabs + 1))))

    local heredoc_id="${RANDOM}_${RANDOM}"
    echo "# BGEN__INCLUDE_STR_BEGIN"
    echo "${indent}read -rd '' ${variable} <<-\"BGEN_EOF_${heredoc_id}\" || :"
    while IFS= read -r line; do
        echo "$indent_plus$line"
    done <"$file"
    echo "${indent_plus}BGEN_EOF_${heredoc_id}"
    echo "# BGEN__INCLUDE_STR_END"

    # Return 200 to tell check() that we've processed something
    return 200
}
