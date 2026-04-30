#!/usr/bin/env bash
# @version: 1.0.0
# Scans .go files for hardcoded secrets, dangerous exec, insecure HTTP,
# weak hashing, SQL string formatting, and unsafe I/O patterns.
# Usage: security-scan.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.go ]] && exit 0

if grep -qiE '(api_key|token|secret|password)\s*=\s*["'"'"'][A-Za-z0-9+/]{8,}' "$file"; then
  echo "[WARNING] possible hardcoded secret in $file — review before committing"
fi

if grep -qiE 'os\.StartProcess\s*\(|exec\.Command\s*\(' "$file"; then
  echo "[WARNING] os/exec usage in $file — verify input is sanitized"
fi

if grep -qiE 'http://[a-zA-Z]' "$file"; then
  echo "[WARNING] insecure http:// URL in $file — use https://"
fi

if grep -qiE 'md5\.New\s*\(\)' "$file"; then
  echo "[WARNING] md5.New() in $file — MD5 is cryptographically broken, use SHA-256 or stronger"
fi

if grep -qiE 'sha1\.New\s*\(\)' "$file"; then
  echo "[WARNING] sha1.New() in $file — SHA1 is weak, use SHA-256 or stronger"
fi

if grep -qiE 'fmt\.Sprintf\s*\(.*SELECT|fmt\.Sprintf\s*\(.*INSERT|fmt\.Sprintf\s*\(.*UPDATE|fmt\.Sprintf\s*\(.*DELETE' "$file"; then
  echo "[WARNING] fmt.Sprintf() used in SQL query in $file — use parameterized queries"
fi

if grep -qiE 'ioutil\.ReadAll\s*\(' "$file"; then
  echo "[WARNING] ioutil.ReadAll() in $file — no size limit, potential memory exhaustion"
fi

exit 0
