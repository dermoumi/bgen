#!/bin/bash

bail() {
    local err_message="$1"
    local err_code="${2:-1}"

    echo "$err_message" >&2
    exit "$err_code"
}

trim_str() {
    echo "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}
