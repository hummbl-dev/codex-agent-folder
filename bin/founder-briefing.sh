#!/usr/bin/env zsh
set -euo pipefail

# founder-briefing.sh
# Operator wrapper around Founder Mode Morning Briefing (Wave 1).

DEFAULT_REPO_DIR="/Users/others/founder-mode/founder-mode"

usage() {
  cat <<'EOF'
Usage:
  founder-briefing.sh test [--repo-dir <path>]
  founder-briefing.sh check [--repo-dir <path>] [--config <path>]
  founder-briefing.sh run [--repo-dir <path>] [--config <path>] [--force]
  founder-briefing.sh status [--repo-dir <path>] [--config <path>]

Defaults:
  --repo-dir /Users/others/founder-mode/founder-mode
  --config   founder_mode/state/preferences.json (repo-relative)

Notes:
  - This script is read/write only within the founder-mode repo state paths.
  - Generated briefings should remain gitignored (see repo .gitignore).
EOF
}

REPO_DIR="${DEFAULT_REPO_DIR}"
CONFIG_REL="founder_mode/state/preferences.json"
FORCE=0

action="${1:-}"
shift || true

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo-dir)
      REPO_DIR="${2:-}"; shift 2
      ;;
    --config)
      CONFIG_REL="${2:-}"; shift 2
      ;;
    --force)
      FORCE=1; shift
      ;;
    -h|--help|help)
      usage; exit 0
      ;;
    *)
      echo "ERROR: unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "${action}" ]; then
  usage
  exit 2
fi
if [ ! -d "${REPO_DIR}" ]; then
  echo "ERROR: repo dir missing: ${REPO_DIR}" >&2
  exit 2
fi

python_exec() {
  if [ -x "${REPO_DIR}/.venv/bin/python" ]; then
    printf "%s\n" "${REPO_DIR}/.venv/bin/python"
  else
    command -v python3
  fi
}

run_in_repo() {
  (cd "${REPO_DIR}" && "$@")
}

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
py="$(python_exec)"
if [ -z "${py}" ]; then
  echo "ERROR: python not found" >&2
  exit 2
fi

case "${action}" in
  test)
    echo "founder_briefing test ts=${ts} repo_dir=${REPO_DIR}"
    run_in_repo "${py}" -m pytest founder_mode/tests -q
    ;;
  check)
    echo "founder_briefing check ts=${ts} repo_dir=${REPO_DIR} config=${CONFIG_REL}"
    set +e
    out="$(run_in_repo env PYTHONPATH=. "${py}" -m founder_mode.services.scheduler --config "${CONFIG_REL}" --check 2>&1)"
    rc="$?"
    set -e
    printf "%s\n" "${out}"
    exit "${rc}"
    ;;
  status)
    echo "founder_briefing status ts=${ts} repo_dir=${REPO_DIR} config=${CONFIG_REL}"
    run_in_repo env PYTHONPATH=. "${py}" -m founder_mode.services.scheduler --config "${CONFIG_REL}"
    ;;
  run)
    echo "founder_briefing run ts=${ts} repo_dir=${REPO_DIR} config=${CONFIG_REL} force=${FORCE}"
    if [ "${FORCE}" -eq 1 ]; then
      run_in_repo env PYTHONPATH=. "${py}" -m founder_mode.services.scheduler --config "${CONFIG_REL}" --force
    else
      run_in_repo env PYTHONPATH=. "${py}" -m founder_mode.services.scheduler --config "${CONFIG_REL}" --once
    fi
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

