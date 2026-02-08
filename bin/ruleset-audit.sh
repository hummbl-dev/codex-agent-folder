#!/usr/bin/env zsh
set -euo pipefail

# ruleset-audit.sh
# Read-only audit of GitHub rulesets (and minimal branch-protection signals)
# for drift detection. Writes optional receipts; never mutates repo settings.

ROOT_DIR="${0:A:h:h}"

usage() {
  cat <<'EOF'
Usage:
  ruleset-audit.sh [--repo owner/name] [--expect "name=enforcement,..."] [--out-dir <dir>] [--soft]

Defaults:
  --repo hummbl-dev/founder-mode
  --out-dir $WORKSPACE_ROOT/_state/coordination/ruleset-audit

Options:
  --expect   Comma-separated expectations. Example:
               "main-core-governance=active,main-required-checks=active"
             Enforcement values are GitHub ruleset enforcement strings (e.g., active, disabled).
  --soft     Never exit non-zero (still prints FAIL lines).

Notes:
  - Uses gh API; for auth override issues, run via:
      env -u GH_TOKEN -u GITHUB_TOKEN ruleset-audit.sh
EOF
}

REPO="hummbl-dev/founder-mode"
EXPECT=""
OUT_DIR="${ROOT_DIR}/_state/coordination/ruleset-audit"
SOFT=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      REPO="${2:-}"; shift 2
      ;;
    --expect)
      EXPECT="${2:-}"; shift 2
      ;;
    --out-dir)
      OUT_DIR="${2:-}"; shift 2
      ;;
    --soft)
      SOFT=1; shift
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

if [ -z "${REPO}" ] || ! printf "%s" "${REPO}" | /usr/bin/awk -F/ 'NF==2{ok=1} END{exit(!ok)}'; then
  echo "ERROR: --repo must be owner/name" >&2
  exit 2
fi

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
mkdir -p "${OUT_DIR}"
chmod 700 "${OUT_DIR}" 2>/dev/null || true

raw_json_path="${OUT_DIR}/rulesets_${ts}.json"
summary_path="${OUT_DIR}/rulesets_${ts}.summary.txt"

set +e
raw_json="$(env -u GH_TOKEN -u GITHUB_TOKEN gh api -H "Accept: application/vnd.github+json" "repos/${REPO}/rulesets?per_page=100" 2>&1)"
rc=$?
set -e

printf "%s\n" "${raw_json}" > "${raw_json_path}"

if [ "${rc}" -ne 0 ]; then
  echo "FAIL ruleset_audit repo=${REPO} ts=${ts} reason=gh_api_error rc=${rc} receipt=${raw_json_path}"
  if [ "${SOFT}" -eq 1 ]; then
    exit 0
  fi
  exit 1
fi

python3 - <<'PY' "${REPO}" "${EXPECT}" "${ts}" "${raw_json_path}" "${summary_path}"
import json
import sys
from pathlib import Path

repo, expect, ts, raw_path, summary_path = sys.argv[1:6]
raw = Path(raw_path).read_text()
data = json.loads(raw) if raw.strip() else []

def norm(s: str) -> str:
  return (s or "").strip()

rulesets = []
for r in data:
  rulesets.append({
    "id": r.get("id"),
    "name": r.get("name"),
    "enforcement": r.get("enforcement"),
    "target": r.get("target"),
    "conditions": r.get("conditions") or {},
  })

exp = {}
if expect:
  for part in expect.split(","):
    part = part.strip()
    if not part:
      continue
    if "=" not in part:
      raise SystemExit(f"ERROR: bad --expect entry (expected name=enforcement): {part}")
    k, v = part.split("=", 1)
    exp[norm(k)] = norm(v)

lines = []
lines.append(f"ts={ts}")
lines.append(f"repo={repo}")
lines.append(f"rulesets={len(rulesets)}")
lines.append("")
lines.append("name\tenforcement\ttarget\tinclude_refs")
for r in sorted(rulesets, key=lambda x: (x["name"] or "")):
  include = ""
  cond = (r.get("conditions") or {}).get("ref_name") or {}
  if isinstance(cond, dict):
    inc = cond.get("include") or []
    include = ",".join(inc) if isinstance(inc, list) else str(inc)
  lines.append(f"{r.get('name')}\t{r.get('enforcement')}\t{r.get('target')}\t{include}")

fails = []
for name, enforcement in exp.items():
  match = next((r for r in rulesets if norm(r.get("name")) == name), None)
  if not match:
    fails.append(f"missing:{name}")
  else:
    got = norm(match.get("enforcement"))
    if got != enforcement:
      fails.append(f"enforcement_mismatch:{name}:{got}!={enforcement}")

Path(summary_path).write_text("\n".join(lines) + "\n")

if fails:
  print(f"FAIL ruleset_audit repo={repo} ts={ts} fails={','.join(fails)} summary={summary_path} raw={raw_path}")
  sys.exit(1)

print(f"PASS ruleset_audit repo={repo} ts={ts} summary={summary_path} raw={raw_path}")
PY

rc="$?"
if [ "${rc}" -ne 0 ] && [ "${SOFT}" -eq 1 ]; then
  exit 0
fi
exit "${rc}"
