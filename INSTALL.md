# Cortex Install Guide

## Prerequisites

| Tool | Required | Purpose |
|---|---|---|
| [Claude Code](https://claude.ai/code) | Yes | Runs hooks and commands |
| `bash` 4.0+ | Yes | All hook scripts |
| `jq` | Yes | JSON parsing in every hook |
| `node` 16+ | Yes | `post-code-intel.sh` code intelligence hook |
| `git` | Yes | Branch detection, commit command |

Install `jq` on Windows:

```bash
# Scoop (recommended)
scoop install jq

# winget
winget install jqlang.jq

# Chocolatey
choco install jq
```

Verify: `jq --version` — expected: `jq-1.7.x` or later.

---

## Installation

Copy two folders into your Windows user directory. That's it.

**1. Copy `.cortex` to your user directory:**

```
C:\Users\subhan.amiraslanov\.cortex\
```

**2. Copy `.claude` to your user directory:**

```
C:\Users\subhan.amiraslanov\.claude\
```

Both folders sit directly under `C:\Users\<your-username>\` — not inside any project, not inside any subfolder.

**3. Open any project in Claude Code and run:**

```
/init-cortex
```

This deploys hooks, validates the registry, and confirms the setup is wired correctly. Run it once per project on first use.

**4. Verify the install:**

```
/doctor
```

All hooks, commands, and scanners should report as active.

---

## How it works

Cortex resolves its runtime path automatically. When no project-local `.cortex/` folder is present, it falls back to `$HOME/.cortex` — which on Windows maps to `C:\Users\<username>\.cortex`.

No environment variables. No configuration. No per-project copies of the framework.

The `.claude/` folder wires Cortex into Claude Code by providing `settings.json` (hook bindings) and thin command wrappers. It contains no framework logic — everything runs from `.cortex`.

---

## Summary

Copy `.cortex` and `.claude` into `C:\Users\<username>\`, then run `/init-cortex` once in each project. Every project on the machine is covered from that single install.
