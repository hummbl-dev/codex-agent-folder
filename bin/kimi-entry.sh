#!/bin/bash
# Kimi CLI Entry Point
# Launches kimi-cli with Kimi agent identity context

export AGENT_NAME="kimi"
export AGENT_HOME="$HOME/workspace/agents/kimi"
export AGENT_IDENTITY="$AGENT_HOME/IDENTITY.md"
export AGENT_MEMORY="$AGENT_HOME/memory"

# Display boot sequence
cat << 'EOF'
🤖 Kimi Agent Boot Sequence
===========================
Loading identity from: workspace/agents/kimi/
Palette: steel/orange execution
Purpose: Tooling, verification, implementation
Status: v0.0.1 approved
EOF

# Change to home directory and spawn kimi-cli
cd "$HOME" || exit 1

# Check if kimi-cli is available
if command -v kimi-cli &> /dev/null; then
    kimi-cli "$@"
elif command -v kimi &> /dev/null; then
    kimi "$@"
else
    echo "Error: kimi-cli not found. Install with: brew install kimi-cli"
    exit 1
fi
