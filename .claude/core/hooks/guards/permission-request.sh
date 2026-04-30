#!/usr/bin/env bash
# @version: 1.3.0
# PermissionRequest hook — analyzes a pending tool execution and outputs a
# structured explanation so the user can make an informed approval decision.
# Never blocks (always exits 0); only enriches the approval prompt.

source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0

input=$(cat)
tool=$(echo "$input" | jq -r '.tool_name // empty' 2>/dev/null)
cmd=$(echo "$input"  | jq -r '.command // empty'   2>/dev/null)

# Fallback: TOOL_NAME env var set by Claude Code
[[ -z "$tool" ]] && tool="${TOOL_NAME:-Bash}"
[[ -z "$cmd"  ]] && exit 0

# ---------------------------------------------------------------------------
# 1. Intent classification
# ---------------------------------------------------------------------------
intent="unknown"

if grep -qiE '(^|\s)(rm|mkdir|cp|mv|touch|cat|ls|find|chmod|chown|ln|tar|zip|unzip|rsync|scp)(\s|$)' <<< "$cmd"; then
  intent="file_operation"
fi
if grep -qE '(^|\s)git(\s|$)' <<< "$cmd"; then
  intent="git_operation"
fi
if grep -qiE '(^|\s)(curl|wget|ssh|nc|ncat|ping|nmap|ftp|sftp|telnet|openssl\s+s_client)(\s|$)' <<< "$cmd"; then
  intent="network_operation"
fi
if grep -qiE '(^|\s)(sudo|su\s|chmod|chown|systemctl|service|mount|umount|iptables|useradd|groupadd|passwd)(\s|$)|(/etc/|/sys/|/proc/|/dev/)' <<< "$cmd"; then
  intent="system_operation"
fi
# system_operation takes precedence over git
if grep -qiE '(^|\s)sudo(\s|$)' <<< "$cmd"; then
  intent="system_operation"
fi

# ---------------------------------------------------------------------------
# 2. Explanation
# ---------------------------------------------------------------------------
explanation=""
case "$intent" in
  file_operation)
    if grep -qiE '(^|\s)rm(\s|$)' <<< "$cmd"; then
      explanation="This command removes files or directories from the filesystem."
    elif grep -qiE '(^|\s)(cp|mv)(\s|$)' <<< "$cmd"; then
      explanation="This command copies or moves files, potentially overwriting existing data."
    elif grep -qiE '(^|\s)chmod(\s|$)' <<< "$cmd"; then
      explanation="This command changes file permissions."
    else
      explanation="This command performs a file system operation (read, write, or modify files)."
    fi
    ;;
  git_operation)
    if grep -qE 'git\s+push' <<< "$cmd"; then
      explanation="This command pushes local commits to a remote repository."
    elif grep -qE 'git\s+(reset|revert|clean)' <<< "$cmd"; then
      explanation="This command modifies or discards git history and working tree state."
    elif grep -qE 'git\s+(merge|rebase)' <<< "$cmd"; then
      explanation="This command integrates changes from one branch into another."
    else
      explanation="This command performs a git version-control operation."
    fi
    ;;
  network_operation)
    if grep -qiE '(curl|wget).*\|\s*(bash|sh|python|node)' <<< "$cmd"; then
      explanation="This command downloads a remote script and executes it immediately."
    elif grep -qiE '(^|\s)(curl|wget)(\s|$)' <<< "$cmd"; then
      explanation="This command fetches data from a remote URL."
    elif grep -qiE '(^|\s)ssh(\s|$)' <<< "$cmd"; then
      explanation="This command opens a remote shell session on another machine."
    else
      explanation="This command initiates network communication with an external host."
    fi
    ;;
  system_operation)
    if grep -qiE '(^|\s)sudo(\s|$)' <<< "$cmd"; then
      explanation="This command runs an operation with elevated (administrator) privileges."
    elif grep -qiE '(^|\s)systemctl(\s|$)' <<< "$cmd"; then
      explanation="This command controls a system service (start, stop, restart, or enable)."
    else
      explanation="This command modifies system-level configuration or permissions."
    fi
    ;;
  *)
    explanation="This command performs an operation whose full effect could not be determined automatically."
    ;;
esac

# ---------------------------------------------------------------------------
# 3. Risk detection — build a JSON array of risk strings
# ---------------------------------------------------------------------------
risks=()

# Destructive
grep -qiE '(^|\s)rm\s+-[a-z]*r[a-z]*f|rm\s+-[a-z]*f[a-z]*r' <<< "$cmd" && \
  risks+=("destructive: permanently removes files without confirmation")
grep -qE 'git\s+reset\s+--hard' <<< "$cmd" && \
  risks+=("destructive: discards uncommitted changes and rewrites HEAD")
grep -qE 'git\s+clean\s+-[a-z]*f' <<< "$cmd" && \
  risks+=("destructive: permanently deletes untracked files")
grep -qiE '\b(drop\s+table|truncate\s+table)\b' <<< "$cmd" && \
  risks+=("destructive: removes all rows or an entire database table")

# Privilege escalation
grep -qiE '(^|\s)sudo(\s|$)' <<< "$cmd" && \
  risks+=("privilege escalation: executes with root-level permissions")
grep -qiE '(^|\s)su(\s|$)' <<< "$cmd" && \
  risks+=("privilege escalation: switches to another user account")

# Remote execution
grep -qiE '(curl|wget).*\|\s*(bash|sh|zsh|python|node|ruby|perl)' <<< "$cmd" && \
  risks+=("remote execution: runs untrusted code fetched from the internet")
grep -qiE '(base64\s+-d|base64\s+--decode).*\|\s*(bash|sh)' <<< "$cmd" && \
  risks+=("remote execution: decodes and runs obfuscated command payload")

# Sensitive data
grep -qiE '\.(env|pem|key|pfx|p12|cer|pkcs12)(\s|"|$)' <<< "$cmd" && \
  risks+=("sensitive data: accesses credential or private key files")
grep -qiE '\$(AWS_|GITHUB_TOKEN|PASSWORD|SECRET|TOKEN|API_KEY)' <<< "$cmd" && \
  risks+=("sensitive data: references secrets or API tokens")

# Force flags
grep -qE '\s--force(\s|$)' <<< "$cmd" && \
  risks+=("data loss: --force may overwrite or destroy remote state")
grep -qE '\s--no-verify(\s|$)' <<< "$cmd" && \
  risks+=("integrity: --no-verify skips safety hooks and pre-commit checks")

# Build risks JSON array
risks_json=$(printf '%s\n' "${risks[@]}" | jq -R . | jq -s . 2>/dev/null)
[[ -z "$risks_json" || "$risks_json" == "null" ]] && risks_json='[]'

# ---------------------------------------------------------------------------
# 4. Safer alternatives
# ---------------------------------------------------------------------------
suggestion=""

grep -qiE 'rm\s+-[a-z]*r[a-z]*f' <<< "$cmd" && \
  suggestion="Replace 'rm -rf' with 'rm -ri' to confirm each deletion interactively"

grep -qE 'git\s+push.*--force(\s|$)' <<< "$cmd" && \
  suggestion="Use 'git push --force-with-lease' to avoid overwriting commits others have pushed"

grep -qE 'git\s+reset\s+--hard' <<< "$cmd" && \
  suggestion="Use 'git stash' to save changes before resetting, or 'git reset --soft' to preserve them staged"

grep -qE 'git\s+clean\s+-[a-z]*f' <<< "$cmd" && \
  suggestion="Run 'git clean -n' first to preview which files would be removed"

grep -qiE '(curl|wget).*\|\s*(bash|sh|zsh|python|node)' <<< "$cmd" && \
  suggestion="Download the script first ('curl -O url'), inspect its contents, then execute it"

grep -qiE '(^|\s)sudo(\s|$)' <<< "$cmd" && \
  suggestion="Verify whether elevated privileges are truly required; prefer scoped tools or user-space alternatives"

grep -qE '\s--no-verify(\s|$)' <<< "$cmd" && \
  suggestion="Fix the failing hook instead of bypassing it with --no-verify"

[[ -z "$suggestion" ]] && suggestion="null"

# ---------------------------------------------------------------------------
# 5. Output — requires confirmation always (this hook only informs)
# ---------------------------------------------------------------------------
jq -n \
  --arg  intent               "$intent" \
  --arg  explanation          "$explanation" \
  --argjson risks             "$risks_json" \
  --argjson suggestion        "$([[ $suggestion == null ]] && echo null || echo "\"$suggestion\"")" \
  --argjson requiresConfirmation true \
  '{
    intent:               $intent,
    explanation:          $explanation,
    risks:                $risks,
    suggestion:           $suggestion,
    requiresConfirmation: $requiresConfirmation
  }'

exit 0
