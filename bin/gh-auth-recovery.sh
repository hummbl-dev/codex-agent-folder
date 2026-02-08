#!/usr/bin/env zsh
set -euo pipefail

PREFLIGHT_SCRIPT="/Users/others/bin/gh-auth-preflight.sh"
GH_SAFE_SCRIPT="/Users/others/bin/gh-safe.sh"

usage() {
  cat <<'USAGE'
Usage:
  gh-auth-recovery.sh check
  gh-auth-recovery.sh diagnose
  gh-auth-recovery.sh run <gh args...>
  gh-auth-recovery.sh status

Modes:
  check     Strict pass/fail auth gate.
  diagnose  Receipt-backed diagnostics and fix order.
  run       Execute gh command with GH_TOKEN/GITHUB_TOKEN removed.
  status    Short auth status summary.
USAGE
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
  if [ -n "${candidate}" ] && [ -x "${candidate}" ] && [ "${candidate}" != "/Users/others/bin/gh" ]; then
    printf "%s\n" "${candidate}"
    return
  fi
  printf "%s\n" ""
}

check_requirements() {
  if [ ! -x "${PREFLIGHT_SCRIPT}" ]; then
    echo "ERROR: missing ${PREFLIGHT_SCRIPT}" >&2
    exit 2
  fi
  if [ ! -x "${GH_SAFE_SCRIPT}" ]; then
    echo "ERROR: missing ${GH_SAFE_SCRIPT}" >&2
    exit 2
  fi
}

run_check() {
  "${PREFLIGHT_SCRIPT}" check
}

run_status() {
  local overrides="0"
  if [ -n "${GH_TOKEN:-}" ] || [ -n "${GITHUB_TOKEN:-}" ]; then
    overrides="1"
  fi

  local gh_bin
  gh_bin="$(resolve_gh_bin)"
  echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "env_override_present=${overrides}"
  echo "gh_bin=${gh_bin:-not_found}"

  if [ -z "${gh_bin}" ]; then
    echo "gh_auth_status=unavailable"
    return 1
  fi

  local auth_line
  local auth_output
  local rc=0
  auth_output="$(unset GH_TOKEN GITHUB_TOKEN; "${gh_bin}" auth status 2>&1)" || rc=$?
  auth_line="${auth_output%%$'\n'*}"

  echo "gh_auth_status_exit=${rc}"
  echo "gh_auth_status_line=${auth_line}"
  return "${rc}"
}

run_diagnose() {
  echo "### GH Auth Diagnose ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
  echo "1) Preflight (warn mode):"
  set +e
  "${PREFLIGHT_SCRIPT}" warn
  local preflight_rc=$?
  set -e
  echo "preflight_exit=${preflight_rc}"

  echo "2) Current status summary:"
  set +e
  run_status
  local status_rc=$?
  set -e

  echo "3) Deterministic fix order:"
  echo "- Detect env overrides: GH_TOKEN/GITHUB_TOKEN"
  echo "- Unset overrides for command execution"
  echo "- Verify keyring auth with gh auth status"
  echo "- Escalate PAT scope only with direct scope evidence"

  return "${status_rc}"
}

run_safe() {
  if [ "$#" -eq 0 ]; then
    echo "ERROR: run mode requires gh arguments" >&2
    exit 2
  fi
  (unset GH_TOKEN GITHUB_TOKEN; "${GH_SAFE_SCRIPT}" "$@")
}

main() {
  check_requirements

  local action="${1:-check}"
  shift || true

  case "${action}" in
    check)
      run_check
      ;;
    diagnose)
      run_diagnose
      ;;
    run)
      run_safe "$@"
      ;;
    status)
      run_status
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
