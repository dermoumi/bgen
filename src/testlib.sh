#!/usr/bin/env bash

__test_failed=()
__test_report=()
__bgen_covered_lines=()

if [[ "$NO_COLOR" ]]; then
    __COL_DANGER=""
    __COL_SUCCESS=""
    __COL_TITLE=""
    __COL_FILENAME=""
    __COL_RESET=""
else
    __COL_DANGER="\e[31m"
    __COL_SUCCESS="\e[32m"
    __COL_TITLE="\e[36m"
    __COL_FILENAME="\e[33m"
    __COL_RESET="\e[0m"
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
        .coverage-file {
            margin-bottom: 2rem;
        }
        .line-highlight {
            background: linear-gradient(to right,hsl(100deg 89% 63% / 12%) 70%,hsl(105deg 86% 63% / 22%));
        }
    </style>
</head>
<body>
EOF
)

__BGEN_COVERAGE_HTML_FILE=$(
    cat <<-"EOF"
<div class="coverage-file">
    <p class="coverage-file-title">
        <span class="coverage-file-name">__COVERAGE_FILE_NAME__</span>
        <span class="coverage-covered-lines">
            (<span
                class="covered"
            >__COVERAGE_FILE_COVERED_LINES__</span>/<span
                class="total"
            >__COVERAGE_FILE_TOTAL_LINES__</span>)
        <span>
    </p>
    <pre
        class="line-numbers linkable-line-numbers" data-line="__COVERAGE_FILE_LINES__"
    ><code class="language-bash">__COVERAGE_FILE_CODE__</code></pre>
</div>
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
</body>
</html>
EOF
)

# shellcheck disable=SC2120
__get_source_line() {
    local bgen_line="$1"

    local line_file=("UNKNOWN_FILE")
    local line_nr=(0)
    local line_offset=(0)
    while IFS= read -r line; do
        local current_line_nr current_line_type
        current_line_nr="$(awk '{printf $1}' <<<"$line")"
        current_line_type="$(awk '{printf $2}' <<<"$line")"

        if ((current_line_nr > bgen_line)); then
            break
        fi

        # keep it as ifs, bash 3.2 seems to complain when i use a case here
        if [[ "$current_line_type" == "BGEN__BEGIN" ]]; then
            local file
            file="$(awk '{OFS=""; $1=""; $2=""; printf $0 }' <<<"$line")"
            line_file=("$file" "${line_file[@]}")
            line_nr=("$current_line_nr" "${line_nr[@]}")
            line_offset=(0 "${line_offset[@]}")
        elif [[ "$current_line_type" == "BGEN__END" ]]; then
            local file_start_line_nr="${line_nr[0]}"
            local file_lines=$((current_line_nr - file_start_line_nr))
            line_file=("${line_file[@]:1}")
            line_nr=("${line_nr[@]:1}")
            line_offset=("${line_offset[@]:1}")
            line_offset[0]=$((line_offset[0] + file_lines))
        fi
    done <<<"$__BGEN_LINEMAP__"

    echo "${line_file[0]/$PWD\//}:$((bgen_line - line_nr[0] - line_offset[0]))"
}
export -f __get_source_line

__handle_error() {
    local rc="$__bgen_current_rc"

    if ((BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4)) && [[ "${__bgen_assert_line:-}" ]]; then
        local line=$((__bgen_assert_line + 1))
    elif [[ "$__bgen_current_cmd" == "$__bgen_previous_cmd" ]]; then
        # if we have two successive return commands, use the previous one's line
        local line="$__bgen_previous_cmd_line"
    else
        local line="$__bgen_current_cmd_line"

        if ((BASH_VERSINFO[0] < 4)); then
            line=$((line + 1))
        fi
    fi

    __error_handled=1

    local source_line
    source_line="$(__get_source_line "$line")"
    printf '%b%s (rc=%s)%b\n' "$__COL_DANGER" "$source_line" "$rc" "$__COL_RESET" >&2

    exit "$rc"
}
export -f __handle_error

__handle_exit() {
    local rc="$__bgen_current_rc"

    # save coverage file
    declare -p __bgen_test_covered_lines >"$__bgen_env_file"

    if [[ "${__error_handled:-}" ]]; then
        exit "$rc"
    fi

    local line="$__bgen_previous_cmd_line"

    # workaround for bash <4.0 returning 0 on nounset errors
    if [[ "$rc" == 0 ]]; then
        [[ "${__func_finished_successfully:-}" ]] && exit 0

        # this is the same code bash returns on version 4+ in these cases
        rc=127

        if [[ "${__bgen_previous_cmd_line:-}" ]]; then
            line=$((__bgen_previous_cmd_line))
        fi
    elif [[ "${__bgen_previous_cmd_line:-}" ]]; then
        line="$__bgen_previous_cmd_line"
    fi

    local source_line
    source_line="$(__get_source_line "$line")"
    printf '%b%s (rc=%s)%b\n' "$__COL_DANGER" "$source_line" "$rc" "$__COL_RESET" >&2

    exit "$rc"
}
export -f __handle_exit

__handle_debug() {
    local rc="$1"
    local line="$2"
    local cmd="$3"

    if ((BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 1))); then
        line=$((line + 1))
    fi

    if ((__bgen_previous_rc == 0)); then
        __bgen_previous_rc="$__bgen_current_rc"
        __bgen_previous_cmd="$__bgen_current_cmd"
        __bgen_previous_cmd_line="$__bgen_current_cmd_line"
    fi

    __bgen_current_rc="$rc"
    __bgen_current_cmd="$cmd"
    __bgen_current_cmd_line="$line"

    __bgen_test_covered_lines[$line]=1
}
export -f __handle_debug

__bgen_join_by() {
    if (($# <= 1)); then
        return 0
    fi

    local delimiter="$1"
    local first="$2"
    shift 2

    printf %s "$first" "${@/#/$delimiter}"
}

__bgen_is_line_covered() {
    local nr="$1"
    local line="$2"

    if [[ "${__bgen_covered_lines[$nr]-}" ]]; then
        return 0
    fi

    if [[ "$line" =~ ^[[:space:]]*[\(\)\{\}]?[[:space:]]*$ ]]; then
        ((last_line_is_covered))
        return
    fi

    if [[ "$line" =~ ^[[:space:]]*\# ]]; then
        return 0
    fi

    return 1
}

__bgen_add_file_coverage() {
    local filename="$1"
    local covered_hunks="$2"
    local covered_lines_count="$3"
    local total_lines_count="$4"

    local code
    code="$(cat "$filename")"
    code="${code//</&lt;}"
    code="${code//>/&gt;}"

    local html
    html="${__BGEN_COVERAGE_HTML_FILE/__COVERAGE_FILE_NAME__/${filename/$PWD\//}}"
    html="${html/__COVERAGE_FILE_COVERED_LINES__/$covered_lines_count}"
    html="${html/__COVERAGE_FILE_TOTAL_LINES__/$total_lines_count}"
    html="${html/__COVERAGE_FILE_LINES__/$covered_hunks}"
    html="${html/__COVERAGE_FILE_CODE__/$code}"

    coverage_output+="$html"
}

__bgen_report_coverage() {
    shopt -s extglob

    local coverage_output="${__BGEN_COVERAGE_HTML_HEADER}"

    local line_file=("UNKNOWN_FILE")
    local line_nr=(0)
    local line_offset=(0)

    local covered_file_lines=(0)
    local total_file_lines=(0)

    local total_covered=0
    local total_lines=0

    local covered_hunks=()
    local covered_hunks_count=(0)
    local hunk_start=("")
    local hunk_end=("")

    local last_line_is_covered=0

    echo
    local current_line_nr=0
    while IFS= read -r line; do
        current_line_nr=$((current_line_nr + 1))

        if [[ "$line" =~ ^[[:space:]]*\#[[:space:]]BGEN__BEGIN[[:space:]] ]]; then
            local file="${line/*([[:space:]])\#[[:space:]]BGEN__BEGIN+([[:space:]])/}"
            line_file=("$file" "${line_file[@]}")
            line_nr=("$current_line_nr" "${line_nr[@]}")
            line_offset=(0 "${line_offset[@]}")

            covered_file_lines=(0 "${covered_file_lines[@]}")
            total_file_lines=(0 "${total_file_lines[@]}")

            covered_hunks_count=(0 "${covered_hunks_count[@]}")
            hunk_start=("" "${hunk_start[@]}")
            hunk_end=("" "${hunk_end[@]}")

            continue
        elif [[ "$line" =~ ^[[:space:]]*\#[[:space:]]BGEN__END[[:space:]] ]]; then
            if [[ "${hunk_start[0]}" ]]; then
                if [[ "${hunk_start[0]}" == "${hunk_end[0]}" ]]; then
                    covered_hunks+=("${hunk_start[0]}")
                else
                    covered_hunks+=("${hunk_start[0]}-${hunk_end[0]}")
                fi
                covered_hunks_count[0]=$((covered_hunks_count[0] + 1))
                hunk_start[0]=""
                hunk_end[0]=""
            fi

            local file_covered_hunks=("${covered_hunks[@]::${covered_hunks_count[0]}}")
            __bgen_add_file_coverage "${line_file[0]}" "$(__bgen_join_by "," "${file_covered_hunks[@]}")" \
                "${covered_file_lines[0]}" "${total_file_lines[0]}"

            local file_start="${line_nr[0]}"
            local file_size=$((current_line_nr - file_start))

            line_file=("${line_file[@]:1}")
            line_nr=("${line_nr[@]:1}")
            line_offset=("${line_offset[@]:1}")
            line_offset[0]=$((line_offset[0] + file_size))

            total_covered=$((total_covered + covered_file_lines[0]))
            total_lines=$((total_lines + total_file_lines[0]))

            covered_file_lines=("${covered_file_lines[@]:1}")
            covered_file_lines[0]=$((covered_file_lines[0] + 1))

            total_file_lines=("${total_file_lines[@]:1}")
            total_file_lines[0]=$((total_file_lines[0] + 1))

            covered_hunks=("${covered_hunks[@]:${covered_hunks_count[0]}}")
            covered_hunks_count=("${covered_hunks_count[@]:1}")
            hunk_start=("${hunk_start[@]:1}")
            hunk_end=("${hunk_end[@]:1}")

            if [[ "${hunk_start[0]}" ]]; then
                hunk_end[0]=$((hunk_end[0] + 1))
            else
                local line_nr_offset=$((current_line_nr - line_nr[0] - line_offset[0]))
                hunk_start[0]="$line_nr_offset"
                hunk_end[0]="$line_nr_offset"
            fi

            last_line_is_covered=1
            continue
        fi

        if ((${#line_file[@]} > 1)); then
            if __bgen_is_line_covered "$current_line_nr" "$line"; then
                if [[ "${hunk_start[0]}" ]]; then
                    hunk_end[0]=$((hunk_end[0] + 1))
                else
                    local line_nr_offset=$((current_line_nr - line_nr[0] - line_offset[0]))
                    hunk_start[0]="$line_nr_offset"
                    hunk_end[0]="$line_nr_offset"
                fi

                covered_file_lines[0]=$((covered_file_lines[0] + 1))

                last_line_is_covered=1
            else
                if [[ "${hunk_start[0]}" ]]; then
                    if [[ "${hunk_start[0]}" == "${hunk_end[0]}" ]]; then
                        covered_hunks+=("${hunk_start[0]}")
                    else
                        covered_hunks+=("${hunk_start[0]}-${hunk_end[0]}")
                    fi

                    covered_hunks_count[0]=$((covered_hunks_count[0] + 1))
                    hunk_start[0]=""
                    hunk_end[0]=""
                fi

                last_line_is_covered=0
            fi

            total_file_lines[0]=$((total_file_lines[0] + 1))

            # printf '%s %s:\t%s\e[30m (%s)\e[0m\n' \
            #     "${last_line_is_covered/0/-}" "$current_line_nr" "$line" "${hunk_start[0]-}-${hunk_end[0]-}" >&2
        fi
    done <<<"$BASH_EXECUTION_STRING"

    coverage_output+="${__BGEN_COVERAGE_HTML_FOOTER}"
    echo "$coverage_output" >"coverage.html"

    echo "covered: $total_covered/$total_lines"
    echo
    echo "totol lines $current_line_nr"
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

__run_test() {
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
        trap '__handle_debug "$?" "$LINENO" "$BASH_COMMAND"' DEBUG
        trap 'trap - DEBUG; __handle_error "$LINENO"' ERR
        trap 'trap - DEBUG; __handle_exit "$LINENO"' EXIT

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
    eval "${coverage_array/declare -a __bgen_test_covered_lines=/__bgen_covered_lines+=}"

    # print a dot or F depending on test status
    if ((err)); then
        printf "%bF%b" "$__COL_DANGER" "$__COL_RESET"
        __test_failed+=("$test_func")
    else
        printf "%b.%b" "$__COL_SUCCESS" "$__COL_RESET"
    fi

    : "${BGEN_NO_CAPTURE:=}"
    if ! ((err || BGEN_NO_CAPTURE)); then
        return
    fi

    if [[ -s "$stdout_file" || -s "$stderr_file" ]]; then
        local report
        report=$(
            printf '\n%b----- %s ----- %b\n' "$__COL_FILENAME" "$test_func" "$__COL_RESET"

            if [[ -s "$stdout_file" ]]; then
                printf "%bstdout:%b\n" "$__COL_TITLE" "$__COL_RESET"
                cat "$stdout_file"
                echo
            fi

            if [[ -s "$stderr_file" ]]; then
                printf "%bstderr:%b\n" "$__COL_TITLE" "$__COL_RESET"
                cat "$stderr_file"
                echo
            fi
        )
        __test_report+=("$report")
    fi
}

# look over test functions
for __test_func in "${__BGEN_TEST_FUNCS__[@]}"; do
    __run_test "$__test_func"
done
echo

if (("${#__test_failed[@]}")); then
    printf "\n%bFailed tests:%b\n" "$__COL_TITLE" "$__COL_RESET"
    for test_func in "${__test_failed[@]}"; do
        echo "    $test_func"
    done
fi

# report on coverage if requested
BGEN_COVERAGE=1
if ((BGEN_COVERAGE)); then
    __bgen_report_coverage
fi

if (("${#__test_report[@]}")); then
    for test_report in "${__test_report[@]}"; do
        echo "$test_report"
    done
fi

# exit with error if any test failed
if (("${#__test_failed[@]}")); then
    exit 1
fi
