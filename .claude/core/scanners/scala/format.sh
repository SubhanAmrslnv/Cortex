#!/usr/bin/env bash
# @version: 1.0.0
# Formats .scala files using scalafmt (if available).
# Usage: format.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.scala && $file != *.sc ]] && exit 0

command -v scalafmt &>/dev/null && scalafmt "$file" 2>/dev/null

exit 0
