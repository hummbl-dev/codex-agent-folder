#!/usr/bin/env zsh
set -euo pipefail

# briefing-launchd.sh
# LaunchAgent helper for Founder Mode briefing scheduler (runs scheduler --once on interval).
# Non-destructive: backs up any existing plist before overwriting.

usage() {
  cat <<'EOF'
Usage:
  briefing-launchd.sh render [--repo-dir <path>] [--label <label>] [--interval <seconds>]
  briefing-launchd.sh install [--repo-dir <path>] [--label <label>] [--interval <seconds>]
  briefing-launchd.sh status [--label <label>]
  briefing-launchd.sh uninstall [--label <label>]

Defaults:
  --repo-dir  /Users/others/founder-mode/founder-mode
  --label     ai.founder-mode.briefing
  --interval  60

Notes:
  - The scheduler computes T-30 before wake time from founder_mode/state/preferences.json.
  - This installs under ~/Library/LaunchAgents (user domain).
  - No secrets should be placed in the plist environment.
EOF
}

REPO_DIR="/Users/others/founder-mode/founder-mode"
LABEL="ai.founder-mode.briefing"
INTERVAL="60"

action="${1:-}"
shift || true

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo-dir)
      REPO_DIR="${2:-}"; shift 2
      ;;
    --label)
      LABEL="${2:-}"; shift 2
      ;;
    --interval)
      INTERVAL="${2:-}"; shift 2
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

if ! [[ "${INTERVAL}" =~ ^[0-9]+$ ]] || [ "${INTERVAL}" -lt 10 ]; then
  echo "ERROR: --interval must be integer seconds (>=10)" >&2
  exit 2
fi

PLIST_DIR="${HOME}/Library/LaunchAgents"
PLIST_PATH="${PLIST_DIR}/${LABEL}.plist"
UID_NUM="$(id -u)"

python_path() {
  if [ -x "${REPO_DIR}/.venv/bin/python" ]; then
    printf "%s\n" "${REPO_DIR}/.venv/bin/python"
  else
    command -v python3
  fi
}

render_plist() {
  local py
  py="$(python_path)"
  if [ -z "${py}" ]; then
    echo "ERROR: python not found" >&2
    return 2
  fi
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>

  <key>WorkingDirectory</key>
  <string>${REPO_DIR}</string>

  <key>ProgramArguments</key>
  <array>
    <string>${py}</string>
    <string>-m</string>
    <string>founder_mode.services.scheduler</string>
    <string>--once</string>
  </array>

  <key>EnvironmentVariables</key>
  <dict>
    <key>PYTHONPATH</key>
    <string>.</string>
  </dict>

  <key>StartInterval</key>
  <integer>${INTERVAL}</integer>

  <key>StandardOutPath</key>
  <string>${HOME}/Library/Logs/founder-mode-briefing.out.log</string>
  <key>StandardErrorPath</key>
  <string>${HOME}/Library/Logs/founder-mode-briefing.err.log</string>
</dict>
</plist>
EOF
}

case "${action}" in
  render)
    if [ ! -d "${REPO_DIR}" ]; then
      echo "ERROR: repo dir missing: ${REPO_DIR}" >&2
      exit 2
    fi
    render_plist
    ;;
  install)
    if [ ! -d "${REPO_DIR}" ]; then
      echo "ERROR: repo dir missing: ${REPO_DIR}" >&2
      exit 2
    fi
    mkdir -p "${PLIST_DIR}"
    if [ -f "${PLIST_PATH}" ]; then
      backup="${PLIST_PATH}.backup.$(date -u +%Y-%m-%dT%H%M%SZ)"
      cp -p "${PLIST_PATH}" "${backup}"
      echo "backup_created ${backup}"
    fi
    render_plist > "${PLIST_PATH}"
    chmod 600 "${PLIST_PATH}" || true
    echo "plist_written ${PLIST_PATH}"

    # (Re)load
    launchctl bootout "gui/${UID_NUM}" "${PLIST_PATH}" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/${UID_NUM}" "${PLIST_PATH}"
    echo "installed label=${LABEL} domain=gui/${UID_NUM} interval=${INTERVAL}"
    ;;
  status)
    launchctl print "gui/${UID_NUM}/${LABEL}" 2>&1 | sed -n '1,200p'
    ;;
  uninstall)
    if [ -f "${PLIST_PATH}" ]; then
      launchctl bootout "gui/${UID_NUM}" "${PLIST_PATH}" >/dev/null 2>&1 || true
      disabled="${PLIST_PATH}.disabled.$(date -u +%Y-%m-%dT%H%M%SZ)"
      mv "${PLIST_PATH}" "${disabled}"
      echo "uninstalled bootout=1 plist_renamed_to=${disabled}"
    else
      echo "uninstall_noop missing_plist=${PLIST_PATH}"
    fi
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

