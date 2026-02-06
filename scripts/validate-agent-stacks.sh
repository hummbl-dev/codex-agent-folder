#!/usr/bin/env bash
# validate-agent-stacks.sh — Read-only scaffold validator for HUMMBL agent identity stacks
# Safe to run without network or mutation. Exit 0 = clean, exit 1 = findings.
set -euo pipefail

AGENTS_DIR="workspace/agents"
AVATARS_DIR="avatars"
GALLERY="avatars/GALLERY.md"
REQUIRED_DOCS=("AGENT.md" "IDENTITY.md" "USER.md" "SOUL.md" "MEMORY.md")
TEAMS=("dialectic" "hexaops" "octave" "pentad" "red-blue-purple" "septet")
FINDINGS=0

echo "=== HUMMBL Agent Stack Validator ==="
echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# --- 1. Identity stack completeness ---
echo "--- Identity Stack Completeness ---"
agent_count=0
for agent_dir in "$AGENTS_DIR"/*/; do
    agent=$(basename "$agent_dir")
    agent_count=$((agent_count + 1))
    for doc in "${REQUIRED_DOCS[@]}"; do
        if [[ ! -f "$agent_dir/$doc" ]]; then
            echo "  MISSING: $agent/$doc"
            FINDINGS=$((FINDINGS + 1))
        fi
    done
    if [[ ! -d "$agent_dir/memory" ]]; then
        echo "  MISSING: $agent/memory/ directory"
        FINDINGS=$((FINDINGS + 1))
    else
        entry_count=$(find "$agent_dir/memory" -name "*.md" -type f | wc -l | tr -d ' ')
        if [[ "$entry_count" -eq 0 ]]; then
            echo "  EMPTY:   $agent/memory/ (no daily logs)"
            FINDINGS=$((FINDINGS + 1))
        fi
    fi
    # Check for empty identity docs (< 10 bytes likely means placeholder)
    for doc in "${REQUIRED_DOCS[@]}"; do
        if [[ -f "$agent_dir/$doc" ]]; then
            size=$(wc -c < "$agent_dir/$doc" | tr -d ' ')
            if [[ "$size" -lt 10 ]]; then
                echo "  STUB:    $agent/$doc ($size bytes — likely empty)"
                FINDINGS=$((FINDINGS + 1))
            fi
        fi
    done
done
echo "  Scanned $agent_count agent directories."
echo ""

# --- 2. Avatar asset coverage ---
echo "--- Avatar Asset Coverage ---"
is_team() {
    local name="$1"
    for team in "${TEAMS[@]}"; do
        if [[ "$name" == "$team" ]]; then
            return 0
        fi
    done
    return 1
}

for agent_dir in "$AGENTS_DIR"/*/; do
    agent=$(basename "$agent_dir")
    if is_team "$agent"; then
        continue
    fi
    for suffix in "avatar.png" "avatar-mono.png" "avatar-brief.md"; do
        asset="$AVATARS_DIR/${agent}-${suffix}"
        if [[ ! -f "$asset" ]]; then
            echo "  MISSING: $asset"
            FINDINGS=$((FINDINGS + 1))
        fi
    done
done
echo ""

# --- 3. Gallery entry check ---
echo "--- Gallery Entry Check ---"
for agent_dir in "$AGENTS_DIR"/*/; do
    agent=$(basename "$agent_dir")
    if ! grep -qi "$agent" "$GALLERY" 2>/dev/null; then
        echo "  NO GALLERY ROW: $agent"
        FINDINGS=$((FINDINGS + 1))
    fi
done

pending_count=$(grep -c '⏳' "$GALLERY" 2>/dev/null || echo "0")
echo "  Pending approvals in gallery: $pending_count"
echo ""

# --- 4. Summary ---
echo "=== Summary ==="
echo "  Agents scanned: $agent_count"
echo "  Findings: $FINDINGS"
if [[ "$FINDINGS" -gt 0 ]]; then
    echo "  Status: FINDINGS DETECTED — review above."
    exit 1
else
    echo "  Status: CLEAN"
    exit 0
fi
