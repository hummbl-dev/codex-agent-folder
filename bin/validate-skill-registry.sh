#!/usr/bin/env zsh
set -euo pipefail

exit_code=0

codex_skills=(
  "/Users/others/.codex/skills/coordinate/SKILL.md"
  "/Users/others/.codex/skills/coordination-integrity/SKILL.md"
  "/Users/others/.codex/skills/coordination-dashboard/SKILL.md"
  "/Users/others/.codex/skills/coordination-gate/SKILL.md"
  "/Users/others/.codex/skills/coordination-gate-snapshot/SKILL.md"
  "/Users/others/.codex/skills/coordination-hooks/SKILL.md"
  "/Users/others/.codex/skills/session-heartbeat/SKILL.md"
  "/Users/others/.codex/skills/coordination-canonicalize/SKILL.md"
  "/Users/others/.codex/skills/gh-auth-recovery/SKILL.md"
  "/Users/others/.codex/skills/cross-review-gate/SKILL.md"
  "/Users/others/.codex/skills/ruleset-audit/SKILL.md"
  "/Users/others/.codex/skills/pr-readiness/SKILL.md"
  "/Users/others/.codex/skills/founder-briefing/SKILL.md"
  "/Users/others/.codex/skills/launchd-briefing-scheduler/SKILL.md"
)

claude_commands=(
  "/Users/others/.claude/commands/coordinate.md"
  "/Users/others/.claude/commands/coordination-integrity.md"
  "/Users/others/.claude/commands/coordination-dashboard.md"
  "/Users/others/.claude/commands/coordination-gate.md"
  "/Users/others/.claude/commands/coordination-gate-snapshot.md"
  "/Users/others/.claude/commands/coordination-hooks.md"
  "/Users/others/.claude/commands/session-heartbeat.md"
  "/Users/others/.claude/commands/coordination-canonicalize.md"
  "/Users/others/.claude/commands/gh-auth-recovery.md"
  "/Users/others/.claude/commands/cross-review-gate.md"
  "/Users/others/.claude/commands/ruleset-audit.md"
  "/Users/others/.claude/commands/pr-readiness.md"
  "/Users/others/.claude/commands/founder-briefing.md"
  "/Users/others/.claude/commands/launchd-briefing-scheduler.md"
)

scripts=(
  "/Users/others/bin/coordinate.sh"
  "/Users/others/bin/coordination-integrity.sh"
  "/Users/others/bin/coordination-dashboard.sh"
  "/Users/others/bin/coordination-gate.sh"
  "/Users/others/bin/coordination-gate-snapshot.sh"
  "/Users/others/bin/install-coordination-hooks.sh"
  "/Users/others/bin/session-heartbeat.sh"
  "/Users/others/bin/coordination-canonicalize.sh"
  "/Users/others/bin/gh-auth-recovery.sh"
  "/Users/others/bin/cross-review-gate.sh"
  "/Users/others/bin/ruleset-audit.sh"
  "/Users/others/bin/pr-readiness.sh"
  "/Users/others/bin/founder-briefing.sh"
  "/Users/others/bin/briefing-launchd.sh"
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
