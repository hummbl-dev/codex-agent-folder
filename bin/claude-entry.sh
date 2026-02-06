#!/bin/bash
# Claude Code Entry Point
# Launches Claude Code with Claude agent identity context

export AGENT_NAME="claude"
export AGENT_HOME="$HOME/workspace/agents/claude"
export AGENT_IDENTITY="$AGENT_HOME/IDENTITY.md"
export AGENT_MEMORY="$AGENT_HOME/memory"

# Display boot sequence
cat << 'EOF'
🎯 Claude Agent Boot Sequence
=============================
Loading identity from: workspace/agents/claude/
Palette: target/synthesis motif
Purpose: Advisory, summarization, review
Status: v0.0.1 approved
EOF

# Change to home directory and spawn claude
cd "$HOME" || exit 1

# Check if claude is available
if command -v claude &> /dev/null; then
    claude "$@"
else
    echo "Error: claude not found. Install with: npm install -g @anthropic-ai/claude-code"
    exit 1
fi
