#!/usr/bin/env zsh
set -euo pipefail

COORD_LOG="${COORD_LOG_PATH:-/Users/others/founder-mode/founder-mode/_state/coordination/messages.tsv}"
HEARTBEAT_DIR="${HEARTBEAT_DIR:-/Users/others/_state/coordination}"
HEARTBEAT_LOG="${HEARTBEAT_LOG:-${HEARTBEAT_DIR}/heartbeat.tsv}"
NOTE="${HEARTBEAT_NOTE:-caffeine=on}"

timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

probe_processes() {
  local ps_output
  if ps_output="$(ps -axo command 2>/dev/null)"; then
    local claude_running codex_running codex_count
    claude_running="$(printf "%s\n" "${ps_output}" | awk 'tolower($0) ~ /(^|[[:space:]])claude$/ || $0 ~ /bin\/claude-entry\.sh/ {found=1} END{print found+0}')"
    codex_running="$(printf "%s\n" "${ps_output}" | awk 'tolower($0) ~ /(^|[[:space:]])codex$/ || $0 ~ /bin\/codex-entry\.sh/ {found=1} END{print found+0}')"
    codex_count="$(printf "%s\n" "${ps_output}" | awk 'tolower($0) ~ /(^|[[:space:]])codex$/ {c+=1} END{print c+0}')"
    printf "%s\t%s\t%s\n" "${claude_running}" "${codex_running}" "${codex_count}"
  else
    printf "NA\tNA\tNA\n"
  fi
}

compute_log_stats() {
  local log_file="$1"
  if [ ! -f "${log_file}" ]; then
    printf "0\t\t\t\t0\t0\n"
    return
  fi

  awk -F '\t' '
    BEGIN {
      ts_pattern = "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"
      schema = "legacy"
      total_lines = 0
      entries = 0
      malformed = 0
      out_of_order = 0
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
        if (NF >= 5 && $1 ~ ts_pattern) valid = 1
      } else {
        if (NF >= 4 && $1 ~ ts_pattern) valid = 1
      }

      if (valid == 1) {
        entries += 1
        if (prev_ts != "" && $1 < prev_ts) out_of_order += 1
        prev_ts = $1
        last_ts = $1
        last_from = $2
        last_to = $3
        if (schema == "v2") {
          last_type = $4
        } else {
          last_type = "legacy"
        }
      } else {
        malformed += 1
      }
    }
    END {
      printf "%d\t%s\t%s\t%s\t%d\t%d\n", entries, last_ts, last_from, last_to, out_of_order, malformed
    }
  ' "${log_file}"
}

mkdir -p "${HEARTBEAT_DIR}"
if [ ! -f "${HEARTBEAT_LOG}" ]; then
  printf "timestamp_utc\tclaude_running\tcodex_running\tcodex_count\tlog_entries\tlast_msg_ts\tlast_msg_from\tlast_msg_to\tout_of_order\tmalformed\tnote\n" > "${HEARTBEAT_LOG}"
fi

ts="$(timestamp_utc)"
IFS=$'\t' read -r claude_running codex_running codex_count <<< "$(probe_processes)"
IFS=$'\t' read -r log_entries last_msg_ts last_msg_from last_msg_to out_of_order malformed <<< "$(compute_log_stats "${COORD_LOG}")"

printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
  "${ts}" \
  "${claude_running}" \
  "${codex_running}" \
  "${codex_count}" \
  "${log_entries}" \
  "${last_msg_ts}" \
  "${last_msg_from}" \
  "${last_msg_to}" \
  "${out_of_order}" \
  "${malformed}" \
  "${NOTE}" >> "${HEARTBEAT_LOG}"

echo "heartbeat_written ${ts} -> ${HEARTBEAT_LOG}"
