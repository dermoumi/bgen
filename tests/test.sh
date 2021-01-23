#!/usr/bin/env bash

bgen:import _ignored_file2

test_testing_asserts_again() {
    assert_status 5
}

test_testing_asserts_correctly() {
    echo hm
    echo eh
    # commas
    echo weee $2
    exit 1
}

not_a_test_funca() {
    echo hahaha
}
