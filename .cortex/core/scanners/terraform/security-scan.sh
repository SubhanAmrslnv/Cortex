#!/usr/bin/env bash
# @version: 1.0.0
# Scans .tf/.tfvars files for hardcoded secrets, insecure HTTP, open ingress CIDRs,
# admin passwords, publicly accessible resources, and unencrypted storage.
# Usage: security-scan.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.tf && $file != *.tfvars ]] && exit 0

if grep -qiE '(api_key|token|secret|password)\s*=\s*["'"'"'][A-Za-z0-9+/]{8,}' "$file"; then
  echo "[WARNING] possible hardcoded secret in $file — use variables or a secrets manager"
fi

if grep -qiE 'http://[a-zA-Z]' "$file"; then
  echo "[WARNING] insecure http:// URL in $file — use https://"
fi

if grep -qiE 'cidr_blocks\s*=\s*\[?"0\.0\.0\.0/0"' "$file"; then
  echo "[WARNING] 0.0.0.0/0 ingress CIDR in $file — overly permissive, restrict to known IPs"
fi

if grep -qiE '(admin_password|root_password|master_password)\s*=\s*["'"'"'][^"'"'"']+' "$file"; then
  echo "[WARNING] admin/root password in $file — use a secrets manager, not plaintext config"
fi

if grep -qiE 'publicly_accessible\s*=\s*true' "$file"; then
  echo "[WARNING] publicly_accessible = true in $file — verify this resource must be public"
fi

if grep -qiE 'encrypted\s*=\s*false' "$file"; then
  echo "[WARNING] encrypted = false in $file — enable encryption at rest"
fi

exit 0
