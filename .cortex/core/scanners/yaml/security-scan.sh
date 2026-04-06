#!/usr/bin/env bash
# @version: 1.0.0
# Scans .yaml/.yml files for hardcoded secrets, insecure HTTP, 0.0.0.0 binding,
# privileged containers, root execution, host network, and insecure TLS options.
# Usage: security-scan.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.yaml && $file != *.yml ]] && exit 0

if grep -qiE '(api_key|token|secret|password)\s*:\s*.{8,}' "$file"; then
  echo "[WARNING] possible hardcoded secret in $file — use a secrets manager or sealed secrets"
fi

if grep -qiE 'http://[a-zA-Z]' "$file"; then
  echo "[WARNING] insecure http:// URL in $file — use https://"
fi

if grep -qiE '0\.0\.0\.0' "$file"; then
  echo "[WARNING] 0.0.0.0 binding in $file — verify this intentionally listens on all interfaces"
fi

if grep -qiE 'privileged\s*:\s*true' "$file"; then
  echo "[WARNING] privileged: true in $file — grants full host access, use specific capabilities"
fi

if grep -qiE 'runAsUser\s*:\s*0\b|runAsRoot\s*:\s*true' "$file"; then
  echo "[WARNING] container running as root in $file — use a non-root user"
fi

if grep -qiE 'hostNetwork\s*:\s*true' "$file"; then
  echo "[WARNING] hostNetwork: true in $file — shares host network namespace, use with caution"
fi

if grep -qiE 'allowPrivilegeEscalation\s*:\s*true' "$file"; then
  echo "[WARNING] allowPrivilegeEscalation: true in $file — set to false for least privilege"
fi

if grep -qiE 'insecureSkipVerify\s*:\s*true' "$file"; then
  echo "[WARNING] insecureSkipVerify: true in $file — disables TLS verification, man-in-the-middle risk"
fi

exit 0
