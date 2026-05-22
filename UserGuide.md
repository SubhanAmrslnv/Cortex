# Cortex User Guide

Cortex is a hook-driven runtime that runs alongside [Claude Code](https://claude.ai/code) inside each project's `.claude/` directory. It gives you a live status dashboard, automatic risk scoring on shell commands, async file scanning, lazy memory retrieval, and a small set of slash commands. Nothing runs at session startup — every feature is on-demand.

This guide explains:

1. The dashboard rendered under the chatbox — element by element.
2. The slash commands you can type in Claude Code.
3. What runs automatically when you edit files or run commands.
4. Common diagnostics and where to look when something feels off.

For full installation details, see `INSTALL.md`. For architecture, see `README.md`. For the rules Claude Code itself follows in this repo, see `CLAUDE.md`.

---

## 0. Quick install

Run from the project root where you want `.claude/` to land. Requires git 2.27+.

**Bash (Linux / macOS / Git Bash):**
```bash
git clone --depth 1 --filter=blob:none --sparse --branch main \
  https://github.com/SubhanAmrslnv/Cortex.git .cortex-tmp
git -C .cortex-tmp sparse-checkout set .claude
cp -R .cortex-tmp/.claude .
rm -rf .cortex-tmp
```

**PowerShell (Windows):**
```powershell
git clone --depth 1 --filter=blob:none --sparse --branch main https://github.com/SubhanAmrslnv/Cortex.git .cortex-tmp
git -C .cortex-tmp sparse-checkout set .claude
Copy-Item .cortex-tmp/.claude . -Recurse -Force
Remove-Item .cortex-tmp -Recurse -Force
```

Re-run to update — the manual clone overwrites `.claude/` wholesale, so back up user-local state under `cache/`, `logs/`, `temp/`, `state/`, and `project/memory/` first.

---

## 1. The Status Line — element by element

Every turn, a multi-line dashboard renders under the chatbox. It is a live snapshot of `.claude/` state — nothing is cached, nothing is faked.

```
Cortex v4.1.1 │ Claude │ ⏱ 0s
  ─────────────────────────────────────────────────────
  🪝 Hooks 28/28    📜 Commands 2/2    🔎 Scanners 14    🛡️ Risk 30/70
  💾 Memory 8KB    📨 Events 0    📂 Indexed 0    📑 Audit 512    🧠 Context 4%
  📊 Tests 12 (~84 cases)    🗂️ Plans 3    🌿 feat/x +2 ~5
```

### Header line

| Element | What it shows | When to look at it |
|---|---|---|
| `Cortex v4.1.1` | Framework version, read from `.claude/config/cortex.config.json → version`. | Confirms which Cortex release is installed. After a re-run of the installer, this is the first thing to verify. |
| `Claude` (or `Opus 4.7`, `Sonnet 4.6`, …) | The model Claude Code is currently using. Read from the per-turn session JSON. | When you want to confirm what tier you're on — pairs with the advisory model router (see §5). |
| `⏱ 0s` | Wall-clock time elapsed on the current turn. | If a single turn takes long, this tells you whether the slowness is in the model or in Cortex's own hooks. |

### Row 1 — registry health

| Element | What it shows | When to look at it |
|---|---|---|
| `🪝 Hooks X/28` | `X` = framework scripts in `.claude/registry/hooks.json` that exist on disk. `28` is the registered total. | If `X < 28`, the on-disk install drifted from the registry. Re-run the installer to repair. |
| `📜 Commands X/2` | `X` = slash-command markdown files in `.claude/commands/` that match `.claude/registry/commands.json`. | If `X < 2`, `debug.md` or `commit.md` is missing. Re-run the installer. |
| `🔎 Scanners 14` | Count of unique scanner scripts in `.claude/registry/scanners.json`. | Confirms language scanners (JS, TS, Python, C#, Go, …) are registered. Drops only if you delete from the registry. |
| `🛡️ Risk 30/70` | The `warn` and `block` thresholds from `cortex.config.json → riskThresholds`. | Reminder of where the pre-tool guard draws its lines. Change the thresholds in config, not in scripts. |

### Row 2 — workload state

| Element | What it shows | When to look at it |
|---|---|---|
| `💾 Memory 8KB` | Total disk size of `.claude/project/memory/` (`du -sk`). Holds saved plans, debug findings, lazy module summaries. | A steadily growing number is healthy. If memory bloats unexpectedly, prune with `bash .claude/core/memory/plans.sh prune <days>`. |
| `📨 Events 0` | Number of pending events queued under `.claude/temp/events/`. | Should drop to `0` between turns. If it stays at `3+`, the dispatcher is failing silently — check `.claude/logs/`. |
| `📂 Indexed N` | Line count of `.claude/cache/file-index.txt` (the lazy retrieval index). | `0` means no retrieval has happened yet this session. A non-zero number means memory retrieval has warmed the index. |
| `📑 Audit 512` | Line count of `.claude/logs/audit.log`. Hooks append one structured line per important event. | When you want to retrace what Cortex did — `tail -n 50 .claude/logs/audit.log`. |
| `🧠 Context 4%` | Percent of the model's context window used this session. Falls back to `—` during synthetic tests (no `transcript_path`). | If it climbs past ~70%, expect summarisation soon — wrap up the current thread or split into a new session. |

### Row 3 — project signal

| Element | What it shows | When to look at it |
|---|---|---|
| `📊 Tests 12 (~84 cases)` | Test-file count (matches `*.test.*`, `*.spec.*`, `test_*.py`, `*_test.go`, `*Tests.cs`) and an estimated case count (`grep -cE` for `it(`, `def test_`, `[Fact]`, …). | Quick read on test coverage shape. Drops when you delete tests; rises when you add them. |
| `🗂️ Plans 3` | Saved plans under `.claude/project/memory/plans/` — populated automatically when Claude Code writes a plan file. | Confirms plan persistence is working. Inspect with `bash .claude/core/memory/plans.sh list`. |
| `🌿 feat/x +2 ~5` | Current branch, plus `+N` untracked files and `~N` modified tracked files. | A glance at git state without leaving the chat. Replaces "wait, did I commit that?". |

### Reading the colours

- **Green** — healthy state.
- **Yellow** — non-zero pending work (e.g. `📨 Events 3` between turns, modified files in git).
- **Orange / red** — drift or trouble (e.g. `🪝 Hooks 12/28`, audit log unusually large).
- **Dim grey (`—`)** — value not available this turn (typical for `🧠 Context` during the very first message).

### Fallback line

If you see only `│ Cortex │ —` (one short line, no dashboard), Cortex's bootstrap failed for this turn. Common causes:

1. `jq` not on PATH — every hook depends on it.
2. `.claude/` is missing in the current working directory.
3. `CORTEX_ROOT` is set to a stale path.

Diagnose with `bash .claude/core/statusline/render.sh < /dev/null` from a terminal.

---

## 2. Slash Commands

Type these directly in Claude Code's chat:

| Command | What it does |
|---|---|
| `/debug` | Runtime-aware self-healing debugger. Fans out five probes in parallel (listening ports, project logs, build run, test replay, HTTP probe), retrieves relevant memory, and proposes patches in a tight loop. Use this when something is broken and you don't yet know why. |
| `/commit` | Drafts a conventional-commit message from the staged diff and creates the commit. Warns if you're on `main`, `master`, or `develop`. Never adds Claude attribution or emoji. |

The earlier analyzer commands (`/doctor`, `/hotspot`, `/impact`, `/timeline`, `/init-cortex`, `/update-cortex`, etc.) were retired in v4. Their work either folded into `/debug` or moved to the installer CLI (`npx @subhanamrslnv/cortex-cli`).

---

## 3. What runs automatically

You don't invoke these — they fire on Claude Code events.

| When you… | …Cortex runs |
|---|---|
| Submit a prompt | `prompt-router.sh` labels the intent (one of 32 categories) for the advisory model router. The prompt itself is unchanged. |
| Try a `Bash` command | `pre-guard.sh` scores it across 6 risk categories. Risk < 30 = silent allow; 30–69 = allow with a warning; ≥ 70 = block. `rm -rf` and `curl \| sh` block on their own. |
| Get a permission prompt | `permission-request.sh` enriches it with risk reasons and a safer alternative; `permission-denied.sh` proposes a recovery path if you deny. |
| Save a file with `Write` or `Edit` | `bus.sh` publishes a `FileChanged` event. The dispatcher fans subscribers out in parallel: `post-format.sh` (formatter), `post-scan.sh` (CVE / lint / type scan), `plans-watcher.sh` (if the file is `*/plans/*.md`, persist it). |
| Hit a tool error | `post-error-analyzer.sh` classifies it (runtime error, dependency, permission, syntax, build, network, timeout) so Claude Code can react before retrying. |
| End the turn after a build failure | `stop-build.sh` runs once to retry the build. If retry fails, it surfaces — does not loop. |

Important properties:

- **All file scans are async.** Saving a file does not block the chat — events drain in the background. Watch `📨 Events` drop to `0`.
- **No SessionStart hook.** Nothing is profiled when you open Claude Code. Heavy work happens only on demand.

---

## 4. The risk score, explained

`pre-guard.sh` adds points for each pattern it sees in a Bash command:

| Category | Examples | Points |
|---|---|---|
| Catastrophic | `rm -rf`, `curl \| sh`, `wget \| bash` | +70 (blocks alone) |
| Destructive | `drop table`, `git reset --hard`, `git clean -f` | +50 |
| Security | reverse shells, base64-piped exec, known pentest tools | +40 |
| Privileged | `sudo`, writes to `/etc/`, `/usr/`, `/bin/` | +30 |
| Sensitive | reading `.env`, `.pem`, `.key`, `.pfx` files | +25 |
| Dangerous flags | `--force`, `--no-verify` | +20 |
| Branch context | running `git` on `main`/`master`/`develop` | +20 |

The thresholds (`warn 30 / block 70`) are configurable in `.claude/config/cortex.config.json → riskThresholds`. The status-line `🛡️ Risk 30/70` is a live reminder of where the lines are drawn.

---

## 5. The model router (advisory)

`core/router/model-router.sh` suggests a tier (`haiku`, `sonnet`, `opus`) based on the labelled intent:

- **Haiku** — 10 intents like `typo_fix`, `commit_message`, `format_code`, `rename`. Triggered only when the prompt has explicit "trivial / simple / pure / typo / rename" keywords.
- **Sonnet** — 12 intents covering most real dev work: `bug_fix`, `refactor`, `debug`, `feature_small`, `unit_test_complex`, `api_design`, etc. This is the default — Cortex prefers to over-tier rather than under-tier.
- **Opus** — 10 intents: `architecture`, `migration_schema`, `security_review`, `performance_audit`, `incident_rca`, `code_review_deep`, `multi_repo_change`. Needs explicit signals in the prompt.

The router is **advisory**. Your actual active model is whatever you have set in Claude Code (see `/model`). The router just labels what tier the work would ideally use, surfacing under-/over-tiering.

---

## 6. Memory and plans

Cortex remembers across sessions without preloading anything. Two stores:

### Lazy file index
`.claude/cache/file-index.txt` is built **only** when `core/memory/retrieve.sh` is called for the first time, or when it's older than `memory.indexMaxAgeSeconds` (default 1 hour). Retrieval scores files by:

- path keyword hits (+3)
- basename keyword hits (+5)
- intent-layer match (+2)
- recent git changes (+4)

Returns at most 5 files with a 3-line structural summary each. No embeddings, no API calls.

### Saved plans
When Claude Code writes any `*/plans/*.md` file (including the user-global `~/.claude/plans/`), the `FileChanged` event auto-copies it into `.claude/project/memory/plans/<slug>.md` with frontmatter, and updates the `plans.json` index.

Inspect plans manually:

```bash
bash .claude/core/memory/plans.sh list         # newest first
bash .claude/core/memory/plans.sh get <slug>   # print one
bash .claude/core/memory/plans.sh search <q>   # keyword search
bash .claude/core/memory/plans.sh prune 90     # drop plans older than 90 days
```

The `🗂️ Plans` element on the status line is a live count of this directory.

---

## 7. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `│ Cortex │ —` (fallback line, no dashboard) | `jq` missing, wrong `CORTEX_ROOT`, or `.claude/` not in CWD | `bash .claude/core/statusline/render.sh < /dev/null` for a clean error; install `jq` if missing |
| `🪝 Hooks 12/28` (or any `X < 28`) | Registry references scripts not on disk | Re-run the installer; or `git status` to see what's missing |
| `📨 Events 3+` persisting between turns | Dispatcher subscribers erroring and not consuming events | Check `.claude/logs/`, fix the failing subscriber, then `rm .claude/temp/events/*.json` |
| `🧠 Context —` stuck on `—` | Claude Code didn't pass `transcript_path` (synthetic test) | Normal during local script tests; populates in a real session |
| Hook blocked a command you needed | Risk score ≥ 70 | Read the printed `reason` and `suggestion`; restructure the command. Do not bypass with `--no-verify`. |
| A formatter ran when you didn't want it | `post-format.sh` is subscribed to `FileChanged` | Remove it from `.claude/core/events/subscriptions.json → FileChanged` |
| Smoke test fails | Hook contract changed | Run `bash .claude/test/run.sh` — it tells you exactly which assertion failed |

For anything not listed, the audit log (`.claude/logs/audit.log`) and dispatcher logs are the first places to look.

---

## 8. Configuration cheat-sheet

`.claude/config/cortex.config.json`:

| Key | What it controls |
|---|---|
| `version` | The string rendered next to `Cortex` on the status line |
| `riskThresholds.warn` | Below this, commands pass silently |
| `riskThresholds.block` | At/above this, commands are blocked |
| `modelPolicy.default` | Default tier when intent has no specific mapping (recommend `sonnet`) |
| `modelPolicy.intents` | Per-intent tier mapping (32 entries) |
| `eventBus.maxJobs` | Max parallel subscribers per event |
| `planner.maxJobs` | Max parallel tasks in a planner DAG |
| `memory.indexMaxAgeSeconds` | How stale the lazy index can get before rebuild |
| `debug.expectedPorts` | Ports `/debug` checks for listening services |
| `debug.logPaths` | Glob patterns `/debug` tails for runtime errors |

Changes take effect on the next turn — no restart needed.

---

## 9. Recommended MCP servers

Cortex itself does not require MCP servers, but Claude Code can be extended with project-scoped ones via `.claude/.mcp.json`. Register them one at a time from the project root — each command writes a single entry, so each addition is a reviewable diff:

```bash
claude mcp add --scope project filesystem -- npx -y @modelcontextprotocol/server-filesystem "$PWD"
claude mcp add --scope project git        -- npx -y @cyanheads/git-mcp-server
claude mcp add --scope project playwright -- npx -y @playwright/mcp@latest
```

PowerShell users: replace `$PWD` with `(Get-Location).Path`.

After registration, restart Claude Code and run `/mcp` — all three should report `connected`. The first session in a project triggers a one-time trust prompt for the checked-in `.mcp.json`.

### Additional MCP servers

Optional extras. Each needs the listed prerequisite:

```bash
claude mcp add --scope project postgres   -- npx -y @henkey/postgres-mcp-server --connection-string "${CORTEX_PG_URL}"
claude mcp add --scope project figma --env FIGMA_API_KEY="${FIGMA_API_KEY}" -- npx -y figma-developer-mcp --stdio
claude mcp add --scope project docker     -- uvx docker-mcp
```

- **postgres** — `CORTEX_PG_URL` exported before launching Claude Code.
- **figma** — `FIGMA_API_KEY` exported before launching Claude Code.
- **docker** — `uv` on PATH (`winget install astral-sh.uv` or `pip install uv`) and Docker Desktop running.

PowerShell users substitute `${VAR}` with `$env:VAR`.

### Full MCP server list

Copy-paste to wire all six at once:

```bash
claude mcp add --scope project filesystem -- npx -y @modelcontextprotocol/server-filesystem "$PWD"
claude mcp add --scope project git        -- npx -y @cyanheads/git-mcp-server
claude mcp add --scope project playwright -- npx -y @playwright/mcp@latest
claude mcp add --scope project postgres   -- npx -y @henkey/postgres-mcp-server --connection-string "${CORTEX_PG_URL}"
claude mcp add --scope project figma --env FIGMA_API_KEY="${FIGMA_API_KEY}" -- npx -y figma-developer-mcp --stdio
claude mcp add --scope project docker     -- uvx docker-mcp
```

---

## 10. Uninstall

```bash
rm -rf .claude
```

Cortex never writes outside the project directory. There is nothing else to clean up.
