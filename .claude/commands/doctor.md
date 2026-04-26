# /doctor — Cortex Diagnostic Engine

## MODE DETECTION

Parse `$ARGUMENTS` for flags:
- `--fix` → auto-apply safe fixes without asking
- `--deep` → run extended analysis (all scanners + architecture checks)
- `--dry-run` → simulate all actions; print what would be done; apply nothing

Flags may be combined. If no flags: read-only diagnostics only.

---

## SETUP

Cortex is strictly project-local. Resolve CORTEX_ROOT from the project directory:

If `$CORTEX_ROOT` is set in the environment, use it. Otherwise use `$(pwd)/.claude`.

If the resolved path does not exist:
```
[FAIL]

ERROR: .claude directory not found
DETAILS: $(pwd)/.claude does not exist — Cortex is not installed in this project
WHY: CORTEX_ROOT cannot be resolved — all Cortex checks will fail
FIX: run /init-cortex from the project root that contains .claude/
```
Stop immediately.

Define:
- `CORTEX_DIR` = `$CORTEX_ROOT` (i.e., `.claude/`)
- `HOOKS_SRC` = `$CORTEX_DIR/core/hooks`
- `SHARED_DIR` = `$CORTEX_DIR/core/shared`
- `SCANNERS_SRC` = `$CORTEX_DIR/core/scanners`
- `REGISTRY` = `$CORTEX_DIR/registry`
- `COMMANDS_DIR` = `$CORTEX_DIR/commands`

There is no global `~/.claude/hooks/` directory. All hooks run directly from `$HOOKS_SRC/`.

Collect all issues into a list. Track the highest severity seen (PASS → WARN → FAIL).

---

## PHASE 1 — CORTEX SYSTEM DIAGNOSTICS

### CHECK 1 — Folder structure

Verify each required path exists:

| Path | Required |
|---|---|
| `$CORTEX_DIR/core/` | YES |
| `$CORTEX_DIR/core/hooks/` | YES |
| `$CORTEX_DIR/core/hooks/guards/` | YES |
| `$CORTEX_DIR/core/hooks/runtime/` | YES |
| `$CORTEX_DIR/core/shared/bootstrap.sh` | YES |
| `$CORTEX_DIR/core/scanners/` | YES |
| `$CORTEX_DIR/registry/` | YES |
| `$CORTEX_DIR/config/` | YES |
| `$COMMANDS_DIR` | YES |

For each missing path:
```
TYPE: ERROR
TITLE: Required path missing
DETAILS: <path> does not exist
WHY: Cortex cannot load hooks, scanners, or commands without this path
FIX: run /init-cortex to restore the Cortex directory structure
```

### CHECK 2 — commands.json

Read `$REGISTRY/commands.json`.

If missing:
```
TYPE: ERROR
TITLE: commands.json not found
DETAILS: $REGISTRY/commands.json does not exist
WHY: command registry is required to validate command availability
FIX: restore commands.json from the Cortex source repository
```

For each command name in the `commands` array, check `$COMMANDS_DIR/<name>.md` exists.
If missing:
```
TYPE: ERROR
TITLE: Command file missing: <name>
DETAILS: $COMMANDS_DIR/<name>.md is listed in commands.json but does not exist on disk
WHY: /<name> cannot be invoked — the command runner will exit non-zero
FIX: create $COMMANDS_DIR/<name>.md with the command implementation
```

### CHECK 3 — hooks.json

Read `$REGISTRY/hooks.json`.

If missing:
```
TYPE: ERROR
TITLE: hooks.json not found
DETAILS: $REGISTRY/hooks.json does not exist
WHY: hook registry is required for version validation
FIX: restore hooks.json from the Cortex source repository
```

For each entry in hooks.json:

a. Check `source` and `version` fields exist. If either is absent:
```
TYPE: ERROR
TITLE: Malformed hooks.json entry: <key>
DETAILS: entry is missing the '<field>' field
WHY: /init-cortex cannot validate this hook without a valid source path and version
FIX: add missing '<field>' field to the <key> entry in hooks.json
```

b. Check `$CORTEX_DIR/<source>` exists. If not:
```
TYPE: ERROR
TITLE: Hook source file missing: <key>
DETAILS: $CORTEX_DIR/<source> does not exist on disk
WHY: hook cannot fire — Claude Code will invoke a missing script
FIX: restore <source> from the Cortex repository
```

c. Verify the hook sources bootstrap.sh on its first executable line:
```bash
source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0
```
If the hook still contains an inline `if [ -z "$CORTEX_ROOT" ]` block:
```
TYPE: WARNING
TITLE: Hook not using bootstrap: <key>
DETAILS: <hook-name> has an inline CORTEX_ROOT block instead of sourcing bootstrap.sh
WHY: bootstrap.sh is the single source of truth for path resolution and validation
FIX: replace the inline block with: source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0
```

### CHECK 4 — scanners.json

Read `$REGISTRY/scanners.json`.

If missing:
```
TYPE: ERROR
TITLE: scanners.json not found
DETAILS: $REGISTRY/scanners.json does not exist
WHY: post-scan.sh and post-format.sh are registry-driven and cannot dispatch without this file
FIX: restore scanners.json from the Cortex source repository
```

For each extension key (excluding `*`) and each scanner path in its array, check `$CORTEX_DIR/core/scanners/<path>` exists.
If missing:
```
TYPE: WARNING
TITLE: Scanner file missing: <path>
DETAILS: <path> is mapped in scanners.json but $CORTEX_DIR/core/scanners/<path> does not exist
WHY: files with extension <ext> will not be scanned — security issues may go undetected
FIX: create the scanner script at $CORTEX_DIR/core/scanners/<path> or remove the mapping from scanners.json
```

### CHECK 5 — Hook version validation

For each hook in hooks.json:

a. Read the source file at `$CORTEX_DIR/<source>`. Locate `^# @version:` (line 1 or 2). Extract the version. If absent, treat as `0.0.0`:
```
TYPE: WARNING
TITLE: Hook missing version tag: <hook-name>
DETAILS: $CORTEX_DIR/<source> has no '# @version: X.Y.Z' line
WHY: /init-cortex cannot perform version-aware tracking
FIX: add '# @version: X.Y.Z' on line 2 of <source>
```

b. Compare the source `# @version:` against the version in hooks.json:
- source > registry:
```
TYPE: WARNING
TITLE: Hook version not synced in registry: <hook-name>
DETAILS: source version <src_ver> is newer than registry version <reg_ver>
WHY: /init-cortex version checks will be inaccurate — the hook may appear current when it isn't
FIX: update hooks.json version for <hook-name> to <src_ver>
```
- source < registry:
```
TYPE: WARNING
TITLE: Registry version ahead of source: <hook-name>
DETAILS: registry version <reg_ver> is newer than source file version <src_ver>
WHY: registry may reflect intended version before source was updated
FIX: bump the # @version: tag in $CORTEX_DIR/<source> to match hooks.json
```

c. Check `stop-build.sh` exists at `$HOOKS_SRC/runtime/stop-build.sh`:
```
TYPE: ERROR
TITLE: stop-build.sh missing
DETAILS: $HOOKS_SRC/runtime/stop-build.sh does not exist
WHY: the Stop hook will fail silently — build errors will not be reported after session end
FIX: restore stop-build.sh from the Cortex source repository
```

### CHECK 6 — settings.json wiring

Read `$CORTEX_DIR/settings.json`.

If missing:
```
TYPE: ERROR
TITLE: settings.json not found
DETAILS: $CORTEX_DIR/settings.json does not exist
WHY: no hooks are wired to Claude Code events — the entire Cortex runtime is inactive
FIX: restore settings.json from the Cortex source repository
```

For each hook name in hooks.json, verify a `command` entry exists in the hooks block whose path follows the project-local pattern:
```
bash ${CORTEX_ROOT:-$(pwd)/.claude}/core/hooks/<guards|runtime>/<hook-name>
```

If any entry uses `~/.claude/hooks/` (the old global model):
```
TYPE: ERROR
TITLE: Stale global path in settings.json: <hook-name>
DETAILS: settings.json entry for <hook-name> references ~/.claude/hooks/ — the old global-install path
WHY: Cortex is now strictly project-local; the global path no longer exists
FIX: replace the path with: bash ${CORTEX_ROOT:-$(pwd)/.claude}/core/hooks/<subdir>/<hook-name>
```

If an entry is missing entirely:
```
TYPE: ERROR
TITLE: Hook not wired: <hook-name>
DETAILS: settings.json has no command entry for <hook-name>
WHY: <hook-name> will never fire — its guarded events have no protection
FIX: add: bash ${CORTEX_ROOT:-$(pwd)/.claude}/core/hooks/<subdir>/<hook-name>
```

Check the Stop hook entry points to `$HOOKS_SRC/runtime/stop-build.sh` via the `${CORTEX_ROOT:-...}` pattern.

---

## PHASE 2 — PROJECT CODE DIAGNOSTICS

### Identify project type

Inspect the working directory (NOT `.claude/`, `.git/`).

- `.sln` or `*.csproj` present → .NET
- `package.json` present → Node/React
- Both → mixed
- Neither → generic (shell scripts, config, markdown)

### Select files to scan

.NET: `*.cs`, `*.csproj`
Node/React: `*.ts`, `*.tsx`, `*.js`, `*.jsx`
Generic: `*.sh`, `*.json`

Skip: `node_modules/`, `bin/`, `obj/`, `dist/`, `*.lock`, `*.log`, `*.min.js`, `*.map`, `.claude/`, `.git/`

In `--deep` mode: also scan `*.json` (non-lock), `*.yaml`, `*.yml`, `*.env`.

Use Glob to discover candidate files. Read only files needed to perform the checks below. Do not read files speculatively.

### Code checks

For every file read, perform these checks. Only report issues you can confirm from the file content — do not guess.

**Syntax / Runtime Risk**
- Calling methods on a value that may be null/undefined without a null guard
- Incorrect async/await usage: missing `await` on async call, unhandled promise rejection
- Variables used before declaration
- Wrong argument count/type for known APIs

**Logical Bugs**
- Conditions that are always true or always false
- Empty catch blocks (swallowing exceptions silently)
- Return paths that produce unexpected `undefined` or `null`
- Dead code after `return` or `throw`
- Missing `break` in switch/case where clearly unintentional

**Security Issues**
- Hardcoded credentials, API keys, tokens, connection strings
- Raw SQL string concatenation with a variable (`"SELECT * FROM ... " + userInput`)
- `eval()` or `innerHTML` with dynamic content
- Shell exec / `Process.Start` with unsanitized input
- Sensitive values written to logs

**Code Quality** (only flag if it represents a real risk)
- Functions exceeding ~80 lines with no decomposition
- Empty catch blocks that only log (error swallowed, caller not notified)
- Obvious copy-paste duplication in critical logic paths

**Architecture** (`--deep` only)
- Direct database/repository access from a controller or UI component
- Missing validation on any public API input parameter
- Cross-layer dependency violations (UI importing data-access types directly)

For each issue found:
```
TYPE: ERROR | WARNING | INFO
TITLE: <short description>
DETAILS: <file>:<line> — <what exactly is wrong>
WHY: <technical reason this is a problem>
FIX: <exact, single change to resolve this>
```

---

## OUTPUT

### Header

Print overall status based on highest severity found:
- Any ERROR → `[FAIL]`
- Any WARNING, no ERROR → `[WARN]`
- No issues → `[PASS]`

Then print all collected issues in order: ERRORs first, then WARNINGs, then INFOs.

Format each issue as:
```
TYPE: ERROR | WARNING | INFO
TITLE: <title>
DETAILS: <details>
WHY: <why>
FIX: <fix>
```

Then print the summary box:
```
╔══════════════════════════════════════╗
║         DOCTOR REPORT SUMMARY        ║
╠══════════════════════════════════════╣
║  CORTEX:  PASS | WARN | FAIL         ║
║  PROJECT: PASS | WARN | FAIL         ║
╠══════════════════════════════════════╣
║  Cortex issues:  <n>                 ║
║  Project issues: <n>                 ║
║  Total:          <n>                 ║
╚══════════════════════════════════════╝
```

---

## FIX MODE

If `--fix` was provided:

For each fixable issue (those whose FIX is deterministic and safe):
- Missing runtime directories → `mkdir -p <dir>`
- Stale `~/.claude/hooks/` path in settings.json → apply Edit to correct the path to the project-local form
- Missing executable permissions → `chmod +x <file>`

If `--dry-run` is also present: print the proposed changes as diffs but apply nothing.

If `--dry-run` is NOT present: apply fixes immediately, then print:
```
Fixed: <brief description of what was changed>
```

Do NOT auto-fix:
- Code issues in project files (these require human review)
- Registry corrections that require structural changes
- Anything that modifies `.claude/local/`

Do NOT ask the user for permission before fixing. Apply deterministic fixes silently.
