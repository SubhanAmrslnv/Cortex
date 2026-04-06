#!/usr/bin/env bash
# @version: 1.0.0
# Scans .mk/Makefile files for hardcoded secrets, curl|sh, wget|sh,
# rm -rf /, chmod 777, and insecure HTTP URLs.
# Usage: security-scan.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.mk && $(basename "$file") != Makefile && $(basename "$file") != makefile && $(basename "$file") != GNUmakefile ]] && exit 0

if grep -qiE '(api_key|token|secret|password)\s*[=:]\s*[A-Za-z0-9+/]{8,}' "$file"; then
  echo "[WARNING] possible hardcoded secret in $file — use environment variables"
fi

if grep -qiE 'curl\s+.*\|\s*(bash|sh)\b|wget\s+.*\|\s*(bash|sh)\b' "$file"; then
  echo "[WARNING] curl/wget piped to shell in $file — remote code execution risk"
fi

if grep -qiE 'rm\s+-[a-z]*r[a-z]*f[a-z]*\s+/' "$file"; then
  echo "[WARNING] rm -rf / in $file — potential system destruction"
fi

if grep -qiE 'chmod\s+777' "$file"; then
  echo "[WARNING] chmod 777 in $file — overly permissive, use minimal required permissions"
fi

if grep -qiE 'http://[a-zA-Z]' "$file"; then
  echo "[WARNING] insecure http:// URL in $file — use https://"
fi

exit 0
