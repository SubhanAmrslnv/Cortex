#!/usr/bin/env bash
# @version: 1.0.0
# Formats .dart files using dart format (if available).
# Usage: format.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.dart ]] && exit 0

command -v dart &>/dev/null && dart format "$file" 2>/dev/null
