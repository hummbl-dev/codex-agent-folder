#!/usr/bin/env zsh
set -euo pipefail

WATCH_AGENT="${1:-codex}"
WATCH_COUNT="${WATCH_COUNT:-30}"
AUDIT_INTERVAL_SECONDS="${AUDIT_INTERVAL_SECONDS:-30}"
ROOT_DIR="${0:A:h:h}"
BIN_DIR="${ROOT_DIR}/bin"

BRIDGE_SCRIPT="${BIN_DIR}/agent-bridge.sh"
HEARTBEAT_LOG="${HEARTBEAT_LOG:-${ROOT_DIR}/_state/coordination/heartbeat.tsv}"

usage() {
  cat <<'EOF'
Usage:
  coordination-dashboard.sh [watch_agent]

Streams:
  - LIVE watch stream from agent-bridge
  - periodic audit snapshots
  - latest heartbeat row

Env:
  WATCH_COUNT=30
  AUDIT_INTERVAL_SECONDS=30
EOF
}

if [ "${WATCH_AGENT}" = "-h" ] || [ "${WATCH_AGENT}" = "--help" ]; then
  usage
  exit 0
fi

if [ ! -x "${BRIDGE_SCRIPT}" ]; then
  echo "ERROR: bridge script not executable: ${BRIDGE_SCRIPT}" >&2
  exit 2
fi

print_audit() {
  local now
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "[AUDIT ${now}]"
  "${BRIDGE_SCRIPT}" audit | sed 's/^/[AUDIT] /'
  if [ -f "${HEARTBEAT_LOG}" ]; then
    tail -n 1 "${HEARTBEAT_LOG}" | sed 's/^/[HEARTBEAT] /'
  fi
}

cleanup() {
  if [ -n "${WATCH_PID:-}" ]; then
    kill "${WATCH_PID}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

echo "[DASHBOARD] start_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ") watch_agent=${WATCH_AGENT} interval=${AUDIT_INTERVAL_SECONDS}s"

(
  "${BRIDGE_SCRIPT}" watch "${WATCH_AGENT}" "${WATCH_COUNT}" |
    while IFS= read -r line; do
      printf "[WATCH] %s\n" "${line}"
    done
) 2>/dev/null &
WATCH_PID=$!

while true; do
  print_audit
  sleep "${AUDIT_INTERVAL_SECONDS}"
done
