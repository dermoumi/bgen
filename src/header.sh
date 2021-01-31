#!/usr/bin/env bash

set -o errexit -o errtrace -o pipefail -o nounset

LOG_LEVEL="${LOG_LEVEL:-6}" # 7 = debug -> 0 = emergency
NO_COLOR="${NO_COLOR:-}"
