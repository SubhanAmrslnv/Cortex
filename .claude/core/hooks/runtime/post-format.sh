#!/usr/bin/env bash
# @version: 2.4.0
# PostToolUse formatter — pure dispatcher. All extension→scanner mappings live in
# .cortex/registry/scanners.json. No language-specific logic in this file.
# Resolves CORTEX_ROOT: env var > project-local .cortex > global ~/.cortex.
# Payload delivered via stdin by Claude Code.

if [ -z "$CORTEX_ROOT" ]; then
  if [ -d "$(pwd)/.claude" ]; then
    export CORTEX_ROOT="$(pwd)/.claude"
  else
    export CORTEX_ROOT="$(pwd)/.claude"
  fi
fi
command -v jq &>/dev/null || exit 0

input=$(cat)
[[ -z "$input" ]] && exit 0

file=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$file" || ! -f "$file" ]] && exit 0

# File size guard — skip large files
max_size=500000
filesize=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo 0)
(( filesize > max_size )) && exit 0

# Binary file guard
if command -v file &>/dev/null && file "$file" 2>/dev/null | grep -q "binary"; then
  exit 0
fi

# Extension detection — handle compound extensions
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
jq empty "$REGISTRY" 2>/dev/null || { echo "[format] Invalid scanners.json" >&2; exit 0; }

# Merge wildcard + extension-specific entries, deduplicate, keep only format.sh entries
mapfile -t formatters < <(
  jq -r --arg e "$ext" '
    ((.["*"] // []) + (.[$e] // [])) | unique | .[]
  ' "$REGISTRY" 2>/dev/null \
  | tr -d '\r' \
  | grep '/format\.sh$'
)

[[ ${#formatters[@]} -eq 0 ]] && exit 0

# Run all formatters in parallel with per-formatter timeout and error isolation
pids=()
for scanner in "${formatters[@]}"; do
  if [[ ! -f "$SCANNERS_DIR/$scanner" ]]; then
    [[ "${CORTEX_DEBUG:-0}" == "1" ]] && echo "[format] Missing formatter: $scanner" >&2
    continue
  fi

  [[ "${CORTEX_DEBUG:-0}" == "1" ]] && echo "[format] Running: $scanner on $file" >&2

  (
    timeout 10 bash "$SCANNERS_DIR/$scanner" "$file" 2>&1
    rc=$?
    if [[ $rc -eq 124 ]]; then
      echo "[format] Timeout (10s): $scanner" >&2
    elif [[ $rc -ne 0 ]]; then
      echo "[format] Formatter failed (exit $rc): $scanner" >&2
    fi
  ) &
  pids+=($!)
done

for pid in "${pids[@]}"; do
  wait "$pid" 2>/dev/null || true
done

exit 0
