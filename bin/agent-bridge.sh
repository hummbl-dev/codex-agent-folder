#!/usr/bin/env zsh
set -euo pipefail

SELF="${AGENT_NAME:-codex}"
ROOT_DIR="${0:A:h:h}"
FOUNDER_REPO_DIR_DEFAULT="${ROOT_DIR}/founder-mode/founder-mode"

FOUNDATION_COORD_ROOT="${FOUNDER_REPO_DIR_DEFAULT}/_state/coordination"
LEGACY_COORD_ROOT="${ROOT_DIR}/_state/coordination"
SINGLE_SOURCE_MODE="${COORD_SINGLE_SOURCE_MODE:-enforce}"

detect_root_dir() {
  if [ -n "${COORD_ROOT:-}" ]; then
    printf "%s\n" "${COORD_ROOT}"
    return
  fi

  case "$(pwd -P)" in
    ${FOUNDER_REPO_DIR_DEFAULT}* )
      printf "%s\n" "${FOUNDATION_COORD_ROOT}"
      return
      ;;
  esac

  if [ -d "${FOUNDATION_COORD_ROOT}" ]; then
    printf "%s\n" "${FOUNDATION_COORD_ROOT}"
    return
  fi

  printf "%s\n" "${LEGACY_COORD_ROOT}"
}

ROOT_DIR="$(detect_root_dir)"
LOG_FILE="${ROOT_DIR}/messages.tsv"

if [ "${SINGLE_SOURCE_MODE}" != "off" ] && [ "${ROOT_DIR}" = "${LEGACY_COORD_ROOT}" ]; then
  cat <<EOF >&2
ERROR: single-source mode blocks legacy coordination writes.
resolved_root=${ROOT_DIR}
required_root=${FOUNDATION_COORD_ROOT}

Use one of:
  1) run from founder-mode repo (auto-detects required root)
  2) set COORD_ROOT=${FOUNDATION_COORD_ROOT}
  3) temporary override: COORD_SINGLE_SOURCE_MODE=off
EOF
  exit 2
fi

mkdir -p "${ROOT_DIR}"
touch "${LOG_FILE}"

detect_schema() {
  if [ -n "${BRIDGE_SCHEMA:-}" ]; then
    printf "%s\n" "${BRIDGE_SCHEMA}"
    return
  fi

  if [ ! -s "${LOG_FILE}" ]; then
    printf "v2\n"
    return
  fi

  local first_line
  first_line="$(head -n 1 "${LOG_FILE}" || true)"
  if [ "${first_line}" = $'timestamp\tfrom\tto\ttype\tmessage' ]; then
    printf "v2\n"
  else
    printf "legacy\n"
  fi
}

SCHEMA="$(detect_schema)"

ensure_v2_header() {
  if [ "${SCHEMA}" != "v2" ]; then
    return
  fi
  if [ ! -s "${LOG_FILE}" ]; then
    printf "timestamp\tfrom\tto\ttype\tmessage\n" >> "${LOG_FILE}"
  fi
}

usage() {
  cat <<'EOF'
Usage:
  agent-bridge.sh send <to-agent> <message...>
  agent-bridge.sh send <to-agent> <TYPE> <message...>
  agent-bridge.sh inbox [agent]
  agent-bridge.sh recent [count]
  agent-bridge.sh watch [agent] [count]
  agent-bridge.sh audit
  agent-bridge.sh doctor

Notes:
  - Timestamps are UTC ISO-8601.
  - Default log root auto-detects founder-mode first:
    $WORKSPACE_ROOT/founder-mode/founder-mode/_state/coordination/messages.tsv
  - Legacy fallback:
    $WORKSPACE_ROOT/_state/coordination/messages.tsv
  - Single-source mode (default): COORD_SINGLE_SOURCE_MODE=enforce
EOF
}

timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

sanitize_message() {
  local raw="$1"
  raw="${raw//$'\t'/ }"
  raw="${raw//$'\r'/ }"
  raw="${raw//$'\n'/\\n}"
  printf "%s\n" "${raw}"
}

is_known_type() {
  case "$1" in
    PROPOSAL|ACK|STATUS|SITREP|BLOCKED|DECISION|QUESTION)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

cmd="${1:-}"
case "${cmd}" in
  send)
    if [ "$#" -lt 3 ]; then
      usage
      exit 1
    fi
    to_agent="$2"
    shift 2
    message_type="STATUS"
    if [ "$#" -ge 2 ] && is_known_type "$1"; then
      message_type="$1"
      shift 1
    fi
    message="$*"
    if [ -z "${message}" ]; then
      usage
      exit 1
    fi
    message="$(sanitize_message "${message}")"
    ts="$(timestamp_utc)"
    if [ "${SCHEMA}" = "v2" ]; then
      ensure_v2_header
      printf "%s\t%s\t%s\t%s\t%s\n" "${ts}" "${SELF}" "${to_agent}" "${message_type}" "${message}" >> "${LOG_FILE}"
    else
      if [ "${message_type}" = "STATUS" ]; then
        printf "%s\t%s\t%s\t%s\n" "${ts}" "${SELF}" "${to_agent}" "${message}" >> "${LOG_FILE}"
      else
        printf "%s\t%s\t%s\t[%s] %s\n" "${ts}" "${SELF}" "${to_agent}" "${message_type}" "${message}" >> "${LOG_FILE}"
      fi
    fi
    printf "sent %s -> %s at %s (%s, %s)\n" "${SELF}" "${to_agent}" "${ts}" "${SCHEMA}" "${LOG_FILE}"
    ;;
  inbox)
    agent="${2:-${SELF}}"
    if [ "${SCHEMA}" = "v2" ]; then
      awk -F '\t' -v agent="${agent}" 'NR == 1 || (NF >= 5 && $3 == agent) {print}' "${LOG_FILE}" || true
    else
      awk -F '\t' -v agent="${agent}" 'NF >= 4 && $3 == agent {print}' "${LOG_FILE}" || true
    fi
    ;;
  recent)
    count="${2:-20}"
    tail -n "${count}" "${LOG_FILE}" || true
    ;;
  watch)
    agent="${2:-${SELF}}"
    count="${3:-20}"
    if [ "${SCHEMA}" = "v2" ]; then
      tail -n "${count}" -f "${LOG_FILE}" | awk -F '\t' -v agent="${agent}" '
        NR == 1 && $1 == "timestamp" { print; next }
        NF >= 5 && ($2 == agent || $3 == agent) { print; fflush() }
      '
    else
      tail -n "${count}" -f "${LOG_FILE}" | awk -F '\t' -v agent="${agent}" '
        NF >= 4 && ($2 == agent || $3 == agent) { print; fflush() }
      '
    fi
    ;;
  audit)
    printf "log_file=%s\nschema=%s\n" "${LOG_FILE}" "${SCHEMA}"
    if [ "${SCHEMA}" = "v2" ]; then
      awk -F '\t' '
        NR == 1 { next }
        {
          ts_pattern = "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"
          if (NF >= 5 && $1 ~ ts_pattern) {
            total += 1
            type[$4] += 1
            if (prev != "" && $1 < prev) {
              out += 1
              printf "out_of_order line %d: %s < %s\n", NR, $1, prev
            }
            prev = $1
          } else {
            malformed += 1
          }
        }
        END {
          printf "entries=%d\n", total
          for (t in type) {
            printf "type[%s]=%d\n", t, type[t]
          }
          printf "malformed=%d\n", malformed
          printf "out_of_order=%d\n", out
        }
      ' "${LOG_FILE}"
    else
      awk -F '\t' '
        {
          ts_pattern = "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"
          if (NF >= 4 && $1 ~ ts_pattern) {
            total += 1
            if (prev != "" && $1 < prev) {
              out += 1
              printf "out_of_order line %d: %s < %s\n", NR, $1, prev
            }
            prev = $1
          } else {
            malformed += 1
          }
        }
        END {
          printf "entries=%d\n", total
          printf "malformed=%d\n", malformed
          printf "out_of_order=%d\n", out
        }
      ' "${LOG_FILE}"
    fi
    ;;
  doctor)
    printf "root_dir=%s\nlog_file=%s\nschema=%s\nsingle_source_mode=%s\n" "${ROOT_DIR}" "${LOG_FILE}" "${SCHEMA}" "${SINGLE_SOURCE_MODE}"
    ;;
  ""|help|-h|--help)
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac
