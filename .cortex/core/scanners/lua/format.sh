#!/usr/bin/env bash
# @version: 1.0.0
# Formats .lua files using stylua (if available).
# Usage: format.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.lua ]] && exit 0

command -v stylua &>/dev/null && stylua "$file" 2>/dev/null
/
exit 0
