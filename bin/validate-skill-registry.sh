#!/usr/bin/env zsh
set -euo pipefail

exit_code=0

codex_skills=(
  "/Users/others/.codex/skills/coordinate/SKILL.md"
  "/Users/others/.codex/skills/coordination-integrity/SKILL.md"
  "/Users/others/.codex/skills/gh-auth-recovery/SKILL.md"
  "/Users/others/.codex/skills/cross-review-gate/SKILL.md"
)

claude_commands=(
  "/Users/others/.claude/commands/coordinate.md"
  "/Users/others/.claude/commands/coordination-integrity.md"
  "/Users/others/.claude/commands/gh-auth-recovery.md"
  "/Users/others/.claude/commands/cross-review-gate.md"
)

scripts=(
  "/Users/others/bin/coordinate.sh"
  "/Users/others/bin/coordination-integrity.sh"
  "/Users/others/bin/gh-auth-recovery.sh"
  "/Users/others/bin/cross-review-gate.sh"
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
  check_pattern "${path}" '^#!/usr/bin/env zsh' 'shebang'
done

if [ "${exit_code}" -eq 0 ]; then
  echo "PASS registry_validation"
else
  echo "FAIL registry_validation"
fi

exit "${exit_code}"
