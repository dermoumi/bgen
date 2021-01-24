#!/usr/bin/env bash

__bgen_test_entrypoint() {
    local failed_tests_funcs=()
    local test_reports=()

    local coverage_map=()

    # linemap shows at what lines each file starts and ends
    if [[ ! "${__BGEN_TEST_LINEMAP:-}" ]]; then
        local linemap=()
        local line_nr=0
        while IFS= read -r line; do
            line_nr=$((line_nr + 1))

            local line="${line#${line%%[![:space:]]*}}" # strip leading whitepsace if any
            if [[ "$line" =~ ^\#[[:space:]]BGEN__ ]]; then
                linemap+=("$line_nr ${line:2}")
            fi
        done <<<"$BASH_EXECUTION_STRING"

        local linemap_str
        linemap_str="$(__bgen_test_join_by $'\n' "${linemap[@]}")"
        export __BGEN_TEST_LINEMAP="$linemap_str"
    fi

    # look over test functions
    if declare -p __BGEN_TEST_FUNCS__ >/dev/null 2>&1; then
        # bgen test created a variable with specific tests to run
        for test_func in "${__BGEN_TEST_FUNCS__[@]}"; do
            __bgen_test_run_single "$test_func"
        done
    else
        # no specific tests to run, find and run all tests that start with test_xxxx
        while IFS= read -r line; do
            if [[ "$line" == "declare -f test_"[[:alnum:]]* ]]; then
                local test_func="${line#${line%%test_*}}"
                __bgen_test_run_single "$test_func"
            fi
        done < <(declare -F)
    fi
    echo

    if (("${#test_reports[@]}")); then
        for test_report in "${test_reports[@]}"; do
            echo "$test_report"
        done
        printf '\n%b-----%b' "$__BGEN_TEST_COL_FILENAME" "$__BGEN_TEST_COL_RESET"
    fi

    if (("${#failed_tests_funcs[@]}")); then
        printf "\n%bFailed tests:%b\n" "$__BGEN_TEST_COL_TITLE" "$__BGEN_TEST_COL_RESET"
        for test_func in "${failed_tests_funcs[@]}"; do
            echo "    $test_func"
        done
    fi

    # report on coverage if requested
    : "${BGEN_NO_COVERAGE:=0}"
    : "${BGEN_HTML_REPORT_FILE:=}"
    : "${BGEN_COVERAGE_M_THRESHOLD:=60}"
    : "${BGEN_COVERAGE_H_THRESHOLD:=85}"
    if ! ((BGEN_NO_COVERAGE)); then
        printf "\n%bCoverage:%b\n" "$__BGEN_TEST_COL_TITLE" "$__BGEN_TEST_COL_RESET"
        __bgen_test_make_coverage_report
    fi

    # exit with error if any test failed
    if (("${#failed_tests_funcs[@]}")); then
        printf '\n%bSome tests have failed%b\n' "$__BGEN_TEST_COL_DANGER" "$__BGEN_TEST_COL_RESET"
        exit 1
    else
        printf '\n%bAll tests passed successfully %s%b\n' \
            "$__BGEN_TEST_COL_SUCCESS" "☆*･゜ﾟ･*(^O^)/*･゜ﾟ･*☆" "$__BGEN_TEST_COL_RESET"
    fi
}

# requires 2 variables: source_file and source_line_nr to be declared
__bgen_test_get_source_line() {
    local bgen_line="$1"

    # stacks to keep track of...
    local files_stack=("UNKNOWN_FILE") # which file we're currently processing
    local line_nrs_stack=(0)           # the start line number of the file
    local offsets_stack=(0)            # how much lines should we offset from this file's linecount

    while IFS= read -r line; do
        # parse the line number
        local line="${line#${line%%[![:space:]]*}}" # strip leading whitespace if any
        local line_nr="${line%%[[:space:]]*}"       # strip everything from the first space

        if ((line_nr > bgen_line)); then
            break
        fi

        # bash 3.2 seems to complain when i use case .. in .. esac here
        if [[ "$line" =~ ^[[:digit:]]+[[:space:]]+BGEN__BEGIN[[:space:]]+ ]]; then
            : "${line#*BGEN__BEGIN[[:space:]]}"
            local file="${_#${_%%[![:space:]]*}}"

            # add values related to this file to the new stack
            files_stack=("$file" "${files_stack[@]}")
            line_nrs_stack=("$line_nr" "${line_nrs_stack[@]}")
            offsets_stack=(0 "${offsets_stack[@]}")
        elif [[ "$line" =~ ^[[:digit:]]+[[:space:]]+BGEN__END[^[:alnum:]]+ ]]; then
            local file_start_line_nr="${line_nrs_stack[0]}"
            local file_lines=$((line_nr - file_start_line_nr))

            # pop the first item from the stack
            files_stack=("${files_stack[@]:1}")
            line_nrs_stack=("${line_nrs_stack[@]:1}")
            offsets_stack=("${offsets_stack[@]:1}")

            # offset the previous item's lines with the linecount of this file
            offsets_stack[0]=$((offsets_stack[0] + file_lines))
        fi
    done <<<"$__BGEN_TEST_LINEMAP"

    if declare -p source_file 1>/dev/null 2>&1; then
        source_file="${files_stack[0]/$PWD\//}"
    fi

    if declare -p source_line_nr 1>/dev/null 2>&1; then
        source_line_nr=$((bgen_line - line_nrs_stack[0] - offsets_stack[0]))
    fi
}
export -f __bgen_test_get_source_line

# called when a test's subprocess exits with a non-zero return code
__bgen_test_error_handler() {
    local rc="$__bgen_test_current_rc"

    # get error line number
    if ((BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4)) && [[ "${__bgen_assert_line:-}" ]]; then
        # bash version 4.0 to 4.3 only call the handler AFTER the returning function was left
        # the workaround here is to have assert functions to keep track of the line they left at instead
        local line_nr=$((__bgen_assert_line + 1))
    elif [[ "$__bgen_test_current_cmd" == "$__bgen_test_prev_cmd" ]]; then
        # if we have two successive return commands, use the previous one's line
        # workaround for when bash reports the return AFTER the returning to the parent function
        local line_nr="$__bgen_test_prev_line_nr"
    else
        local line_nr="$__bgen_test_current_line_nr"

        # bash 3.2 strangely uses the previous line for errors
        if ((BASH_VERSINFO[0] < 4)); then
            line_nr=$((line_nr + 1))
        fi
    fi

    # prevent the exit_handler from outputting anything since it's also executed
    __bgen_test_error_handled=1

    # print the original source file and line number for easy debugging
    local source_file=""
    local source_line_nr=""
    __bgen_test_get_source_line "$line_nr"
    printf '%b%s:%s (rc=%s)%b\n' \
        "$__BGEN_TEST_COL_DANGER" "$source_file" "$source_line_nr" "$rc" "$__BGEN_TEST_COL_RESET" >&2

    # exit with the same return code we came with
    exit "$rc"
}
export -f __bgen_test_error_handler

# called when a test's subprocess exits
__bgen_test_exit_handler() {
    local rc="$__bgen_test_current_rc"

    # save coverage lines into a file, only way to communicate them to the parent process
    declare -p __bgen_test_covered_lines >"$__bgen_env_file"

    # if the error handler was already triggered, don't do anything else here
    if ((${__bgen_test_error_handled:-})); then
        exit "$rc"
    fi

    # more reliable than LINENO
    local line_nr="$__bgen_test_prev_line_nr"

    # get exit line number
    if [[ "$rc" == 0 ]]; then
        # workaround for bash <4.0 returning 0 on nounset errors
        [[ "${__func_finished_successfully:-}" ]] && exit 0

        # this is the same code bash returns on version 4+ in these cases
        rc=127

        if [[ "${__bgen_test_prev_line_nr:-}" ]]; then
            line_nr=$((__bgen_test_prev_line_nr))
        fi
    elif [[ "${__bgen_test_prev_line_nr:-}" ]]; then
        line_nr="$__bgen_test_prev_line_nr"
    fi

    # print the original source and line number for easy debugging
    local source_file=""
    local source_line_nr=""
    __bgen_test_get_source_line "$line_nr"
    printf '%b%s:%s (rc=%s)%b\n' \
        "$__BGEN_TEST_COL_DANGER" "$source_file" "$source_line_nr" "$rc" "$__BGEN_TEST_COL_RESET" >&2

    # exit with the same return code we came with
    exit "$rc"
}
export -f __bgen_test_exit_handler

# called before each line, use to keep track of what lines
# were executed, and which are the last 2 commands and their rc and line numbers
# used for error reporting and code coverage
__bgen_test_debug_handler() {
    local rc="$1"
    local line_nr="$2"
    local cmd="$3"

    # bash versions <5.1 don't seem to count the shebang in their line count
    if ((BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 1))); then
        line_nr=$((line_nr + 1))
    fi

    if ((__bgen_previous_rc == 0)); then
        __bgen_previous_rc="$__bgen_test_current_rc"
        __bgen_test_prev_cmd="$__bgen_test_current_cmd"
        __bgen_test_prev_line_nr="$__bgen_test_current_line_nr"
    fi

    __bgen_test_current_rc="$rc"
    __bgen_test_current_cmd="$cmd"
    __bgen_test_current_line_nr="$line_nr"

    __bgen_test_covered_lines[$line_nr]=1
}
export -f __bgen_test_debug_handler

# joins lines with a delimited
__bgen_test_join_by() {
    if (($# <= 1)); then
        return 0
    fi

    local delimiter="$1"
    local first="$2"
    shift 2

    printf '%s' "$first" "${@/#/$delimiter}"
}

# Returns true if a line is covered according to the coverage map
__bgen_is_line_covered() {
    local line_nr="$1"
    local line="$2"

    if [[ "${coverage_map[$line_nr]-}" ]]; then
        # line is in the coverage map
        return 0
    fi

    if [[ "$line" =~ ^[[:space:]]*$ ]]; then
        # line is empty space
        # covered only if the previous line also covered
        ((${is_prev_line_covered_stack[0]-}))
        return
    fi

    if [[ "$line" =~ ^[[:space:]]*\# ]]; then
        # line is a comment
        # covered only if the previous line also covered
        ((${is_prev_line_covered_stack[0]-}))
        return
    fi

    if [[ "$line" =~ ^[[:space:]]*[\(\)\{\}][[:space:]]*$ ]]; then
        # line is a single parenthesis
        # covered only if the previous line also covered
        ((${is_prev_line_covered_stack[0]-}))
        return
    fi

    # otherwise, line is not covered
    return 1
}

# prints coverage report for a given file
__bgen_test_add_file_report() {
    local filename="$1"
    local covered_hunks="$2"
    local covered_lines_count="$3"
    local total_lines_count="$4"

    local percent=$((100 * covered_lines_count / total_lines_count))
    local filename_short="${filename/$PWD\//}"

    if ((percent >= BGEN_COVERAGE_H_THRESHOLD)); then
        local coverage_rating="h"
        local coverage_color="$__BGEN_TEST_COL_SUCCESS"
    elif ((percent >= BGEN_COVERAGE_M_THRESHOLD)); then
        local coverage_rating="m"
        local coverage_color="$__BGEN_TEST_COL_WARNING"
    else
        local coverage_rating="l"
        local coverage_color="$__BGEN_TEST_COL_DANGER"
    fi

    if [[ "$BGEN_HTML_REPORT_FILE" ]]; then
        local file_id="${filename_short//[![:alnum:]-_]/_}"

        local code
        code="$(cat "$filename")"
        code="${code//</&lt;}"
        code="${code//>/&gt;}"

        local html
        html="${__BGEN_COVERAGE_HTML_FILE//__COVERAGE_FILE_NAME__/$filename_short}"
        html="${html//__COVERAGE_FILE_ID__/$file_id}"
        html="${html//__COVERAGE_FILE_COVERED__/$covered_lines_count}"
        html="${html//__COVERAGE_FILE_LINES__/$total_lines_count}"
        html="${html//__COVERAGE_FILE_PERCENT__/$percent}"
        html="${html//__COVERAGE_FILE_RATING__/$coverage_rating}"
        html="${html//__COVERAGE_FILE_HUNKS__/$covered_hunks}"
        html="${html//__COVERAGE_FILE_CODE__/$code}"

        html_report+="$html"
    fi

    local report_line
    report_line="$(
        printf '%s %b(%s/%s)\t%b%3s%%%b' "$filename_short" \
            "$__BGEN_TEST_COL_TRIVIAL" "$covered_lines_count" \
            "$total_lines_count" "$coverage_color" "$percent" "$__BGEN_TEST_COL_RESET"
    )"

    coverage_report+=("$report_line")
}

# print final coverage report
__bgen_test_make_coverage_report() {
    shopt -u extglob

    local html_report=""
    local coverage_report=()

    local files_stack=("UNKNOWN_FILE")
    local line_nrs_stack=(0)
    local offsets_stack=(0)

    local covered_lines_stack=(0)
    local total_lines_stack=(0)

    local total_covered=0
    local total_lines=0

    local covered_hunks=()
    local covered_hunk_count_stack=(0)
    local hunk_start_stack=("")
    local hunk_end_stack=("")

    local is_prev_line_covered_stack=(1)

    local line_nr=0
    while IFS= read -r line; do
        local line="${line#${line%%[![:space:]]*}}" # strip leading whitepsace if any
        line_nr=$((line_nr + 1))

        if [[ "$line" =~ ^\#[[:space:]]BGEN__BEGIN[[:space:]] ]]; then
            : "${line#*BGEN__BEGIN[[:space:]]}"
            local file="${_#${_%%[![:space:]]*}}"

            files_stack=("$file" "${files_stack[@]}")
            line_nrs_stack=("$line_nr" "${line_nrs_stack[@]}")
            offsets_stack=(0 "${offsets_stack[@]}")

            covered_lines_stack=(0 "${covered_lines_stack[@]}")
            total_lines_stack=(0 "${total_lines_stack[@]}")

            covered_hunk_count_stack=(0 "${covered_hunk_count_stack[@]}")
            hunk_start_stack=("" "${hunk_start_stack[@]}")
            hunk_end_stack=("" "${hunk_end_stack[@]}")

            is_prev_line_covered_stack=(1 "${is_prev_line_covered_stack[@]}")

            continue
        elif [[ "$line" =~ ^\#[[:space:]]BGEN__END[[:space:]] ]]; then
            if [[ "${hunk_start_stack[0]}" ]]; then
                if [[ "${hunk_start_stack[0]}" == "${hunk_end_stack[0]}" ]]; then
                    covered_hunks+=("${hunk_start_stack[0]}")
                else
                    covered_hunks+=("${hunk_start_stack[0]}-${hunk_end_stack[0]}")
                fi
                covered_hunk_count_stack[0]=$((covered_hunk_count_stack[0] + 1))
                hunk_start_stack[0]=""
                hunk_end_stack[0]=""
            fi

            local file_covered_hunks=("${covered_hunks[@]::${covered_hunk_count_stack[0]}}")
            __bgen_test_add_file_report "${files_stack[0]}" \
                "$(__bgen_test_join_by "," "${file_covered_hunks[@]}")" \
                "${covered_lines_stack[0]}" "${total_lines_stack[0]}"

            local file_start="${line_nrs_stack[0]}"
            local file_size=$((line_nr - file_start))

            files_stack=("${files_stack[@]:1}")
            line_nrs_stack=("${line_nrs_stack[@]:1}")
            offsets_stack=("${offsets_stack[@]:1}")
            offsets_stack[0]=$((offsets_stack[0] + file_size))

            total_covered=$((total_covered + covered_lines_stack[0]))
            total_lines=$((total_lines + total_lines_stack[0]))

            covered_lines_stack=("${covered_lines_stack[@]:1}")
            covered_lines_stack[0]=$((covered_lines_stack[0] + 1))

            total_lines_stack=("${total_lines_stack[@]:1}")
            total_lines_stack[0]=$((total_lines_stack[0] + 1))

            covered_hunks=("${covered_hunks[@]:${covered_hunk_count_stack[0]}}")
            covered_hunk_count_stack=("${covered_hunk_count_stack[@]:1}")
            hunk_start_stack=("${hunk_start_stack[@]:1}")
            hunk_end_stack=("${hunk_end_stack[@]:1}")

            if [[ "${hunk_start_stack[0]}" ]]; then
                hunk_end_stack[0]=$((hunk_end_stack[0] + 1))
            else
                local line_nr_offset=$((line_nr - line_nrs_stack[0] - offsets_stack[0]))
                hunk_start_stack[0]="$line_nr_offset"
                hunk_end_stack[0]="$line_nr_offset"
            fi

            is_prev_line_covered_stack=("${is_prev_line_covered_stack[@]:1}")

            continue
        fi

        if ((${#files_stack[@]} > 1)); then
            if __bgen_is_line_covered "$line_nr" "$line"; then
                if [[ "${hunk_start_stack[0]}" ]]; then
                    hunk_end_stack[0]=$((hunk_end_stack[0] + 1))
                else
                    local line_nr_offset=$((line_nr - line_nrs_stack[0] - offsets_stack[0]))
                    hunk_start_stack[0]="$line_nr_offset"
                    hunk_end_stack[0]="$line_nr_offset"
                fi

                covered_lines_stack[0]=$((covered_lines_stack[0] + 1))

                is_prev_line_covered_stack[0]=1
            else
                if [[ "${hunk_start_stack[0]}" ]]; then
                    if [[ "${hunk_start_stack[0]}" == "${hunk_end_stack[0]}" ]]; then
                        covered_hunks+=("${hunk_start_stack[0]}")
                    else
                        covered_hunks+=("${hunk_start_stack[0]}-${hunk_end_stack[0]}")
                    fi

                    covered_hunk_count_stack[0]=$((covered_hunk_count_stack[0] + 1))
                    hunk_start_stack[0]=""
                    hunk_end_stack[0]=""
                fi

                is_prev_line_covered_stack[0]=0
            fi

            total_lines_stack[0]=$((total_lines_stack[0] + 1))
        fi
    done <<<"$BASH_EXECUTION_STRING"

    local coverage_percent
    coverage_percent=$((100 * total_covered / total_lines))
    if ((coverage_percent >= BGEN_COVERAGE_H_THRESHOLD)); then
        local coverage_color="$__BGEN_TEST_COL_SUCCESS"
        local coverage_rating="h"
    elif ((coverage_percent >= BGEN_COVERAGE_M_THRESHOLD)); then
        local coverage_color="$__BGEN_TEST_COL_WARNING"
        local coverage_rating="m"
    else
        local coverage_color="$__BGEN_TEST_COL_DANGER"
        local coverage_rating="l"
    fi

    # print file reports
    __bgen_test_format_columns "  " < <(
        printf '  \t%s\n' "${coverage_report[@]}"
        printf '\n  \tTOTAL COVERED %b(%s/%s)\t%b%3s%%%b\n' \
            "$__BGEN_TEST_COL_TRIVIAL" "$total_covered" "$total_lines" \
            "$coverage_color" "$coverage_percent" "$__BGEN_TEST_COL_RESET"
    )

    # save html report
    if [[ "$BGEN_HTML_REPORT_FILE" ]]; then
        local coverage_date
        coverage_date=$(date)

        local html_header="${__BGEN_COVERAGE_HTML_HEADER//__COVERAGE_DATE__/$coverage_date}"
        html_header="${html_header//__COVERAGE_TITLE__/Coverage report}"
        html_header="${html_header//__COVERAGE_TOTAL_COVERED__/$total_covered}"
        html_header="${html_header//__COVERAGE_TOTAL_LINES__/$total_lines}"
        html_header="${html_header//__COVERAGE_TOTAL_PERCENT__/$coverage_percent}"
        html_header="${html_header//__COVERAGE_TOTAL_RATING__/$coverage_rating}"

        local final_html_report="$html_header"
        final_html_report+="$html_report"
        final_html_report+="${__BGEN_COVERAGE_HTML_FOOTER}"
        echo "$final_html_report" >"$BGEN_HTML_REPORT_FILE"

        printf "\n    %bCoverage report file: %s%b\n" \
            "$__BGEN_TEST_COL_TITLE" "$BGEN_HTML_REPORT_FILE" "$__BGEN_TEST_COL_RESET"
    fi
}

# formats tab separated stdin entries as columns
__bgen_test_format_columns() {
    local separator="${1:-' '}"

    # parse manually
    local column_widths=()
    local lines=()
    local cell
    local cell_width

    # for each column find the longest cell
    while IFS= read -r line; do
        if [[ "$line" ]]; then
            local i=0
            while IFS= read -r cell; do
                cell_width="${#cell}"
                if ((cell_width > column_widths[i])); then
                    column_widths[$i]="$cell_width"
                fi
                i=$((i + 1))
            done <<<"${line//$'\t'/$'\n'}"
        fi

        lines+=("$line")
    done

    # generate a printf string such as it can print each cells at a given width
    local printf_query
    printf_query=$(printf -- "$separator%%-%ss" "${column_widths[@]}")
    for line in "${lines[@]-}"; do
        if [[ ! "$line" ]]; then
            echo
            continue
        fi

        cells=()
        while IFS= read -r cell; do
            cells+=("$cell")
        done <<<"${line//$'\t'/$'\n'}"
        # shellcheck disable=SC2059
        printf "${printf_query/$separator/}\n" "${cells[@]}"
    done
}

assert_status() {
    local status_code="$?"

    local expected_code="${1:-}"
    [[ "${2:-}" ]] && status_code="$2"

    [[ "$status_code" == "$expected_code" ]] && return 0

    echo "assert_status: expected $expected_code, got $status_code" >&2
    __bgen_assert_line="${BASH_LINENO[0]-}"
    return 1
}
export -f assert_status

assert_eq() {
    local left="$1"
    local right="$2"

    [[ "$left" == "$right" ]] && return 0

    (
        echo "assert_eq expected:"
        echo "$left"
        echo
        echo "assert_eq got:"
        echo "$right"
    ) >&2
    __bgen_assert_line="${BASH_LINENO[0]-}"
    return 1
}
export -f assert_eq

__bgen_test_run_single() {
    local test_func="$1"
    local stdout_file stderr_file

    stdout_file="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm '$stdout_file'" EXIT

    stderr_file="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm '$stderr_file'" EXIT

    env_file="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm '$env_file'" EXIT
    export __bgen_env_file="$env_file"

    # we don't want this subshell to cause the entire test to fail
    # so we relax bash options until we get a status code
    set +o errexit +o errtrace +o nounset +o pipefail
    (
        # Used to track coverage
        __bgen_test_covered_lines=()

        # set up some hooks to print original error lines and files
        trap '__bgen_test_debug_handler "$?" "$LINENO" "$BASH_COMMAND"' DEBUG
        trap 'trap - DEBUG; __bgen_test_error_handler "$LINENO"' ERR
        trap 'trap - DEBUG; __bgen_test_exit_handler "$LINENO"' EXIT

        # enable some bash options to allow error checking
        set -o errexit -o errtrace -o nounset -o pipefail -o functrace

        # call our test function
        "$test_func"

        # workaround to check if function didn't end prematurely
        # bash 3.2 exists with rc=0 on unset variables :/
        __func_finished_successfully=1
    ) >"$stdout_file" 2>"$stderr_file"
    local err=$?
    set -o errexit -o errtrace -o nounset -o pipefail

    # Merge covered lines into the global list
    local coverage_array
    coverage_array="$(cat "$env_file")"
    if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4))); then
        # going throug a variable becuase bash 3.2 doesn't allow escaping single quote in substitutions
        local substitution="'coverage_map+="
        # workaround bash <4.4 quoting the content of the variables in declare's output
        eval "$(eval "echo ${coverage_array/declare -a __bgen_test_covered_lines=\'/$substitution}")"
    else
        eval "${coverage_array/declare -a __bgen_test_covered_lines=/coverage_map+=}"
    fi

    # print a dot or F depending on test status
    if ((err)); then
        printf "%bF%b" "$__BGEN_TEST_COL_DANGER" "$__BGEN_TEST_COL_RESET"
        failed_tests_funcs+=("$test_func")
    else
        printf "%b.%b" "$__BGEN_TEST_COL_SUCCESS" "$__BGEN_TEST_COL_RESET"
    fi

    : "${BGEN_NO_CAPTURE:=}"
    if ! ((err || BGEN_NO_CAPTURE)); then
        return
    fi

    if [[ -s "$stdout_file" || -s "$stderr_file" ]]; then
        local report
        report=$(
            printf '\n%b----- %s ----- %b\n' "$__BGEN_TEST_COL_FILENAME" "$test_func" "$__BGEN_TEST_COL_RESET"

            if [[ -s "$stdout_file" ]]; then
                printf "%bstdout:%b\n" "$__BGEN_TEST_COL_TRIVIAL" "$__BGEN_TEST_COL_RESET"
                cat "$stdout_file"
                echo
            fi

            if [[ -s "$stderr_file" ]]; then
                printf "%bstderr:%b\n" "$__BGEN_TEST_COL_TRIVIAL" "$__BGEN_TEST_COL_RESET"
                cat "$stderr_file"
                echo
            fi
        )
        test_reports+=("$report")
    fi
}

if [[ "$NO_COLOR" ]]; then
    __BGEN_TEST_COL_DANGER=""
    __BGEN_TEST_COL_WARNING=""
    __BGEN_TEST_COL_SUCCESS=""
    __BGEN_TEST_COL_TITLE=""
    __BGEN_TEST_COL_FILENAME=""
    __BGEN_TEST_COL_RESET=""
else
    __BGEN_TEST_COL_DANGER="\e[31m"
    __BGEN_TEST_COL_WARNING="\e[33m"
    __BGEN_TEST_COL_SUCCESS="\e[32m"
    __BGEN_TEST_COL_TITLE="\e[36m"
    __BGEN_TEST_COL_FILENAME="\e[33m"
    __BGEN_TEST_COL_TRIVIAL="\e[90m"
    __BGEN_TEST_COL_RESET="\e[0m"
fi

__BGEN_COVERAGE_HTML_HEADER=$(
    cat <<-"EOF"
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>__COVERAGE_TITLE__</title>

    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/prism/1.23.0/themes/prism-coy.min.css"
        integrity="sha512-CKzEMG9cS0+lcH4wtn/UnxnmxkaTFrviChikDEk1MAWICCSN59sDWIF0Q5oDgdG9lxVrvbENSV1FtjLiBnMx7Q=="
        crossorigin="anonymous" />
    <link rel="stylesheet"
        href="https://cdnjs.cloudflare.com/ajax/libs/prism/1.23.0/plugins/line-numbers/prism-line-numbers.min.css"
        integrity="sha512-cbQXwDFK7lj2Fqfkuxbo5iD1dSbLlJGXGpfTDqbggqjHJeyzx88I3rfwjS38WJag/ihH7lzuGlGHpDBymLirZQ=="
        crossorigin="anonymous" />
    <link rel="stylesheet"
        href="https://cdnjs.cloudflare.com/ajax/libs/prism/1.23.0/plugins/line-highlight/prism-line-highlight.min.css"
        integrity="sha512-nXlJLUeqPMp1Q3+Bd8Qds8tXeRVQscMscwysJm821C++9w6WtsFbJjPenZ8cQVMXyqSAismveQJc0C1splFDCA=="
        crossorigin="anonymous" />
    <style>
        body {
            font-family: monospace;
        }
        pre[class*=language-]:before, pre[class*=language-]:after {
            display: none;
            content: unset;
        }
        .coverage-file pre {
            margin-bottom: 1rem;
            font-size: 0.7rem;
        }
        .line-highlight {
            background: linear-gradient(to right,hsl(100deg 89% 63% / 12%) 70%,hsl(105deg 86% 63% / 22%));
        }
        .coverage-percent {
            color: white;
            padding: 0 0.1rem;
            display: inline-block;
            text-align: center;
            min-width: 2.2rem;
        }
        .coverage-rating-h .coverage-percent {
            background-color: green;
        }
        .coverage-rating-m .coverage-percent {
            background-color: orange;
        }
        .coverage-rating-l .coverage-percent {
            background-color: red;
        }
    </style>
</head>
<body>
<div class="coverage-header coverage-rating-__COVERAGE_TOTAL_RATING__">
    <div class="stats">
        <span class="coverage-percent">__COVERAGE_TOTAL_PERCENT__%</span>
        Total (__COVERAGE_TOTAL_COVERED__/__COVERAGE_TOTAL_LINES__)
    </div>
    <div class="date">
        Date: __COVERAGE_DATE__
        <a href="#" class="collapse-all">Collapse All</a>
        <a href="#" class="expand-all">Expand All</a>
    </div>
    <hr/>
</div>
EOF
)

__BGEN_COVERAGE_HTML_FILE=$(
    cat <<-"EOF"
<details class="coverage-file coverage-rating-__COVERAGE_FILE_RATING__" id="__COVERAGE_FILE_ID__" open>
    <summary class="coverage-file-title">
        <span class="coverage-percent">__COVERAGE_FILE_PERCENT__%</span>
        <span class="coverage-file-name">__COVERAGE_FILE_NAME__</span>
        <span class="coverage-covered-lines">(<span
                class="covered"
            >__COVERAGE_FILE_COVERED__</span>/<span
                class="total"
            >__COVERAGE_FILE_LINES__</span>)<span>
    </summary>
    <pre
        class="line-numbers" id="pre-__COVERAGE_FILE_ID__" data-line="__COVERAGE_FILE_HUNKS__"
    ><code class="language-bash">__COVERAGE_FILE_CODE__</code></pre>
</details>
EOF
)

__BGEN_COVERAGE_HTML_FOOTER=$(
    cat <<-"EOF"
<script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.23.0/prism.min.js"
    integrity="sha512-YBk7HhgDZvBxmtOfUdvX0z8IH2d10Hp3aEygaMNhtF8fSOvBZ16D/1bXZTJV6ndk/L/DlXxYStP8jrF77v2MIg=="
    crossorigin="anonymous"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.23.0/components/prism-bash.min.js"
    integrity="sha512-JvRd44DHaJAv/o3wxi/dxhz2TO/jwwX8V5/LTr3gj6QMQ6qNNGXk/psoingLDuc5yZmccOq7XhpVaelIZE4tsQ=="
    crossorigin="anonymous"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.23.0/plugins/line-numbers/prism-line-numbers.min.js"
    integrity="sha512-br8H6OngKoLht57WKRU5jz3Vr0vF+Tw4G6yhNN2F3dSDheq4JiaasROPJB1wy7PxPk7kV/+5AIbmoZLxxx7Zow=="
    crossorigin="anonymous"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.23.0/plugins/line-highlight/prism-line-highlight.min.js"
    integrity="sha512-MGMi0fbhnsk/a/9vCluWv3P4IOfHijjupSoVYEdke+QQyGBOAaXNXnwW6/IZSH7JLdknDf6FL6b57o+vnMg3Iw=="
    crossorigin="anonymous"></script>
<script>
var collapseBtn = document.querySelector('.collapse-all');
if (collapseBtn) {
    collapseBtn.addEventListener('click', function(e) {
        e.preventDefault();
        var elems = document.querySelectorAll('details[open]');
        for (var i = 0; i < elems.length; ++i) {
            elems[i].open = false;
        }
    })
}
var expandBtn = document.querySelector('.expand-all');
if (expandBtn) {
    expandBtn.addEventListener('click', function(e) {
        e.preventDefault();
        var elems = document.querySelectorAll('details');
        for (var i = 0; i < elems.length; ++i) {
            elems[i].open = true;
        }
    })
}
</script>
</body>
</html>
EOF
)

__bgen_test_entrypoint "$@"
