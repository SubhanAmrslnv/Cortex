# /init-cortex — Cortex Environment Setup and Validation

## WINDOWS PATH NOTE

On Windows (Git Bash / MSYS2), `$HOME` and `$(pwd)` expand to Unix-style paths like `/c/Users/...`. Native Windows Python cannot open these paths — it requires `C:/Users/...`.

**Rule**: never pass a bash-expanded path directly to Python's `open()`. Always use bash `[ -f ]` / `[ -d ]` / `cat` for file operations, or convert the path first:

```bash
NATIVE_PATH=$(python3 -c "import os,sys; print(os.path.normpath(sys.argv[1]))" "$THE_PATH")
```

---

## MODE DETECTION

Parse `$ARGUMENTS` for flags:
- `--force` → redeploy ALL hooks regardless of version
- `--dry-run` → simulate all actions; print what would be done; apply nothing

Flags may be combined.

---

## STEP 1 — Resolve CORTEX_ROOT

Cortex is strictly project-local. CORTEX_ROOT always points to the project's own `.claude/` directory.

If `$CORTEX_ROOT` is already set in the environment, use it. Otherwise set it to `$(pwd)/.claude`.

If the resolved path does not exist:
```
[FAIL]

TYPE: ERROR
TITLE: .claude directory not found
DETAILS: $(pwd)/.claude does not exist
WHY: /init-cortex must run from inside a Cortex-enabled project directory
FIX: cd to the project root that contains .claude/ and re-run /init-cortex
```
Stop.

There is no global install, no `~/.claude/cortex.env`, and no `~/.claude/hooks/` directory. All hooks run directly from `$CORTEX_ROOT/core/hooks/`.

---

## STEP 2 — Validate directory structure

Verify each required path exists under `$CORTEX_ROOT`:

| Path | Required |
|---|---|
| `$CORTEX_ROOT/core/hooks/guards/` | YES |
| `$CORTEX_ROOT/core/hooks/runtime/` | YES |
| `$CORTEX_ROOT/core/shared/bootstrap.sh` | YES |
| `$CORTEX_ROOT/core/scanners/` | YES |
| `$CORTEX_ROOT/registry/` | YES |
| `$CORTEX_ROOT/config/` | YES |

Ensure runtime directories exist (create if missing and not `--dry-run`):
- `$CORTEX_ROOT/cache/scans/`
- `$CORTEX_ROOT/logs/`
- `$CORTEX_ROOT/temp/`
- `$CORTEX_ROOT/state/`

For each missing required directory:
```
TYPE: ERROR
TITLE: Required directory missing: <path>
DETAILS: <path> does not exist
WHY: Cortex cannot load hooks, scanners, or commands without this directory
FIX: restore the directory from the Cortex source repository
```

---

## STEP 3 — Registry version validation

Read `$CORTEX_ROOT/registry/hooks.json`.

If missing:
```
[FAIL]

TYPE: ERROR
TITLE: hooks.json not found
DETAILS: $CORTEX_ROOT/registry/hooks.json does not exist
WHY: hook registry is required to validate hook versions
FIX: restore hooks.json from the Cortex source repository
```
Stop.

For each entry (hook name + `source` path + `version`):

a. Resolve source: `$CORTEX_ROOT/<source>`
b. Extract source version from `# @version: X.Y.Z` on line 1 or 2. If absent, treat as `0.0.0`.
c. Compare source version against the version declared in hooks.json:

**`--force` mode**: always report as UPDATED regardless.

**Normal mode**:
- source version > registry version → WARN (source was updated but registry not synced)
- source version == registry version → OK
- source version < registry version → WARN (registry ahead of source — possible edit without version bump)

Record each hook as: `OK` | `WARNING`

Since hooks run directly from `$CORTEX_ROOT/core/hooks/` there is no deployment step. The registry is used only for version tracking and `/doctor` validation.

---

## STEP 4 — Validate settings.json wiring

Read `$CORTEX_ROOT/settings.json`.

If missing:
```
TYPE: ERROR
TITLE: settings.json not found
DETAILS: $CORTEX_ROOT/settings.json does not exist
WHY: no hooks are wired to Claude Code events — the entire Cortex runtime is inactive
FIX: restore settings.json from the Cortex source repository
```

For each hook name in hooks.json, verify a `command` entry whose path contains `core/hooks/` and the hook filename exists in the hooks block.

Hook paths in settings.json must use the form:
```
${CORTEX_ROOT:-$(pwd)/.claude}/core/hooks/<guards|runtime>/<hook-name>
```

No hook entry should reference `~/.claude/hooks/` — that is the old global model.

For each absent or incorrectly-pathed entry:
```
TYPE: ERROR
TITLE: Hook not wired: <hook-name>
DETAILS: settings.json has no command entry for <hook-name> using the project-local path pattern
WHY: <hook-name> will never fire — its guarded events have no protection
FIX: add the wiring entry using: bash ${CORTEX_ROOT:-$(pwd)/.claude}/core/hooks/<subdir>/<hook-name>
```

---

## STEP 5 — Validate command registry

Read `$CORTEX_ROOT/registry/commands.json`.

For each name in `commands`, check `$CORTEX_ROOT/commands/<name>.md` exists.

Record each as `OK` or `ERROR`.

---

## STEP 6 — Validate scanner availability

Read `$CORTEX_ROOT/registry/scanners.json`.

For each extension key (excluding `*`), for each scanner path in its array, check `$CORTEX_ROOT/core/scanners/<path>` exists using bash `[ -f ]`.

Record each as `OK` or `WARNING (missing)`.

---

## STEP 7 — Validate hook registry consistency

For each hook in hooks.json, verify the version in hooks.json matches the `# @version:` tag in the source file.

If mismatched:
```
TYPE: WARNING
TITLE: Registry version mismatch: <hook-name>
DETAILS: hooks.json declares <registry_ver> but source file contains <source_ver>
WHY: version tracking is inaccurate — /doctor version checks will be unreliable
FIX: update the version field for <hook-name> in hooks.json to match the source file
```

Also verify each hook sources bootstrap.sh, not an inline CORTEX_ROOT block:
```bash
source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0
```

If a hook still has the old inline `if [ -z "$CORTEX_ROOT" ]` block:
```
TYPE: WARNING
TITLE: Hook not using bootstrap: <hook-name>
DETAILS: <hook-name> has an inline CORTEX_ROOT resolution block instead of sourcing bootstrap.sh
WHY: bootstrap.sh is the single source of truth — inline blocks will diverge
FIX: replace the inline block with: source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0
```

---

## OUTPUT

Print the overall status (`[PASS]`, `[WARN]`, or `[FAIL]`) based on highest severity found.

Then print the structured report:

```
=== CORTEX INIT REPORT ===
Mode: <default | --force | --dry-run | --force --dry-run>
Generated: <timestamp>

[CORTEX_ROOT]
  Path:       <resolved path>
  Model:      project-local (no global install)

[STRUCTURE]
  <path>    OK | CREATED | MISSING
  ...

[HOOKS]
  <hook-name>    OK | WARNING    source: <ver> registry: <ver>
  ...

[SETTINGS]
  $CORTEX_ROOT/settings.json    OK | MISSING | INCOMPLETE
  <if INCOMPLETE: list each missing hook entry>

[COMMANDS]
  <command>    OK | ERROR
  ...

[SCANNERS]
  <ext>/<scanner>    OK | WARNING
  ...

[REGISTRY CONSISTENCY]
  <hook-name>    OK | WARNING <detail>
  ...

STATUS: PASS | WARN | FAIL
```

For each issue, also print in structured format:
```
TYPE: ERROR | WARNING
TITLE: <title>
DETAILS: <details>
WHY: <why>
FIX: <fix>
```
