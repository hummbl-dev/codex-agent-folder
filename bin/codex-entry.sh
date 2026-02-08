#!/bin/bash
# Codex CLI Entry Point
# Launches codex with Codex agent identity context

export AGENT_NAME="codex"
export AGENT_HOME="$HOME/workspace/agents/codex"
export AGENT_IDENTITY="$AGENT_HOME/IDENTITY.md"
export AGENT_MEMORY="$AGENT_HOME/memory"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BIN_DIR="${ROOT_DIR}/bin"
GH_PREFLIGHT_SCRIPT="${BIN_DIR}/gh-auth-preflight.sh"

# Prevent env-token override of keyring auth in this session.
unset GH_TOKEN GITHUB_TOKEN

# Ensure gh wrapper hardening is active in this shell lineage.
case ":$PATH:" in
  *":${BIN_DIR}:"*) ;;
  *) export PATH="${BIN_DIR}:$PATH" ;;
esac

# Display boot sequence
cat << 'EOF'
🧭 Codex Agent Boot Sequence
============================
Loading identity from: workspace/agents/codex/
Palette: compass/grid governance
Purpose: Execution agent, RPBx assignments
Status: v0.0.1 approved
EOF

# Change to home directory and spawn codex
cd "$HOME" || exit 1

# Log GitHub auth preflight state without blocking startup.
if [ -x "$GH_PREFLIGHT_SCRIPT" ]; then
    "$GH_PREFLIGHT_SCRIPT" warn || true
fi

# Check if codex is available
if command -v codex &> /dev/null; then
    codex "$@"
else
    echo "Error: codex not found. Install with: npm install -g @openai/codex"
    exit 1
fi
