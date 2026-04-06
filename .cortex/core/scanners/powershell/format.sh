#!/usr/bin/env bash
# @version: 1.0.0
# Formats .ps1 files using Invoke-Formatter via pwsh (if available).
# Usage: format.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.ps1 && $file != *.psm1 && $file != *.psd1 ]] && exit 0

command -v pwsh &>/dev/null && pwsh -Command "Invoke-Formatter -ScriptDefinition (Get-Content -Raw '$file') | Set-Content '$file'" 2>/dev/null
