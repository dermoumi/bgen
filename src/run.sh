#!/bin/bash

bgen:import build.sh

run_project() {
    export __BGEN_PIPE_SOURCE__="$0"
    build_project_to_stdout | bash -s "$@"
}
