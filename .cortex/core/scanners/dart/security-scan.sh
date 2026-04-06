#!/usr/bin/env bash
# @version: 1.0.0
# Scans .dart files for hardcoded secrets, insecure HTTP, debugPrint in prod,
# sensitive SharedPreferences keys, and Process.run with potential user input.
# Usage: security-scan.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.dart ]] && exit 0

if grep -qiE '(api_key|token|secret|password)\s*=\s*["'"'"'][A-Za-z0-9+/]{8,}' "$file"; then
  echo "[WARNING] possible hardcoded secret in $file — review before committing"
fi

if grep -qiE 'http://[a-zA-Z]' "$file"; then
  echo "[WARNING] insecure http:// URL in $file — use https://"
fi

if grep -qiE '\bdebugPrint\s*\(' "$file"; then
  echo "[WARNING] debugPrint() in $file — remove debug output before production release"
fi

if grep -qiE 'SharedPreferences.*setString.*[Pp]assword|setString\s*\(\s*['"'"'"][Pp]assword|setString\s*\(\s*['"'"'"][Tt]oken' "$file"; then
  echo "[WARNING] sensitive key in SharedPreferences in $file — use flutter_secure_storage instead"
fi

if grep -qiE 'Process\.run\s*\(' "$file"; then
  echo "[WARNING] Process.run() in $file — verify user input is not passed unsanitized"
fi

exit 0
