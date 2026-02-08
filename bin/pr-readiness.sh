#!/usr/bin/env zsh
set -euo pipefail

# pr-readiness.sh
# Read-only PR readiness report (CI + review + mergeability + cross-review gate).

usage() {
  cat <<'EOF'
Usage:
  pr-readiness.sh <pr_number> [--repo-dir <path>] [--soft]

Defaults:
  --repo-dir /Users/others/founder-mode/founder-mode

Notes:
  - Uses gh API; avoid auth override issues via:
      env -u GH_TOKEN -u GITHUB_TOKEN /Users/others/bin/pr-readiness.sh <pr>
EOF
}

PR="${1:-}"
if [ -z "${PR}" ] || [[ "${PR}" = "-h" ]] || [[ "${PR}" = "--help" ]]; then
  usage
  exit 2
fi
shift

REPO_DIR="/Users/others/founder-mode/founder-mode"
SOFT=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo-dir)
      REPO_DIR="${2:-}"; shift 2
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

if ! [[ "${PR}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: pr_number must be an integer" >&2
  exit 2
fi
if [ ! -d "${REPO_DIR}" ]; then
  echo "ERROR: repo dir missing: ${REPO_DIR}" >&2
  exit 2
fi

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "pr_readiness ts=${ts} pr=${PR} repo_dir=${REPO_DIR}"

set +e
pr_json="$(cd "${REPO_DIR}" && env -u GH_TOKEN -u GITHUB_TOKEN gh pr view "${PR}" --json number,state,isDraft,mergeable,reviewDecision,headRefName,baseRefName,url,author,statusCheckRollup 2>&1)"
rc="$?"
set -e

if [ "${rc}" -ne 0 ]; then
  echo "FAIL pr_readiness reason=gh_pr_view_error rc=${rc}"
  echo "${pr_json}" | sed -n '1,40p'
  [ "${SOFT}" -eq 1 ] && exit 0
  exit 1
fi

OUT_DIR="/Users/others/_state/coordination/pr-readiness"
mkdir -p "${OUT_DIR}"
chmod 700 "${OUT_DIR}" 2>/dev/null || true
receipt_json="${OUT_DIR}/pr_${PR}_${ts}.json"
printf "%s\n" "${pr_json}" > "${receipt_json}"

python3 - <<'PY' "${receipt_json}"
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text())

checks = data.get("statusCheckRollup") or []
summary = {"total": 0, "success": 0, "fail": 0, "pending": 0}
lines = []
for c in checks:
  name = c.get("name")
  status = c.get("status")
  concl = c.get("conclusion") or ""
  summary["total"] += 1
  if status != "COMPLETED":
    summary["pending"] += 1
  elif concl == "SUCCESS":
    summary["success"] += 1
  elif concl:
    summary["fail"] += 1
  else:
    summary["pending"] += 1
  lines.append(f"  - {name}: {status} ({concl or 'pending'})")

print(f"receipt_json={path}")
print(f"url={data.get('url')}")
print(f"state={data.get('state')} draft={data.get('isDraft')} mergeable={data.get('mergeable')} reviewDecision={data.get('reviewDecision')}")
print(f"head={data.get('headRefName')} base={data.get('baseRefName')} author={data.get('author',{}).get('login')}")
print(f"checks_total={summary['total']} checks_success={summary['success']} checks_fail={summary['fail']} checks_pending={summary['pending']}")
if lines:
  print("checks:")
  print("\n".join(lines))
PY

exit_code=0

set +e
cross_out="$(cd "${REPO_DIR}" && /Users/others/bin/cross-review-gate.sh verify "${PR}" 2>&1)"
cross_rc="$?"
set -e
if [ "${cross_rc}" -ne 0 ]; then
  echo "FAIL cross_review_gate rc=${cross_rc}"
  echo "${cross_out}" | sed -n '1,40p'
  exit_code=1
else
  echo "PASS cross_review_gate"
fi

set +e
coord_gate_out="$(/Users/others/bin/coordination-gate.sh check 2>&1)"
coord_gate_rc="$?"
set -e
if [ "${coord_gate_rc}" -ne 0 ]; then
  echo "FAIL coordination_gate rc=${coord_gate_rc}"
  echo "${coord_gate_out}" | tail -n 1
  exit_code=1
else
  echo "PASS coordination_gate"
fi

if [ "${exit_code}" -ne 0 ]; then
  echo "FAIL pr_readiness pr=${PR} ts=${ts}"
  [ "${SOFT}" -eq 1 ] && exit 0
  exit 1
fi

echo "PASS pr_readiness pr=${PR} ts=${ts}"
exit 0
