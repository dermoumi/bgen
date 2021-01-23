#!/usr/bin/env bash

test_asserts_correctly() {
    echo hi
    [[ "" ]] || exit 2
}

test_asserts_again() {
    echo test
    # return 4
    assert_status 2
}

not_a_test_func() {
    echo hahaha
}
