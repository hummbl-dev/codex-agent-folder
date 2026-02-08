#!/usr/bin/env zsh
set -euo pipefail

GATE_SCRIPT="${COORD_GATE_SCRIPT:-/Users/others/bin/coordination-gate.sh}"
SNAPSHOT_DIR="${COORD_SNAPSHOT_DIR:-/Users/others/_state/coordination}"
SNAPSHOT_TSV="${COORD_SNAPSHOT_TSV:-${SNAPSHOT_DIR}/gate-status.tsv}"

timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

extract_field() {
  local line="$1"
  local key="$2"
  printf "%s\n" "${line}" | awk -v key="${key}" '
    {
      for (i = 1; i <= NF; i++) {
        if ($i ~ ("^" key "=")) {
          gsub("^" key "=", "", $i)
          print $i
          exit
        }
      }
    }
  '
}

mkdir -p "${SNAPSHOT_DIR}"
if [ ! -f "${SNAPSHOT_TSV}" ]; then
  printf "timestamp_utc\tcurrent_result\tschema\tentries\tout_of_order\tmalformed\tmalformed_rate\tbaseline_out_of_order\tbaseline_malformed\tbaseline_malformed_rate\tcheck_result\n" > "${SNAPSHOT_TSV}"
fi

status_output="$("${GATE_SCRIPT}" status 2>&1 || true)"
current_line="$(printf "%s\n" "${status_output}" | awk '/^current / {sub(/^current /, ""); print; exit}')"
baseline_line="$(printf "%s\n" "${status_output}" | awk '/^baseline / {print; exit}')"

if [ -z "${current_line}" ]; then
  current_line="FAIL unknown schema=unknown entries=0 malformed=0 out_of_order=0 malformed_rate=1.000000 reasons=status_parse_error"
fi

current_result="$(printf "%s\n" "${current_line}" | awk '{print $1}')"
schema="$(extract_field "${current_line}" "schema")"
entries="$(extract_field "${current_line}" "entries")"
out_of_order="$(extract_field "${current_line}" "out_of_order")"
malformed="$(extract_field "${current_line}" "malformed")"
malformed_rate="$(extract_field "${current_line}" "malformed_rate")"

baseline_out_of_order="$(extract_field "${baseline_line}" "max_out_of_order")"
baseline_malformed="$(extract_field "${baseline_line}" "max_malformed")"
baseline_malformed_rate="$(extract_field "${baseline_line}" "max_malformed_rate")"

set +e
check_output="$("${GATE_SCRIPT}" check 2>&1)"
check_exit=$?
set -e

if [ "${check_exit}" -eq 0 ]; then
  check_result="PASS"
else
  check_result="FAIL"
fi

ts="$(timestamp_utc)"
printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
  "${ts}" \
  "${current_result:-unknown}" \
  "${schema:-unknown}" \
  "${entries:-0}" \
  "${out_of_order:-0}" \
  "${malformed:-0}" \
  "${malformed_rate:-0.000000}" \
  "${baseline_out_of_order:-unset}" \
  "${baseline_malformed:-unset}" \
  "${baseline_malformed_rate:-unset}" \
  "${check_result}" >> "${SNAPSHOT_TSV}"

echo "gate_snapshot_written ${ts} -> ${SNAPSHOT_TSV} (current=${current_result:-unknown}, check=${check_result})"
