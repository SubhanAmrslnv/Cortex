#!/usr/bin/env bash
# @version: 1.0.0
# Scans .kt/.kts files for hardcoded secrets, dangerous exec, insecure HTTP,
# weak hashing, sensitive Log.d output, and insecure SharedPreferences usage.
# Usage: security-scan.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.kt && $file != *.kts ]] && exit 0

if grep -qiE '(api_key|token|secret|password)\s*=\s*["'"'"'][A-Za-z0-9+/]{8,}' "$file"; then
  echo "[WARNING] possible hardcoded secret in $file — review before committing"
fi

if grep -qiE 'Runtime\.getRuntime\s*\(\s*\)\s*\.exec\s*\(' "$file"; then
  echo "[WARNING] Runtime.getRuntime().exec() in $file — command injection risk"
fi

if grep -qiE 'http://[a-zA-Z]' "$file"; then
  echo "[WARNING] insecure http:// URL in $file — use https://"
fi

if grep -qiE 'MessageDigest\.getInstance\s*\(\s*"(MD5|SHA-1|SHA1)"' "$file"; then
  echo "[WARNING] weak hash algorithm (MD5/SHA1) in $file — use SHA-256 or stronger"
fi

if grep -qiE 'Log\.(d|v|i)\s*\(.*[Pp]assword|Log\.(d|v|i)\s*\(.*[Tt]oken|Log\.(d|v|i)\s*\(.*[Ss]ecret' "$file"; then
  echo "[WARNING] sensitive data in Log.d/v/i() in $file — avoid logging credentials"
fi

if grep -qiE 'SharedPreferences.*putString.*[Pp]assword|putString.*[Pp]assword' "$file"; then
  echo "[WARNING] password stored in SharedPreferences in $file — use Android Keystore instead"
fi

exit 0
