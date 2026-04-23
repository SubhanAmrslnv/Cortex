#!/usr/bin/env bash
# @version: 1.0.0
# Scans .swift files for hardcoded secrets, insecure HTTP, print() in prod,
# NSLog, weak hashing, insecure Keychain accessibility, and unsafe UserDefaults.
# Usage: security-scan.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.swift ]] && exit 0

if grep -qiE '(api_key|token|secret|password)\s*=\s*["'"'"'][A-Za-z0-9+/]{8,}' "$file"; then
  echo "[WARNING] possible hardcoded secret in $file — review before committing"
fi

if grep -qiE 'http://[a-zA-Z]' "$file"; then
  echo "[WARNING] insecure http:// URL in $file — use https://"
fi

if grep -qiE '\bprint\s*\(' "$file"; then
  echo "[WARNING] print() in $file — remove debug output before production release"
fi

if grep -qiE '\bNSLog\s*\(' "$file"; then
  echo "[WARNING] NSLog() in $file — logs are visible in device console, avoid in production"
fi

if grep -qiE '(CC_MD5|CC_SHA1)\s*\(' "$file"; then
  echo "[WARNING] weak hash (MD5/SHA1) in $file — use SHA-256 or stronger"
fi

if grep -qiE 'kSecAttrAccessibleAlways\b' "$file"; then
  echo "[WARNING] kSecAttrAccessibleAlways in $file — use kSecAttrAccessibleWhenUnlocked instead"
fi

if grep -qiE 'UserDefaults\.standard\.(set|setValue).*[Pp]assword|UserDefaults\.standard\.(set|setValue).*[Tt]oken' "$file"; then
  echo "[WARNING] sensitive data in UserDefaults in $file — use Keychain for credentials"
fi

exit 0
