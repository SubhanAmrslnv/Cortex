#!/usr/bin/env bash
# @version: 1.0.0
# Scans .rb files for hardcoded secrets, eval, backtick exec, system(),
# Open3 with user input, insecure HTTP, MD5, and SQL string interpolation.
# Usage: security-scan.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.rb ]] && exit 0

if grep -qiE '(api_key|token|secret|password)\s*=\s*["'"'"'][A-Za-z0-9+/]{8,}' "$file"; then
  echo "[WARNING] possible hardcoded secret in $file — review before committing"
fi

if grep -qiE '\beval\s*\(' "$file"; then
  echo "[WARNING] eval() in $file — code injection risk"
fi

if grep -qiE '`[^`]*\$\{?[a-zA-Z_][a-zA-Z0-9_]*\}?[^`]*`' "$file"; then
  echo "[WARNING] backtick execution with interpolation in $file — command injection risk"
fi

if grep -qiE '\bsystem\s*\(' "$file"; then
  echo "[WARNING] system() in $file — verify input is sanitized"
fi

if grep -qiE 'Open3\.(popen|capture|pipeline)' "$file"; then
  echo "[WARNING] Open3 usage in $file — verify user input is not passed unsanitized"
fi

if grep -qiE 'http://[a-zA-Z]' "$file"; then
  echo "[WARNING] insecure http:// URL in $file — use https://"
fi

if grep -qiE 'Digest::MD5' "$file"; then
  echo "[WARNING] MD5 in $file — do not use for passwords or security-sensitive hashing"
fi

if grep -qiE '\.(where|find_by|execute)\s*\(\s*"[^"]*#\{' "$file"; then
  echo "[WARNING] SQL string interpolation in $file — use parameterized queries"
fi

exit 0
