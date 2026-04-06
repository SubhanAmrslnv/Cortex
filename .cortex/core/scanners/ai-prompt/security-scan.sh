#!/usr/bin/env bash
# @version: 1.0.0
# Scans .prompt/.claude files for prompt injection patterns, system prompt leakage,
# excessive repetition, and hardcoded secrets embedded in prompts.
# Usage: security-scan.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.prompt && $file != *.claude ]] && exit 0

if grep -qiE '(ignore previous instructions|disregard (all |your )?previous|you are now|act as if|jailbreak|forget (all |your )?(previous |prior )?instructions)' "$file"; then
  echo "[WARNING] prompt injection pattern in $file — potential adversarial prompt detected"
fi

if grep -qiE '(reveal (your |the )?(system |initial )?prompt|print (your |the )?(system |initial )?prompt|show (your |the )?instructions)' "$file"; then
  echo "[WARNING] system prompt leakage pattern in $file — user may be attempting to extract instructions"
fi

if grep -qiE '(api_key|token|secret|password)\s*[:=]\s*[A-Za-z0-9+/]{8,}' "$file"; then
  echo "[WARNING] possible hardcoded secret in prompt file $file — remove credentials from prompts"
fi

# Check for excessive word repetition (any single word >10 occurrences)
most_repeated=$(tr -s '[:space:]' '\n' < "$file" | sort | uniq -c | sort -rn | head -1 | awk '{print $1}')
if [[ "$most_repeated" -gt 10 ]]; then
  echo "[WARNING] excessive word repetition in $file — possible repetition attack pattern"
fi

exit 0
