#!/usr/bin/env zsh
set -euo pipefail

exit_code=0

ROOT_DIR="${0:A:h:h}"

codex_skills=(
  "${HOME}/.codex/skills/coordinate/SKILL.md"
  "${HOME}/.codex/skills/coordination-integrity/SKILL.md"
  "${HOME}/.codex/skills/coordination-dashboard/SKILL.md"
  "${HOME}/.codex/skills/coordination-gate/SKILL.md"
  "${HOME}/.codex/skills/coordination-gate-snapshot/SKILL.md"
  "${HOME}/.codex/skills/coordination-hooks/SKILL.md"
  "${HOME}/.codex/skills/session-heartbeat/SKILL.md"
  "${HOME}/.codex/skills/coordination-canonicalize/SKILL.md"
  "${HOME}/.codex/skills/gh-auth-recovery/SKILL.md"
  "${HOME}/.codex/skills/cross-review-gate/SKILL.md"
  "${HOME}/.codex/skills/ruleset-audit/SKILL.md"
  "${HOME}/.codex/skills/pr-readiness/SKILL.md"
  "${HOME}/.codex/skills/founder-briefing/SKILL.md"
  "${HOME}/.codex/skills/launchd-briefing-scheduler/SKILL.md"
)

claude_commands=(
  "${HOME}/.claude/commands/coordinate.md"
  "${HOME}/.claude/commands/coordination-integrity.md"
  "${HOME}/.claude/commands/coordination-dashboard.md"
  "${HOME}/.claude/commands/coordination-gate.md"
  "${HOME}/.claude/commands/coordination-gate-snapshot.md"
  "${HOME}/.claude/commands/coordination-hooks.md"
  "${HOME}/.claude/commands/session-heartbeat.md"
  "${HOME}/.claude/commands/coordination-canonicalize.md"
  "${HOME}/.claude/commands/gh-auth-recovery.md"
  "${HOME}/.claude/commands/cross-review-gate.md"
  "${HOME}/.claude/commands/ruleset-audit.md"
  "${HOME}/.claude/commands/pr-readiness.md"
  "${HOME}/.claude/commands/founder-briefing.md"
  "${HOME}/.claude/commands/launchd-briefing-scheduler.md"
)

scripts=(
  "${ROOT_DIR}/bin/coordinate.sh"
  "${ROOT_DIR}/bin/coordination-integrity.sh"
  "${ROOT_DIR}/bin/coordination-dashboard.sh"
  "${ROOT_DIR}/bin/coordination-gate.sh"
  "${ROOT_DIR}/bin/coordination-gate-snapshot.sh"
  "${ROOT_DIR}/bin/install-coordination-hooks.sh"
  "${ROOT_DIR}/bin/session-heartbeat.sh"
  "${ROOT_DIR}/bin/coordination-canonicalize.sh"
  "${ROOT_DIR}/bin/gh-auth-recovery.sh"
  "${ROOT_DIR}/bin/cross-review-gate.sh"
  "${ROOT_DIR}/bin/ruleset-audit.sh"
  "${ROOT_DIR}/bin/pr-readiness.sh"
  "${ROOT_DIR}/bin/founder-briefing.sh"
  "${ROOT_DIR}/bin/briefing-launchd.sh"
)

check_file() {
  local path="$1"
  if [ ! -f "${path}" ]; then
    echo "FAIL missing_file ${path}"
    exit_code=1
    return 1
  fi
  echo "PASS file_exists ${path}"
  return 0
}

match_pattern() {
  local pattern="$1"
  local path="$2"
  /usr/bin/awk -v pat="${pattern}" '
    $0 ~ pat { found=1; exit }
    END { exit(found ? 0 : 1) }
  ' "${path}"
}

check_pattern() {
  local path="$1"
  local pattern="$2"
  local label="$3"
  if match_pattern "${pattern}" "${path}"; then
    echo "PASS ${label} ${path}"
  else
    echo "FAIL ${label} ${path}"
    exit_code=1
  fi
}

for path in "${codex_skills[@]}"; do
  check_file "${path}" || continue
  check_pattern "${path}" '^---$' 'frontmatter'
  check_pattern "${path}" '^## Quick Start' 'quick_start'
  check_pattern "${path}" '^## Workflow' 'workflow'
  check_pattern "${path}" '^## Validation Commands' 'validation_commands'
done

for path in "${claude_commands[@]}"; do
  check_file "${path}" || continue
  check_pattern "${path}" '^name:' 'name_field'
  check_pattern "${path}" '^## Usage' 'usage_section'
  check_pattern "${path}" '^## Actions' 'actions_section'
done

for path in "${scripts[@]}"; do
  check_file "${path}" || continue
  if [ -x "${path}" ]; then
    echo "PASS executable ${path}"
  else
    echo "FAIL executable ${path}"
    exit_code=1
  fi
  check_pattern "${path}" '^#!/usr/bin/env (zsh|bash)$' 'shebang'
done

if [ "${exit_code}" -eq 0 ]; then
  echo "PASS registry_validation"
else
  echo "FAIL registry_validation"
fi

exit "${exit_code}"
