#!/usr/bin/env bash
# @version: 1.0.0
# Scans .proto files for deprecated field_mask patterns, missing field numbers,
# insecure HTTP in option URLs, and insecure channel options.
# Usage: security-scan.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.proto ]] && exit 0

if grep -qiE '\bFieldMask\b.*deprecated|deprecated.*\bFieldMask\b' "$file"; then
  echo "[WARNING] deprecated FieldMask pattern in $file — use google.protobuf.FieldMask"
fi

if grep -qiE '^\s+\w+\s+\w+\s*;' "$file"; then
  echo "[WARNING] field without explicit field number in $file — all proto3 fields need numbers"
fi

if grep -qiE 'option\s*\(google\.api\.http\).*=.*"http://' "$file"; then
  echo "[WARNING] http:// in HTTP option URL in $file — use https://"
fi

if grep -qiE 'grpc\.insecure_channel_credentials|insecure_channel' "$file"; then
  echo "[WARNING] insecure channel credentials in $file — use TLS credentials in production"
fi

exit 0
