#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
BIN_DIR="${ROOT_DIR}/bin"

PREFLIGHT_SCRIPT="${BIN_DIR}/gh-auth-preflight.sh"

if [ "$#" -eq 0 ]; then
  echo "Usage: gh-safe.sh <gh arguments...>" >&2
  exit 2
fi

if [ ! -x "${PREFLIGHT_SCRIPT}" ]; then
  echo "ERROR: missing preflight script: ${PREFLIGHT_SCRIPT}" >&2
  exit 2
fi

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
  if [ -n "${candidate}" ] && [ -x "${candidate}" ] && [ "${candidate}" != "${BIN_DIR}/gh" ]; then
    printf "%s\n" "${candidate}"
    return
  fi
  printf "%s\n" ""
}

GH_BIN="$(resolve_gh_bin)"
if [ -z "${GH_BIN}" ]; then
  echo "ERROR: cannot resolve real gh binary" >&2
  exit 2
fi

GH_REAL_BIN="${GH_BIN}" "${PREFLIGHT_SCRIPT}" check
exec "${GH_BIN}" "$@"
