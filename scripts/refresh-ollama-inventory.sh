#!/usr/bin/env bash
set -euo pipefail

# refresh-ollama-inventory.sh
# Purpose: Generate daily Ollama inventory artifacts (.txt, .csv) and OSI-licensed tag list.
# Timestamps are UTC (ISO-8601-like, safe for filenames).
#
# Usage:
#   scripts/refresh-ollama-inventory.sh [--no-start-daemon] [--commit] [--push]
#
# Behavior:
# - Writes artifacts to codex-agent-folder/artifacts/ollama/
# - Tries to contact Ollama daemon at 127.0.0.1:11434; if unavailable and not suppressed,
#   attempts to start with `ollama serve` locally.
# - If daemon remains unreachable, falls back to enumerating manifests in ~/.ollama/models.
# - With --commit, creates a single commit (GPG signing disabled) for new artifacts.
# - With --push, pushes to origin/main (requires approval and network access).

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
OUT_DIR="$REPO_DIR/artifacts/ollama"
mkdir -p "$OUT_DIR"

NO_START=0
DO_COMMIT=0
DO_PUSH=0
for arg in "$@"; do
  case "$arg" in
    --no-start-daemon) NO_START=1 ;;
    --commit) DO_COMMIT=1 ;;
    --push) DO_PUSH=1 ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

TS=$(date -u +%Y-%m-%dT%H-%M-%SZ)
TXT="$OUT_DIR/ollama-list-$TS.txt"
CSV="$OUT_DIR/ollama-list-$TS.csv"
OSI="$OUT_DIR/osi-licensed-ollama-models-$TS.txt"

OLLAMA_BIN="${OLLAMA_BIN:-$(command -v ollama || true)}"
PING() { curl -sSf http://127.0.0.1:11434/api/version >/dev/null 2>&1; }

ensure_daemon() {
  if PING; then return 0; fi
  if [ "$NO_START" = 1 ]; then return 1; fi
  if [ -n "$OLLAMA_BIN" ]; then
    echo "Starting Ollama daemon..." >&2
    (nohup "$OLLAMA_BIN" serve > /tmp/ollama-serve.log 2>&1 &)
    for i in {1..40}; do
      sleep 0.25
      if PING; then return 0; fi
    done
  fi
  return 1
}

write_txt_from_daemon() {
  "$OLLAMA_BIN" list > "$TXT"
}

write_txt_from_manifests() {
  echo "NAME                ID              SIZE      MODIFIED" > "$TXT"
  base="$HOME/.ollama/models/manifests/registry.ollama.ai/library"
  if [ -d "$base" ]; then
    # List tags from manifest paths; ID/SIZE/MODIFIED unknown in fallback
    while IFS= read -r f; do
      tag="$(basename "$(dirname "$f")"):$(basename "$f")"
      printf "%s  %s  %s  %s\n" "$tag" "N/A" "N/A" "N/A" >> "$TXT"
    done < <(find "$base" -maxdepth 2 -type f | sort)
  fi
}

generate_csv() {
  python3 - "$TXT" "$CSV" << 'PY'
import csv, re, sys
src=sys.argv[1]
dst=sys.argv[2]
rows=[]
with open(src,'r',encoding='utf-8',errors='ignore') as f:
    lines=[l.rstrip('\n') for l in f]
for i,l in enumerate(lines):
    if i==0:  # header
        continue
    if not l.strip():
        continue
    parts=re.split(r'\s{2,}', l.strip())
    if len(parts) < 4:
        continue
    name, mid, size, modified = parts[0], parts[1], parts[2], parts[3]
    rows.append((name, mid, size, modified))
with open(dst,'w',newline='',encoding='utf-8') as out:
    w=csv.writer(out)
    w.writerow(['name','id','size','modified'])
    for r in rows:
        w.writerow(r)
PY
}

generate_osi_list() {
  python3 - "$OSI" << 'PY'
import json, os, glob, re, sys
dst=sys.argv[1]
home=os.path.expanduser('~')
base=os.path.join(home,'.ollama','models','manifests','registry.ollama.ai','library')
models={}
if os.path.isdir(base):
    for manifest in glob.glob(os.path.join(base,'*','*')):
        try:
            with open(manifest,'r') as f:
                data=json.load(f)
        except Exception:
            continue
        rel=manifest.replace(home+os.sep,'')
        parts=rel.split('/')[-2:]
        tag=f"{parts[0]}:{parts[1]}"
        lic_layers=[l for l in data.get('layers',[]) if l.get('mediaType','').endswith('image.license')]
        heads=[]
        for l in lic_layers:
            sha=l.get('digest','').split(':')[-1]
            path=os.path.join(home,'.ollama','models','blobs',f'sha256-{sha}')
            try:
                with open(path,'r',errors='ignore') as bf:
                    head=''.join([next(bf) for _ in range(5)])
                heads.append(head)
            except Exception:
                pass
        models[tag]='\n'.join(heads)
OSI_PATTERNS=[r'Apache License', r'MIT License', r'BSD', r'GPL', r'LGPL', r'MPL', r'CDDL', r'ISC']
RESTRICT_PATTERNS=[r'LLAMA', r'Llama', r'Acceptable Use Policy']
osi_tags=[]
for tag,text in models.items():
    if any(re.search(p, text) for p in RESTRICT_PATTERNS):
        continue
    if any(re.search(p, text) for p in OSI_PATTERNS):
        osi_tags.append(tag)
with open(dst,'w',encoding='utf-8') as out:
    out.write('# OSI-licensed Ollama model tags (UTC {})\n'.format(os.popen('date -u +%Y-%m-%dT%H:%M:%SZ').read().strip()))
    for t in sorted(osi_tags):
        out.write(t+'\n')
PY
}

# Main
if [ -z "${OLLAMA_BIN}" ]; then
  echo "WARN: ollama binary not found; using manifest fallback" >&2
  write_txt_from_manifests
else
  if ensure_daemon; then
    write_txt_from_daemon || write_txt_from_manifests
  else
    echo "WARN: Ollama daemon unreachable; using manifest fallback" >&2
    write_txt_from_manifests
  fi
fi

generate_csv
generate_osi_list

echo "ARTIFACT_TXT: ${TXT}"
echo "ARTIFACT_CSV: ${CSV}"
echo "ARTIFACT_OSI: ${OSI}"

if [ "$DO_COMMIT" = 1 ]; then
  (
    cd "$REPO_DIR"
    echo 'Pre-commit hygiene:'
    git status --porcelain || true
    git diff --stat || true
    git add "${TXT#$REPO_DIR/}" "${CSV#$REPO_DIR/}" "${OSI#$REPO_DIR/}"
    git -c commit.gpgsign=false commit -m "inventory(ollama): refresh artifacts — UTC $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    git status -sb
  )
fi

if [ "$DO_PUSH" = 1 ]; then
  (
    cd "$REPO_DIR"
    git push origin main
    echo "PUSH_DONE_UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  )
fi

