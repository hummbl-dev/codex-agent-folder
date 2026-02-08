#!/usr/bin/env zsh
set -euo pipefail

COORD_LOG="${COORD_LOG_PATH:-/Users/others/founder-mode/founder-mode/_state/coordination/messages.tsv}"
BASELINE_FILE="${COORD_BASELINE_FILE:-/Users/others/_state/coordination/health-baseline.env}"
HEALTH_SCRIPT="${COORD_HEALTH_SCRIPT:-/Users/others/bin/coordination-health.sh}"

usage() {
  cat <<'EOF'
Usage:
  coordination-gate.sh init
  coordination-gate.sh check
  coordination-gate.sh status

Purpose:
  Baseline-aware gate for coordination log quality.
  - init: captures current out_of_order/malformed values as baseline
  - check: fails only if metrics exceed baseline ceilings
  - status: shows current metrics and stored baseline
EOF
}

extract_metrics() {
  local line="$1"
  local out_of_order malformed malformed_rate entries
  out_of_order="$(printf "%s\n" "${line}" | awk '{for(i=1;i<=NF;i++) if($i ~ /^out_of_order=/){sub("out_of_order=","",$i); print $i}}')"
  malformed="$(printf "%s\n" "${line}" | awk '{for(i=1;i<=NF;i++) if($i ~ /^malformed=/){sub("malformed=","",$i); print $i}}')"
  malformed_rate="$(printf "%s\n" "${line}" | awk '{for(i=1;i<=NF;i++) if($i ~ /^malformed_rate=/){sub("malformed_rate=","",$i); print $i}}')"
  entries="$(printf "%s\n" "${line}" | awk '{for(i=1;i<=NF;i++) if($i ~ /^entries=/){sub("entries=","",$i); print $i}}')"
  printf "%s\t%s\t%s\t%s\n" "${out_of_order:-0}" "${malformed:-0}" "${malformed_rate:-0.000000}" "${entries:-0}"
}

current_health_line() {
  local output
  output="$("${HEALTH_SCRIPT}" "${COORD_LOG}" 2>&1 || true)"
  printf "%s\n" "${output}" | tail -n 1
}

write_baseline() {
  local out_of_order="$1"
  local malformed="$2"
  local malformed_rate="$3"
  mkdir -p "$(dirname "${BASELINE_FILE}")"
  cat > "${BASELINE_FILE}" <<EOF
# Baseline captured in UTC ISO-8601
COORD_MAX_OUT_OF_ORDER=${out_of_order}
COORD_MAX_MALFORMED=${malformed}
COORD_MAX_MALFORMED_RATE=${malformed_rate}
EOF
}

cmd="${1:-}"
case "${cmd}" in
  init)
    line="$(current_health_line)"
    IFS=$'\t' read -r out_of_order malformed malformed_rate entries <<< "$(extract_metrics "${line}")"
    write_baseline "${out_of_order}" "${malformed}" "${malformed_rate}"
    printf "baseline_initialized file=%s entries=%s out_of_order=%s malformed=%s malformed_rate=%s\n" \
      "${BASELINE_FILE}" "${entries}" "${out_of_order}" "${malformed}" "${malformed_rate}"
    ;;
  status)
    line="$(current_health_line)"
    printf "current %s\n" "${line}"
    if [ -f "${BASELINE_FILE}" ]; then
      # shellcheck disable=SC1090
      source "${BASELINE_FILE}"
      printf "baseline file=%s max_out_of_order=%s max_malformed=%s max_malformed_rate=%s\n" \
        "${BASELINE_FILE}" "${COORD_MAX_OUT_OF_ORDER:-unset}" "${COORD_MAX_MALFORMED:-unset}" "${COORD_MAX_MALFORMED_RATE:-unset}"
    else
      printf "baseline file=%s missing=1\n" "${BASELINE_FILE}"
    fi
    ;;
  check)
    if [ ! -f "${BASELINE_FILE}" ]; then
      echo "ERROR: missing baseline file. Run: coordination-gate.sh init" >&2
      exit 2
    fi
    # shellcheck disable=SC1090
    source "${BASELINE_FILE}"
    COORD_MAX_OUT_OF_ORDER="${COORD_MAX_OUT_OF_ORDER}" \
    COORD_MAX_MALFORMED="${COORD_MAX_MALFORMED}" \
    COORD_MAX_MALFORMED_RATE="${COORD_MAX_MALFORMED_RATE}" \
      "${HEALTH_SCRIPT}" "${COORD_LOG}"
    ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac
