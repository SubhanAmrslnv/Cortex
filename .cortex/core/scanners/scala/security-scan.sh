#!/usr/bin/env bash
# @version: 1.0.0
# Scans .scala/.sc files for hardcoded secrets, Runtime.exec, insecure HTTP,
# weak hashing, and XML.loadString (XXE risk).
# Usage: security-scan.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.scala && $file != *.sc ]] && exit 0

if grep -qiE '(api_key|token|secret|password)\s*=\s*["'"'"'][A-Za-z0-9+/]{8,}' "$file"; then
  echo "[WARNING] possible hardcoded secret in $file — review before committing"
fi

if grep -qiE 'Runtime\.getRuntime\s*\(\s*\)\s*\.exec\s*\(|Runtime\.exec\s*\(' "$file"; then
  echo "[WARNING] Runtime.exec() in $file — command injection risk"
fi

if grep -qiE 'http://[a-zA-Z]' "$file"; then
  echo "[WARNING] insecure http:// URL in $file — use https://"
fi

if grep -qiE '"(MD5|SHA-1|SHA1)"' "$file"; then
  echo "[WARNING] weak hash algorithm (MD5/SHA1) in $file — use SHA-256 or stronger"
fi

if grep -qiE 'XML\.loadString\s*\(' "$file"; then
  echo "[WARNING] XML.loadString() in $file — XXE risk, use a safe XML parser configuration"
fi

exit 0
