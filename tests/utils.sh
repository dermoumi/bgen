#!/bin/bash

bgen:import ../src/utils.sh

test_bail_prints_message_and_exits() {
    local output
    output=$(
        assert_exits_with_code 42 \
            bail "this is a test message" 42 \
            2>&1
    )
    assert_eq "$output" "this is a test message"
}

test_trim_str_removes_leading_and_trailing_spaces() {
    local output
    output=$(trim_str "        hello    world       ")

    assert_eq "$output" "hello    world"
}

test_debug_subshells() {
    # trap -p DEBUG RETURN EXIT ERR >&2

    local array_decl=(
        "elem1"
        "elem2"
        "elem3"
    )

    # standalone subshell
    (
        test test
        if true; then
            true
        fi
        echo "array" "${array_decl[2]}" >&2
        if true; then
            true
        fi
        # trap -p DEBUG RETURN EXIT ERR >&2
        return
    )

    read -rd "" var <<-"MYDOC" || :
weeeeee

echo '
hello world
cave johnson here
'"
assdfa
"
MYDOC

    echo "$var"

    echo '
        hello world
        cave johnson here
    a' "b
        assdfa
    "

    local output
    output=$(
        for i in {0..2}; do
            true "$i"
        done
        # test comment
        : 42 bail "this is a test message" 42 2>&1
    )

    local output
    output=$(
        for i in {0..2}; do
            true "$i"
        done
        : 42 \
            bail "this is a test message" 42 \
            2>&1
    )

    local output
    output=$(
        for i in {0..2}; do
            true "$i"
        done
        assert_exits_with_code 42 bail "this is a test message" 42 2>&1
        return
        echo henlo
    )

    local output
    output=$(
        for i in {0..2}; do
            true "$i"
        done
        assert_exits_with_code 42 \
            bail "this is a test message" 42 \
            2>&1
        return
        echo henlo
    )
    sadfsdas
    true
    assert_eq "$output" "this is a test message"
}
