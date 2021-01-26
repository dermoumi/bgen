#!/usr/bin/env bash

bgen:import src/lib/asserts.sh

__bgen_test_entrypoint() {
    local failed_tests_funcs=()
    local test_reports=()

    local coverage_map=()
    local trails_map=()

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

    # loop over test functions
    printf "%bRunning tests...%b\n" "$__BGEN_TEST_COL_TITLE" "$__BGEN_TEST_COL_RESET"
    local passed_test_count=0
    local total_test_count=0
    if declare -p __BGEN_TEST_FUNCS__ >/dev/null 2>&1; then
        # bgen test created a variable with specific tests to run
        for test_func in "${__BGEN_TEST_FUNCS__[@]}"; do
            __bgen_test_run_single "$test_func"
            total_test_count=$((total_test_count + 1))
        done
    else
        # no specific tests to run, find and run all tests that start with test_xxxx
        while IFS= read -r line; do
            if [[ "$line" == "declare -f test_"[[:alnum:]]* ]]; then
                local test_func="${line#${line%%test_*}}"
                __bgen_test_run_single "$test_func"
                total_test_count=$((total_test_count + 1))
            fi
        done < <(declare -F)
    fi

    if ((total_test_count == 0)); then
        echo "    No tests to run :("
    else
        # return to line after the dots
        echo
    fi

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
    : "${BGEN_COVERAGE:=0}"
    : "${BGEN_HTML_REPORT_FILE:=}"
    : "${BGEN_COVERAGE_M_THRESHOLD:=60}"
    : "${BGEN_COVERAGE_H_THRESHOLD:=85}"
    if ((BGEN_COVERAGE)); then
        printf "\n%bCoverage:%b\n" "$__BGEN_TEST_COL_TITLE" "$__BGEN_TEST_COL_RESET"
        __bgen_test_make_coverage_report
    fi

    if ((total_test_count > 0)); then
        local n_tests
        if ((total_test_count == 1)); then
            n_tests="1 test"
        else
            n_tests=$(printf '%s tests' "$total_test_count")
        fi

        # exit with error if any test failed
        if ((${#failed_tests_funcs[@]})); then
            printf '\n%b%s/%s passed successfully%b\n' \
                "$__BGEN_TEST_COL_DANGER" "$passed_test_count" "$n_tests" "$__BGEN_TEST_COL_RESET"
            exit 1
        else
            printf '\n%b%s passed successfully %s%b\n' \
                "$__BGEN_TEST_COL_SUCCESS" "$n_tests" "☆*･゜ﾟ･*(^O^)/*･゜ﾟ･*☆" "$__BGEN_TEST_COL_RESET"
        fi
    fi
}

# requires 2 variables: source_file and source_line_nr to be declared
__bgen_test_get_source_line() {
    local bgen_line=$1

    # stacks to keep track of...
    local files_stack=("UNKNOWN_FILE") # which file we're currently processing
    local line_nrs_stack=(0)           # the start line number of the file
    local offsets_stack=(0)            # how much lines should we offset from this file's linecount

    while IFS= read -r line; do
        # parse the line number
        local line=${line#${line%%[![:space:]]*}} # strip leading whitespace if any
        local line_nr=${line%%[[:space:]]*}       # strip everything from the first space

        if ((line_nr > bgen_line)); then
            break
        fi

        # bash 3.2 seems to complain when i use case .. in .. esac here
        if [[ "$line" =~ ^[[:digit:]]+[[:space:]]+BGEN__BEGIN[[:space:]]+ ]]; then
            : "${line#*BGEN__BEGIN[[:space:]]}"
            local file=${_#${_%%[![:space:]]*}}

            # add values related to this file to the new stack
            files_stack=("$file" "${files_stack[@]}")
            line_nrs_stack=("$line_nr" "${line_nrs_stack[@]}")
            offsets_stack=(0 "${offsets_stack[@]}")
        elif [[ "$line" =~ ^[[:digit:]]+[[:space:]]+BGEN__END[^[:alnum:]]+ ]]; then
            local file_start_line_nr=${line_nrs_stack[0]}
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
    local rc=$__bgen_test_current_rc

    # get error line number
    if [[ "${__bgen_assert_line:-}" ]]; then
        # bash versions <=4.3 only call the handler AFTER the returning function was left
        # the workaround here is to have assert functions to keep track of the line they left at instead
        local line_nr=$__bgen_assert_line

        # once again seems bash versions <=5.0 totally ignore the shebang's line
        if ((BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 1))); then
            line_nr=$((line_nr + 1))
        fi
    elif [[ "$__bgen_test_current_cmd" == "$__bgen_test_prev_cmd" ]]; then
        # if we have two successive return commands, use the previous one's line
        # workaround for when bash reports the return AFTER the returning to the parent function
        local line_nr=$__bgen_test_prev_line_nr
    else
        local line_nr=$__bgen_test_current_line_nr

        # bash 3.2 strangely uses the previous line for errors
        if ((BASH_VERSINFO[0] < 4)); then
            line_nr=$((line_nr + 1))
        fi
    fi

    # prevent the exit_handler from outputting anything since it's also executed
    __bgen_test_error_handled=1

    # print the original source file and line number for easy debugging
    local source_file=
    local source_line_nr=
    __bgen_test_get_source_line "$line_nr"
    printf '%b%s:%s (status: %s)%b\n' \
        "$__BGEN_TEST_COL_DANGER" "$source_file" "$source_line_nr" "$rc" "$__BGEN_TEST_COL_RESET" >&2

    # exit with the same return code we came with
    exit "$rc"
}
export -f __bgen_test_error_handler

# called when a test's subprocess exits
__bgen_test_exit_handler() {
    local rc=$__bgen_test_current_rc
    local subshell_mode=${2:-}

    # save coverage lines into a file, only way to communicate them to the parent process
    local env_file="$__bgen_env_dir/${BASH_SUBSHELL}_${RANDOM}_${RANDOM}.env"
    declare -p __bgen_test_covered_lines >>"$env_file"

    if [[ "${__bgen_test_subshell_line_count+x}" ]]; then
        local __bgen_test_subshell_trails=()
        __bgen_test_subshell_trails[$__bgen_test_subshell_line_end]=$((__bgen_test_subshell_line_count))
        declare -p __bgen_test_subshell_trails >>"$env_file"
    fi

    # if the error handler was already triggered, don't do anything else here
    if ((${__bgen_test_error_handled:-})) || ((subshell_mode)); then
        exit "$rc"
    fi

    # more reliable than LINENO
    local line_nr=$__bgen_test_prev_line_nr

    # get exit line number
    if ((rc == 0)); then
        # workaround for bash <4.0 returning 0 on nounset errors
        [[ "${__func_finished_successfully:-}" ]] && exit 0

        # this is the same code bash returns on version 4+ in these cases
        rc=127

        if [[ "${__bgen_test_prev_line_nr:-}" ]]; then
            line_nr=$((__bgen_test_prev_line_nr))
        fi
    elif [[ "${__bgen_test_prev_line_nr:-}" ]]; then
        line_nr=$__bgen_test_prev_line_nr
    fi

    # print the original source and line number for easy debugging
    local source_file=
    local source_line_nr=
    __bgen_test_get_source_line "$line_nr"
    printf '%b%s:%s (status: %s)%b\n' \
        "$__BGEN_TEST_COL_DANGER" "$source_file" "$source_line_nr" "$rc" "$__BGEN_TEST_COL_RESET" >&2

    # exit with the same return code we came with
    exit "$rc"
}
export -f __bgen_test_exit_handler

# called before each line, use to keep track of what lines
# were executed, and which are the last 2 commands and their rc and line numbers
# used for error reporting and code coverage
__bgen_test_debug_handler() {
    local rc=$1
    local line_nr=$2
    local cmd=$3
    local old_=$4

    # bash versions <5.1 don't seem to count the shebang in their line count
    if ((BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 1))); then
        line_nr=$((line_nr + 1))
    fi

    if [[ ! "${__bgen_previous_rc+x}" ]]; then
        export __bgen_previous_rc=0
        export __bgen_test_prev_cmd=
        export __bgen_test_prev_line_nr=1
    else
        export __bgen_previous_rc=$__bgen_test_current_rc
        if ((__bgen_previous_rc == 0)); then
            export __bgen_test_prev_cmd=$__bgen_test_current_cmd
            export __bgen_test_prev_line_nr=$__bgen_test_current_line_nr
        fi
    fi

    if [[ "${__bgen_test_main_subshell:-}" != "$BASH_SUBSHELL" ]]; then
        trap 'trap - DEBUG; __bgen_test_exit_handler "$LINENO" 1' EXIT

        # special case for multiline output subshells "$(\n ... )"
        if [[ "$__bgen_test_prev_cmd" == *$'\n'* ]]; then
            # calculate number of lines by removing all \n chars
            # and getting character difference from the original string
            : "${__bgen_test_prev_cmd//$'\n'/}"
            __bgen_test_subshell_line_count=$((${#__bgen_test_prev_cmd} - ${#_} + 1))

            __bgen_test_subshell_line_start=$((__bgen_test_prev_line_nr - __bgen_test_subshell_line_count + 1))
            __bgen_test_subshell_line_end=$((__bgen_test_prev_line_nr))
        fi
    fi

    export __bgen_test_current_rc=$rc
    export __bgen_test_current_cmd=$cmd

    if [[ "${__bgen_test_subshell_line_start+x}" ]] && ((\
    __bgen_test_subshell_line_start <= line_nr && line_nr >= __bgen_test_subshell_line_end)); then
        line_nr=$((line_nr - __bgen_test_subshell_line_count + 1))
        __bgen_test_covered_lines[$line_nr]=2 # run this in the second pass
    else
        line_nr="$line_nr"
        __bgen_test_covered_lines[$line_nr]=1
    fi
    export __bgen_test_current_line_nr=$line_nr

    if ((${BGEN_COVERAGE_DEBUG:-})); then
        local source_line_nr=
        local source_file=
        __bgen_test_get_source_line "$line_nr"
        printf -- '- %s %s %-4s %-4s %s %s\n' "$__bgen_test_main_subshell" "$BASH_SUBSHELL" \
            "$source_line_nr" "$line_nr" \
            "${__bgen_test_covered_lines[$line_nr]}" "$cmd" >&2
    fi

    # restore the original value of $_
    : "$old_"
}
export -f __bgen_test_debug_handler

# joins lines with a delimited
__bgen_test_join_by() {
    if (($# <= 1)); then
        return 0
    fi

    local delimiter=$1
    local first=$2
    shift 2

    printf '%s' "$first" "${@/#/$delimiter}"
}

# Returns true if a line is covered according to the coverage map
__bgen_is_line_covered() {
    local line_nr=$1
    local line=$2

    if ((coverage_map[line_nr])); then
        # line is in the coverage map
        return 0
    fi

    if [[ "$line" =~ ^[[:space:]]*$ ]]; then
        # line is empty space
        # covered only if the previous line also covered
        ((${is_prev_line_covered-}))
        return
    fi

    if [[ "$line" =~ ^[[:space:]]*\# ]]; then
        # line is a comment
        # covered only if the previous line also covered
        ((${is_prev_line_covered-}))
        return
    fi

    if [[ "$line" =~ ^[[:space:]]*(\(|\{|\)|\}|do|done|then|fi)[[:space:]]*$ ]]; then
        # line is a single curly brace or parenthesis
        # covered only if the previous line also covered
        ((${is_prev_line_covered-}))
        return
    fi

    # otherwise, line is not covered
    return 1
}

# prints coverage report for a given file
__bgen_test_add_file_report() {
    local filename=$1
    local covered_hunks=$2
    local covered_lines_count=$3
    local total_lines_count=$4

    local percent=$((100 * covered_lines_count / total_lines_count))
    local filename_short=${filename/$PWD\//}

    if ((percent >= BGEN_COVERAGE_H_THRESHOLD)); then
        local coverage_rating=h
        local coverage_color=$__BGEN_TEST_COL_SUCCESS
    elif ((percent >= BGEN_COVERAGE_M_THRESHOLD)); then
        local coverage_rating=m
        local coverage_color=$__BGEN_TEST_COL_WARNING
    else
        local coverage_rating=l
        local coverage_color=$__BGEN_TEST_COL_DANGER
    fi

    if [[ "$BGEN_HTML_REPORT_FILE" ]]; then
        local file_id=${filename_short//[![:alnum:]-_]/_}

        : "$(<"$filename")"
        : "${_//</&lt;}"
        local code=${_//>/&gt;}

        : "${__BGEN_COVERAGE_HTML_FILE//__COVERAGE_FILE_NAME__/$filename_short}"
        : "${_//__COVERAGE_FILE_ID__/$file_id}"
        : "${_//__COVERAGE_FILE_COVERED__/$covered_lines_count}"
        : "${_//__COVERAGE_FILE_LINES__/$total_lines_count}"
        : "${_//__COVERAGE_FILE_PERCENT__/$percent}"
        : "${_//__COVERAGE_FILE_RATING__/$coverage_rating}"
        : "${_//__COVERAGE_FILE_HUNKS__/$covered_hunks}"
        local html="${_//__COVERAGE_FILE_CODE__/$code}"

        html_report+=$html
    fi

    local report_line
    report_line="$(
        printf '%s %b(%s/%s)\t%b%3s%%%b' "$filename_short" \
            "$__BGEN_TEST_COL_TRIVIAL" "$covered_lines_count" \
            "$total_lines_count" "$coverage_color" "$percent" "$__BGEN_TEST_COL_RESET"
    )"

    coverage_report+=("$report_line")
}

__bgen_test_reverse_lines() {
    tac 2>/dev/null || tail -r 2>/dev/null || gtac
}

__bgen_test_count_lines() {
    if wc -l <<<"$1"; then
        return
    fi

    # calculate number of lines by removing all \n chars
    # and getting character difference from the original string
    : "${1//$'\n'/}"
    echo $((${#1} - ${#_} + 1))
}

# takes trailing lines (ending with backslash) into account
# in the length of trails map
__bgen_test_normalize_trails_map() {
    local current_trail=0
    local trail_start=0

    local line_nr
    line_nr=$(__bgen_test_count_lines "$BASH_EXECUTION_STRING")
    while IFS= read -r line; do
        if ((trails_map[line_nr])); then
            current_trail=$((line_nr))
            trail_start=$((line_nr - trails_map[line_nr]))
        elif ((trail_start != 0 && line_nr < trail_start)); then
            current_trail=0
            trail_start=0
            line_nr=$((line_nr - 1))
            continue
        fi

        if ((line_nr <= current_trail && line_nr > trail_start)) \
            && [[ "$line" =~ [\\]$ ]] && ! [[ "$line" =~ \\[\\]$ ]]; then
            # shift all lines in this trail by 1
            trail_start=$((trail_start - 1))
            for ((i = trail_start + 1; i <= line_nr; i++)); do
                if [[ "${coverage_map[$((i + 1))]+x}" ]]; then
                    coverage_map[$i]=$((coverage_map[i + 1]))
                else
                    unset "coverage_map[$i]"
                fi
            done
            unset "coverage_map[$line_nr]"
        fi

        line_nr=$((line_nr - 1))
    done < <(__bgen_test_reverse_lines <<<"$BASH_EXECUTION_STRING")
}

__bgen_test_extend_coverage_hunk() {
    if [[ "$hunk_start" ]]; then
        hunk_end=$((hunk_end + pending_lines + 1))
    else
        local line_nr_offset=$((line_nr - file_start - line_offset))
        hunk_start=$((line_nr_offset - pending_lines))
        hunk_end=$line_nr_offset
    fi
    file_covered_lines=$((file_covered_lines + pending_lines + 1))
}

__bgen_test_close_coverage_hunk() {
    if [[ "$hunk_start" ]]; then
        if [[ "$hunk_start" == "$hunk_end" ]]; then
            covered_hunks+=("$hunk_start")
        else
            covered_hunks+=("$hunk_start-$hunk_end")
        fi

        hunk_start=
        hunk_end=
    fi
}

__bgen_test_contains_str_start() {
    local str=$1
    if [[ "$str" != *[\'\"]* || "$str" =~ ^[[:space:]]*\# ]]; then
        return 1
    fi

    local i=$str_search_offset
    str_search_offset=0
    quote_type=
    while ((i < ${#str})); do
        local char=${str:$i:1}
        if [[ "$char" =~ [\'\"] ]] && ( ((i == 0)) || [[ "${str:$((i - 1)):1}" != \\ ]]); then
            if [[ ! "$quote_type" ]]; then
                quote_type=$char
            elif [[ "$char" == "$quote_type" ]]; then
                quote_type=
            fi
        fi
        i=$((i + 1))
    done

    [[ "$quote_type" ]]
}

__bgen_test_contains_str_end() {
    local str=$1
    local quote_type=$2

    if ! [[ "$quote_type" && "$str" == *$quote_type* ]]; then
        return 1
    fi

    : "${str%%[$quote_type]*}"
    str_search_offset=$((${#_} + 1))
}

__bgen_test_contains_heredoc_start() {
    local str=$1
    if [[ "$str" != *[^\<]\<\<[\-\"\_[:alnum:]]* || "$str" =~ ^[[:space:]]*\# ]]; then
        return 1
    fi

    : "${str##*[^<]<<}"
    : "${_#\-}"
    : "${_#\"}"
    : "${_%%\"*}"
    local token=$_
    if ! [[ "$token" =~ [_[:alpha:]][_[:alnum:]]* ]]; then
        return 1
    fi
    heredoc_token=$token
}

__bgen_test_contains_heredoc_end() {
    local str=$1
    local token=$2

    [[ "$token" && "$str" =~ ^[$'\t']*"$token"$ ]]
}

__bgen_test_contains_array_start() {
    local str=$1
    if ! [[ "$str" =~ [_[:alnum:]]\=\( ]] || [[ "$str" =~ ^[[:space:]]*\# ]]; then
        return 1
    fi

    local i=0
    local open=0
    local quote_type=
    while ((i < ${#str})); do
        if [[ "${str:$i:1}" =~ [\'\"] ]] && ( ((i == 0)) || [[ "${str:$((i - 1)):1}" != \\ ]]); then
            if [[ ! "$quote_type" ]]; then
                quote_type=${str:$i:1}
            elif [[ "${str:$i:1}" == "$quote_type" ]]; then
                quote_type=
            fi
        elif ((i > 2)) && [[ ! "$quote_type" ]]; then
            if [[ "${str:$((i - 1)):2}" == '=(' && "${str:$((i - 2)):1}" != \\ ]]; then
                open=1
            elif [[ "${str:$i:1}" == ')' && "${str:$((i - 1))}" != \\ ]]; then
                open=0
            fi
        fi
        i=$((i + 1))
    done

    ((open))
}

__bgen_test_contains_array_end() {
    [[ "$1" =~ ^[[:space:]]*\) ]]
}

# parses coverage map
__bgen_test_parse_coverage_map() {
    local current_file=${1:-}
    local file_start=$line_nr
    local line_offset=0

    local file_covered_lines=0

    local hunk_start=
    local hunk_end=

    local pending_lines=0 # lines that end with a backslash or $(
    local covered_hunks=()
    local is_prev_line_covered=1

    local in_string=
    local string_covered=0
    local str_search_offset=0

    local in_heredoc=
    local in_array_decl=

    while IFS= read -r line; do
        line_nr=$((line_nr + 1))

        : "${line%${line##*[![:space:]]}}"  # strip any trailing whitespace if any
        local line=${_#${_%%[![:space:]]*}} # strip leading whitepsace if any

        if ((${BGEN_COVERAGE_EXPERIMENTAL:-})); then
            if __bgen_test_contains_str_end "$line" "$in_string"; then
                in_string=
                if ((string_covered)); then
                    __bgen_test_extend_coverage_hunk
                    pending_lines=0
                    continue
                fi
                string_covered=0
            fi

            if __bgen_test_contains_heredoc_end "$line" "$in_heredoc"; then
                in_heredoc=
            fi

            if ((in_array_decl)) && __bgen_test_contains_array_end "$line"; then
                in_array_decl=
            fi

            if [[ "$in_string" || "$in_heredoc" || "$in_array_decl" ]]; then
                if ((coverage_map[line_nr])); then
                    __bgen_test_extend_coverage_hunk
                    is_prev_line_covered=1
                    pending_lines=0
                else
                    pending_lines=$((pending_lines + 1))
                fi
                continue
            fi

            local heredoc_token=
            if __bgen_test_contains_heredoc_start "$line"; then
                if ((coverage_map[line_nr])); then
                    __bgen_test_extend_coverage_hunk
                    is_prev_line_covered=1
                    pending_lines=0
                else
                    pending_lines=$((pending_lines + 1))
                fi
                in_heredoc=$heredoc_token
                continue
            fi

            local quote_type=
            if __bgen_test_contains_str_start "$line"; then
                if ((coverage_map[line_nr])); then
                    __bgen_test_extend_coverage_hunk
                    is_prev_line_covered=1
                    string_covered=1
                    pending_lines=0
                else
                    pending_lines=$((pending_lines + 1))
                fi
                in_string=$quote_type
                continue
            fi

            if __bgen_test_contains_array_start "$line"; then
                if ((coverage_map[line_nr])); then
                    __bgen_test_extend_coverage_hunk
                    is_prev_line_covered=1
                    pending_lines=0
                else
                    pending_lines=$((pending_lines + 1))
                fi
                in_array_decl=1
                continue
            fi

            # lines ending with $(
            if [[ "$line" =~ ([^\\]|^)\$\($ ]]; then
                if ((coverage_map[line_nr])); then
                    __bgen_test_extend_coverage_hunk
                    is_prev_line_covered=1
                    pending_lines=0
                else
                    pending_lines=$((pending_lines + 1))
                fi
                continue
            fi
        fi

        if [[ "$line" =~ ^\#[[:space:]]BGEN__END[[:space:]] ]]; then
            pending_lines=0
            __bgen_test_close_coverage_hunk

            local file_line_count=$((line_nr - file_start - line_offset - 1))

            __bgen_test_add_file_report "$current_file" \
                "$(__bgen_test_join_by , "${covered_hunks[@]}")" \
                "$file_covered_lines" "$file_line_count"

            total_covered=$((total_covered + file_covered_lines))
            total_lines=$((total_lines + file_line_count))

            return
        fi

        if [[ "$line" =~ ^\#[[:space:]]BGEN__BEGIN[[:space:]] ]]; then
            : "${line#*BGEN__BEGIN[[:space:]]}"
            local file=${_#${_%%[![:space:]]*}}

            local start_line_nr=$line_nr
            __bgen_test_parse_coverage_map "$file"
            line_offset=$((line_offset + line_nr - start_line_nr))

            __bgen_test_extend_coverage_hunk
            pending_lines=0
            continue
        fi

        # lines ending with backslash
        if [[ "$line" =~ ([^\\]|^)\\$ ]]; then
            pending_lines=$((pending_lines + 1))
            continue
        fi

        if [[ "$current_file" ]]; then
            if __bgen_is_line_covered "$line_nr" "$line"; then
                __bgen_test_extend_coverage_hunk
                is_prev_line_covered=1
            else
                __bgen_test_close_coverage_hunk
                is_prev_line_covered=0
            fi
        fi

        # reset the pending lines count
        pending_lines=0
    done
}

# print final coverage report
__bgen_test_make_coverage_report() {
    local html_report=
    local coverage_report=()

    local total_covered=0
    local total_lines=0

    local line_nr=0
    __bgen_test_normalize_trails_map
    __bgen_test_parse_coverage_map <<<"$BASH_EXECUTION_STRING"

    if ((total_lines == 0)); then
        echo "    Nothing to cover :/"
        return
    fi

    local coverage_percent
    coverage_percent=$((100 * total_covered / total_lines))
    if ((coverage_percent >= BGEN_COVERAGE_H_THRESHOLD)); then
        local coverage_color=$__BGEN_TEST_COL_SUCCESS
        local coverage_rating=h
    elif ((coverage_percent >= BGEN_COVERAGE_M_THRESHOLD)); then
        local coverage_color=$__BGEN_TEST_COL_WARNING
        local coverage_rating=m
    else
        local coverage_color=$__BGEN_TEST_COL_DANGER
        local coverage_rating=l
    fi

    # print file reports
    __bgen_test_format_columns < <(
        printf '  \t%s\n' "${coverage_report[@]}"
        printf '\n  \tTOTAL COVERED %b(%s/%s)\t%b%3s%%%b\n' \
            "$__BGEN_TEST_COL_TRIVIAL" "$total_covered" "$total_lines" \
            "$coverage_color" "$coverage_percent" "$__BGEN_TEST_COL_RESET"
    )

    # save html report
    if [[ "$BGEN_HTML_REPORT_FILE" ]]; then
        local coverage_date
        coverage_date=$(date)

        : "${__BGEN_COVERAGE_HTML_HEADER//__COVERAGE_DATE__/$coverage_date}"
        : "${_//__COVERAGE_TITLE__/Coverage report}"
        : "${_//__COVERAGE_TOTAL_COVERED__/$total_covered}"
        : "${_//__COVERAGE_TOTAL_LINES__/$total_lines}"
        : "${_//__COVERAGE_TOTAL_PERCENT__/$coverage_percent}"
        local html_header="${_//__COVERAGE_TOTAL_RATING__/$coverage_rating}"

        local final_html_report=$html_header
        final_html_report+=$html_report
        final_html_report+=$__BGEN_COVERAGE_HTML_FOOTER
        echo "$final_html_report" >"$BGEN_HTML_REPORT_FILE"

        printf "\n    %bCoverage report file: %s%b\n" \
            "$__BGEN_TEST_COL_TITLE" "$BGEN_HTML_REPORT_FILE" "$__BGEN_TEST_COL_RESET"
    fi
}

# formats tab separated stdin entries as columns
# shellcheck disable=SC2120
__bgen_test_format_columns() {
    local separator=${1:-  }

    if column -o "$separator" -s $'\t' -t -L 2>/dev/null; then
        return
    fi

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

__bgen_test_run_single() {
    local test_func=$1

    local stdout_file
    stdout_file=$(mktemp)
    # shellcheck disable=SC2064
    trap "rm '$stdout_file'" EXIT

    local stderr_file env_dir
    stderr_file=$(mktemp)
    # shellcheck disable=SC2064
    trap "rm '$stderr_file'" EXIT

    local env_dir
    env_dir=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "rm -rf '$env_dir'" EXIT
    export __bgen_env_dir="$env_dir"

    # we don't want this subshell to cause the entire test to fail
    # so we relax bash options until we get a status code
    set +o errexit +o errtrace +o nounset +o pipefail
    (
        # used to track sub-subshells
        export __bgen_test_main_subshell=$BASH_SUBSHELL

        # Used to track coverage
        __bgen_test_covered_lines=()

        # enable some bash options to allow error checking
        set -o errexit -o errtrace -o nounset -o pipefail -o functrace

        # set up some hooks to print original error lines and files
        trap '__bgen_test_debug_handler "$?" "$LINENO" "$BASH_COMMAND" "$_"' DEBUG
        trap 'trap - DEBUG; __bgen_test_error_handler "$LINENO"' ERR
        trap 'trap - DEBUG; __bgen_test_exit_handler "$LINENO"' EXIT

        # call our test function
        "$test_func"

        # workaround to check if function didn't end prematurely
        # bash 3.2 exists with rc=0 on unset variables :/
        __func_finished_successfully=1
    ) >"$stdout_file" 2>"$stderr_file"
    local err=$?
    set -o errexit -o errtrace -o nounset -o pipefail

    # Merge covered lines into the global list
    for env_file in "$env_dir"/*; do
        if [[ "$env_file" == "$env_dir/*" ]]; then
            break
        fi

        local env_arrays
        env_arrays=$(<"$env_file")
        if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4))); then
            # workaround bash <4.4 quoting the content of the variables in declare's output
            local intermediary_coverage_map=()
            local affect_intermediary_coverage_map="'intermediary_coverage_map+="
            local intermediary_trails_map=()
            local affect_intermediary_trails_map="'intermediary_trails_map+="
            local newline_sub="'"$'\n'"'"
            local newline=$'\n'

            # also these versions for somereason concat array elements instead of replacing them
            # so we unset existing values before setting new ones
            : "${env_arrays//declare -a __bgen_test_covered_lines=\'/$affect_intermediary_coverage_map}"
            : "${_//declare -a __bgen_test_subshell_trails=\'/$affect_intermediary_trails_map}"
            : "${_//$newline_sub/$newline}"
            eval "$(eval "echo $_")"
            for index in "${!intermediary_coverage_map[@]}"; do
                unset "coverage_map[$index]"
            done
            for index in "${!intermediary_trails_map[@]}"; do
                unset "trails_map[$index]"
            done

            local affect_coverage_map="'coverage_map+="
            local affect_trails_map="'trails_map+="
            : "${env_arrays//declare -a __bgen_test_covered_lines=\'/$affect_coverage_map}"
            : "${_//declare -a __bgen_test_subshell_trails=\'/$affect_trails_map}"
            : "${_//$newline_sub/$newline}"
            eval "$(eval "echo $_")"
        else
            : "${env_arrays//declare -a __bgen_test_covered_lines=/coverage_map+=}"
            : "${_//declare -a __bgen_test_subshell_trails=/trails_map+=}"
            eval "$_"
        fi
    done

    # print a dot or F depending on test status
    if ((err)); then
        printf "%bF%b" "$__BGEN_TEST_COL_DANGER" "$__BGEN_TEST_COL_RESET"
        failed_tests_funcs+=("$test_func")
    else
        passed_test_count=$((passed_test_count + 1))
        printf "%b.%b" "$__BGEN_TEST_COL_SUCCESS" "$__BGEN_TEST_COL_RESET"
    fi

    : "${BGEN_CAPTURE:=}"
    if ((err == 0 && BGEN_CAPTURE != 0)); then
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

read -rd "" __BGEN_COVERAGE_HTML_HEADER <<-"EOF" || :
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

read -rd "" __BGEN_COVERAGE_HTML_FILE <<-"EOF" || :
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

read -rd "" __BGEN_COVERAGE_HTML_FOOTER <<-"EOF" || :
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
(function() {
    function collapseAll() {
        var elems = document.querySelectorAll('details[open]');
        for (var i = 0; i < elems.length; ++i) {
            elems[i].open = false;
        }
    }
    function expandAll() {
        var elems = document.querySelectorAll('details');
        for (var i = 0; i < elems.length; ++i) {
            elems[i].open = true;
        }
    }

    var collapseBtn = document.querySelector('.collapse-all');
    if (collapseBtn) {
        collapseBtn.addEventListener('click', function(e) {
            e.preventDefault();
            collapseAll();
        })
    }

    var expandBtn = document.querySelector('.expand-all');
    if (expandBtn) {
        expandBtn.addEventListener('click', function(e) {
            e.preventDefault();
            expandAll();
        })
    }

    // collapsing using js because line highlighter doesn't work on collapsed details blocks
    setTimeout(collapseAll);
})();
</script>
</body>
</html>
EOF

__bgen_test_entrypoint "$@"
