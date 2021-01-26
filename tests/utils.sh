#!/bin/bash
bgen:import ../src/utils.sh

test_bail_prints_message_and_exits() {
    local output
    output=$(
        assert_exits_with_code 42 \
            bail "2this is a test message" 42 \
            2>&1
    )
    assert_eq "$output" "2this is a test message"
}

test_trim_str_removes_leading_and_trailing_spaces() {
    local output
    output=$(trim_str "        hello    world       ")

    assert_eq "$output" "hello    world"
}
