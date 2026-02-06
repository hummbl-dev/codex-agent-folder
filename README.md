# HUMMBL Agent Workspace

**Status:** Option A (Revised) — Agent-Aligned Workspace with Nested Repo  
**Created:** 2026-02-06  
**Agent Count:** 58

## Overview

This is the root workspace for the HUMMBL agent federation. Each CLI tool spawns its named agent identity:

| CLI Tool | Agent Identity | Purpose |
|----------|---------------|---------|
| `kimi` | Kimi 🤖 | Execution, tooling, verification |
| `codex` | Codex 🧭 | Execution, RPBx assignments |
| `claude` | Claude 🎯 | Advisory, summarization, review |

## Quick Start

```bash
# Reload shell config
source ~/.zshrc

# Launch agents
kimi                    # Spawn Kimi agent
codex                   # Spawn Codex agent  
claude                  # Spawn Claude agent

# Check agent context
whoami-kimi             # Display Kimi identity
whoami-codex            # Display Codex identity
whoami-claude           # Display Claude identity

# Federation status
agent-count             # Count agents
agent-list              # List all agents
```

## Repository Structure

```
/Users/others/                    ← This repo (scaffold only)
├── AGENTS.md                     # Canonical agent instructions
├── .gitignore                    # Strict exclusions
├── .REPO_AUTHORIZED              # Conversion marker
├── README.md                     # This file
├── bin/                          # Agent entry scripts
│   ├── kimi-entry.sh
│   ├── codex-entry.sh
│   └── claude-entry.sh
└── shared-hummbl-space/          # NESTED REPO (hummbl-agent)
    ├── .git/                     # Separate git repository
    ├── agents/                   # 58 agent identity stacks
    ├── avatars/                  # PNG assets + GALLERY.md
    ├── memory/                   # Shared daily logs
    └── scripts/                  # Agent tooling

# Symlinks (convenience)
agents → shared-hummbl-space/agents
avatars → shared-hummbl-space/avatars
memory → shared-hummbl-space/memory
scripts → shared-hummbl-space/scripts
```

## Two-Repo Architecture

### Root Repo (`/Users/others`)
- **Purpose:** Your personal workspace scaffold
- **Remote:** (configure as needed)
- **Tracks:** Entry scripts, AGENTS.md, tooling configuration

### Nested Repo (`shared-hummbl-space/`)
- **Purpose:** HUMMBL agent federation content
- **Remote:** `https://github.com/hummbl-dev/shared-hummbl-space.git`
- **Contains:** 58 agents, avatars, shared memory, scripts

## Updating

```bash
# Update agent federation (nested repo)
hummbl-pull

# Or manually:
cd shared-hummbl-space
git pull origin main
```

## Architecture Philosophy

Each CLI tool spawns its named agent identity:

1. **Kimi CLI** launches → Kimi agent (execution, tooling)
2. **Codex CLI** launches → Codex agent (execution, governance)
3. **Claude Code** launches → Claude agent (advisory, review)

Agents have:
- Individual identity stacks (`agents/<name>/IDENTITY.md`)
- Personal memory (`agents/<name>/memory/`)
- Specialized skills and authority boundaries

## Documentation

- `AGENTS.md` — Complete agent instructions and protocols
- `agents/<name>/IDENTITY.md` — Individual agent identity
- `agents/<name>/AGENT.md` — Operational brief

## Authorized By

Reuben Bowlby — 2026-02-06
