#!/usr/bin/env bash
# @version: 1.0.0
# Formats .php files using php-cs-fixer (if available).
# Usage: format.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.php ]] && exit 0

command -v php-cs-fixer &>/dev/null && php-cs-fixer fix "$file" 2>/dev/null
