#!/usr/bin/env bash
# @version: 1.0.0
# Formats .rs files using rustfmt (if available).
# Usage: format.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.rs ]] && exit 0

command -v rustfmt &>/dev/null && rustfmt "$file" 2>/dev/null

exit 0
