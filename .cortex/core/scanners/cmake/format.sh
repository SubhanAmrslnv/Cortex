#!/usr/bin/env bash
# @version: 1.0.0
# Formats .cmake/CMakeLists.txt files using cmake-format (if available).
# Usage: format.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.cmake && $(basename "$file") != CMakeLists.txt ]] && exit 0

command -v cmake-format &>/dev/null && cmake-format -i "$file" 2>/dev/null

exit 0
