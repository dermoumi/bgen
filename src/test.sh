#!/usr/bin/env bash

bgen:import build

test_project() {
    # TODO: Check for shfmt and jq

    export __BGEN_PIPE_SOURCE__="${__base__:-$0} test"
    eval "$(build_tests_to_stdout)"

    local jq_query='.Stmts[]
        | select(.Cmd.Type == "FuncDecl" and (.Cmd.Name.Value | test("^test_"; "i")))
        | .Cmd.Name.Value'

    local tests_dir
    read_project_meta

    if [[ ! -d "$tests_dir" ]]; then
        echo "tests directory '${tests_dir/$PWD\//}' does not exist" >&2
        return 1
    fi

    for test_file in "$tests_dir"/*; do
        [[ -f "$test_file" ]] || continue

        for func in $(shfmt -tojson <"$test_file" | jq -Mr "$jq_query"); do
            echo "${test_file/$tests_dir\//}::$func"
            "$func"
        done
    done
}
