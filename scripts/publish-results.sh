#!/usr/bin/env bash
# Appends one run from build/runs/<RUN_ID> to vv-tcms/ and records it in the run index.
# Existing runs are never modified or replaced:
#   vv-tcms/runs/<RUN_ID>/...   the run folder (copied, refused if it already exists)
#   vv-tcms/index.jsonl         one JSON line appended per run (verdict counts)
#
# Usage: scripts/publish-results.sh <RUN_ID>
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 RUN_ID" >&2
  exit 64
fi
RUN_ID="$1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$REPO_ROOT/build/runs/$RUN_ID"
DEST="$REPO_ROOT/vv-tcms/runs/$RUN_ID"
INDEX="$REPO_ROOT/vv-tcms/index.jsonl"

if [ ! -f "$SRC/test-run.yaml" ]; then
  echo "error: no test-run.yaml in $SRC; run scripts/run-tests.sh first" >&2
  exit 1
fi
if [ -e "$DEST" ]; then
  echo "error: $DEST already exists; refusing to overwrite a published run" >&2
  exit 1
fi
if [ -f "$INDEX" ] && grep -q "\"run_id\":\"$RUN_ID\"" "$INDEX"; then
  echo "error: run $RUN_ID is already in $INDEX" >&2
  exit 1
fi

mkdir -p "$DEST"
cp -R "$SRC/." "$DEST/"
rm -f "$DEST/RUN_ID"

# Verdict counts come from the test-run record, not from the logs.
summary="$(python3 -I - "$DEST/test-run.yaml" "$RUN_ID" <<'PY'
import json
import sys

import yaml

path, run_id = sys.argv[1], sys.argv[2]
with open(path) as f:
    run = yaml.safe_load(f)
verdicts = {}
for result in run.get("results", []):
    verdict = result.get("verdict", "unknown")
    verdicts[verdict] = verdicts.get(verdict, 0) + 1
print(json.dumps({
    "run_id": run_id,
    "build_id": run.get("build_id"),
    "tester": run.get("tester"),
    "started_at": run.get("started_at"),
    "finished_at": run.get("finished_at"),
    "total": len(run.get("results", [])),
    "verdicts": verdicts,
}, sort_keys=True))
PY
)"
printf '%s\n' "$summary" >> "$INDEX"
echo "Published $RUN_ID to vv-tcms/runs/$RUN_ID and appended to vv-tcms/index.jsonl"
