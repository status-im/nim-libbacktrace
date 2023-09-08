#!/bin/bash

F="$1"

[[ -f "${F}" ]] || { echo "Output file not found: ${F}. Aborting."; exit 1; }

# catering for the rare case Glibc has debugging symbols
[[ $(grep -Ev "libc-start.c|libc_start_call_main.h" "${F}" | grep -A1 "getBacktrace():" | grep -v '^$' | wc -l | tr -d '[:space:]') == 1 ]] || { echo "Check failed."; exit 1; }

rm -f "${F}"

