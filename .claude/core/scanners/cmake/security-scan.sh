#!/usr/bin/env bash
# @version: 1.0.0
# Scans .cmake files for hardcoded secrets, insecure HTTP URLs,
# and execute_process() with potential user input patterns.
# Usage: security-scan.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.cmake && $(basename "$file") != CMakeLists.txt ]] && exit 0

if grep -qiE '(api_key|token|secret|password)\s*[=:]\s*[A-Za-z0-9+/]{8,}' "$file"; then
  echo "[WARNING] possible hardcoded secret in $file — use CMake cache variables or env vars"
fi

if grep -qiE 'http://[a-zA-Z]' "$file"; then
  echo "[WARNING] insecure http:// URL in $file — use https://"
fi

if grep -qiE 'execute_process\s*\(.*\$\{[A-Z_]+\}' "$file"; then
  echo "[WARNING] execute_process() with variable input in $file — verify input is sanitized"
fi

exit 0
