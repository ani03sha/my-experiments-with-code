#!/bin/bash

FILE=${1:-traces.ndjson}
N=${2:-5}

if [ ! -f "$FILE" ]; then
    echo "Error: $FILE not found"
    exit 1
fi

node trace_summary.js "$FILE" "$N"