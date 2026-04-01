# Cortex — Claude Code Global Configuration

Version-controlled global configuration for [Claude Code](https://claude.ai/code).
Covers security guards, auto-formatting, audit logging, and behavior rules for .NET (C#), TypeScript, React, and React Native projects.

---

## New Machine Setup

```bash
git clone https://github.com/SubhanAmrslnv/Cortex.git ~/.claude/Cortex
```

Then open Claude Code in this directory and run:

```
/init
```

`/init` verifies all hooks, scripts, and settings are wired correctly — run it whenever you set up a new machine or after pulling updates.

See [INSTALL.md](./INSTALL.md) for full prerequisites (Git, jq, Node.js, .NET SDK).

---

## What's Inside

### Hooks

| Event | Script | What it does |
|---|---|---|
| PreToolUse (Bash) | `pre-guard.sh` | Blocks 18 categories of dangerous commands before they run |
| PostToolUse (Write\|Edit) | `post-format.sh` | Auto-formats `.cs`, `.ts`, `.html`, `.scss` on save |
| PostToolUse (Write\|Edit) | `post-secret-scan.sh` | Warns on hardcoded secrets in any file |
| PostToolUse (Write\|Edit) | `post-dotnet-security-scan.sh` | Warns on unsafe .NET APIs in `.cs` files |
| PostToolUse (Write\|Edit) | `post-react-security-scan.sh` | Warns on XSS patterns in `.ts/.tsx/.js/.jsx` |
| PostToolUse (Write\|Edit\|Bash) | `post-audit-log.sh` | Appends every tool use to `~/.claude/audit.log` |
| Stop | `stop-build-and-fix.sh` | Builds project; on failure calls Claude Haiku to fix and retries |
| Stop | `stop-git-autocommit.sh` | Auto-generates a conventional commit message from diff stats |

### Security Guards (`pre-guard.sh`)

- Dangerous commands: `rm -rf`, `drop table`, `truncate`, `--force`
- Force-push or direct commit to `main`/`master`
- Non-conventional commit message format
- Staging secret files (`.env`, `.key`, `.pem`, `.pfx`)
- Destructive git ops (`reset --hard`, `clean -f`)
- Files >1MB staged (excludes binaries/assets)
- SQL injection patterns in CLI args
- Writes to system directories (`/etc`, `/usr`, `/bin`)
- `sudo` usage
- Known exploit tools (`sqlmap`, `nmap`, `hydra`, `hashcat`, etc.)
- Reverse shells, base64 execution, cron persistence, curl-pipe-to-shell

---

## Deploying Hook Changes

Hook scripts live in `.claude/hooks/` (source) and must be synced to `~/.claude/hooks/` (runtime):

```bash
cp .claude/hooks/*.sh ~/.claude/hooks/
```

Run this after any hook edit, or run `/init` to do it automatically.

---

## Requirements

| Tool | Purpose |
|---|---|
| [Git](https://git-scm.com/download/win) | Version control |
| [jq](https://jqlang.github.io/jq/download/) | JSON parsing in hook scripts |
| [Node.js](https://nodejs.org) | Prettier, ESLint |
| [.NET SDK](https://dotnet.microsoft.com/download) | `dotnet format`, `dotnet build` |
| [Claude Code](https://claude.ai/code) | `npm install -g @anthropic-ai/claude-code` |

---

## Custom Commands

| Command | Description |
|---|---|
| `/init` | Verify and restore all hooks, scripts, and settings on a new machine |
