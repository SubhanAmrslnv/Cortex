#!/usr/bin/env bash
# @version: 1.0.0
# Scans .ps1/.psm1/.psd1 files for hardcoded secrets, Invoke-Expression, iex,
# DownloadString, insecure HTTP, plaintext SecureString, and RunAs patterns.
# Usage: security-scan.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.ps1 && $file != *.psm1 && $file != *.psd1 ]] && exit 0

if grep -qiE '(api_key|token|secret|password)\s*=\s*["'"'"'][A-Za-z0-9+/]{8,}' "$file"; then
  echo "[WARNING] possible hardcoded secret in $file — use SecretManagement module or env vars"
fi

if grep -qiE '\bInvoke-Expression\b' "$file"; then
  echo "[WARNING] Invoke-Expression in $file — code injection risk"
fi

if grep -qiE '\biex\s*\(' "$file"; then
  echo "[WARNING] iex() alias in $file — Invoke-Expression shorthand, code injection risk"
fi

if grep -qiE '\.DownloadString\s*\(' "$file"; then
  echo "[WARNING] DownloadString() in $file — verify content before executing downloaded code"
fi

if grep -qiE 'http://[a-zA-Z]' "$file"; then
  echo "[WARNING] insecure http:// URL in $file — use https://"
fi

if grep -qiE 'ConvertTo-SecureString\s+.*-AsPlainText' "$file"; then
  echo "[WARNING] ConvertTo-SecureString with plaintext in $file — use credential store instead"
fi

if grep -qiE 'Start-Process\s+.*-Verb\s+RunAs' "$file"; then
  echo "[WARNING] Start-Process -Verb RunAs in $file — privilege escalation, verify intent"
fi

exit 0
