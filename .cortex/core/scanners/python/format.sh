#!/usr/bin/env bash
# @version: 1.0.0
# Formats .py files using black (if available), then isort (if available).
# Usage: format.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.py ]] && exit 0

command -v black &>/dev/null && black "$file" 2>/dev/null
command -v isort &>/dev/null && isort "$file" 2>/dev/null
