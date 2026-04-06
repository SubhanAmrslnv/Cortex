#!/usr/bin/env bash
# @version: 1.0.0
# Formats .go files using gofmt (if available), then goimports (if available).
# Usage: format.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.go ]] && exit 0

command -v gofmt &>/dev/null && gofmt -w "$file" 2>/dev/null
command -v goimports &>/dev/null && goimports -w "$file" 2>/dev/null
