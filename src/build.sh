#!/usr/bin/env bash

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
    local output_file
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
    # used later to keep track of whether a file was imported or not
    # declared here to be on the biggest private scope it's needed in
    local imported_files=()

    local project_name header_file entrypoint_file entrypoint_func shebang_string imports_dir
    read_project_meta

    # build the project
    echo_header
    process_file "$entrypoint_file"
    echo_entrypoint_call
}

build_tests_to_stdout() {
    # used later to keep track of whether a file was imported or not
    # declared here to be on the biggest private scope it's needed in
    local imported_files=()

    local project_name header_file tests_dir shebang_string imports_dir
    read_project_meta

    # make sure tests directory exists
    if ! [[ -d "$tests_dir" ]]; then
        echo "tests directory '$tests_dir' does not exist" >&2
        exit 1
    fi

    local test_files=()
    local test_funcs=()
    local failed=
    while (($#)); do
        case "$1" in
        -k)
            test_funcs+=("$2")
            shift 2
            ;;
        -k=*)
            test_funcs+=("${1/-k=/}")
            shift
            ;;
        *)
            local file="$1"
            shift

            if [[ -f "$file" ]]; then
                test_files+=("$file")
                continue
            fi

            echo "test file '$file' does not exist" >&2
            failed=1
            ;;
        esac
    done

    if [[ "$failed" ]]; then
        exit 1
    elif ! ((${#test_files[@]})); then
        test_files=("$tests_dir"/*)
    fi

    # build the tests file
    echo_header
    for test_file in "${test_files[@]}"; do
        [[ -f "$test_file" ]] || continue

        bgen_import "$test_file" || { check && true; }
    done

    echo "__BGEN_TEST_FUNCS__=("
    if ((${#test_funcs[@]})); then
        printf '    %q\n' "${test_funcs[@]}"
    else
        # shellcheck disable=SC2028
        echo "\$(declare -F | awk '\$3 ~ /^ *test_/ {printf \"%s\n\", \$3}')"
    fi
    echo ")"

    bgen:include_str testlib "testlib.sh"
    # shellcheck disable=SC2154
    echo "$testlib"
}

# shellcheck disable=SC2034
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
    if is_declared project_name; then
        project_name="$bgen_project_name"
    fi

    # get header file
    if is_declared header_file; then
        header_file="${bgen_header_file:-}"
    fi

    # get entrypoint file
    if is_declared entrypoint_file; then
        entrypoint_file="${bgen_entrypoint_file:-"$meta_dir/src/main.sh"}"
    fi

    # get entrypoint func
    if is_declared entrypoint_func; then
        entrypoint_func="${bgen_entrypoint_func:-}"
    fi

    # get shebang string
    if is_declared shebang_string; then
        shebang_string="${bgen_shebang_string:-"#!/usr/bin/env bash"}"
    fi

    # get output file
    if is_declared output_file; then
        output_file="${bgen_output_file:-"$meta_dir/bin/$bgen_project_name"}"
    fi

    # tests dir
    if is_declared tests_dir; then
        tests_dir="${bgen_tests_dir:-"$meta_dir/tests"}"
    fi

    # imports dir
    if is_declared imports_dir; then
        imports_dir="${bgen_imports_dir:-"$meta_dir/deps"}"
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
        # Process source directives that point ot static files
        process_directive "$line" || { check && continue; }

        # Remove first shebang in the file
        if ! [[ "$found_first_line" ]]; then
            process_shebang "$line" || { check && continue; }
        fi

        if [[ ! "$found_first_line" ]]; then
            if ! echo "$line" | grep -E "^[[:space:]]*$" >/dev/null; then
                found_first_line=1
            fi
        fi

        # Otherwise echo the line as is
        echo "$line"
    done <"$file"

    popd >/dev/null || exit
}

echo_entrypoint_call() {
    if [[ "$entrypoint_func" ]]; then
        # shellcheck disable=SC2016
        printf '\n[[ "$__main__" ]] && %s "$@"\n' "$entrypoint_func"
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
        found_first_line=1
        echo "# BGEN__SHEBANG_REMOVED"
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

find_source_file() {
    local file="${1:-}"

    # If the file exists, return it
    if [[ -f "$file" ]]; then
        echo "$file"
        return
    fi

    # Check if there exists a file with `.sh` appended to it
    if [[ -f "${file}.sh" ]]; then
        echo "${file}.sh"
        return
    fi

    # Check in import directories
    for dir in "${imports_dir[@]}"; do
        if [[ -f "$dir/$file" ]]; then
            echo "$dir/$file"
            return
        fi
        if [[ -f "$dir/${file}.sh" ]]; then
            echo "$dir/${file}.sh"
            return
        fi
    done
}

bgen_import() {
    local file="${1:-}"
    if [[ ! "$file" ]]; then
        bail "bgen:import requires 1 parameter (filename)"
    fi

    # Raise error if file does not exit
    source_file=$(find_source_file "${1:-}")
    if [[ ! -f "$source_file" ]]; then
        bail "bgen import error: cannot import '$file'"
    fi

    # Don't re-import file if it was already imported
    if ! is_in_array "$(realpath "$source_file")" "${imported_files[@]-}"; then
        # Mark file as imported
        imported_files+=("$(realpath "$source_file")")

        # Add a comment indicating where the processing starts
        echo "# BGEN__BEGIN $source_file"

        # Do normal file processing
        process_file "$source_file"

        # Add a comment indicating where the processing starts
        echo "# BGEN__END $source_file"
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

    echo "# BGEN__INCLUDE_STR_BEGIN"
    echo "${indent}${variable}=\$("
    echo "${indent}cat <<-\"EOF\""
    while IFS= read -r line; do
        echo "$indent_plus$line"
    done <"$file"
    echo "${indent_plus}EOF"
    echo "${indent})"
    echo "# BGEN__INCLUDE_STR_END"

    # Return 200 to tell check() that we've processed something
    return 200
}

is_in_array() {
    local target="$1"
    shift

    for item in "$@"; do
        [[ "$target" == "$item" ]] && return 0
    done

    return 1
}

# Utility function to check if any of the passed variables is not declared
# @param    variable_name...    names of variables to check
is_declared() {
    declare -p "$@" >/dev/null 2>/dev/null
}
