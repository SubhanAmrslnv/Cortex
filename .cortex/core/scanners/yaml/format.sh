#!/usr/bin/env bash
# @version: 1.0.0
# Formats .yaml/.yml files using prettier (if available).
# Usage: format.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.yaml && $file != *.yml ]] && exit 0

command -v prettier &>/dev/null && prettier --write "$file" 2>/dev/null
