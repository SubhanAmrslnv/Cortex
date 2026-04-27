#!/usr/bin/env bash
# @version: 1.2.0
# Notification hook — aggregates signals from previous hooks, filters noise,
# emits only medium/high severity actionable notifications.
# Reads payload from stdin. Always exits 0.
#
# Notifications accumulated as raw JSON strings (no per-call jq spawn).
# Single jq call at the end builds the final response.

source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0

input=$(cat)
[[ -z "$input" ]] && exit 0

declare -a notif_parts=()
seen=""  # dedup: pipe-separated "type|message_key"

add_notification() {
  local type="$1" severity="$2" message="$3" file="${4:-}"
  local key="${type}|${message:0:60}"
  # Skip duplicates
  [[ "$seen" == *"${key}|"* ]] && return
  seen="${seen}${key}|"

  # Escape strings for safe JSON embedding
  local msg_esc="${message//\\/\\\\}"; msg_esc="${msg_esc//\"/\\\"}"
  local type_esc="${type//\"/\\\"}"
  local sev_esc="${severity//\"/\\\"}"

  local entry="{\"type\":\"$type_esc\",\"severity\":\"$sev_esc\",\"message\":\"$msg_esc\""
  if [[ -n "$file" ]]; then
    local file_esc="${file//\\/\\\\}"; file_esc="${file_esc//\"/\\\"}"
    entry="${entry},\"file\":\"$file_esc\""
  fi
  entry="${entry}}"
  notif_parts+=("$entry")
}

# ─── 1. Security signals ─────────────────────────────────────────────────────
# Single jq call extracts all [file, message] pairs — no per-item jq spawn
while IFS=$'\t' read -r file msg; do
  [[ -z "$msg" ]] && continue
  case "$msg" in
    *secret*|*credential*|*api_key*|*private_key*|*password*|*token*)
      add_notification "security" "high" "Possible hardcoded secret detected — review before committing" "$file" ;;
    *XSS*|*innerHTML*|*dangerouslySetInnerHTML*|*eval*)
      add_notification "security" "high" "XSS-prone pattern detected — verify intent and sanitize input" "$file" ;;
    *sql*inject*|*string concat*sql*)
      add_notification "security" "high" "Possible SQL injection risk — use parameterised queries" "$file" ;;
    *http://*|*insecure protocol*)
      add_notification "security" "medium" "Insecure HTTP URL detected — use HTTPS" "$file" ;;
    *unsafe*|*exec\(*|*shell_exec*|*eval\(\)*)
      add_notification "security" "high" "Unsafe code execution pattern detected" "$file" ;;
    *)
      add_notification "security" "medium" "$msg" "$file" ;;
  esac
done < <(echo "$input" | jq -r '.security_warnings[]? | [(.file // ""), (.message // "")] | @tsv' 2>/dev/null)

# Raw scanner WARNING lines
raw_security=$(echo "$input" | jq -r '.security_output // empty' 2>/dev/null)
if [[ -n "$raw_security" ]]; then
  while IFS= read -r line; do
    [[ "$line" =~ ^WARNING:\ possible\ hardcoded ]] && \
      add_notification "security" "high" "Possible hardcoded secret detected — review before committing" ""
    [[ "$line" =~ XSS ]] && \
      add_notification "security" "high" "XSS-prone pattern detected — verify intent and sanitize input" ""
  done <<< "$raw_security"
fi

# ─── 2. Build signals ────────────────────────────────────────────────────────
build_status=$(echo "$input" | jq -r '.build_status // empty'          2>/dev/null)
build_error=$(echo "$input"  | jq -r '.build_error // .build_stderr // empty' 2>/dev/null)

if [[ "$build_status" == "failed" || "$build_status" == "error" ]]; then
  msg="Build failed"
  if grep -qiE 'cannot find module|unresolved|missing' <<< "$build_error"; then
    msg="Build failed — missing dependency"
  elif grep -qiE 'syntaxerror|unexpected token|error cs[0-9]+|error ts[0-9]+' <<< "$build_error"; then
    msg="Build failed — syntax or type error"
  elif grep -qiE 'permission denied' <<< "$build_error"; then
    msg="Build failed — permission denied"
  fi
  add_notification "build" "high" "$msg" ""
fi

test_status=$(echo "$input"  | jq -r '.test_status // empty'  2>/dev/null)
test_failed=$(echo "$input"  | jq -r '.tests_failed // empty' 2>/dev/null)
if [[ "$test_status" == "failed" || ( -n "$test_failed" && "$test_failed" -gt 0 2>/dev/null ) ]]; then
  add_notification "build" "high" "${test_failed:-some} test(s) failed — review test output" ""
fi

# ─── 3. Code quality signals ─────────────────────────────────────────────────
# Single jq call extracts all [path, issue-type] pairs — replaces nested while+jq loops
complex_count=0; dup_count=0; struct_count=0
complex_files=""; dup_files=""; struct_files=""

while IFS=$'\t' read -r fpath itype; do
  case "$itype" in
    complexity)  (( complex_count++ )); complex_files+=" $fpath" ;;
    duplication) (( dup_count++ ));     dup_files+=" $fpath"     ;;
    structure)   (( struct_count++ ));  struct_files+=" $fpath"  ;;
  esac
done < <(echo "$input" | jq -r '.code_intel.files[]? | .path as $p | .issues[]? | [$p, .type] | @tsv' 2>/dev/null)

if [[ $complex_count -gt 0 ]]; then
  file_count=$(echo "$complex_files" | tr ' ' '\n' | grep -cv '^$' 2>/dev/null || echo 1)
  sev="medium"; [[ $file_count -gt 2 ]] && sev="high"
  first_file=$(echo "$complex_files" | tr ' ' '\n' | grep -v '^$' | head -1)
  add_notification "code_quality" "$sev" \
    "High method complexity detected in ${file_count} file(s) — consider refactoring" "$first_file"
fi

if [[ $dup_count -gt 0 ]]; then
  first_file=$(echo "$dup_files" | tr ' ' '\n' | grep -v '^$' | head -1)
  add_notification "code_quality" "medium" \
    "Code duplication detected in ${dup_count} location(s) — extract shared logic" "$first_file"
fi

if [[ $struct_count -gt 0 ]]; then
  first_file=$(echo "$struct_files" | tr ' ' '\n' | grep -v '^$' | head -1)
  add_notification "code_quality" "medium" \
    "Structural issue detected — file too large or mixed responsibilities" "$first_file"
fi

# ─── 4. Performance signals ──────────────────────────────────────────────────
perf_delta=$(echo "$input" | jq -r '.performance.delta_percent // empty'       2>/dev/null)
perf_metric=$(echo "$input" | jq -r '.performance.metric // "response time"'   2>/dev/null)

if [[ -n "$perf_delta" && "$perf_delta" =~ ^[0-9] ]]; then
  delta_int=${perf_delta%.*}   # integer part only (avoids bc dependency)
  if (( delta_int > 20 )); then
    sev="medium"; (( delta_int > 40 )) && sev="high"
    add_notification "performance" "$sev" \
      "Performance degraded by ${perf_delta}% in ${perf_metric}" ""
  fi
fi

# ─── 5. Error analyzer signals ───────────────────────────────────────────────
err_type=$(echo "$input"    | jq -r '.last_error.type       // empty' 2>/dev/null)
err_msg=$(echo "$input"     | jq -r '.last_error.message    // empty' 2>/dev/null)
err_file=$(echo "$input"    | jq -r '.last_error.file       // empty' 2>/dev/null)
err_suggest=$(echo "$input" | jq -r '.last_error.suggestion // empty' 2>/dev/null)

if [[ -n "$err_type" && "$err_type" != "unknown" ]]; then
  case "$err_type" in
    dependency_error)
      add_notification "build" "high" \
        "Dependency error: ${err_msg:0:100} — ${err_suggest}" "$err_file" ;;
    permission_error)
      add_notification "build" "high" \
        "Permission error: ${err_msg:0:100}" "$err_file" ;;
    syntax_error)
      add_notification "build" "high" \
        "Syntax error: ${err_msg:0:100}" "$err_file" ;;
    runtime_error)
      add_notification "build" "high" \
        "Runtime error: ${err_msg:0:100}" "$err_file" ;;
    network_error)
      add_notification "general" "medium" \
        "Network error: ${err_msg:0:100} — ${err_suggest}" "" ;;
    *)
      [[ -n "$err_msg" ]] && \
        add_notification "general" "medium" "${err_msg:0:100}" "$err_file" ;;
  esac
fi

# ─── Output — suppress empty or all-low results ──────────────────────────────
[[ ${#notif_parts[@]} -eq 0 ]] && exit 0

# Build JSON array from accumulated parts
notif_json=$(printf '%s,' "${notif_parts[@]}")
notif_json="[${notif_json%,}]"

# Filter: only emit if at least one medium or high notification
has_significant=$(echo "$notif_json" | \
  jq '[.[] | select(.severity == "medium" or .severity == "high")] | length' 2>/dev/null || echo 0)

[[ "$has_significant" -eq 0 ]] && exit 0

jq -n --argjson n "$notif_json" '{"notifications": $n}'

exit 0
