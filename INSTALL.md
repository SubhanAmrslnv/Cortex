# Installing Cortex

Cortex is an event-driven, project-local AI runtime framework for [Claude Code](https://claude.ai/code). It lives entirely inside each project's `.claude/` directory — **no global install, no shared state, no startup profiling.** Every project gets its own pinned copy and its own hook, planner, memory, router, and status-line setup.

---

## Prerequisites

| Tool | Required | Why |
|---|---|---|
| `bash` 4+ | yes | All hook scripts and core logic |
| `git` 2.27+ | yes | Sparse clone of `.claude/`; branch protection + status-line metrics |
| `jq` | yes | Every hook parses JSON via `jq`; without it hooks silently no-op at runtime |
| [Claude Code](https://claude.ai/code) | yes | Hook + command runtime |

**Install `jq`** (runtime requirement for hooks, not the installer):
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt install jq

# Windows — Scoop
scoop install jq

# Windows — winget
winget install jqlang.jq
```

Verify: `jq --version` and `git --version`.

On Windows, use **Git Bash** (ships with [Git for Windows](https://git-scm.com/)) or WSL.

---

## Install

Run from the root of the project where you want `.claude/` to land.

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

To pin a different branch, tag, or SHA, change `--branch main` to your target ref.

---

## What the install does

1. **Sparse clone** — `git clone --depth 1 --filter=blob:none --sparse --branch main https://github.com/SubhanAmrslnv/Cortex.git` into `.cortex-tmp`, then `git sparse-checkout set .claude` so only `.claude/` is materialised.
2. **Copy** — `.claude/` from the clone is copied into the target project. Re-running overwrites wholesale, so back up user-local subtrees (`project/memory/`, `cache/`, `logs/`, `temp/`, `state/`) before updating in place.
3. **Local-only directories** — `cache/`, `logs/`, `temp/events/`, `state/`, and `project/memory/plans/` are created on first hook run if they don't already exist.
4. **Executable bits** — on POSIX systems, ensure `chmod +x` on every shell script under `.claude/core/`.

---

## Activate

Once `.claude/` is in place, open Claude Code in the project — there is no separate activation step.

---

## Verify

**Status-line check** — open Claude Code in the project. You should see a five-line block under the chatbox:
```
Cortex v4.0.0 │ Opus 4.7 │ ⏱ 0s
  ─────────────────────────────────────────────────────
  🪝 Hooks 28/28    📜 Commands 4/4    🔎 Scanners 14    🛡️ Risk 30/70
  💾 Memory 17KB    📨 Events 0    📂 Indexed 0    📑 Audit 0    🧠 Context 0%
  📊 Tests 0 (~0 cases)    🗂️ Plans 0    🤖 MCP 0/0    🌿 main clean
```
If you only see a single `│ Cortex │ —` fallback line, something failed bootstrap — most often a missing `jq` or a wrong `CORTEX_ROOT`. Inspect with:
```bash
bash .claude/core/statusline/render.sh < /dev/null
```

**Hook smoke test:**
```bash
bash .claude/test/run.sh
```

---

## Recommended MCP servers

Cortex itself does not require MCP servers, but Claude Code can be wired to project-scoped MCP servers via `.claude/.mcp.json`. Register them one at a time from the project root — each command writes a single entry, so each addition produces a reviewable diff:

```bash
claude mcp add --scope project filesystem -- npx -y @modelcontextprotocol/server-filesystem "$PWD"
claude mcp add --scope project git        -- npx -y @cyanheads/git-mcp-server
claude mcp add --scope project playwright -- npx -y @playwright/mcp@latest
```

PowerShell users: substitute `$PWD` with `(Get-Location).Path`.

After registration, restart Claude Code and run `/mcp` — all three should report `connected`. The first session in a project triggers a one-time trust prompt for the checked-in `.mcp.json`.

### Additional MCP servers

Optional extras. Each requires the listed prerequisite:

```bash
claude mcp add --scope project postgres   -- npx -y @henkey/postgres-mcp-server --connection-string "${CORTEX_PG_URL}"
claude mcp add --scope project figma --env FIGMA_API_KEY="${FIGMA_API_KEY}" -- npx -y figma-developer-mcp --stdio
claude mcp add --scope project docker     -- uvx docker-mcp
```

Prerequisites:

- **postgres** — `CORTEX_PG_URL` exported before launching Claude Code.
- **figma** — `FIGMA_API_KEY` exported before launching Claude Code.
- **docker** — `uv` on PATH (`winget install astral-sh.uv` or `pip install uv`) and Docker Desktop running.

PowerShell users substitute `${VAR}` with `$env:VAR`. Example:

```powershell
[Environment]::SetEnvironmentVariable('CORTEX_PG_URL', 'postgres://user:pass@localhost:5432/your_db', 'User')
[Environment]::SetEnvironmentVariable('FIGMA_API_KEY', 'figd_xxx...', 'User')
```

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

## Update

Re-run the sparse clone — it overwrites `.claude/` wholesale, so back up user-local state under `.claude/cache/`, `.claude/logs/`, `.claude/temp/`, `.claude/state/`, and `.claude/project/memory/` first.

```bash
git clone --depth 1 --filter=blob:none --sparse --branch main \
  https://github.com/SubhanAmrslnv/Cortex.git .cortex-tmp
git -C .cortex-tmp sparse-checkout set .claude
cp -R .cortex-tmp/.claude .
rm -rf .cortex-tmp
```

---

## Uninstall

```bash
rm -rf .claude
```

There is no other state to clean. Cortex never writes outside the project directory.

---

## Configuration

`.claude/config/cortex.config.json` (v4.0.0):
```json
{
  "riskThresholds":  { "warn": 30, "block": 70 },
  "modelPolicy":     { "default": "sonnet", "intents": { ... 32 keys ... } },
  "eventBus":        { "maxJobs": 4 },
  "planner":         { "maxJobs": 4 },
  "memory":          { "indexMaxAgeSeconds": 3600 },
  "debug":           { "expectedPorts": [...], "logPaths": [...] },
  "statusLine":      { "contextWindow": 200000 }
}
```

| Key | Effect |
|---|---|
| `riskThresholds.warn/block` | Pre-tool risk score thresholds (used by `pre-guard.sh`) |
| `modelPolicy.intents` | Per-intent model choice for the router |
| `eventBus.maxJobs` | Max parallel subscribers per event |
| `planner.maxJobs` | Worker-pool concurrency cap |
| `memory.indexMaxAgeSeconds` | Lazy index rebuild interval |
| `debug.expectedPorts` | Ports that `process-inspector.sh` checks |
| `debug.logPaths` | Glob patterns for `log-stream.sh` |
| `statusLine.contextWindow` | Override the 200k/1M auto-detect for context % |

---

## Troubleshooting

**Status line shows `│ Cortex │ —`** — bootstrap failed. Most common causes: `jq` not on PATH (runtime requirement for hooks), or the project moved and `.claude/` wasn't carried over. Inspect with `bash .claude/core/statusline/render.sh < /dev/null`.

**Hooks count low** (e.g. `🪝 Hooks 12/28`) — some script files in the registry don't exist on disk. Re-run the installer to re-fetch.

**Context % stuck at `—`** — Claude Code didn't pass `transcript_path` in the session JSON. This happens during synthetic tests; in a real session it always populates.

**Events count keeps growing** — the dispatcher's subscribers are erroring and never deleting consumed events. Clear with `rm .claude/temp/events/*.json` and check `dispatcher.sh` stderr (write to a file in `.claude/logs/`).

**MSYS / Git Bash CRLF issue** — handled by the renderer (`tr -d '\r'`), but if you write your own hook that reads `jq` output on Windows, strip CR yourself.

**Strict project-local** — Cortex never falls back to `$HOME/.claude/`. If `.claude/` is missing at `$(pwd)`, every hook exits 0 silently. Don't symlink — copy or re-install.

---

## Branch Protection

Cortex's `pre-guard.sh` adds +20 risk for `git push`/`commit` against `main`, `master`, or `develop`. Combined with the default threshold of 70, this won't block a single commit, but it will warn. **Always work on a feature branch and open a PR.**
