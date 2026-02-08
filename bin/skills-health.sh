#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
BIN_DIR="${ROOT_DIR}/bin"
FOUNDER_REPO_DIR_DEFAULT="${ROOT_DIR}/founder-mode/founder-mode"

REGISTRY_SCRIPT="${BIN_DIR}/validate-skill-registry.sh"
COORD_SCRIPT="${BIN_DIR}/coordination-integrity.sh"
AUTH_SCRIPT="${BIN_DIR}/gh-auth-recovery.sh"
CROSS_SCRIPT="${BIN_DIR}/cross-review-gate.sh"

LOG_PATH="${FOUNDER_REPO_DIR_DEFAULT}/_state/coordination/messages.tsv"
REPO_PATH="${FOUNDER_REPO_DIR_DEFAULT}"
PR_NUMBER="${SKILLS_HEALTH_PR:-}"
SOFT_MODE=0
VERBOSE=0

usage() {
  cat <<'USAGE'
Usage:
  skills-health.sh [--pr <number>] [--log <path>] [--repo <path>] [--soft] [--verbose]

Checks:
  1) Skill/command registry integrity
  2) Coordination integrity gate
  3) GH auth recovery gate
  4) Cross-review gate verify (optional, requires --pr)

Options:
  --pr <number>    PR number for cross-review verification
  --log <path>     Coordination log path override
  --repo <path>    Repository path for cross-review queries
  --soft           Always exit 0 (report-only mode)
  --verbose        Print full output for all checks
  -h, --help       Show help
USAGE
}

require_exec() {
  local path="$1"
  if [ ! -x "${path}" ]; then
    echo "ERROR missing_executable=${path}" >&2
    exit 2
  fi
}

sanitize_line() {
  local line="$1"
  line="${line//$'\t'/ }"
  line="${line//$'\r'/ }"
  line="${line//$'\n'/ }"
  printf "%s\n" "${line}" | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//'
}

classify_failure() {
  local label="$1"
  local tmp_file="$2"
  local content

  content="$(cat "${tmp_file}" 2>/dev/null || true)"

  case "${label}" in
    registry)
      echo "LOGIC"
      return
      ;;
    coordination)
      if [[ "${content}" == *"out_of_order>"* ]] || [[ "${content}" == *"malformed>"* ]]; then
        echo "DATA"
      else
        echo "LOGIC"
      fi
      return
      ;;
    gh_auth)
      if [[ "${content}" == *"env_override_detected"* ]] || [[ "${content}" == *"gh_status_exit="* ]] || [[ "${content}" == *"gh_not_found"* ]]; then
        echo "ENV"
      else
        echo "LOGIC"
      fi
      return
      ;;
    cross_review)
      if [[ "${content}" == *"error connecting to api.github.com"* ]] || [[ "${content}" == *"githubstatus.com"* ]] || [[ "${content}" == *"unable to fetch PR"* ]] || [[ "${content}" == *"no git remotes found"* ]]; then
        echo "ENV"
      elif [[ "${content}" == *"reason=state=MERGED"* ]] || [[ "${content}" == *"reason=no_non_author_approval"* ]] || [[ "${content}" == *"reason=check_not_completed"* ]] || [[ "${content}" == *"reason=check_not_green"* ]]; then
        echo "GATE"
      else
        echo "LOGIC"
      fi
      return
      ;;
    *)
      echo "UNKNOWN"
      ;;
  esac
}

run_check() {
  local label="$1"
  shift

  local tmp
  tmp="$(mktemp /tmp/skills-health-${label}.XXXXXX)"

  set +e
  "$@" >"${tmp}" 2>&1
  local rc=$?
  set -e

  local verdict="PASS"
  local class="OK"
  if [ "${rc}" -ne 0 ]; then
    verdict="FAIL"
    class="$(classify_failure "${label}" "${tmp}")"
  fi

  local summary
  summary="$(tail -n 1 "${tmp}" 2>/dev/null || true)"
  summary="$(sanitize_line "${summary:-no_output}")"

  printf "%s\t%s\tclass=%s\trc=%s\t%s\n" "${label}" "${verdict}" "${class}" "${rc}" "${summary}"

  if [ "${VERBOSE}" -eq 1 ] || [ "${rc}" -ne 0 ]; then
    sed 's/^/  /' "${tmp}" || true
  fi

  rm -f "${tmp}"
  return "${rc}"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --pr)
      PR_NUMBER="${2:-}"
      shift 2
      ;;
    --log)
      LOG_PATH="${2:-}"
      shift 2
      ;;
    --repo)
      REPO_PATH="${2:-}"
      shift 2
      ;;
    --soft)
      SOFT_MODE=1
      shift
      ;;
    --verbose)
      VERBOSE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR unknown_option=$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

require_exec "${REGISTRY_SCRIPT}"
require_exec "${COORD_SCRIPT}"
require_exec "${AUTH_SCRIPT}"
require_exec "${CROSS_SCRIPT}"

if [ ! -f "${LOG_PATH}" ]; then
  echo "ERROR missing_log=${LOG_PATH}" >&2
  exit 2
fi
if [ ! -d "${REPO_PATH}" ]; then
  echo "ERROR missing_repo=${REPO_PATH}" >&2
  exit 2
fi

overall=0

echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "log_path=${LOG_PATH}"
echo "repo_path=${REPO_PATH}"
if [ -n "${PR_NUMBER}" ]; then
  echo "pr=${PR_NUMBER}"
else
  echo "pr=none"
fi

echo "--- checks ---"
run_check registry "${REGISTRY_SCRIPT}" || overall=1
run_check coordination "${COORD_SCRIPT}" check "${LOG_PATH}" || overall=1
run_check gh_auth "${AUTH_SCRIPT}" check || overall=1

if [ -n "${PR_NUMBER}" ]; then
  run_check cross_review zsh -lc "cd '${REPO_PATH}' && '${CROSS_SCRIPT}' verify '${PR_NUMBER}'" || overall=1
else
  echo "cross_review\tSKIP\tclass=NA\trc=0\tpr_not_provided"
fi

if [ "${overall}" -eq 0 ]; then
  echo "FINAL_STATUS=PASS"
else
  echo "FINAL_STATUS=FAIL"
fi

if [ "${SOFT_MODE}" -eq 1 ]; then
  echo "SOFT_MODE=1 -> exit_code=0"
  exit 0
fi

exit "${overall}"
