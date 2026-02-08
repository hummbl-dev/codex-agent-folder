#!/usr/bin/env zsh
set -euo pipefail

MODE="${1:-check}"
LOG_DIR="${GH_PREFLIGHT_LOG_DIR:-/Users/others/_state/coordination}"
LOG_FILE="${GH_PREFLIGHT_LOG_FILE:-${LOG_DIR}/gh-auth-preflight.tsv}"
AGENT="${AGENT_NAME:-unknown}"

usage() {
  cat <<'EOF'
Usage:
  gh-auth-preflight.sh [check|warn]

Modes:
  check  Enforce pass/fail; exits non-zero on auth risk/failure.
  warn   Report + log only; never blocks caller.
EOF
}

sanitize() {
  local raw="$1"
  raw="${raw//$'\t'/ }"
  raw="${raw//$'\r'/ }"
  raw="${raw//$'\n'/ }"
  printf "%s\n" "${raw}" | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//'
}

resolve_gh_bin() {
  if [ -n "${GH_REAL_BIN:-}" ] && [ -x "${GH_REAL_BIN}" ]; then
    printf "%s\n" "${GH_REAL_BIN}"
    return
  fi
  if [ -x "/usr/local/bin/gh" ]; then
    printf "%s\n" "/usr/local/bin/gh"
    return
  fi
  local candidate
  candidate="$(command -v gh 2>/dev/null || true)"
  if [ -n "${candidate}" ] && [ -x "${candidate}" ]; then
    printf "%s\n" "${candidate}"
    return
  fi
  printf "%s\n" ""
}

if [ "${MODE}" != "check" ] && [ "${MODE}" != "warn" ]; then
  if [ "${MODE}" = "-h" ] || [ "${MODE}" = "--help" ] || [ "${MODE}" = "help" ]; then
    usage
    exit 0
  fi
  usage >&2
  exit 2
fi

mkdir -p "${LOG_DIR}"
if [ ! -f "${LOG_FILE}" ]; then
  printf "timestamp_utc\tagent\tmode\toverrides_present\tgh_status_exit\tresult\tsummary\n" > "${LOG_FILE}"
fi

timestamp_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
overrides_present=0
if [ -n "${GH_TOKEN:-}" ] || [ -n "${GITHUB_TOKEN:-}" ]; then
  overrides_present=1
fi

gh_status_exit=0
result="PASS"
summary=""

if [ "${overrides_present}" -eq 1 ]; then
  result="FAIL"
  summary="env_override_detected: unset GH_TOKEN/GITHUB_TOKEN before gh auth status"
fi

GH_BIN="$(resolve_gh_bin)"
if [ -z "${GH_BIN}" ]; then
  gh_status_exit=127
  result="FAIL"
  summary="gh_not_found"
else
  set +e
  gh_output="$("${GH_BIN}" auth status 2>&1)"
  gh_status_exit=$?
  set -e

  if [ -z "${summary}" ]; then
    summary="$(printf "%s\n" "${gh_output}" | head -n 1)"
  else
    summary="${summary}; $(printf "%s\n" "${gh_output}" | head -n 1)"
  fi

  if [ "${gh_status_exit}" -ne 0 ]; then
    result="FAIL"
  fi
fi

summary="$(sanitize "${summary}")"
printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
  "${timestamp_utc}" \
  "${AGENT}" \
  "${MODE}" \
  "${overrides_present}" \
  "${gh_status_exit}" \
  "${result}" \
  "${summary}" >> "${LOG_FILE}"

printf "gh_auth_preflight mode=%s result=%s overrides=%s gh_status_exit=%s\n" \
  "${MODE}" "${result}" "${overrides_present}" "${gh_status_exit}"

if [ "${MODE}" = "warn" ]; then
  exit 0
fi

if [ "${result}" = "PASS" ]; then
  exit 0
fi

exit 1
