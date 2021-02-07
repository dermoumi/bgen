#!/usr/bin/env bash

bgen:import lib/meta
bgen:import lib/build

command_test() {
    barg.arg targets \
        --multi \
        --value=FILE \
        --desc="Test script files or directories to run."
    barg.arg test_funcs \
        --multi \
        --short=k \
        --value FUNC \
        --desc "Names of test functions to run."
    barg.arg no_capture \
        --short=O \
        --long=no-capture \
        --env=BGEN_NO_CAPTURE \
        --desc "Also show the output of succeeding tests."
    barg.arg coverage \
        --short=c \
        --long=coverage \
        --env=BGEN_COVERAGE \
        --desc "Make a code coverage report."
    barg.arg coverage_experimental \
        --implies=coverage \
        --short=C \
        --long=coverage-experimental \
        --env=BGEN_COVERAGE_EXPERIMENTAL \
        --desc "Enable experimental code coverage features."
    barg.arg coverage_debug \
        --implies=no_capture \
        --implies=coverage \
        --short=D \
        --long=coverage-debug \
        --env=BGEN_COVERAGE_DEBUG \
        --desc "Print lines as they're executed to stderr."
    barg.arg coverage_file \
        --short=H \
        --long=html-report \
        --value=FILE \
        --default=coverage.html \
        --env=BGEN_HTML_REPORT_FILE \
        --desc "Name of the coverage html report."
    barg.arg print_source \
        --short=p \
        --long=print-source \
        --desc "Print test script's source code instead of executing it."

    local targets=()
    local test_funcs=()
    local no_capture=
    local coverage=
    local coverage_experimental=
    local coverage_debug=
    local coverage_file=
    local print_source=

    local should_exit=
    local should_exit_err=0
    barg.parse "$@"
    if ((should_exit)); then
        return "$should_exit_err"
    fi

    # shellcheck disable=2034
    local project_root=
    # shellcheck disable=2034
    local header_file=
    # shellcheck disable=2034
    local shebang_string=
    # shellcheck disable=2034
    local import_paths=
    local tests_dir=
    local entrypoint_file=
    local entrypoint_func=
    local source_dir=
    local is_library=
    read_project_meta

    # check whether bgen is sourced or directly executed
    local process process_dir process_file process_base
    if [[ "${__BGEN_PIPE_SOURCE__:-}" ]]; then
        process="$__BGEN_PIPE_SOURCE__"
    elif [[ "${BASH_SOURCE+x}" ]]; then
        process="${BASH_SOURCE[0]}"
    else
        process="$0"
    fi

    # Set magic variables for current file, directory, os, etc.
    process_dir="$(cd "$(dirname "${process}")" && pwd)"
    process_file="${process_dir}/$(basename "${process}")"
    # shellcheck disable=SC2034,SC2015
    process_base="$(basename "${process_file}" .sh)"

    local process_base=${process_base:-$0}
    export __BGEN_PIPE_SOURCE__="$process_base test"

    local script_file
    script_file=$(mktemp)
    # shellcheck disable=SC2064
    trap "rm -rf '$script_file'" EXIT

    build_tests_to_stdout >"$script_file"

    if ((print_source)); then
        cat "$script_file"
    else
        bash "$script_file"
    fi
}

build_tests_to_stdout() {
    # used later to keep track of whether a file was imported or not
    # declared here to be on the biggest private scope it's needed in
    # shellcheck disable=2034
    local imported_files=()

    local test_files=()
    if ! ((${#targets[@]})); then
        # make sure tests directory exists
        if ! [[ -d "$tests_dir" ]]; then
            butl.fail "tests directory '$tests_dir' does not exist"
            return
        fi

        collect_testfiles_in_dir "$tests_dir"
    else
        for target in "${targets[@]}"; do
            if [[ -d "$target" ]]; then
                collect_testfiles_in_dir "$target"
            else
                test_files+=("$target")
            fi
        done
    fi

    # build the tests file
    echo_shebang
    echo_header

    # pre-including the project for tests to have better coverage reports
    if ((is_library)); then
        if shopt -qs globstar; then
            local keep_globstar=1
        fi

        shopt -s globstar
        for file in "${source_dir%/}"/**/*.sh; do
            # If we have the same path as the query, then we got no file
            if [[ "$file" == "${source_dir%/}/**/*.sh" ]]; then
                break
            fi

            # ignore files that start with an underscore
            if [[ "${file##*/}" == _* ]]; then
                continue
            fi

            local err=0
            bgen_import "$file" || err=$?
            if ((err != 200)); then
                if ! ((keep_globstar)); then
                    shopt -u globstar
                fi

                return $err
            fi
        done

        if ! ((keep_globstar)); then
            shopt -u globstar
        fi
    elif [[ "$entrypoint_func" && -s "$entrypoint_file" ]]; then
        # if there's no entrypoint function, we assume the entrypoint file
        # runs actual code and that can cause problems during tests
        local err=0
        bgen_import "$entrypoint_file" || err=$?
        if ((err != 200)); then
            return $err
        fi
    fi

    for test_file in "${test_files[@]}"; do
        [[ -f "$test_file" ]] || continue

        local err=0
        bgen_import "$test_file" || err=$?
        if ((err != 200)); then
            return $err
        fi
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

    local assertlib
    bgen:include_str assertlib "lib/asserts.sh"
    process_input <<<"$assertlib"

    local bootstrap
    bgen:include_str bootstrap "lib/tests_bootstrap.sh"
    process_input <<<"$bootstrap"
}

collect_testfiles_in_dir() {
    local dir=$1

    for file in "$dir"/*; do
        # ${file##*/} keeps only what's after the last slash (aka the basename)
        if [[ "${file##*/}" != "_"* ]]; then
            test_files+=("$file")
        fi
    done
}
