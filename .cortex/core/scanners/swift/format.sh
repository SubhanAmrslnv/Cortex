#!/usr/bin/env bash
# @version: 1.0.0
# Formats .swift files using swiftformat (if available).
# Usage: format.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.swift ]] && exit 0

command -v swiftformat &>/dev/null && swiftformat "$file" 2>/dev/null
