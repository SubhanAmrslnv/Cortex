#!/usr/bin/env bash
# @version: 1.6.0
# UserPromptSubmit structured prompt engine — detects intent, scores command routing,
# finds relevant files via keyword + stack-trace heuristics (single find pass),
# extracts ±20-line snippets, loads project profile, outputs enriched prompt.
# --y suffix: strip flag, inject GLOBAL ANSWER POLICY (YES-default).
# Reads payload JSON from stdin. Outputs {"prompt": "..."} or exits 0 to pass through.

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

prompt=$(echo "$input" | jq -r '.prompt // empty' 2>/dev/null)
[[ -z "$prompt" ]] && exit 0

# ── --y flag handling ─────────────────────────────────────────────────────
yes_mode=0
if [[ "$prompt" =~ (^|[[:space:]])--y([[:space:]]|$) || "$prompt" == *" --y" || "$prompt" == "--y" ]]; then
  yes_mode=1
  prompt=$(echo "$prompt" | sed 's/[[:space:]]*--y[[:space:]]*$//' | sed 's/[[:space:]]*--y[[:space:]]/ /g' | xargs)
fi

# ── Intent detection ──────────────────────────────────────────────────────
prompt_lower=$(echo "$prompt" | tr '[:upper:]' '[:lower:]')
intent="question"

if echo "$prompt_lower" | grep -qE '\b(fix|bug|error|issue|broken|crash|fail|exception|traceback|stacktrace|undefined|null)\b'; then
  intent="bug_fix"
elif echo "$prompt_lower" | grep -qE '\b(add|implement|create|build|develop|new feature|integrate|write)\b'; then
  intent="feature_request"
elif echo "$prompt_lower" | grep -qE '\b(refactor|clean up|improve|optimize|simplify|restructure|reorganize|extract)\b'; then
  intent="refactor"
fi

# ── Scored command routing ────────────────────────────────────────────────
# Score the prompt against known Cortex commands; emit hint if confident.
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

# ── Load project profile ──────────────────────────────────────────────────
PROFILE="$CORTEX_ROOT/cache/project-profile.json"
project_type="unknown"
if [[ -f "$PROFILE" ]]; then
  project_type=$(jq -r '.project_type // "unknown"' "$PROFILE" 2>/dev/null)
fi

# ── Extract keywords from prompt ──────────────────────────────────────────
mapfile -t keywords < <(
  echo "$prompt_lower" \
  | tr -s ' \t\n.,;:!?()[]{}=<>/\\@#$%^&*`"'"'" '\n' \
  | awk 'length >= 4' \
  | grep -vxE '(this|that|with|from|have|will|would|could|should|about|some|into|over|when|then|than|your|their|they|what|which|also|just|more|make|need|want|like|know|here|there|where|does|been|only|very|much|each|such|many|both|most|find|show|give|tell|help|please|using|code|file|line|func|function|method|class|type|variable|return|import|export|true|false|null|void)' \
  | sort -u | head -10
)

# ── File discovery: single find pass over source files ───────────────────
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
    2>/dev/null | head -500
)

# ── Score files by relevance ──────────────────────────────────────────────
declare -A file_scores

# Keyword-based filename scoring
for kw in "${keywords[@]}"; do
  [[ ${#kw} -lt 4 ]] && continue
  for f in "${all_files[@]}"; do
    fname=$(basename "${f%.*}" | tr '[:upper:]' '[:lower:]')
    if [[ "$fname" == *"$kw"* ]]; then
      file_scores["$f"]=$(( ${file_scores["$f"]:-0} + 3 ))
    fi
  done
done

# Stack-trace heuristic: file references in prompt (name.ext or name.ext:line)
while IFS= read -r ref; do
  [[ -z "$ref" ]] && continue
  ref_base=$(basename "$ref" | cut -d: -f1 | tr '[:upper:]' '[:lower:]')
  for f in "${all_files[@]}"; do
    fbase=$(basename "$f" | tr '[:upper:]' '[:lower:]')
    [[ "$fbase" == "$ref_base" ]] && \
      file_scores["$f"]=$(( ${file_scores["$f"]:-0} + 5 ))
  done
done < <(echo "$prompt" | grep -oE '[A-Za-z0-9_/.-]+\.(cs|ts|tsx|js|jsx|py|go|rs|java)(:[0-9]+)?' 2>/dev/null | head -10)

# Sort by score, top 3
mapfile -t top_files < <(
  for f in "${!file_scores[@]}"; do
    echo "${file_scores[$f]} $f"
  done | sort -rn | head -3 | awk '{print $2}'
)

# ── Extract ±20-line snippets ─────────────────────────────────────────────
snippets=""
for f in "${top_files[@]}"; do
  [[ ! -f "$f" ]] && continue
  fsize=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo 0)
  (( fsize > 102400 )) && continue

  best_line=1
  for kw in "${keywords[@]}"; do
    [[ ${#kw} -lt 4 ]] && continue
    found=$(grep -ni "$kw" "$f" 2>/dev/null | head -1 | cut -d: -f1)
    [[ -n "$found" ]] && best_line=$found && break
  done

  start=$(( best_line - 20 )); (( start < 1 )) && start=1
  end=$(( best_line + 20 ))

  chunk=$(sed -n "${start},${end}p" "$f" 2>/dev/null)
  [[ -n "$chunk" ]] && snippets="${snippets}
--- ${f} (lines ${start}–${end}) ---
${chunk}"
done

# ── Build enriched prompt ─────────────────────────────────────────────────
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
