#!/bin/bash

F="$1"

[[ -f "${F}" ]] || { echo "Output file not found: ${F}. Aborting."; exit 1; }

[[ $(grep -A1 "getBacktrace():" "${F}" | grep -v '^$' | wc -l | tr -d '[:space:]') == 1 ]] || { echo "Check failed."; exit 1; }

rm -f "${F}"

