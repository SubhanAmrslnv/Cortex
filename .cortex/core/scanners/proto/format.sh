#!/usr/bin/env bash
# @version: 1.0.0
# Formats .proto files using buf format (if available).
# Usage: format.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.proto ]] && exit 0

command -v buf &>/dev/null && buf format -w "$file" 2>/dev/null
