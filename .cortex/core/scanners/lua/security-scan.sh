#!/usr/bin/env bash
# @version: 1.0.0
# Scans .lua files for hardcoded secrets, loadstring(), dofile(),
# os.execute() with variables, and insecure HTTP URLs.
# Usage: security-scan.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.lua ]] && exit 0

if grep -qiE '(api_key|token|secret|password)\s*=\s*["'"'"'][A-Za-z0-9+/]{8,}' "$file"; then
  echo "[WARNING] possible hardcoded secret in $file — review before committing"
fi

if grep -qiE '\bloadstring\s*\(' "$file"; then
  echo "[WARNING] loadstring() in $file — code injection risk"
fi

if grep -qiE '\bdofile\s*\(' "$file"; then
  echo "[WARNING] dofile() in $file — arbitrary file execution risk"
fi

if grep -qiE '\bos\.execute\s*\(\s*[a-zA-Z_]' "$file"; then
  echo "[WARNING] os.execute() with variable in $file — command injection risk"
fi

if grep -qiE 'http://[a-zA-Z]' "$file"; then
  echo "[WARNING] insecure http:// URL in $file — use https://"
fi

exit 0
