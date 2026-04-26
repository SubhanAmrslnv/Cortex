#!/usr/bin/env bash
# @version: 1.3.0
# PostToolUse audit logger — appends structured JSON entries to .claude/logs/audit.log.
# Features: log rotation, flock concurrency safety, secret masking, payload truncation.
# Log stays project-local; no writes to $HOME.

source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0

input=$(cat)
[[ -z "$input" ]] && exit 0

tool_name=$(echo "$input" | jq -r '.tool_name // "unknown"' 2>/dev/null || echo "unknown")

# Filter noise — skip tools that produce no actionable audit signal
case "$tool_name" in
  notification|heartbeat) exit 0 ;;
esac

tool_input=$(echo "$input" | jq -c '.tool_input // {}' 2>/dev/null || echo "{}")

# Mask sensitive fields
tool_input=$(echo "$tool_input" | sed -E \
  's/"(password|token|api[_-]?key|secret|authorization|auth)"\s*:\s*"[^"]+"/"\1":"***"/gi')

# Truncate oversized payloads (keep first 2000 chars)
tool_input="${tool_input:0:2000}"

# Build structured JSON entry
log_entry=$(jq -n \
  --arg time "$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')" \
  --arg tool "$tool_name" \
  --argjson input "$tool_input" \
  '{time: $time, tool: $tool, input: $input}' 2>/dev/null)

# Fallback to plain text if jq assembly fails
[[ -z "$log_entry" ]] && log_entry="{\"time\":\"$(date -Iseconds)\",\"tool\":\"$tool_name\",\"input\":{}}"

LOG_FILE="$CORTEX_LOGS/audit.log"
MAX_SIZE=5000000  # 5 MB

# Log rotation — keep one backup
if [[ -f "$LOG_FILE" ]]; then
  size=$(stat -c%s "$LOG_FILE" 2>/dev/null || stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
  if (( size > MAX_SIZE )); then
    mv "$LOG_FILE" "${LOG_FILE}.1"
  fi
fi

# Concurrency-safe write via flock
{
  flock -x 200
  echo "$log_entry" >&200
} 200>>"$LOG_FILE"

[[ "${CORTEX_DEBUG:-0}" == "1" ]] && echo "[audit] Logged: $tool_name" >&2

exit 0
