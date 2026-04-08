# /commit — Safe Intelligent Commit Creation

## STEP 1 — Detect current branch

Run: `git rev-parse --abbrev-ref HEAD`

Save as `CURRENT_BRANCH`.

---

## STEP 2 — Check for changes

Run: `git status --short`

If working tree is clean and nothing staged:
```
[PASS]

Nothing to commit — working tree is clean.
```
Stop.

---

## STEP 3 — Run lightweight Cortex diagnostics

Before staging or committing anything, run a reduced /doctor check covering only Cortex system integrity (Phase 1 only). Do NOT run project code diagnostics here.

Perform:
- hooks.json readable
- All hooks deployed (each `~/.cortex/core/hooks/<path>` exists)
- All hook files are executable (`-x` permission)
- All hook versions match (source == runtime)
- settings.json exists and all hook paths resolve

Collect any issues. If any ERROR is found:
```
[FAIL]

TYPE: ERROR
TITLE: Cortex system integrity check failed
DETAILS: <specific hook, path, or permission issue>
WHY: committing with a broken Cortex configuration may bypass security scanning or formatting
FIX: run /init-cortex
```
Stop. Do not proceed to commit.

---

## STEP 4 — Stage changed files

Run both of the following to capture modified and new untracked files:
```
git add -u
git add .
```

Then guard against an empty index:

Run: `git diff --cached --quiet`

If exit code is 0 (nothing staged):
```
[PASS]

No changes staged after add — nothing to commit.
```
Stop.

---

## STEP 5 — Sensitive file detection

Run: `git diff --cached --name-only`

If any staged file matches `\.env$|\.pem$|\.key$|\.pfx$|\.p12$|id_rsa|credentials`:
```
[FAIL]

TYPE: ERROR
TITLE: Sensitive file detected in staged changes
DETAILS: <matching filename(s)>
WHY: committing credentials or private keys permanently embeds them in git history — even a later revert does not remove them
FIX: unstage the file with `git reset HEAD <file>` and add it to .gitignore
```
Stop. Do not proceed to commit.

---

## STEP 6 — Risk / impact assessment

Run the following to collect staging metrics:
```
git diff --cached --name-status
git diff --cached --name-only
```

Compute:
- `TOTAL_FILES` — total number of staged files
- `HAS_SCHEMA` — any staged file matches `\.sql$|migration|schema`
- `HAS_CONFIG` — any staged file matches `package\.json|\.yml$|\.yaml$|\.json$|\.config\.|\.env\.|settings`
- `HAS_TESTS` — any staged file path contains `test` or `spec`
- `HAS_NEW` — any line in name-status starts with `A`
- `HAS_DELETED` — any line in name-status starts with `D`

If `TOTAL_FILES > 20`:
```
[WARN]

Large commit detected (TOTAL_FILES files staged).
WHY: high file count increases blast radius and regression risk — consider splitting into focused commits.
```
Continue (do not stop — this is a warning only).

If `HAS_SCHEMA` is true:
```
[WARN]

Schema or migration file detected in staged changes.
WHY: database schema changes are irreversible in most environments — verify migration is safe before proceeding.
```
Continue.

---

## STEP 7 — Run formatters and security scanners

Get the staged file list: `git diff --cached --name-only`

Pass **all staged files at once** to each applicable scanner (do not loop file by file):

**Formatters**: for each extension that has a `format.sh` entry in `~/.cortex/registry/scanners.json`, invoke the formatter once passing all matching staged files as arguments. If a formatter exits non-zero:
```
[FAIL]

TYPE: ERROR
TITLE: Formatter failed: <file>
DETAILS: <formatter script> exited non-zero for <file>
WHY: committing unformatted code violates project style rules
FIX: inspect formatter output, fix formatting in <file>, then re-run /commit
```
Stop.

**Security scanners**: invoke `generic/secret-scan.sh` once with all staged files. Then invoke any extension-specific `security-scan.sh` entries, each called once with all matching files. If any scanner finds issues:
```
[FAIL]

TYPE: ERROR
TITLE: Security scan failed: <file>
DETAILS: <scanner> detected <finding> in <file>
WHY: committing vulnerable code propagates risk into git history
FIX: resolve <finding> in <file> (line <n>), then re-run /commit
```
Stop.

If no staged files match any scanner, skip silently.

---

## STEP 8 — Branch routing

### CASE A — Protected branch (main, master, develop)

Ask the user:
> "You are on a protected branch (`<CURRENT_BRANCH>`). Enter a new branch name:"

Wait for explicit user input. Do NOT auto-generate a branch name.

Then ask:
> "Enter the commit subject line:"

Wait for explicit user input. Do NOT proceed until provided.

Then ask:
> "Enter a short description (optional — press Enter to skip):"

Wait for user input.

Once all inputs are provided:
1. Run: `git checkout -b <branch-name>`
2. Print: `Branch '<branch-name>' created.`
3. Proceed to Step 9 using user-provided subject and description.

### CASE B — Safe branch

Generate a conventional commit message automatically from the staged diff.

Run: `git diff --cached` and `git diff --cached --stat`

**Derive commit type** using semantic signals (evaluate in order):

| Priority | Condition | Type |
|---|---|---|
| 1 | `HAS_TESTS > 0` | `test` |
| 2 | `HAS_NEW > 0` AND content adds exported functions/classes | `feat` |
| 3 | diff content matches `fix\|bug\|error\|crash\|null\|undefined` | `fix` |
| 4 | `HAS_CONFIG > 0` AND no logic changes | `chore` |
| 5 | only whitespace/formatting changes | `style` |
| 6 | only `.md` / doc files | `docs` |
| 7 | performance-focused change | `perf` |
| 8 | default | `refactor` |

**Derive scope** — find the dominant top-level directory:

Run:
```
git diff --cached --name-only | awk -F/ '{print $1}' | sort | uniq -c | sort -nr | head -1 | awk '{print $2}'
```

Use the result as scope. If the result is a file (no `/` in path), use its basename without extension.

**Generate subject**: `<type>(<scope>): <summary>`
- Summary must reflect the actual diff — no vague words like "update", "changes", "fix stuff"
- 72 characters max
- No trailing period
- No Claude attribution, no emoji

**Validate subject** before proceeding:
- Must match: `^(feat|fix|refactor|docs|chore|style|test|perf)\([^)]+\): .{1,50}$`
- Must not exceed 72 characters total
- If either check fails, regenerate once. If it still fails, fall back to CASE A (ask user).

**Generate description** (body): 2–5 bullet points using `-`
- Each bullet is one concrete fact from the diff
- State what changed and why
- No vague filler, no Claude attribution
- Append metadata line: `affects: <TOTAL_FILES> file(s) on <CURRENT_BRANCH>`

**Preview**:
```
Generated commit:
  Subject:     <subject>
  Description:
    - <bullet 1>
    - <bullet 2>
    ...
    affects: <N> file(s) on <branch>
```

Ask the user:
> "Proceed with this commit? (y/n)"

Wait for explicit input. If `n` or anything other than `y`:
```
[PASS]

Commit cancelled by user.
```
Stop.

Proceed to Step 9 with generated subject and description.

---

## STEP 9 — Commit

Run:
```
git commit -m "<subject>" -m "<description bullets joined with newlines>"
```

On success:
```
[PASS]

Commit created on '<branch>' — <subject>
```

On failure, print the git error verbatim and stop.
