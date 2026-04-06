#!/usr/bin/env bash
# @version: 1.0.0
# Scans .java files for hardcoded secrets, dangerous exec, unsafe deserialization,
# weak hashing, SQL string concatenation, and other common vulnerability patterns.
# Usage: security-scan.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.java ]] && exit 0

if grep -qiE '(api_key|token|secret|password)\s*=\s*["'"'"'][A-Za-z0-9+/]{8,}' "$file"; then
  echo "[WARNING] possible hardcoded secret in $file — review before committing"
fi

if grep -qiE 'Runtime\.exec\s*\(' "$file"; then
  echo "[WARNING] Runtime.exec() in $file — command injection risk"
fi

if grep -qiE 'ProcessBuilder\s*\(' "$file"; then
  echo "[WARNING] ProcessBuilder in $file — verify input is sanitized"
fi

if grep -qiE 'ObjectInputStream\s*\(' "$file"; then
  echo "[WARNING] ObjectInputStream in $file — unsafe deserialization with untrusted data"
fi

if grep -qiE 'http://[a-zA-Z]' "$file"; then
  echo "[WARNING] insecure http:// URL in $file — use https://"
fi

if grep -qiE 'MessageDigest\.getInstance\s*\(\s*"(MD5|SHA-1|SHA1)"' "$file"; then
  echo "[WARNING] weak hash algorithm (MD5/SHA1) in $file — use SHA-256 or stronger"
fi

if grep -qiE 'String\.format\s*\(.*SELECT|String\.format\s*\(.*INSERT|String\.format\s*\(.*UPDATE|String\.format\s*\(.*DELETE' "$file"; then
  echo "[WARNING] String.format() used in SQL query in $file — use PreparedStatement"
fi

if grep -qiE 'System\.out\.println\s*\(' "$file"; then
  echo "[WARNING] System.out.println() in $file — use a proper logger in production code"
fi

exit 0
