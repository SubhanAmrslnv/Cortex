#!/usr/bin/env bash
# @version: 1.0.0
# Formats .rb files using rubocop --auto-correct (if available).
# Usage: format.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.rb ]] && exit 0

command -v rubocop &>/dev/null && rubocop --auto-correct "$file" 2>/dev/null

exit 0
