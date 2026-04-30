#!/usr/bin/env bash
# @version: 1.0.0
# Scans .php files for hardcoded secrets, dangerous functions, deprecated APIs,
# SQL injection via superglobals, insecure HTTP, weak hashing, and extract().
# Usage: security-scan.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.php ]] && exit 0

if grep -qiE '(api_key|token|secret|password)\s*=\s*["'"'"'][A-Za-z0-9+/]{8,}' "$file"; then
  echo "[WARNING] possible hardcoded secret in $file — review before committing"
fi

if grep -qiE '\beval\s*\(' "$file"; then
  echo "[WARNING] eval() in $file — code injection risk"
fi

if grep -qiE '\b(exec|shell_exec|system|passthru|popen)\s*\(' "$file"; then
  echo "[WARNING] dangerous shell function in $file — command injection risk"
fi

if grep -qiE '\bmysql_query\s*\(' "$file"; then
  echo "[WARNING] mysql_query() in $file — deprecated API, use PDO or MySQLi"
fi

if grep -qiE '\$_(GET|POST|REQUEST|COOKIE)\[.*\]\s*\..*mysql_query|\$_(GET|POST|REQUEST|COOKIE)\[.*\]\s*\.\s*["'"'"']' "$file"; then
  echo "[WARNING] superglobal used in query string concatenation in $file — SQL injection risk"
fi

if grep -qiE 'http://[a-zA-Z]' "$file"; then
  echo "[WARNING] insecure http:// URL in $file — use https://"
fi

if grep -qiE '\bmd5\s*\(' "$file"; then
  echo "[WARNING] md5() used in $file — do not use for password hashing, use password_hash()"
fi

if grep -qiE '\bextract\s*\(\s*\$_(GET|POST|REQUEST|COOKIE)' "$file"; then
  echo "[WARNING] extract() on superglobal in $file — variable injection risk"
fi

exit 0
