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
    # used later to keep track of whether a file was imported or not
    # declared here to be on the biggest private scope it's needed in
    local imported_files=()

    local project_root=
    local project_name=
    local header_file=
    local entrypoint_file=
    local entrypoint_func=
    local shebang_string=
    local import_paths=
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

    local project_root=
    local project_name=
    local header_file=
    local tests_dir=
    local shebang_string=
    local import_paths=
    local entrypoint_file=
    local entrypoint_func=
    read_project_meta

    # make sure tests directory exists
    if ! [[ -d "$tests_dir" ]]; then
        echo "tests directory '$tests_dir' does not exist" >&2
        exit 1
    fi

    local test_files=()
    local test_funcs=()
    local failed=0
    local no_capture="${BGEN_NO_CAPTURE:-0}"
    local coverage="${BGEN_COVERAGE:-0}"
    local coverage_experimental="${BGEN_COVERAGE_EXPERIMENTAL:-0}"
    local coverage_debug="${BGEN_COVERAGE_DEBUG:-0}"
    local coverage_file="${BGEN_HTML_REPORT_FILE:-}"
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
        -O | --no-capture)
            no_capture=1
            shift
            ;;
        -c | --coverage)
            coverage=1
            shift
            ;;
        -C | --coverage-experimental)
            coverage=1
            coverage_experimental=1
            shift
            ;;
        -D | --coverage-debug)
            coverage=1
            coverage_debug=1
            shift
            ;;
        -h | --html-report)
            coverage=1
            coverage_file="$2"
            shift 2
            ;;
        -h=*)
            coverage=1
            coverage_file="${1/-h=/}"
            shift
            ;;
        --html-report=*)
            coverage=1
            coverage_file="${1/--html-report=/}"
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

    if ((failed)); then
        exit 1
    elif ! ((${#test_files[@]})); then
        for file in "$tests_dir"/*; do
            # ${file##*/} keeps only what's after the last slash (aka the basename)
            if [[ "${file##*/}" != "_"* ]]; then
                test_files+=("$file")
            fi
        done
    fi

    # build the tests file
    echo_header

    # pre-including the project for tests to have better coverage reports
    # if there's no entrypoint function, we assume the entrypoint file
    # runs actual code and that can cause problems during tests
    if [[ "$entrypoint_func" ]]; then
        bgen_import "$entrypoint_file" || { check && true; }
    fi

    for test_file in "${test_files[@]}"; do
        [[ -f "$test_file" ]] || continue

        bgen_import "$test_file" || { check && true; }
    done

    if ((${#test_funcs[@]})); then
        echo "__BGEN_TEST_FUNCS__=("
        printf '    %q\n' "${test_funcs[@]}"
        echo ")"
    fi

    echo "BGEN_NO_CAPTURE=$no_capture"
    echo "BGEN_COVERAGE=$coverage"
    echo "BGEN_COVERAGE_EXPERIMENTAL=$coverage_experimental"
    echo "BGEN_COVERAGE_DEBUG=$coverage_debug"
    printf "BGEN_HTML_REPORT_FILE=%q\n\n" "$coverage_file"

    local testlib
    bgen:include_str testlib "lib/test.sh"
    process_input <<<"$testlib"
}

# shellcheck disable=SC2034
read_project_meta() {
    is_declared import_paths || local import_paths

    # make sure some vars are local if not declared on a parent scope
    is_declared project_root || local project_root
    is_declared project_name || local project_name
    is_declared header_file || local header_file
    is_declared entrypoint_file || local entrypoint_file
    is_declared entrypoint_func || local entrypoint_func
    is_declared shebang_string || local shebang_string
    is_declared output_file || local output_file
    is_declared tests_dir || local tests_dir

    # set some defaults
    entrypoint_file="src/main.sh"
    shebang_string="#!/usr/bin/env bash"
    tests_dir="tests"

    local import_paths_extra=()
    import_paths=()
    if [[ "${BGEN_IMPORT_PATHS:-}" ]]; then
        while read -r -d ':' path; do
            import_paths+=("$path")
        done <<<"${BGEN_IMPORT_PATHS}:"
    fi
    import_paths+=(deps/*/lib)

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
            break
        fi

        cd ..
    done

    # set default project name
    if [[ ! "${project_name:-}" ]]; then
        # ${file##*/} keeps only what's after the last slash (aka the basename)
        project_name="${PWD##*/}"
    fi

    # set default output file
    if [[ ! "${output_file:-}" ]]; then
        output_file="bin/$project_name"
    fi

    # set default entrypoint function
    if [[ ! "${entrypoint_func:-}" ]]; then
        entrypoint_func="$project_name"
    fi

    # add the extra import paths
    if ((${#import_paths_extra[@]})); then
        import_paths=("${import_paths_extra[@]}" "${import_paths[@]}")
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
    file=$(find_file "$file")

    # get directory name
    : "${file%/*}"
    local src_dir="${_:-/}"

    pushd "$src_dir" >/dev/null || return
    process_input <"$file"
    popd >/dev/null || return
}

process_input() {
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
    done
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

    # parse arguments
    declare -a "args=( $_ )"
    if (("${#args[@]}" == 0)); then
        return 0
    fi

    local directive="${args[0]}"
    args=("${args[@]:1}")

    case "$directive" in
    "bgen:import") bgen_import "${args[@]}" ;;
    "bgen:include") bgen_include "${args[@]}" ;;
    "bgen:include_str") bgen_include_str "${args[@]}" ;;
    "bgen:"*) bail "unknown bgen directive: $directive" ;;
    *) ;;
    esac
}

find_file() {
    local file="$1"

    # check if the file exists
    if [[ -r "$file" ]]; then
        realpath "$file"
        return
    fi

    # check in import directories
    for unexpanded_dir in "${import_paths[@]}"; do
        for dir in $unexpanded_dir; do
            # make sure external files are always imported relative to project dir
            if [[ "$dir" != /* ]]; then
                dir="${project_root:-$PWD}/$dir"
            fi

            if [[ -r "$dir/$file" ]]; then
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
    local file="$1"

    find_file "${file}.sh" 2>/dev/null || find_file "$file"
}

bgen_import() {
    local file
    file=$(find_source_file "$1")

    # Don't re-import file if it was already imported
    if is_in_array "$file" "${imported_files[@]-}"; then
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
    local variable="$1"
    local file="$2"
    file=$(find_file "$file")

    local TAB_SIZE=4
    local indent_size="${indent_size:-0}"
    local tabs=$((indent_size / TAB_SIZE))
    local indent
    indent=$(printf "%${indent_size}s")
    indent_plus=$(printf '\t%.0s' $(seq $((tabs + 1))))

    local heredoc_id="$RANDOM$RANDOM"
    echo "# BGEN__INCLUDE_STR_BEGIN"
    echo "${indent}read -r -d '' ${variable} <<-\"BGEN_EOF_${heredoc_id}\" || :"
    while IFS= read -r line; do
        echo "$indent_plus$line"
    done <"$file"
    echo "${indent_plus}BGEN_EOF_${heredoc_id}"
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
