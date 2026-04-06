#!/usr/bin/env bash
# @version: 1.0.0
# Scans .rs files for hardcoded secrets, unsafe blocks, excessive unwrap chains,
# insecure HTTP URLs, and Command::new with potential user input.
# Usage: security-scan.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.rs ]] && exit 0

if grep -qiE '(api_key|token|secret|password)\s*=\s*["'"'"'][A-Za-z0-9+/]{8,}' "$file"; then
  echo "[WARNING] possible hardcoded secret in $file — review before committing"
fi

if grep -qiE '\bunsafe\s*\{' "$file"; then
  echo "[WARNING] unsafe block in $file — verify memory safety invariants are upheld"
fi

unwrap_count=$(grep -ciE '\.unwrap\s*\(\)' "$file" 2>/dev/null || echo 0)
if [[ "$unwrap_count" -gt 3 ]]; then
  echo "[WARNING] $unwrap_count unwrap() calls in $file — consider using ? or proper error handling"
fi

if grep -qiE 'http://[a-zA-Z]' "$file"; then
  echo "[WARNING] insecure http:// URL in $file — use https://"
fi

if grep -qiE 'Command::new\s*\(' "$file"; then
  echo "[WARNING] Command::new() in $file — verify user input is not passed unsanitized"
fi

exit 0
