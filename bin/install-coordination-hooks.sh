#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
BIN_DIR="${ROOT_DIR}/bin"
FOUNDER_REPO_DIR_DEFAULT="${ROOT_DIR}/founder-mode/founder-mode"

TARGET_REPO="${1:-${FOUNDER_REPO_DIR_DEFAULT}}"
HOOK_DIR="${TARGET_REPO}/.git/hooks"
GATE_SCRIPT="${BIN_DIR}/coordination-gate.sh"
AUTH_PREFLIGHT_SCRIPT="${BIN_DIR}/gh-auth-preflight.sh"

usage() {
  cat <<'EOF'
Usage:
  install-coordination-hooks.sh [repo_path]

Behavior:
  - Installs pre-commit and pre-push hooks that run:
      coordination-gate.sh check
      gh-auth-preflight.sh check (pre-push only)
  - Non-destructive: existing hooks are preserved as *.before-coordination
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ ! -d "${TARGET_REPO}/.git" ]; then
  echo "ERROR: target is not a git repo: ${TARGET_REPO}" >&2
  exit 2
fi

if [ ! -x "${GATE_SCRIPT}" ]; then
  echo "ERROR: gate script missing or not executable: ${GATE_SCRIPT}" >&2
  exit 2
fi
if [ ! -x "${AUTH_PREFLIGHT_SCRIPT}" ]; then
  echo "ERROR: auth preflight script missing or not executable: ${AUTH_PREFLIGHT_SCRIPT}" >&2
  exit 2
fi

mkdir -p "${HOOK_DIR}"

install_hook() {
  local hook_name="$1"
  local hook_path="${HOOK_DIR}/${hook_name}"
  local backup_path="${HOOK_DIR}/${hook_name}.before-coordination"

  if [ -f "${hook_path}" ] && [ ! -f "${backup_path}" ]; then
    cp "${hook_path}" "${backup_path}"
  fi

  if [ "${hook_name}" = "pre-push" ]; then
    cat > "${hook_path}" <<EOF
#!/usr/bin/env zsh
set -euo pipefail
${AUTH_PREFLIGHT_SCRIPT} check
${GATE_SCRIPT} check
EOF
  else
    cat > "${hook_path}" <<EOF
#!/usr/bin/env zsh
set -euo pipefail
${GATE_SCRIPT} check
EOF
  fi
  chmod +x "${hook_path}"
  echo "installed_hook ${hook_path}"
}

install_hook "pre-commit"
install_hook "pre-push"

echo "hooks_installed repo=${TARGET_REPO}"
