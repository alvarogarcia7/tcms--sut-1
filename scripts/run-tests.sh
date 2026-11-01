#!/usr/bin/env bash
# Runs every test case in testcases/ against the SUT with tcms-cli, verifies the logs and
# writes the records into build/runs/<RUN_ID>/:
#   test-run.yaml                 tcms-schemas test-run (one result per test case)
#   verification-results.yaml     tcms-schemas verification results (one entry per test case)
#   logs/<ID>_execution_log.json  execution logs written by test-executor
#   audit.log.json                audit trail written by test-executor
#
# Environment (all optional):
#   TCMS_RUN_ID       run identifier (default: RUN-<UTC timestamp>-<git short sha>)
#   TCMS_BUILD_ID     SUT build under test (default: git short sha)
#   TCMS_TESTER       who ran the tests (default: $USER)
#   TCMS_REVIEWER     who checked the results (recorded in test-run.yaml when set)
#   TCMS_BIN_DIR, TCMS_SRC_DIR   see scripts/tcms-env.sh
#
# Exit code: 0 when the run was written, even if test cases failed. Use the
# test-run.yaml verdicts to judge the run. Non-zero means the run could not be recorded.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# shellcheck source=scripts/tcms-env.sh
. "$SCRIPT_DIR/tcms-env.sh"

GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo local)"
RUN_ID="${TCMS_RUN_ID:-RUN-$(date -u +%Y%m%dT%H%M%SZ)-$GIT_SHA}"
BUILD_ID="${TCMS_BUILD_ID:-$GIT_SHA}"
TESTER="${TCMS_TESTER:-${USER:-ci}}"
PLATFORM="$(uname -s) $(uname -m)"

RUN_DIR="$REPO_ROOT/build/runs/$RUN_ID"
LOG_DIR="$RUN_DIR/logs"
if [ -e "$RUN_DIR" ]; then
  echo "error: run $RUN_ID already exists at $RUN_DIR (run IDs are never reused)" >&2
  exit 1
fi
mkdir -p "$LOG_DIR"

echo "Run $RUN_ID (build $BUILD_ID, tester $TESTER)"

# Execute each test case. A failing test case must not stop the run: the verifier
# records it as a fail.
for tc in testcases/*.yml; do
  tc_id="$(basename "$tc" .yml)"
  echo "--- executing $tc"
  rc=0
  AUDIT_LOG_FILE="$RUN_DIR/audit.log.json" \
    "$TEST_EXECUTOR" execute "$tc" || rc=$?
  log="${tc_id}_execution_log.json"
  if [ ! -f "$log" ]; then
    echo "error: test-executor wrote no execution log for $tc (exit $rc)" >&2
    exit 1
  fi
  mv "$log" "$LOG_DIR/$log"
  echo "    exit $rc, log $LOG_DIR/$log"
done

# Verify all logs in one run and write the tcms-schemas records. Paths are relative to the
# repo root so the references stored in the records are portable.
REL_RUN_DIR="build/runs/$RUN_ID"
# Title, project, environment and executor come from the container config (vv-tcms/).
verifier_args=(
  -f "$REL_RUN_DIR/logs"
  -d testcases
  -F yaml
  -o "$REL_RUN_DIR/verification-results.yaml"
  --config vv-tcms/container-config.yaml
  --test-run "$REL_RUN_DIR/test-run.yaml"
  --schema "$RESULT_SCHEMA"
  --run-id "$RUN_ID"
  --build-id "$BUILD_ID"
  --tester "$TESTER"
  --platform "$PLATFORM"
)
if [ -n "${TCMS_REVIEWER:-}" ]; then
  verifier_args+=(--reviewer "$TCMS_REVIEWER")
fi
"$VERIFIER" "${verifier_args[@]}"

echo "Run written to $RUN_DIR"
echo "$RUN_ID" > "$RUN_DIR/RUN_ID"
