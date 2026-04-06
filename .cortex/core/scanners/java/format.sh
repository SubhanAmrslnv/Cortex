#!/usr/bin/env bash
# @version: 1.0.0
# Formats .java files using google-java-format (if available).
# Usage: format.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.java ]] && exit 0

command -v google-java-format &>/dev/null && google-java-format --replace "$file" 2>/dev/null
