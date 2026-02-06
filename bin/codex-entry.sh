#!/bin/bash
# Codex CLI Entry Point
# Launches codex with Codex agent identity context

export AGENT_NAME="codex"
export AGENT_HOME="$HOME/workspace/agents/codex"
export AGENT_IDENTITY="$AGENT_HOME/IDENTITY.md"
export AGENT_MEMORY="$AGENT_HOME/memory"

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

# Check if codex is available
if command -v codex &> /dev/null; then
    codex "$@"
else
    echo "Error: codex not found. Install with: npm install -g @openai/codex"
    exit 1
fi
