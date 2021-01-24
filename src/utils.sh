#!/usr/bin/env bash

bail() {
    local err_message="$1"
    local err_code="${2:-1}"

    echo "$err_message" >&2
    exit "$err_code"
}

trim_str() {
    : "${1#"${1%%[![:space:]]*}"}"
    echo "${_%"${_##*[![:space:]]}"}"
}
