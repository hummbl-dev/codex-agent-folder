#!/usr/bin/env bash
set -euo pipefail

BUS_FILE_DEFAULT="/Users/others/founder-mode/founder-mode/_state/coordination/messages.tsv"
OUT_DIR_DEFAULT="/Users/others/_state/monitoring"

BUS_FILE="${BUS_FILE:-$BUS_FILE_DEFAULT}"
OUT_DIR="${OUT_DIR:-$OUT_DIR_DEFAULT}"

POLL_SEC="${POLL_SEC:-15}"
FETCH_INTERVAL_SEC="${FETCH_INTERVAL_SEC:-300}"
ENABLE_FETCH="${ENABLE_FETCH:-0}"

# Repos to watch for drift
REPO_A_DEFAULT="/Users/others/founder-mode/founder-mode"
REPO_B_DEFAULT="/Users/others"
REPO_A="${REPO_A:-$REPO_A_DEFAULT}"
REPO_B="${REPO_B:-$REPO_B_DEFAULT}"

mkdir -p "$OUT_DIR"
LOG="$OUT_DIR/claude-lightwatch.log"
STATE="$OUT_DIR/claude-lightwatch.state"
PIDFILE="$OUT_DIR/claude-lightwatch.pid"

utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }
log() { printf '%s\t%s\n' "$(utc)" "$*" >> "$LOG"; }

if [[ ! -f "$BUS_FILE" ]]; then
  log "ERROR bus_file_missing BUS_FILE=$BUS_FILE"
  exit 1
fi

# state format: last_line|last_fetch_epoch|repo_a_sig|repo_b_sig
init_state() {
  local lines
  lines=$(wc -l "$BUS_FILE" | awk '{print $1}')
  printf '%s|%s|%s|%s\n' "$lines" "0" "" "" > "$STATE"
}

read_state() {
  if [[ ! -f "$STATE" ]]; then
    init_state
  fi
  IFS='|' read -r LAST_LINE LAST_FETCH_EPOCH REPO_A_SIG REPO_B_SIG < "$STATE"
}

write_state() {
  printf '%s|%s|%s|%s\n' "$LAST_LINE" "$LAST_FETCH_EPOCH" "$REPO_A_SIG" "$REPO_B_SIG" > "$STATE"
}

bus_poll() {
  local cur
  cur=$(wc -l "$BUS_FILE" | awk '{print $1}')

  # Handle truncation/rotation.
  if [[ "$cur" -lt "$LAST_LINE" ]]; then
    log "WARN bus_truncated last_line=$LAST_LINE cur_line=$cur"
    LAST_LINE="$cur"
    return 0
  fi

  if [[ "$cur" -eq "$LAST_LINE" ]]; then
    return 0
  fi

  # Print new claude-code-related lines (from or to claude-code) with high-signal types.
  # TSV columns (observed): ts \t from \t to \t type \t message
  # We only emit DECISION/SITREP/STATUS/ACK from new lines.
  local start
  start=$((LAST_LINE + 1))
  sed -n "${start},${cur}p" "$BUS_FILE" \
    | awk -F'\t' '($2=="claude-code" || $3=="claude-code") && ($4=="DECISION" || $4=="SITREP" || $4=="STATUS" || $4=="ACK") {print}' \
    | while IFS= read -r line; do
        log "BUS $line"
      done

  LAST_LINE="$cur"
}

repo_sig() {
  local repo="$1"
  if [[ ! -d "$repo/.git" ]]; then
    printf 'no-git'
    return 0
  fi

  (cd "$repo" && {
    # Optional fetch (network). Keep it sparse.
    :
  }) >/dev/null 2>&1 || true

  local branch upstream dirty head ab
  branch=$(cd "$repo" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
  head=$(cd "$repo" && git rev-parse --short HEAD 2>/dev/null || echo "?")
  upstream=$(cd "$repo" && git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo "no-upstream")
  dirty=$(cd "$repo" && git status --porcelain 2>/dev/null | wc -l | awk '{print $1}')
  ab="?/?"
  if [[ "$upstream" != "no-upstream" ]]; then
    ab=$(cd "$repo" && git rev-list --left-right --count "${upstream}...HEAD" 2>/dev/null | tr '\t' '/')
  fi
  printf '%s@%s|up=%s|dirty=%s|ab=%s' "$branch" "$head" "$upstream" "$dirty" "$ab"
}

maybe_fetch() {
  if [[ "${ENABLE_FETCH}" != "1" ]]; then
    return 0
  fi
  local now
  now=$(date +%s)
  if (( now - LAST_FETCH_EPOCH < FETCH_INTERVAL_SEC )); then
    return 0
  fi

  for repo in "$REPO_A" "$REPO_B"; do
    if [[ -d "$repo/.git" ]]; then
      (cd "$repo" && git fetch --all --prune) >/dev/null 2>&1 || log "WARN fetch_failed repo=$repo"
    fi
  done

  LAST_FETCH_EPOCH="$now"
}

repo_poll() {
  local a b
  a=$(repo_sig "$REPO_A")
  b=$(repo_sig "$REPO_B")

  if [[ "$a" != "$REPO_A_SIG" ]]; then
    log "REPO repo=$REPO_A sig=$a"
    REPO_A_SIG="$a"
  fi
  if [[ "$b" != "$REPO_B_SIG" ]]; then
    log "REPO repo=$REPO_B sig=$b"
    REPO_B_SIG="$b"
  fi
}

# Main
log "START bus=$BUS_FILE poll_sec=$POLL_SEC enable_fetch=$ENABLE_FETCH fetch_interval_sec=$FETCH_INTERVAL_SEC repo_a=$REPO_A repo_b=$REPO_B"

echo "$$" > "$PIDFILE"

read_state

while true; do
  maybe_fetch
  bus_poll
  repo_poll
  write_state
  sleep "$POLL_SEC"
done
