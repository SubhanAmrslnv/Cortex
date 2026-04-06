#!/usr/bin/env bash
# @version: 1.0.0
# Formats .tf files using terraform fmt (if available).
# Usage: format.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.tf && $file != *.tfvars ]] && exit 0

command -v terraform &>/dev/null && terraform fmt "$file" 2>/dev/null

exit 0
