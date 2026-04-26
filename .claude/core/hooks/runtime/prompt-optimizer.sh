#!/usr/bin/env bash
# @version: 2.0.0
# UserPromptSubmit structured prompt engine.
# Detects intent, scores command routing, finds top-2 relevant files via keyword
# heuristics (single find pass), extracts ±10-line snippets (reduced from ±20),
# and outputs an enriched prompt. Context is capped to prevent token bloat.
# --y suffix: strip flag, inject GLOBAL ANSWER POLICY (YES-default).

source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0

input=$(cat)
[[ -z "$input" ]] && exit 0

prompt=$(echo "$input" | jq -r '.prompt // empty' 2>/dev/null)
[[ -z "$prompt" ]] && exit 0

# Skip enrichment for very long prompts — already rich in context
(( ${#prompt} > 6000 )) && exit 0

# ── --y flag handling ─────────────────────────────────────────────────────────
yes_mode=0
if [[ "$prompt" =~ (^|[[:space:]])--y([[:space:]]|$) || "$prompt" == *" --y" || "$prompt" == "--y" ]]; then
  yes_mode=1
  prompt=$(echo "$prompt" | sed 's/[[:space:]]*--y[[:space:]]*$//' | sed 's/[[:space:]]*--y[[:space:]]/ /g' | xargs)
fi

# ── Intent detection ──────────────────────────────────────────────────────────
prompt_lower=$(echo "$prompt" | tr '[:upper:]' '[:lower:]')
intent="question"

if echo "$prompt_lower" | grep -qE '\b(fix|bug|error|issue|broken|crash|fail|exception|traceback|stacktrace|undefined|null)\b'; then
  intent="bug_fix"
elif echo "$prompt_lower" | grep -qE '\b(add|implement|create|build|develop|new feature|integrate|write)\b'; then
  intent="feature_request"
elif echo "$prompt_lower" | grep -qE '\b(refactor|clean up|improve|optimize|simplify|restructure|reorganize|extract)\b'; then
  intent="refactor"
fi

# ── Scored command routing ────────────────────────────────────────────────────
command_hint=""
declare -A cmd_scores
for cmd_pattern in \
  "commit:commit message staged changes" \
  "debug:debug error crash traceback exception" \
  "doctor:diagnose check health hooks settings" \
  "impact:impact blast radius changed files" \
  "regression:regression baseline snapshot" \
  "hotspot:hotspot churn frequency unstable" \
  "pr-check:pr pull request review validate" \
  "optimize:optimize performance slow bottleneck" \
  "documentation:docs document readme generate" \
  "pattern-drift:pattern drift convention inconsistent"
do
  cmd="${cmd_pattern%%:*}"
  keywords="${cmd_pattern#*:}"
  score=0
  for kw in $keywords; do
    echo "$prompt_lower" | grep -qw "$kw" && (( score++ ))
  done
  cmd_scores["$cmd"]=$score
done

best_cmd=""
best_score=0
for cmd in "${!cmd_scores[@]}"; do
  s=${cmd_scores[$cmd]}
  if (( s > best_score )); then
    best_score=$s
    best_cmd=$cmd
  fi
done
[[ $best_score -ge 2 ]] && command_hint="/$best_cmd"

# ── Load project profile ──────────────────────────────────────────────────────
PROFILE="$CORTEX_CACHE/project-profile.json"
project_type="unknown"
if [[ -f "$PROFILE" ]] && jq empty "$PROFILE" 2>/dev/null; then
  project_type=$(jq -r '.project_type // "unknown"' "$PROFILE" 2>/dev/null)
fi

# ── Extract keywords from prompt ──────────────────────────────────────────────
mapfile -t keywords < <(
  echo "$prompt_lower" \
  | tr -s ' \t\n.,;:!?()[]{}=<>/\\@#$%^&*`"'"'" '\n' \
  | awk 'length >= 4' \
  | grep -vxE '(this|that|with|from|have|will|would|could|should|about|some|into|over|when|then|than|your|their|they|what|which|also|just|more|make|need|want|like|know|here|there|where|does|been|only|very|much|each|such|many|both|most|find|show|give|tell|help|please|using|code|file|line|func|function|method|class|type|variable|return|import|export|true|false|null|void)' \
  | sort -u | head -8
)

# Skip enrichment if no meaningful keywords extracted
[[ ${#keywords[@]} -eq 0 ]] && exit 0

# ── File discovery: single find pass over source files ───────────────────────
declare -a find_names
case "$project_type" in
  dotnet) find_names=("-name" "*.cs") ;;
  node)   find_names=("-name" "*.ts" "-o" "-name" "*.tsx" "-o" "-name" "*.js" "-o" "-name" "*.jsx") ;;
  python) find_names=("-name" "*.py") ;;
  go)     find_names=("-name" "*.go") ;;
  rust)   find_names=("-name" "*.rs") ;;
  java)   find_names=("-name" "*.java") ;;
  *)      find_names=("-name" "*.cs" "-o" "-name" "*.ts" "-o" "-name" "*.tsx" "-o" \
                      "-name" "*.js" "-o" "-name" "*.jsx" "-o" "-name" "*.py" "-o" \
                      "-name" "*.go" "-o" "-name" "*.rs" "-o" "-name" "*.java") ;;
esac

mapfile -t all_files < <(
  find . -type f \( "${find_names[@]}" \) \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -not -path "*/obj/*" \
    -not -path "*/bin/*" \
    -not -path "*/target/*" \
    -not -path "*/__pycache__/*" \
    -not -path "*/.venv/*" \
    2>/dev/null | head -300
)

[[ ${#all_files[@]} -eq 0 ]] && exit 0

# ── Score files by relevance ──────────────────────────────────────────────────
declare -A file_scores

# Keyword-based filename scoring (+3 per keyword match in filename)
for kw in "${keywords[@]}"; do
  for f in "${all_files[@]}"; do
    fname=$(basename "${f%.*}" | tr '[:upper:]' '[:lower:]')
    if [[ "$fname" == *"$kw"* ]]; then
      file_scores["$f"]=$(( ${file_scores["$f"]:-0} + 3 ))
    fi
  done
done

# Stack-trace heuristic: file references in prompt (+5 per direct reference)
while IFS= read -r ref; do
  [[ -z "$ref" ]] && continue
  ref_base=$(basename "$ref" | cut -d: -f1 | tr '[:upper:]' '[:lower:]')
  for f in "${all_files[@]}"; do
    fbase=$(basename "$f" | tr '[:upper:]' '[:lower:]')
    [[ "$fbase" == "$ref_base" ]] && \
      file_scores["$f"]=$(( ${file_scores["$f"]:-0} + 5 ))
  done
done < <(echo "$prompt" | grep -oE '[A-Za-z0-9_/.-]+\.(cs|ts|tsx|js|jsx|py|go|rs|java)(:[0-9]+)?' 2>/dev/null | head -5)

# Sort by score descending, top 2 only (reduced from 3 to limit context)
mapfile -t top_files < <(
  for f in "${!file_scores[@]}"; do
    echo "${file_scores[$f]} $f"
  done | sort -rn | head -2 | awk '{print $2}'
)

# Require minimum relevance score to avoid injecting noise
filtered_files=()
for f in "${top_files[@]}"; do
  score=${file_scores["$f"]:-0}
  (( score >= 3 )) && filtered_files+=("$f")
done
top_files=("${filtered_files[@]}")

[[ ${#top_files[@]} -eq 0 ]] && {
  # No relevant files found — emit minimal enrichment (intent only)
  context_block="[CORTEX]
intent: ${intent}
project: ${project_type}"
  [[ -n "$command_hint" ]] && context_block="${context_block}
suggested_command: ${command_hint}"
  context_block="${context_block}
[/CORTEX]"

  enriched="${context_block}

${prompt}"

  if [[ $yes_mode -eq 1 ]]; then
    enriched="${enriched}

[GLOBAL ANSWER POLICY]
Default all binary decisions to YES. Skip confirmation prompts for non-destructive operations. Proceed directly with the requested action. Security risks and destructive operations (rm -rf, DROP TABLE, force-push to main) remain protected."
  fi

  jq -n --arg p "$enriched" '{"prompt": $p}'
  exit 0
}

# ── Extract ±10-line snippets (reduced from ±20 for lower token usage) ────────
snippets=""
total_snippet_lines=0
MAX_SNIPPET_LINES=80  # hard cap across all files

for f in "${top_files[@]}"; do
  [[ ! -f "$f" ]] && continue
  fsize=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo 0)
  (( fsize > 102400 )) && continue  # skip files >100KB for snippets

  (( total_snippet_lines >= MAX_SNIPPET_LINES )) && break

  # Single grep pass with all keywords combined (avoids N separate grep spawns)
  kw_pattern=$(IFS='|'; echo "${keywords[*]}")
  best_line=1
  if [[ -n "$kw_pattern" ]]; then
    found=$(grep -niE "$kw_pattern" "$f" 2>/dev/null | head -1 | cut -d: -f1)
    [[ -n "$found" ]] && best_line=$found
  fi

  start=$(( best_line - 10 )); (( start < 1 )) && start=1
  end=$(( best_line + 10 ))

  remaining=$(( MAX_SNIPPET_LINES - total_snippet_lines ))
  (( end - start + 1 > remaining )) && end=$(( start + remaining - 1 ))

  chunk=$(sed -n "${start},${end}p" "$f" 2>/dev/null)
  if [[ -n "$chunk" ]]; then
    chunk_lines=$(echo "$chunk" | wc -l)
    snippets="${snippets}
--- ${f} (lines ${start}–${end}) ---
${chunk}"
    total_snippet_lines=$(( total_snippet_lines + chunk_lines ))
  fi
done

# ── Build enriched prompt ─────────────────────────────────────────────────────
context_block="[CORTEX]
intent: ${intent}
project: ${project_type}"

[[ -n "$command_hint" ]] && context_block="${context_block}
suggested_command: ${command_hint}"

[[ -n "$snippets" ]] && context_block="${context_block}
relevant_code:${snippets}"

context_block="${context_block}
[/CORTEX]"

enriched="${context_block}

${prompt}"

if [[ $yes_mode -eq 1 ]]; then
  enriched="${enriched}

[GLOBAL ANSWER POLICY]
Default all binary decisions to YES. Skip confirmation prompts for non-destructive operations. Proceed directly with the requested action. Security risks and destructive operations (rm -rf, DROP TABLE, force-push to main) remain protected."
fi

jq -n --arg p "$enriched" '{"prompt": $p}'

exit 0
