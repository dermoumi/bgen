#!/bin/bash
bgen:import ../src/utils.sh

test_bail_prints_message_and_exits() {
    local stderr="this is a test message"

    assert_exits_with --code 42 --stderr "$stderr" bail "this is a test message" 42
}

test_trim_str_removes_leading_and_trailing_spaces() {
    local stdout="hello    world"

    assert_exits_with --code 0 --stdout "$stdout" trim_str "        hello    world       "
}
