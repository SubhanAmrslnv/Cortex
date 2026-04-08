#!/usr/bin/env bash
# @version: 2.4.0
# PostToolUse scanner — pure dispatcher. All extension→scanner mappings live in
# .cortex/registry/scanners.json. No language-specific logic in this file.
# Resolves CORTEX_ROOT: env var > project-local .cortex > global ~/.cortex.
# Payload delivered via stdin by Claude Code.

if [ -z "$CORTEX_ROOT" ]; then
  if [ -d "$(pwd)/.cortex" ]; then
    export CORTEX_ROOT="$(pwd)/.cortex"
  else
    export CORTEX_ROOT="$HOME/.cortex"
  fi
fi
command -v jq &>/dev/null || exit 0

input=$(cat)
[[ -z "$input" ]] && exit 0

file=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$file" || ! -f "$file" ]] && exit 0

# File size guard — skip large files (generated assets, logs, etc.)
max_size=500000
filesize=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo 0)
(( filesize > max_size )) && exit 0

# Binary file guard — scanners produce no useful output on binaries
if command -v file &>/dev/null && file "$file" 2>/dev/null | grep -q "binary"; then
  exit 0
fi

# Extension detection — handle compound extensions (.tar.gz, .env.local)
filename=$(basename "$file")
case "$filename" in
  *.tar.gz|*.tar.bz2|*.tar.xz) ext=".${filename#*.}" ;;
  *.env.*) ext=".env" ;;
  *) ext=".${filename##*.}" ;;
esac

REGISTRY="$CORTEX_ROOT/registry/scanners.json"
SCANNERS_DIR="$CORTEX_ROOT/core/scanners"

# Registry validation
[[ ! -f "$REGISTRY" ]] && exit 0
jq empty "$REGISTRY" 2>/dev/null || { echo "[scan] Invalid scanners.json" >&2; exit 0; }

# Merge wildcard + extension-specific entries in one jq call, deduplicate, exclude format.sh
mapfile -t scanners < <(
  jq -r --arg e "$ext" '
    ((.["*"] // []) + (.[$e] // [])) | unique | .[]
  ' "$REGISTRY" 2>/dev/null \
  | tr -d '\r' \
  | grep -v '/format\.sh$'
)

[[ ${#scanners[@]} -eq 0 ]] && exit 0

# Run all scanners in parallel with per-scanner timeout and error isolation
pids=()
for scanner in "${scanners[@]}"; do
  if [[ ! -f "$SCANNERS_DIR/$scanner" ]]; then
    [[ "${CORTEX_DEBUG:-0}" == "1" ]] && echo "[scan] Missing scanner: $scanner" >&2
    continue
  fi

  [[ "${CORTEX_DEBUG:-0}" == "1" ]] && echo "[scan] Running: $scanner on $file" >&2

  (
    timeout 10 bash "$SCANNERS_DIR/$scanner" "$file" 2>&1
    rc=$?
    if [[ $rc -eq 124 ]]; then
      echo "[scan] Timeout (10s): $scanner" >&2
    elif [[ $rc -ne 0 ]]; then
      echo "[scan] Scanner failed (exit $rc): $scanner" >&2
    fi
  ) &
  pids+=($!)
done

# Wait for all scanners to finish
for pid in "${pids[@]}"; do
  wait "$pid" 2>/dev/null || true
done

exit 0
