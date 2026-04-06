#!/usr/bin/env bash
# @version: 1.0.0
# Formats .r/.R files using styler via Rscript (if available).
# Usage: format.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.r && $file != *.R ]] && exit 0

command -v Rscript &>/dev/null && Rscript -e "styler::style_file('$file')" 2>/dev/null
