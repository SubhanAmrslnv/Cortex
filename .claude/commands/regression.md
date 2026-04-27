# /regression — Cortex Regression Detection Engine

## MODE DETECTION

Parse `$ARGUMENTS` for flags:
- `--save` → after analysis, save current state as the new baseline snapshot
- `--reset` → delete existing snapshot and save current state as a fresh baseline; do not run comparison
- `--since=<ref>` → compare against the snapshot closest to the given git ref instead of the latest snapshot
- `--deep` → run extended /doctor diagnostics (code checks + architecture) when collecting current state

Default (no flags): compare against the latest snapshot without saving.

---

## STEP 1 — Resolve state directory

Define:
- `STATE_DIR` = `.cortex/state/`
- `SNAPSHOT_FILE` = `.cortex/state/snapshot.json`
- `SNAPSHOT_INDEX` = `.cortex/state/index.json`

If `STATE_DIR` does not exist, create it: `mkdir -p .cortex/state`

### `--reset` mode

Delete `SNAPSHOT_FILE` if it exists. Run Steps 2–3 to collect current state. Save as new baseline (Step 5). Print:
```
[PASS]

Baseline reset. Current state saved as new snapshot.
Snapshot: .cortex/state/snapshot.json
Issues captured: <n>
```
Stop — do not run comparison.

---

## STEP 2 — Load previous snapshot

Read `SNAPSHOT_FILE`. It is a JSON object with this schema:
```json
{
  "timestamp": "<ISO 8601>",
  "git_commit": "<sha>",
  "issues": [
    {
      "id": "<fingerprint>",
      "type": "ERROR | WARNING | INFO",
      "title": "<title>",
      "file": "<path or null>",
      "line": "<number or null>",
      "domain": "CORTEX | PROJECT",
      "details": "<details string>"
    }
  ]
}
```

If `SNAPSHOT_FILE` does not exist:
```
[WARN]

TYPE: WARNING
TITLE: No baseline snapshot found
DETAILS: .cortex/state/snapshot.json does not exist
WHY: regression detection requires a previous state to compare against
FIX: run /regression --save to capture the current state as the baseline, then run /regression on future changes
```
Stop.

If `SNAPSHOT_FILE` exists but is not valid JSON:
```
[FAIL]

TYPE: ERROR
TITLE: Snapshot file is corrupt
DETAILS: .cortex/state/snapshot.json cannot be parsed as JSON
WHY: a corrupt snapshot cannot be used for comparison
FIX: run /regression --reset to delete the corrupt snapshot and capture a fresh baseline
```
Stop.

Save the loaded issues as `PREV_ISSUES`. Save `snapshot.git_commit` as `PREV_COMMIT`.

---

## STEP 3 — Collect current state

Run /doctor diagnostics now. Collect all issues it produces (both Phase 1 Cortex checks and Phase 2 project checks).

In `--deep` mode: run /doctor with `--deep` to include architecture validation and additional file types.
In default mode: run /doctor without flags (standard read-only diagnostics).

For each issue produced by /doctor, assign a stable fingerprint `id`:
```
id = "<domain>:<type>:<title>:<file>:<line>"
```
Where:
- `domain` = `CORTEX` if the issue came from Phase 1, `PROJECT` if from Phase 2
- `file` and `line` = empty string if not applicable
- Normalize `title` to lowercase with spaces replaced by underscores

Save all current issues as `CURR_ISSUES`.

Get the current git commit hash: `git rev-parse HEAD` → save as `CURR_COMMIT`.

---

## STEP 4 — Compare snapshots

Compute three sets by matching on `id` (fingerprint):

**NEW_ISSUES**: issues in `CURR_ISSUES` whose `id` is NOT in `PREV_ISSUES`
**RESOLVED_ISSUES**: issues in `PREV_ISSUES` whose `id` is NOT in `CURR_ISSUES`
**CHANGED_ISSUES**: issues present in both sets where `type` (severity) has changed

For `CHANGED_ISSUES`, record the direction:
- `ESCALATED`: severity went from `WARNING → ERROR` or `INFO → WARNING` or `INFO → ERROR`
- `REDUCED`: severity went from `ERROR → WARNING` or `WARNING → INFO`

A regression is any of:
- `NEW_ISSUES` is non-empty
- `CHANGED_ISSUES` contains any `ESCALATED` entries

If no regressions and no changes:
```
[PASS]

No regressions detected.
Compared against snapshot from <timestamp> (commit <short_sha>).
Resolved issues: <n>
Unchanged issues: <n>
```
If `--save` was provided, proceed to Step 5 before stopping.
Stop.

---

## STEP 5 — Root cause analysis and generate WHY and FIX

For each issue in `NEW_ISSUES` and each `ESCALATED` entry in `CHANGED_ISSUES`:

### Map to file changes

If `issue.file` is set:
- Run: `git log --oneline <PREV_COMMIT>..HEAD -- <issue.file>`
- If commits are found: record each commit hash + message as a candidate root cause
- If no commits found: record "no git history for this file between <PREV_COMMIT> and <CURR_COMMIT>"

If `issue.file` is NOT set (system-level Cortex issue):
- Run: `git log --oneline <PREV_COMMIT>..HEAD -- .cortex/ .claude/`
- Record matching commits

### Identify the most specific cause

From the commit list for each issue, select the commit that most directly relates to the issue:
- Prefer commits that modified `issue.file` directly
- If multiple commits touched the file, prefer the most recent
- If no commit maps to the file, note the absence explicitly — do not guess

### Generate WHY and FIX

**WHY**: one technical sentence explaining the causal chain:
- `"<root_commit> modified <root_file>, which introduced <issue.title> at <issue.file>:<issue.line>"`
- If no root commit found: `"<issue.title> appeared between commit <PREV_COMMIT> and <CURR_COMMIT> — no direct file-level git change identified for <issue.file>"`

Do NOT write "possibly" or "may have". If causal evidence is absent, state the absence explicitly.

**FIX**: one deterministic action (same rules as /doctor — single solution, no alternatives):
- For hook version mismatches → `run /init-cortex`
- For missing deployments → `run /init-cortex`
- For new code issues → state the exact file, line, and change required
- For escalated severity → state what changed and what to revert or patch

---

## OUTPUT

Print the overall status:
- Any regression (new ERROR or escalated severity) → `[FAIL]`
- Only new WARNINGs or reduced severity → `[WARN]`
- No regressions → `[PASS]`

Then print:

```
REGRESSION REPORT
Baseline:  <PREV_COMMIT short sha> — <snapshot timestamp>
Current:   <CURR_COMMIT short sha> — <current timestamp>
```

**REGRESSION DETECTED** section (omit if empty):
```
REGRESSION DETECTED:

NEW ISSUES: <n>
  - [<type>] <title>
    File:    <file>:<line>
    Details: <details>
    Commit:  <root_commit sha> — <root_commit message>
    WHY:     <why sentence>
    FIX:     <fix>

ESCALATED ISSUES: <n>
  - [<prev_type> → <curr_type>] <title>
    File:    <file>:<line>
    Details: <details>
    Commit:  <root_commit sha> — <root_commit message>
    WHY:     <why sentence>
    FIX:     <fix>
```

**RESOLVED ISSUES** section (omit if empty):
```
REMOVED ISSUES: <n>
  - [<type>] <title> (was at <file>:<line>)
```

**CHANGED (reduced severity)** section (omit if empty):
```
REDUCED SEVERITY: <n>
  - [<prev_type> → <curr_type>] <title>
```

**Summary**:
```
╔══════════════════════════════════════╗
║      REGRESSION DETECTION SUMMARY    ║
╠══════════════════════════════════════╣
║  Regressions:        <n>             ║
║  Escalated:          <n>             ║
║  Resolved:           <n>             ║
║  Reduced severity:   <n>             ║
║  Unchanged:          <n>             ║
╚══════════════════════════════════════╝
```

---

## STEP 7 — Save snapshot (if --save)

If `--save` flag was provided, write the current state to `SNAPSHOT_FILE`:

```json
{
  "timestamp": "<ISO 8601 current time>",
  "git_commit": "<CURR_COMMIT>",
  "issues": [ <CURR_ISSUES array> ]
}
```

Also append an entry to `SNAPSHOT_INDEX` (create if absent):
```json
[
  {
    "timestamp": "<ISO 8601>",
    "git_commit": "<CURR_COMMIT>",
    "issue_count": <n>,
    "file": "snapshot.json"
  }
]
```

Print after saving:
```
Snapshot saved: .cortex/state/snapshot.json
  Commit:  <CURR_COMMIT short sha>
  Issues:  <n>
```

---

## CONSTRAINTS

- Never report a regression without comparing against real snapshot data
- Never identify a root cause commit without a confirming `git log` result
- Never write "possibly", "may have", or "might" — state findings or state their absence
- Never report `RESOLVED_ISSUES` as regressions
- Never modify `.cortex/local/`
- Issue fingerprints must be stable across runs for the same issue at the same location
