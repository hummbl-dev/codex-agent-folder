#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
FOUNDER_REPO_DIR_DEFAULT="${ROOT_DIR}/founder-mode/founder-mode"

FOUNDATION_LOG="${FOUNDER_REPO_DIR_DEFAULT}/_state/coordination/messages.tsv"
LEGACY_LOG="${ROOT_DIR}/_state/coordination/messages.tsv"

MAX_OUT_OF_ORDER="${COORD_MAX_OUT_OF_ORDER:-0}"
MAX_MALFORMED="${COORD_MAX_MALFORMED:-0}"
MAX_MALFORMED_RATE="${COORD_MAX_MALFORMED_RATE:-0.00}"

usage() {
  cat <<'EOF'
Usage:
  coordination-health.sh [--all] [log_path ...]

Default:
  Checks founder-mode coordination log only.

Options:
  --all          Check founder-mode and legacy coordination logs.
  -h, --help     Show this help.

Thresholds (env):
  COORD_MAX_OUT_OF_ORDER   max allowed out-of-order entries (default: 0)
  COORD_MAX_MALFORMED      max allowed malformed lines (default: 0)
  COORD_MAX_MALFORMED_RATE max allowed malformed rate [0.00-1.00] (default: 0.00)

Examples:
  coordination-health.sh
  coordination-health.sh --all
  COORD_MAX_OUT_OF_ORDER=1 coordination-health.sh
EOF
}

collect_logs() {
  local include_all="false"
  local -a logs=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --all)
        include_all="true"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        logs+=("$1")
        shift
        ;;
    esac
  done

  if [ "${#logs[@]}" -eq 0 ]; then
    logs+=("${FOUNDATION_LOG}")
    if [ "${include_all}" = "true" ]; then
      logs+=("${LEGACY_LOG}")
    fi
  fi

  printf "%s\n" "${logs[@]}"
}

is_float() {
  case "$1" in
    ''|*[!0-9.]*|*.*.*) return 1 ;;
    *) return 0 ;;
  esac
}

if ! [[ "${MAX_OUT_OF_ORDER}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: COORD_MAX_OUT_OF_ORDER must be an integer >= 0"
  exit 2
fi
if ! [[ "${MAX_MALFORMED}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: COORD_MAX_MALFORMED must be an integer >= 0"
  exit 2
fi
if ! is_float "${MAX_MALFORMED_RATE}"; then
  echo "ERROR: COORD_MAX_MALFORMED_RATE must be a decimal between 0.00 and 1.00"
  exit 2
fi

overall_status=0

while IFS= read -r log_path; do
  if [ -z "${log_path}" ]; then
    continue
  fi
  if [ ! -f "${log_path}" ]; then
    echo "FAIL ${log_path} missing_file=1"
    overall_status=1
    continue
  fi

  stats="$(
    awk -F '\t' '
      BEGIN {
        ts_pattern = "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"
        schema = "legacy"
      }
      NR == 1 {
        if ($0 == "timestamp\tfrom\tto\ttype\tmessage") {
          schema = "v2"
          next
        }
      }
      {
        total_lines += 1
        valid = 0
        if (schema == "v2") {
          if (NF >= 5 && $1 ~ ts_pattern) {
            valid = 1
          }
        } else {
          if (NF >= 4 && $1 ~ ts_pattern) {
            valid = 1
          }
        }

        if (valid == 1) {
          entries += 1
          if (prev_ts != "" && $1 < prev_ts) {
            out_of_order += 1
          }
          prev_ts = $1
        } else {
          malformed += 1
        }
      }
      END {
        if (total_lines > 0) {
          malformed_rate = malformed / total_lines
        } else {
          malformed_rate = 0
        }
        printf "schema=%s entries=%d malformed=%d out_of_order=%d total_lines=%d malformed_rate=%.6f\n",
          schema, entries, malformed, out_of_order, total_lines, malformed_rate
      }
    ' "${log_path}"
  )"

  schema="$(echo "${stats}" | awk '{for(i=1;i<=NF;i++){if($i ~ /^schema=/){sub("schema=","",$i); print $i}}}')"
  entries="$(echo "${stats}" | awk '{for(i=1;i<=NF;i++){if($i ~ /^entries=/){sub("entries=","",$i); print $i}}}')"
  malformed="$(echo "${stats}" | awk '{for(i=1;i<=NF;i++){if($i ~ /^malformed=/){sub("malformed=","",$i); print $i}}}')"
  out_of_order="$(echo "${stats}" | awk '{for(i=1;i<=NF;i++){if($i ~ /^out_of_order=/){sub("out_of_order=","",$i); print $i}}}')"
  malformed_rate="$(echo "${stats}" | awk '{for(i=1;i<=NF;i++){if($i ~ /^malformed_rate=/){sub("malformed_rate=","",$i); print $i}}}')"

  fail_reasons=()
  if [ "${out_of_order}" -gt "${MAX_OUT_OF_ORDER}" ]; then
    fail_reasons+=("out_of_order>${MAX_OUT_OF_ORDER}")
  fi
  if [ "${malformed}" -gt "${MAX_MALFORMED}" ]; then
    fail_reasons+=("malformed>${MAX_MALFORMED}")
  fi

  if awk -v rate="${malformed_rate}" -v max="${MAX_MALFORMED_RATE}" 'BEGIN {exit !(rate > max)}'; then
    fail_reasons+=("malformed_rate>${MAX_MALFORMED_RATE}")
  fi

  if [ "${#fail_reasons[@]}" -gt 0 ]; then
    printf "FAIL %s schema=%s entries=%s malformed=%s out_of_order=%s malformed_rate=%s reasons=%s\n" \
      "${log_path}" "${schema}" "${entries}" "${malformed}" "${out_of_order}" "${malformed_rate}" "${(j:,:)fail_reasons}"
    overall_status=1
  else
    printf "PASS %s schema=%s entries=%s malformed=%s out_of_order=%s malformed_rate=%s\n" \
      "${log_path}" "${schema}" "${entries}" "${malformed}" "${out_of_order}" "${malformed_rate}"
  fi
done < <(collect_logs "$@")

exit "${overall_status}"
