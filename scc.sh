#!/bin/bash

# File to store submodule paths
ignore_file=".ignore"

# Extract submodule paths from .gitmodules and write them to .ignore file
grep -E '^\s*path\s*=' .gitmodules | sed 's/^[[:space:]]*path[[:space:]]*=[[:space:]]*//' > "$ignore_file"

# Run scc (it will automatically use the .ignore file)
scc

rm $ignore_file