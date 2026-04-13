# /update-cortex — Safe Framework Update System

## STEP 1 — Verify .cortex structure

Check that `.cortex/base/` exists in the current working directory.

### Case A — .cortex/base/ does not exist

Clone Cortex into `.cortex/base/`:
```
git clone https://github.com/SubhanAmrslnv/Cortex.git .cortex/base
```

If clone fails:
```
[FAIL]

TYPE: ERROR
TITLE: Clone failed
DETAILS: git clone exited non-zero — remote may be unreachable or URL is incorrect
WHY: cannot update .cortex/base/ without a valid clone
FIX: verify network access and that https://github.com/SubhanAmrslnv/Cortex.git is reachable, then re-run /update-cortex
```
Stop.

Skip to Step 4.

### Case B — .cortex/base/ exists but is NOT a git repository

Auto-recover without prompting the user:

1. Delete `.cortex/base/` (run `rm -rf .cortex/base/`)
2. Print one line: `[AUTO-FIX] .cortex/base/ was not a git repository — deleted and re-cloning…`
3. Clone fresh: `git clone https://github.com/SubhanAmrslnv/Cortex.git .cortex/base`

If clone fails after auto-delete:
```
[FAIL]

TYPE: ERROR
TITLE: Re-clone failed after auto-fix
DETAILS: rm -rf succeeded but git clone exited non-zero
WHY: remote may be unreachable or URL is incorrect
FIX: verify network access and that https://github.com/SubhanAmrslnv/Cortex.git is reachable, then re-run /update-cortex
```
Stop.

Skip to Step 4.

---

## STEP 2 — Fetch remote changes

Inside `.cortex/base/`, run:
```
git fetch origin
```

If fetch fails, auto-recover:

1. Delete `.cortex/base/` (run `rm -rf .cortex/base/`)
2. Print one line: `[AUTO-FIX] git fetch failed — deleted .cortex/base/ and re-cloning…`
3. Clone fresh: `git clone https://github.com/SubhanAmrslnv/Cortex.git .cortex/base`

If clone fails after auto-delete:
```
[FAIL]

TYPE: ERROR
TITLE: Re-clone failed after fetch auto-fix
DETAILS: git fetch failed and re-clone also exited non-zero
WHY: remote may be unreachable, network is down, or URL is incorrect
FIX: verify network access and that https://github.com/SubhanAmrslnv/Cortex.git is reachable, then re-run /update-cortex
```
Stop.

If re-clone succeeds: skip to Step 4 (no diff to show — fresh clone is already up to date).

---

## STEP 3 — Show diff and require confirmation

Run inside `.cortex/base/`: `git diff HEAD origin/main -- .`

If no changes:
```
[PASS]

Already up to date — no changes from remote.
```
Stop.

If there are changes: display the full diff to the user.

Ask exactly:
> "Apply these changes to .cortex/base/? (yes/no)"

Wait for explicit user input. If the answer is anything other than `yes`: stop without modifying any files. Print: `Update cancelled — no changes made.`

---

## STEP 4 — Apply update

Inside `.cortex/base/`, run:
```
git reset --hard origin/main
```

Do NOT touch `.cortex/local/` at any point.
Do NOT overwrite `.claude/` or any other project files outside `.cortex/base/`.

If merge conflicts arise during any git operation: DO NOT auto-resolve. Present the conflicting hunks to the user and wait for explicit instructions. Never pick a side or discard changes without user approval.

---

## STEP 5 — Run /init-cortex automatically

After the base update completes, run `/init-cortex` immediately.

Do NOT ask the user whether to run it — this is mandatory after every update.

---

## STEP 6 — Report

Print the overall status (`[PASS]`, `[WARN]`, or `[FAIL]`) based on the outcome.

Then print:

```
=== UPDATE-CORTEX REPORT ===
Generated: <timestamp>

[BASE]
  Status:        UPDATED | CLONED | NO_CHANGE
  Latest commit: <hash> — <message>

[LOCAL OVERRIDES]
  .cortex/local/ preserved — untouched

[HOOKS REDEPLOYED]
  (output from /init-cortex below)
```

Follow with the full /init-cortex report output.
