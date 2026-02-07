#!/usr/bin/env bash
# lint-prompt-hardening.sh — Validate prompt hardening compliance across agents and commands
# Safe to run without network or mutation. Exit 0 = compliant, exit 1 = findings.
set -euo pipefail

AGENTS_DIR="workspace/agents"
CLAUDE_AGENTS_DIR=".claude/agents"
COMMANDS_DIR=".claude/commands"
RUNNERS_DIR="workspace/active/hummbl-agent/packages/runners"
PREAMBLE_FILE="$RUNNERS_DIR/UNIVERSAL_HARDENING_PREAMBLE.md"
FINDINGS=0

echo "=== Prompt Hardening Lint (9 Laws) ==="
echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# --- Preamble Verification ---
echo "--- Universal Preamble ---"
preamble_ok=true
if [[ -f "$PREAMBLE_FILE" ]]; then
    echo "  Preamble exists: $PREAMBLE_FILE"
    preamble_lines=$(wc -l < "$PREAMBLE_FILE" | tr -d ' ')
    echo "  Preamble size: ${preamble_lines} lines"
else
    echo "  MISSING PREAMBLE: $PREAMBLE_FILE"
    FINDINGS=$((FINDINGS + 1))
    preamble_ok=false
fi

# Check all make-prompt.sh files reference the preamble
runner_count=0
runner_pass=0
for runner_dir in "$RUNNERS_DIR"/*/; do
    make_prompt="$runner_dir/scripts/make-prompt.sh"
    [[ -f "$make_prompt" ]] || continue
    runner=$(basename "$runner_dir")
    runner_count=$((runner_count + 1))
    if grep -q 'UNIVERSAL_HARDENING_PREAMBLE' "$make_prompt"; then
        runner_pass=$((runner_pass + 1))
    else
        echo "  NO PREAMBLE INJECTION: $runner/scripts/make-prompt.sh"
        FINDINGS=$((FINDINGS + 1))
    fi
done
echo "  Runners with preamble injection: $runner_pass/$runner_count"
echo ""

# --- Law 1: Constrain by Negation ---
echo "--- Law 1: Negation Constraints ---"
agent_count=0
negation_pass=0
negation_info=0
for agent_dir in "$AGENTS_DIR"/*/; do
    agent=$(basename "$agent_dir")
    agent_md="$agent_dir/AGENT.md"
    agent_count=$((agent_count + 1))
    if [[ -f "$agent_md" ]]; then
        if grep -qiE '(DO NOT|MUST NOT|may NOT|NEVER)' "$agent_md"; then
            negation_pass=$((negation_pass + 1))
        else
            negation_info=$((negation_info + 1))
            if $preamble_ok; then
                : # Preamble covers universal constraints; suppress per-agent finding
            else
                echo "  MISSING NEGATION: $agent/AGENT.md"
                FINDINGS=$((FINDINGS + 1))
            fi
        fi
    fi
done
echo "  Agents with per-agent negation: $negation_pass/$agent_count"
if $preamble_ok && [[ $negation_info -gt 0 ]]; then
    echo "  Preamble covers universal constraints for remaining $negation_info agents"
fi
echo ""

# --- Law 3: Enforce Format with Schema ---
echo "--- Law 3: Output Format in Commands ---"
cmd_count=0
format_pass=0
for cmd_file in "$COMMANDS_DIR"/*.md; do
    [[ -f "$cmd_file" ]] || continue
    cmd=$(basename "$cmd_file")
    cmd_count=$((cmd_count + 1))
    if grep -qiE '## Output( Format)?' "$cmd_file"; then
        format_pass=$((format_pass + 1))
    else
        echo "  NO OUTPUT FORMAT: $cmd"
        FINDINGS=$((FINDINGS + 1))
    fi
done
echo "  Commands with output format: $format_pass/$cmd_count"
echo ""

# --- Law 5: Untrusted Content Handling ---
echo "--- Law 5: Untrusted Content Handling ---"
specialist_count=0
untrusted_pass=0
for specialist_file in "$CLAUDE_AGENTS_DIR"/*.md; do
    [[ -f "$specialist_file" ]] || continue
    specialist=$(basename "$specialist_file")
    specialist_count=$((specialist_count + 1))
    if grep -qiE '(untrusted|injection|DO NOT follow|content boundary|Law 5: N/A)' "$specialist_file"; then
        untrusted_pass=$((untrusted_pass + 1))
    else
        echo "  NO LAW 5 COVERAGE: $specialist"
        FINDINGS=$((FINDINGS + 1))
    fi
done
echo "  Specialists with untrusted content handling: $untrusted_pass/$specialist_count"
echo ""

# --- Law 8: Design for Failure ---
echo "--- Law 8: Failure Modes ---"
failure_pass=0
failure_info=0
for agent_dir in "$AGENTS_DIR"/*/; do
    agent=$(basename "$agent_dir")
    agent_md="$agent_dir/AGENT.md"
    if [[ -f "$agent_md" ]]; then
        if grep -qiE '## Failure' "$agent_md"; then
            failure_pass=$((failure_pass + 1))
        else
            failure_info=$((failure_info + 1))
            if $preamble_ok; then
                : # Preamble covers universal failure protocol; suppress per-agent finding
            else
                echo "  NO FAILURE MODES: $agent/AGENT.md"
                FINDINGS=$((FINDINGS + 1))
            fi
        fi
    fi
done
echo "  Agents with per-agent failure modes: $failure_pass/$agent_count"
if $preamble_ok && [[ $failure_info -gt 0 ]]; then
    echo "  Preamble covers universal failure protocol for remaining $failure_info agents"
fi
echo ""

# --- Summary ---
echo "=== Summary ==="
echo "  Preamble: $( $preamble_ok && echo 'PRESENT' || echo 'MISSING' )"
echo "  Runners with preamble: $runner_pass/$runner_count"
echo "  Agents scanned: $agent_count"
echo "  Commands scanned: $cmd_count"
echo "  Specialists scanned: $specialist_count"
echo "  Findings: $FINDINGS"
if [[ "$FINDINGS" -gt 0 ]]; then
    echo "  Status: FINDINGS DETECTED — review above."
    exit 1
else
    echo "  Status: COMPLIANT"
    exit 0
fi
