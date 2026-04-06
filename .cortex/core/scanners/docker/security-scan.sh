#!/usr/bin/env bash
# @version: 1.0.0
# Scans Dockerfiles for FROM latest, RUN curl|sh, ADD for URLs, missing USER,
# hardcoded secrets in ENV/ARG, sensitive exposed ports, and privileged patterns.
# Usage: security-scan.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.dockerfile && $file != *Dockerfile* ]] && exit 0

if grep -qiE '^FROM\s+\S+:latest\b' "$file"; then
  echo "[WARNING] FROM :latest in $file — pin to a specific image digest or tag"
fi

if grep -qiE '^RUN\s+.*curl\s+.*\|\s*(bash|sh)\b|^RUN\s+.*wget\s+.*\|\s*(bash|sh)\b' "$file"; then
  echo "[WARNING] RUN curl/wget piped to shell in $file — remote code execution risk"
fi

if grep -qiE '^ADD\s+https?://' "$file"; then
  echo "[WARNING] ADD with URL in $file — use COPY with a local file or RUN curl with checksum"
fi

if ! grep -qiE '^USER\s+' "$file"; then
  echo "[WARNING] no USER directive in $file — container will run as root"
fi

if grep -qiE '^(ENV|ARG)\s+.*(api_key|token|secret|password)\s*=' "$file"; then
  echo "[WARNING] possible secret in ENV/ARG in $file — use build secrets or runtime env injection"
fi

if grep -qiE '^EXPOSE\s+(22|3306|5432)\b' "$file"; then
  echo "[WARNING] sensitive port exposed in $file — avoid exposing database/SSH ports directly"
fi

if grep -qiE '--privileged' "$file"; then
  echo "[WARNING] --privileged flag in $file — grants full host access, use specific capabilities instead"
fi

exit 0
