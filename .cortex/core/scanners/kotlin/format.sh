#!/usr/bin/env bash
# @version: 1.0.0
# Formats .kt/.kts files using ktlint (if available).
# Usage: format.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.kt && $file != *.kts ]] && exit 0

command -v ktlint &>/dev/null && ktlint --format "$file" 2>/dev/null
