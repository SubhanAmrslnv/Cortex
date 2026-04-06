#!/usr/bin/env bash
# @version: 1.0.0
# Formats .sql files using sql-formatter (if available).
# Usage: format.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.sql && $file != *.psql && $file != *.pgsql ]] && exit 0

command -v sql-formatter &>/dev/null && sql-formatter --output "$file" "$file" 2>/dev/null

exit 0
