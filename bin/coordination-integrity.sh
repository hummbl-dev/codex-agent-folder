#!/usr/bin/env zsh
set -euo pipefail

DEFAULT_LOG="/Users/others/founder-mode/founder-mode/_state/coordination/messages.tsv"
HEALTH_SCRIPT="/Users/others/bin/coordination-health.sh"

usage() {
  cat <<'USAGE'
Usage:
  coordination-integrity.sh check [log_path]
  coordination-integrity.sh doctor [log_path]
  coordination-integrity.sh watch [interval_seconds] [log_path]

Modes:
  check   Run strict pass/fail health gate.
  doctor  Run health gate and print line-level diagnostics.
  watch   Run periodic checks (default interval: 30s).
USAGE
}

require_deps() {
  if [ ! -x "${HEALTH_SCRIPT}" ]; then
    echo "ERROR: missing health script: ${HEALTH_SCRIPT}" >&2
    exit 2
  fi
}

diagnose_log() {
  local log_path="$1"

  if [ ! -f "${log_path}" ]; then
    echo "ERROR: log not found: ${log_path}" >&2
    return 2
  fi

  awk -F '\t' '
    BEGIN {
      ts_pattern = "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"
      schema = "legacy"
      out_of_order = 0
      malformed = 0
    }
    NR == 1 {
      if ($0 == "timestamp\tfrom\tto\ttype\tmessage") {
        schema = "v2"
        next
      }
    }
    {
      valid = 0
      if (schema == "v2") {
        if (NF >= 5 && $1 ~ ts_pattern) valid = 1
      } else {
        if (NF >= 4 && $1 ~ ts_pattern) valid = 1
      }

      if (valid == 1) {
        if (prev_ts != "" && $1 < prev_ts) {
          out_of_order += 1
          printf("OUT_OF_ORDER prev_line=%d prev_ts=%s line=%d ts=%s from=%s to=%s type=%s\n", prev_line, prev_ts, NR, $1, $2, $3, $4)
        }
        prev_ts = $1
        prev_line = NR
      } else {
        malformed += 1
        printf("MALFORMED line=%d raw=%s\n", NR, $0)
      }
    }
    END {
      printf("SUMMARY out_of_order=%d malformed=%d\n", out_of_order, malformed)
    }
  ' "${log_path}"
}

run_check() {
  local log_path="$1"
  "${HEALTH_SCRIPT}" "${log_path}"
}

run_doctor() {
  local log_path="$1"
  local rc=0

  set +e
  "${HEALTH_SCRIPT}" "${log_path}"
  rc=$?
  set -e

  echo "DIAGNOSTICS ${log_path}"
  diagnose_log "${log_path}"

  return "${rc}"
}

run_watch() {
  local interval="$1"
  local log_path="$2"

  if ! [[ "${interval}" =~ ^[0-9]+$ ]] || [ "${interval}" -le 0 ]; then
    echo "ERROR: interval_seconds must be an integer > 0" >&2
    exit 2
  fi

  while true; do
    echo "--- $(date -u +%Y-%m-%dT%H:%M:%SZ) coordination-integrity watch ---"
    set +e
    "${HEALTH_SCRIPT}" "${log_path}"
    local rc=$?
    set -e

    if [ "${rc}" -ne 0 ]; then
      echo "DIAGNOSTICS ${log_path}"
      diagnose_log "${log_path}" | head -n 20
    fi

    sleep "${interval}"
  done
}

main() {
  require_deps

  local action="${1:-check}"

  case "${action}" in
    check)
      run_check "${2:-${DEFAULT_LOG}}"
      ;;
    doctor)
      run_doctor "${2:-${DEFAULT_LOG}}"
      ;;
    watch)
      run_watch "${2:-30}" "${3:-${DEFAULT_LOG}}"
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
