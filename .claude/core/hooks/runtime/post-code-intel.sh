#!/usr/bin/env bash
# @version: 1.2.0
# PostToolUse code intelligence — analyzes .cs .js .ts .jsx .tsx files (≤1MB).
# Single combined pass: complexity (methods >50 lines, nesting >3), duplication
# (6-line sliding window cksum), naming (non-descriptive vars, capped 3/file),
# structure (>500 lines, mixed UI+data-access). Outputs JSON. Read-only.

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

# Extension filter
ext=".${file##*.}"
case "$ext" in
  .cs|.js|.ts|.jsx|.tsx) ;;
  *) exit 0 ;;
esac

# Size guard (≤1MB)
filesize=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo 0)
(( filesize > 1048576 )) && exit 0

content=$(cat "$file" 2>/dev/null)
[[ -z "$content" ]] && exit 0

total_lines=$(echo "$content" | wc -l)
issues_json="[]"

_add_issue() {
  local type="$1" line="${2:-0}" message="$3"
  if [[ "$line" -gt 0 ]]; then
    issues_json=$(echo "$issues_json" | jq \
      --arg t "$type" --argjson l "$line" --arg m "$message" \
      '. += [{"type":$t,"line":$l,"message":$m}]')
  else
    issues_json=$(echo "$issues_json" | jq \
      --arg t "$type" --arg m "$message" \
      '. += [{"type":$t,"message":$m}]')
  fi
}

# ── 1. Complexity: methods >50 lines + nesting depth >3 ──────────────────
# Single brace-depth tracking pass — detects both in one read.
cur_depth=0
method_start=0
method_base_depth=0
max_nesting=0
in_method=0
line_num=0

while IFS= read -r line; do
  (( line_num++ ))

  opens=$(echo "$line" | tr -cd '{' | wc -c)
  closes=$(echo "$line" | tr -cd '}' | wc -c)
  cur_depth=$(( cur_depth + opens - closes ))
  (( cur_depth < 0 )) && cur_depth=0

  if [[ $in_method -eq 0 ]]; then
    if echo "$line" | grep -qE \
      '(^\s*(public|private|protected|internal|static|async|override|virtual)\s+.*\(|^\s*function\s+\w+\s*\(|^\s*\w+\s*\(.*\)\s*\{|=>.*\{)'; then
      in_method=1
      method_start=$line_num
      method_base_depth=$cur_depth
      max_nesting=$cur_depth
    fi
  else
    (( cur_depth > max_nesting )) && max_nesting=$cur_depth
    if [[ $cur_depth -lt $method_base_depth && $line_num -gt $method_start ]]; then
      length=$(( line_num - method_start ))
      nest=$(( max_nesting - method_base_depth ))
      [[ $length -gt 50 ]] && \
        _add_issue "complexity" "$method_start" \
          "Method at line $method_start is $length lines (>50) — consider splitting"
      [[ $nest -gt 3 ]] && \
        _add_issue "complexity" "$method_start" \
          "Nesting depth $nest at line $method_start (>3) — reduce with early returns"
      in_method=0
    fi
  fi
done <<< "$content"

# ── 2. Duplication: 6-line sliding window cksum ───────────────────────────
if command -v cksum &>/dev/null; then
  declare -A seen_sums
  win_num=0
  while IFS= read -r chunk; do
    (( win_num++ ))
    normalized=$(echo "$chunk" | tr -s ' \t')
    [[ ${#normalized} -lt 30 ]] && continue  # skip trivial windows
    sum=$(echo "$normalized" | cksum | cut -d' ' -f1)
    if [[ -n "${seen_sums[$sum]+_}" ]]; then
      first=${seen_sums[$sum]}
      _add_issue "duplication" "$win_num" \
        "Duplicate 6-line block near line $win_num (first at line $first) — extract shared logic"
    else
      seen_sums[$sum]=$win_num
    fi
  done < <(awk 'NR==1{for(i=1;i<=NF;i++)buf[i]=$0;next}
                {buf[NR%6+1]=$0; s=""; for(k=1;k<=6;k++) s=s buf[k] "\n"; print s}
                END{if(NR>=6){s="";for(k=1;k<=6;k++) s=s buf[k] "\n"; print s}}
               ' RS='\n' ORS='' <(echo "$content") 2>/dev/null \
         || awk 'BEGIN{n=0}{lines[++n]=$0}
                 END{for(i=1;i<=n-5;i++){s="";for(j=i;j<i+6;j++)s=s lines[j] "\n";print s}}
               ' <<< "$content" 2>/dev/null)
fi

# ── 3. Naming: non-descriptive variable names (capped at 3) ───────────────
naming_count=0
bad_pattern='^\s*(var|let|const|auto|val|int|string|bool|def)\s+(temp|data|obj|result|item|value|thing|foo|bar|baz|tmp|buf|ret|res|x|y|z)\b'
while IFS=: read -r ln _; do
  [[ $naming_count -ge 3 ]] && break
  [[ -z "$ln" ]] && continue
  _add_issue "naming" "$ln" \
    "Non-descriptive variable at line $ln — use a name that expresses intent"
  (( naming_count++ ))
done < <(grep -nE "$bad_pattern" "$file" 2>/dev/null | head -3)

# ── 4. Structure: file >500 lines; mixed UI + data-access ────────────────
if [[ $total_lines -gt 500 ]]; then
  _add_issue "structure" 0 \
    "File is $total_lines lines (>500) — split into focused modules"
fi

has_ui=0; has_data=0
grep -qiE '(render\(|<[A-Z][A-Za-z]+|useState|useEffect|getElementById|querySelector|innerHTML|className=|v-model|@click)' \
  "$file" 2>/dev/null && has_ui=1
grep -qiE '(SELECT |INSERT |UPDATE |DELETE |DbContext|Repository|\.findAll|\.save\(|fetch\(|axios\.|httpClient|SqlCommand|prisma\.)' \
  "$file" 2>/dev/null && has_data=1
if [[ $has_ui -eq 1 && $has_data -eq 1 ]]; then
  _add_issue "structure" 0 \
    "File mixes UI rendering and data-access — separate into view and service layers"
fi

# ── Output ─────────────────────────────────────────────────────────────────
issue_count=$(echo "$issues_json" | jq 'length')
[[ "$issue_count" -eq 0 ]] && exit 0

jq -n \
  --arg path "$file" \
  --argjson issues "$issues_json" \
  '{"code_intel": {"files": [{"path": $path, "issues": $issues}]}}'

exit 0
