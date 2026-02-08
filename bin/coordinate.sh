#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
BIN_DIR="${ROOT_DIR}/bin"
FOUNDER_REPO_DIR_DEFAULT="${ROOT_DIR}/founder-mode/founder-mode"

BRIDGE="${BIN_DIR}/agent-bridge.sh"
CROSS="${BIN_DIR}/cross-review-gate.sh"
DEFAULT_REPO_DIR="${FOUNDER_REPO_DIR_DEFAULT}"

# Default target for Codex -> Claude Code.
DEFAULT_TO_AGENT="claude-code"
SELF="${AGENT_NAME:-codex}"
TO_AGENT="${COORD_TO:-${DEFAULT_TO_AGENT}}"

usage() {
  cat <<'USAGE'
Usage:
  coordinate.sh read [count]
  coordinate.sh post <TYPE> <message...>
  coordinate.sh status <pr>
  coordinate.sh verify <pr>
  coordinate.sh approve <pr>
  coordinate.sh sync

Notes:
  - read/post use the TSV message bus via agent-bridge.
  - status/verify/approve run cross-review-gate from the founder-mode repo.
  - Override message target with COORD_TO=<agent>.
USAGE
}

require_exec() {
  local path="$1"
  if [ ! -x "${path}" ]; then
    echo "ERROR: missing executable: ${path}" >&2
    exit 2
  fi
}

cmd_read() {
  local count="${1:-10}"
  if ! [[ "${count}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: count must be an integer" >&2
    exit 2
  fi
  "${BRIDGE}" recent "${count}"
}

cmd_post() {
  if [ "$#" -lt 2 ]; then
    usage >&2
    exit 2
  fi
  local type="$1"
  shift
  local msg="$*"
  "${BRIDGE}" send "${TO_AGENT}" "${type}" "${msg}"
}

with_repo_dir() {
  if [ ! -d "${DEFAULT_REPO_DIR}" ]; then
    echo "ERROR: repo dir missing: ${DEFAULT_REPO_DIR}" >&2
    exit 2
  fi
  (cd "${DEFAULT_REPO_DIR}" && "$@")
}

cmd_status() {
  local pr="${1:-}"
  if [ -z "${pr}" ]; then
    usage >&2
    exit 2
  fi
  with_repo_dir "${CROSS}" status "${pr}"
}

cmd_verify() {
  local pr="${1:-}"
  if [ -z "${pr}" ]; then
    usage >&2
    exit 2
  fi
  with_repo_dir "${CROSS}" verify "${pr}"
}

cmd_approve() {
  local pr="${1:-}"
  if [ -z "${pr}" ]; then
    usage >&2
    exit 2
  fi
  with_repo_dir "${CROSS}" approve "${pr}"
}

cmd_sync() {
  echo "sync_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ) self=${SELF} to=${TO_AGENT}"
  if [ -d "${DEFAULT_REPO_DIR}" ]; then
    (cd "${DEFAULT_REPO_DIR}" && git status -sb)
    (cd "${DEFAULT_REPO_DIR}" && git log --oneline -1)
  else
    echo "repo_status=missing repo_dir=${DEFAULT_REPO_DIR}"
  fi
  "${BRIDGE}" recent 10
}

main() {
  require_exec "${BRIDGE}"

  local action="${1:-}"
  shift || true

  case "${action}" in
    read)
      cmd_read "$@"
      ;;
    post)
      cmd_post "$@"
      ;;
    status)
      require_exec "${CROSS}"
      cmd_status "$@"
      ;;
    verify)
      require_exec "${CROSS}"
      cmd_verify "$@"
      ;;
    approve)
      require_exec "${CROSS}"
      cmd_approve "$@"
      ;;
    sync)
      cmd_sync
      ;;
    -h|--help|help|"")
      usage
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
