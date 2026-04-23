#!/usr/bin/env bash
# @version: 1.0.0
# Scans .r/.R files for hardcoded secrets, system(), insecure HTTP,
# eval(parse()) patterns, and source() with remote URLs.
# Usage: security-scan.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.r && $file != *.R ]] && exit 0

if grep -qiE '(api_key|token|secret|password)\s*=\s*["'"'"'][A-Za-z0-9+/]{8,}' "$file"; then
  echo "[WARNING] possible hardcoded secret in $file — review before committing"
fi

if grep -qiE '\bsystem\s*\(' "$file"; then
  echo "[WARNING] system() in $file — command injection risk if input is not sanitized"
fi

if grep -qiE 'http://[a-zA-Z]' "$file"; then
  echo "[WARNING] insecure http:// URL in $file — use https://"
fi

if grep -qiE '\beval\s*\(\s*parse\s*\(' "$file"; then
  echo "[WARNING] eval(parse()) in $file — code injection risk"
fi

if grep -qiE '\bsource\s*\(\s*["'"'"']http://' "$file"; then
  echo "[WARNING] source() with http:// URL in $file — remote code execution risk, use https://"
fi

exit 0
