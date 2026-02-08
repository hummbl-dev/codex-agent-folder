#!/usr/bin/env bash
# coordination-canonicalize.sh - Emergency canonicalization of coordination log
#
# GUARD SCRIPT: Refuses to run without explicit approval.
# This script sorts the coordination log by timestamp, destroying append-order history.
#
# Usage:
#   COORD_CANONICALIZE_APPROVED=YES ./coordination-canonicalize.sh [log_path]
#
# Requirements:
#   - COORD_CANONICALIZE_APPROVED=YES environment variable
#   - Creates timestamped backup before any mutation
#   - Prints before/after metrics

set -euo pipefail

LOG_PATH="${1:-/Users/others/founder-mode/founder-mode/_state/coordination/messages.tsv}"
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)

# Guard: require explicit approval
if [[ "${COORD_CANONICALIZE_APPROVED:-}" != "YES" ]]; then
    echo "ERROR: Coordination log canonicalization requires explicit approval."
    echo ""
    echo "The coordination log is append-only by design. Sorting destroys"
    echo "the true append order history and should only be done in emergencies."
    echo ""
    echo "To proceed:"
    echo "  1. Get Reuben approval in the coordination log"
    echo "  2. Run: COORD_CANONICALIZE_APPROVED=YES $0 $LOG_PATH"
    echo ""
    exit 1
fi

# Verify log exists
if [[ ! -f "$LOG_PATH" ]]; then
    echo "ERROR: Log file not found: $LOG_PATH"
    exit 1
fi

# Get before metrics
BEFORE_ENTRIES=$(tail -n +2 "$LOG_PATH" | wc -l | tr -d ' ')
BEFORE_MALFORMED=$(/Users/others/bin/coordination-integrity.sh check "$LOG_PATH" 2>&1 | grep -oE 'malformed=[0-9]+' | cut -d= -f2 || echo "0")
BEFORE_OOO=$(/Users/others/bin/coordination-integrity.sh check "$LOG_PATH" 2>&1 | grep -oE 'out_of_order=[0-9]+' | cut -d= -f2 || echo "0")

echo "=== BEFORE CANONICALIZATION ==="
echo "Log: $LOG_PATH"
echo "Entries: $BEFORE_ENTRIES"
echo "Malformed: $BEFORE_MALFORMED"
echo "Out-of-order: $BEFORE_OOO"
echo ""

# Create timestamped backup
BACKUP_PATH="${LOG_PATH}.backup.${TIMESTAMP}"
cp "$LOG_PATH" "$BACKUP_PATH"
echo "Backup created: $BACKUP_PATH"
echo ""

# Sort the log.
# If the file has the v2 header, preserve it. Otherwise treat the whole file as data (legacy/no-header).
TEMP_FILE=$(mktemp)
first_line="$(head -1 "$LOG_PATH" || true)"
v2_header=$'timestamp\tfrom\tto\ttype\tmessage'
if [[ "$first_line" == "$v2_header" ]]; then
  printf "%s\n" "$v2_header" > "$TEMP_FILE"
  tail -n +2 "$LOG_PATH" | sort -t$'\t' -k1,1 >> "$TEMP_FILE"
else
  sort -t$'\t' -k1,1 "$LOG_PATH" >> "$TEMP_FILE"
fi
mv "$TEMP_FILE" "$LOG_PATH"

# Get after metrics
AFTER_ENTRIES=$(tail -n +2 "$LOG_PATH" | wc -l | tr -d ' ')
AFTER_MALFORMED=$(/Users/others/bin/coordination-integrity.sh check "$LOG_PATH" 2>&1 | grep -oE 'malformed=[0-9]+' | cut -d= -f2 || echo "0")
AFTER_OOO=$(/Users/others/bin/coordination-integrity.sh check "$LOG_PATH" 2>&1 | grep -oE 'out_of_order=[0-9]+' | cut -d= -f2 || echo "0")

echo "=== AFTER CANONICALIZATION ==="
echo "Entries: $AFTER_ENTRIES"
echo "Malformed: $AFTER_MALFORMED"
echo "Out-of-order: $AFTER_OOO"
echo ""

# Verify no data loss
if [[ "$BEFORE_ENTRIES" != "$AFTER_ENTRIES" ]]; then
    echo "WARNING: Entry count changed ($BEFORE_ENTRIES -> $AFTER_ENTRIES)"
    echo "Restore from: $BACKUP_PATH"
    exit 1
fi

# Final integrity check
if /Users/others/bin/coordination-integrity.sh check "$LOG_PATH" 2>&1 | grep -q "^PASS"; then
    echo "=== RESULT ==="
    echo "PASS: Canonicalization complete"
    echo "Backup: $BACKUP_PATH"
else
    echo "=== RESULT ==="
    echo "WARN: Canonicalization complete but integrity check not fully passing"
    echo "Backup: $BACKUP_PATH"
fi
