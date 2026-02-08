#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
BIN_DIR="${ROOT_DIR}/bin"
WRAPPER_GH="${BIN_DIR}/gh"

GH_AUTH_RECOVERY_SCRIPT="${BIN_DIR}/gh-auth-recovery.sh"

usage() {
  cat <<'USAGE'
Usage:
  cross-review-gate.sh status <pr>
  cross-review-gate.sh verify <pr>
  cross-review-gate.sh approve <pr>

Actions:
  status  Show PR review/check summary.
  verify  Enforce merge-readiness gate.
  approve Submit non-author approval via safe gh path.
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
  if [ -n "${candidate}" ] && [ -x "${candidate}" ] && [ "${candidate}" != "${WRAPPER_GH}" ]; then
    printf "%s\n" "${candidate}"
    return
  fi
  printf "%s\n" ""
}

gh_read_exec() {
  local gh_bin
  gh_bin="$(resolve_gh_bin)"
  if [ -z "${gh_bin}" ]; then
    echo "ERROR: cannot resolve gh binary" >&2
    return 2
  fi
  (unset GH_TOKEN GITHUB_TOKEN; "${gh_bin}" "$@")
}

gh_write_exec() {
  if [ ! -x "${GH_AUTH_RECOVERY_SCRIPT}" ]; then
    echo "ERROR: missing ${GH_AUTH_RECOVERY_SCRIPT}" >&2
    return 2
  fi
  "${GH_AUTH_RECOVERY_SCRIPT}" run "$@"
}

fetch_pr_json() {
  local pr="$1"
  local out
  if ! out="$(gh_read_exec pr view "${pr}" --json number,title,url,state,mergeStateStatus,reviewDecision,author,reviews,statusCheckRollup 2>&1)"; then
    echo "ERROR: unable to fetch PR ${pr}" >&2
    echo "${out}" >&2
    return 1
  fi
  printf "%s\n" "${out}"
}

print_status() {
  local json="$1"
  PR_JSON="${json}" python3 - <<'PY'
import json
import os

data = json.loads(os.environ["PR_JSON"])
author = (data.get("author") or {}).get("login", "unknown")
checks = data.get("statusCheckRollup") or []
approvals = [r for r in (data.get("reviews") or []) if r.get("state") == "APPROVED"]
non_author_approvals = [r for r in approvals if (r.get("author") or {}).get("login") != author]

print(f"PR #{data.get('number')} {data.get('title')}")
print(f"url={data.get('url')}")
print(f"state={data.get('state')} mergeStateStatus={data.get('mergeStateStatus')} reviewDecision={data.get('reviewDecision')}")
print(f"author={author} approvals_total={len(approvals)} approvals_non_author={len(non_author_approvals)}")
print("checks:")
for check in checks:
    name = check.get("name", "unknown")
    status = check.get("status", "UNKNOWN")
    conclusion = check.get("conclusion") or "pending"
    print(f"- {name}: {status} ({conclusion})")
PY
}

evaluate_gate() {
  local json="$1"
  local mode="$2"

  PR_JSON="${json}" python3 - "$mode" <<'PY'
import json
import os
import sys

mode = sys.argv[1]
data = json.loads(os.environ["PR_JSON"])

reasons = []
author = (data.get("author") or {}).get("login", "unknown")
state = data.get("state")
checks = data.get("statusCheckRollup") or []
reviews = data.get("reviews") or []

if state != "OPEN":
    reasons.append(f"state={state} (expected OPEN)")

ok_conclusions = {"SUCCESS", "NEUTRAL", "SKIPPED"}
for check in checks:
    name = check.get("name", "unknown")
    status = check.get("status", "UNKNOWN")
    conclusion = check.get("conclusion") or "pending"
    if status != "COMPLETED":
        reasons.append(f"check_not_completed:{name}:{status}")
    elif conclusion not in ok_conclusions:
        reasons.append(f"check_not_green:{name}:{conclusion}")

if mode == "full":
    approvals = [r for r in reviews if r.get("state") == "APPROVED"]
    non_author_approvals = [
        r for r in approvals
        if (r.get("author") or {}).get("login") != author
    ]
    if len(non_author_approvals) == 0:
        reasons.append("no_non_author_approval")

if reasons:
    print("GATE=FAIL")
    for reason in reasons:
        print(f"reason={reason}")
    sys.exit(1)

print("GATE=PASS")
sys.exit(0)
PY
}

approve_pr() {
  local pr="$1"
  local json
  json="$(fetch_pr_json "${pr}")"

  print_status "${json}"
  evaluate_gate "${json}" basic

  gh_write_exec pr review "${pr}" --approve --body "Cross-review approval via cross-review-gate."
  echo "approval_submitted=1 pr=${pr}"
}

main() {
  local action="${1:-}"
  local pr="${2:-}"

  if [ -z "${action}" ]; then
    usage >&2
    exit 2
  fi

  case "${action}" in
    status|verify|approve)
      if [ -z "${pr}" ]; then
        echo "ERROR: action '${action}' requires <pr>" >&2
        usage >&2
        exit 2
      fi
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac

  local json
  case "${action}" in
    status)
      json="$(fetch_pr_json "${pr}")"
      print_status "${json}"
      ;;
    verify)
      json="$(fetch_pr_json "${pr}")"
      print_status "${json}"
      evaluate_gate "${json}" full
      ;;
    approve)
      approve_pr "${pr}"
      ;;
  esac
}

main "$@"
