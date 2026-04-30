#!/usr/bin/env bash
# @version: 1.0.0
# Formats .sh/.bash files using shfmt (if available).
# Usage: format.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.sh && $file != *.bash ]] && exit 0

command -v shfmt &>/dev/null && shfmt -w "$file" 2>/dev/null

exit 0
