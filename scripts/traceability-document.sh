#!/usr/bin/env bash
# Generates the traceability document requested by Verdict TCMS (tcms-web) and packs it as
# traceability-document.zip. It reproduces stages 6 and 7 of run_acceptance_suite.sh of
# tcms-cli (branch tcms-40-glossary-impl) on the execution logs that sut-1 already publishes
# in vv-tcms/runs/<RUN_ID>/logs/:
#
#   30_documentation_source/asciidoc/<TC>.adoc      stage 6, one report per test case
#   30_documentation_source/markdown/<TC>.md        stage 6, one report per test case
#   30_documentation_source/consolidated/all_tests_container.yaml   stage 7 (verifier --folder)
#   30_documentation_source/consolidated/all_tests.adoc             stage 7
#   30_documentation_source/consolidated/all_tests.md               stage 7
#   30_documentation_source/MANIFEST.md             request, commits, run, tool versions, files
#
# The per-test containers of stage 4 (verifier --test-case --log), which stage 6 renders, are
# kept in build/traceability/20_verification/ and are not part of the zip.
# Each document is rendered in two tpdg runs (README "Chaining commands"): first the test
# cases (test_cases_md) and the requirement traceability matrix (traceability_matrix_md), then
# the outer document with both in its data. The templates are the TPDG ones in
# vv-tcms/templates/ (verification_methods/, test_results/). PDF is not produced.
#
# Environment:
#   TCMS_DOC_REQUEST_ID  required: the tcms-web request id, written to the manifest
#   TCMS_TESTS_COMMIT    optional: sut-1 commit whose testcases/ and vv-tcms/ are used
#                        (default: the pipeline commit; an unknown commit falls back to it
#                        with a warning in the manifest)
#   TCMS_CODE_COMMIT     optional: SUT code commit, recorded as the build id and in the manifest
#   TCMS_DOC_RUN_ID      optional: run to document (default: the newest run in vv-tcms/index.jsonl
#                        that has execution logs)
#   TEST_PLAN_DOC_GEN    tpdg binary (default tools/tpdg/tpdg)
#   TCMS_BIN_DIR, TCMS_SRC_DIR   see scripts/tcms-env.sh
#
# Exit code: 0 when the zip was written with every document, 1 otherwise.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# shellcheck source=scripts/tcms-env.sh
. "$SCRIPT_DIR/tcms-env.sh"

REQUEST_ID="${TCMS_DOC_REQUEST_ID:-pipeline-${CI_PIPELINE_ID:-local}}"
TPDG_BIN="${TEST_PLAN_DOC_GEN:-$REPO_ROOT/tools/tpdg/tpdg}"
TEMPLATE_DIR="$REPO_ROOT/vv-tcms/templates/test_results"
VERIFICATION_METHODS_DIR="$REPO_ROOT/vv-tcms/templates/verification_methods"
CONTAINER_SCHEMA="$TEMPLATE_DIR/container_schema.json"
PLATFORM="$(uname -s) $(uname -m)"

WORK_DIR="$REPO_ROOT/build/traceability"
SOURCE_DIR="$WORK_DIR/source"
VERIFICATION_RESULTS_DIR="$WORK_DIR/20_verification"
REPORTS_DIR="$WORK_DIR/30_documentation_source"
OUTPUT_LOG="$WORK_DIR/tool-output.txt"
ZIP="$REPO_ROOT/traceability-document.zip"

[ -x "$TPDG_BIN" ] || { echo "error: tpdg not found at $TPDG_BIN (run scripts/fetch-tpdg.sh)" >&2; exit 1; }
for tool in yq jq zip unzip; do
  command -v "$tool" > /dev/null || { echo "error: $tool not found (see the traceability-document job in .gitlab-ci.yml)" >&2; exit 1; }
done

rm -rf "$WORK_DIR" "$ZIP"
mkdir -p "$SOURCE_DIR" "$VERIFICATION_RESULTS_DIR" "$REPORTS_DIR"
warnings=()

# --- Inputs: testcases/ and vv-tcms/ at the requested tests commit ---------------------------
tests_commit="$(git rev-parse HEAD)"
if [ -n "${TCMS_TESTS_COMMIT:-}" ]; then
  if git cat-file -e "${TCMS_TESTS_COMMIT}^{commit}" 2>/dev/null \
     || git fetch -q --depth=1 origin "$TCMS_TESTS_COMMIT" 2>/dev/null; then
    tests_commit="$(git rev-parse "${TCMS_TESTS_COMMIT}^{commit}")"
  else
    warnings+=("TCMS_TESTS_COMMIT $TCMS_TESTS_COMMIT is not a commit of sut-1; used the pipeline commit $tests_commit")
  fi
fi
if [ -n "${TCMS_DOC_FROM_BUILD:-}" ]; then
  # Pipeline mode: the run the test job just wrote to build/runs/ and the working tree.
  run_id="${TCMS_RUN_ID:?TCMS_RUN_ID is not set (TCMS_DOC_FROM_BUILD needs the run to document)}"
  EXECUTION_LOGS_DIR="$REPO_ROOT/build/runs/$run_id/logs"
  TEST_CASES_DIR="$REPO_ROOT/testcases"
  CONTAINER_CONFIG="$REPO_ROOT/vv-tcms/container-config.yaml"
else
  # Request mode: testcases/ and vv-tcms/ at the requested commit.
  git archive "$tests_commit" testcases vv-tcms | tar -x -C "$SOURCE_DIR"
  TEST_CASES_DIR="$SOURCE_DIR/testcases"
  CONTAINER_CONFIG="$SOURCE_DIR/vv-tcms/container-config.yaml"

  run_id="${TCMS_DOC_RUN_ID:-}"
  if [ -z "$run_id" ]; then
    while read -r candidate; do
      if compgen -G "$SOURCE_DIR/vv-tcms/runs/$candidate/logs/*.json" > /dev/null; then
        run_id="$candidate"
        break
      fi
    done < <(jq -r '.run_id' "$SOURCE_DIR/vv-tcms/index.jsonl" | tac)
  fi
  EXECUTION_LOGS_DIR="$SOURCE_DIR/vv-tcms/runs/$run_id/logs"
fi
if [ -z "$run_id" ] || ! compgen -G "$EXECUTION_LOGS_DIR/*.json" > /dev/null; then
  echo "error: no execution logs for run '${run_id:-none}' in $EXECUTION_LOGS_DIR" >&2
  exit 1
fi
build_id="${TCMS_CODE_COMMIT:-$tests_commit}"

echo "Traceability document $REQUEST_ID"
echo "  tests commit:   $tests_commit"
echo "  code commit:    ${TCMS_CODE_COMMIT:-(not given)}"
echo "  run:            $run_id"
echo "  execution logs: ${EXECUTION_LOGS_DIR#"$REPO_ROOT"/}"

failures=0
run_tool() { # run_tool <label> <command...>: prints the tool output only when it fails
  if "${@:2}" > "$OUTPUT_LOG" 2>&1; then
    echo "  ok    $1"
  else
    echo "  FAIL  $1"
    sed 's/^/        /' "$OUTPUT_LOG"
    failures=$((failures + 1))
    return 1
  fi
}

# render_document <container yaml> <md|adoc> <output>
# Run 1: test_cases_md, one result per test case, and traceability_matrix_md, the
#        requirement-to-test matrix. Run 2: the outer document with both in its data.
render_document() {
  local container="$1" format="$2" output="$3" test_case_id
  local label="${output#"$REPORTS_DIR"/}"
  local work="$WORK_DIR/render/$label"
  local suffix="$format.j2"
  mkdir -p "$work/results"

  if ! yq -c . "$container" > "$work/container.json"; then
    echo "  FAIL  $label: container is not readable"
    failures=$((failures + 1))
    return
  fi
  # Per-test result input of tpdg: the test result of the container with type: result.
  while IFS= read -r result; do
    test_case_id="$(jq -r '.test_case_id' <<< "$result")"
    jq -c '{type: "result"} + .' <<< "$result" > "$work/results/$test_case_id.yml"
  done < <(jq -c '.test_results[]' "$work/container.json")

  if run_tool "$label: test_cases" "$TPDG_BIN" --multiple-by-type type "$VERIFICATION_METHODS_DIR" \
       "$work"/results/*.yml --format "$format" --output "$work/test_cases.$format" \
     && jq -c '. + {requirements: ([.test_results[] | .requirement // empty] | unique)}' \
       "$work/container.json" > "$work/matrix_input.json" \
     && run_tool "$label: traceability_matrix" "$TPDG_BIN" --single "$CONTAINER_SCHEMA" \
       "$TEMPLATE_DIR/traceability_matrix.$suffix" "$work/matrix_input.json" \
       --format "$format" --output "$work/traceability_matrix.$format"; then
    jq -c --rawfile test_cases "$work/test_cases.$format" --rawfile matrix "$work/traceability_matrix.$format" \
      '. + {test_cases_md: $test_cases, traceability_matrix_md: $matrix}' \
      "$work/container.json" > "$work/document.json"
    run_tool "$label" "$TPDG_BIN" --single "$CONTAINER_SCHEMA" \
      "$TEMPLATE_DIR/test_container_result.$suffix" "$work/document.json" \
      --format "$format" --output "$output" || true
  fi
}

# --- Stage 6: per test case container (stage 4 verifier call) and AsciiDoc + Markdown -------
echo "Stage 6: Documentation (AsciiDoc and Markdown per test case)"
mkdir -p "$REPORTS_DIR/asciidoc" "$REPORTS_DIR/markdown"
for log_file in "$EXECUTION_LOGS_DIR"/*.json; do
  test_case_id="$(basename "$log_file" .json)"
  test_case_id="${test_case_id%_execution_log}"
  test_case_yaml=""
  for ext in yml yaml; do
    [ -f "$TEST_CASES_DIR/$test_case_id.$ext" ] && test_case_yaml="$TEST_CASES_DIR/$test_case_id.$ext" && break
  done
  if [ -z "$test_case_yaml" ]; then
    warnings+=("test case YAML not found for $(basename "$log_file"); skipped")
    continue
  fi
  container_file="$VERIFICATION_RESULTS_DIR/${test_case_id}_container.yaml"
  run_tool "${test_case_id}_container.yaml" "$VERIFIER" \
    --config "$CONTAINER_CONFIG" \
    --title "Acceptance Test Results - $(basename "$test_case_yaml")" \
    --platform "$PLATFORM" \
    --test-case "$test_case_id" \
    --log "$log_file" \
    --test-case-dir "$TEST_CASES_DIR" \
    --output "$container_file" \
    --schema "$RESULT_SCHEMA" \
    --run-id "$run_id" --build-id "$build_id" --no-test-run \
    --success-on-completion || true
  if [ ! -f "$container_file" ]; then
    echo "  FAIL  ${test_case_id}_container.yaml was not written"
    failures=$((failures + 1))
    continue
  fi
  render_document "$container_file" adoc "$REPORTS_DIR/asciidoc/$test_case_id.adoc"
  render_document "$container_file" md "$REPORTS_DIR/markdown/$test_case_id.md"
done

# --- Stage 7: consolidated documentation (verifier --folder mode) ----------------------------
echo "Stage 7: Consolidated documentation (all test cases)"
mkdir -p "$REPORTS_DIR/consolidated"
consolidated_container="$REPORTS_DIR/consolidated/all_tests_container.yaml"
run_tool "consolidated/all_tests_container.yaml" "$VERIFIER" \
  --folder "$EXECUTION_LOGS_DIR" \
  --test-case-dir "$TEST_CASES_DIR" \
  --config "$CONTAINER_CONFIG" \
  --title "Acceptance Test Suite - All Test Cases" \
  --platform "$PLATFORM" \
  --output "$consolidated_container" \
  --schema "$RESULT_SCHEMA" \
  --run-id "$run_id" --build-id "$build_id" --no-test-run \
  --success-on-completion || true
if [ -f "$consolidated_container" ]; then
  render_document "$consolidated_container" adoc "$REPORTS_DIR/consolidated/all_tests.adoc"
  render_document "$consolidated_container" md "$REPORTS_DIR/consolidated/all_tests.md"
fi

# Empty documents count as failures: tcms-web hands the zip to the user as is.
while IFS= read -r -d '' empty; do
  echo "  FAIL  ${empty#"$REPORTS_DIR"/} is empty"
  failures=$((failures + 1))
done < <(find "$REPORTS_DIR" -type f -empty -print0)

# --- Manifest and zip ------------------------------------------------------------------------
{
  echo "# Traceability document"
  echo
  echo "| Field | Value |"
  echo "|---|---|"
  echo "| Request | $REQUEST_ID |"
  echo "| Tests commit | $tests_commit |"
  echo "| Code commit | ${TCMS_CODE_COMMIT:-(not given)} |"
  echo "| Run | $run_id |"
  echo "| Pipeline | ${CI_PIPELINE_URL:-local} |"
  echo "| tcms-cli | $(basename "$TCMS_SRC_DIR") $("$VERIFIER" --version 2>/dev/null | head -n 1) |"
  echo "| tpdg | $(cat "$(dirname "$TPDG_BIN")/.version" 2>/dev/null || echo unknown) |"
  echo "| Generated | $(date -u +%Y-%m-%dT%H:%M:%SZ) |"
  echo
  echo "Stage 6 (Documentation): asciidoc/ and markdown/, one report per test case."
  echo "Stage 7 (Consolidated Docs): consolidated/, all test cases of the run in one document."
  echo "Each document has the test cases and a requirement traceability matrix."
  echo "PDF is not produced."
  if [ ${#warnings[@]} -gt 0 ]; then
    echo
    echo "## Warnings"
    echo
    for w in "${warnings[@]}"; do echo "- $w"; done
  fi
  echo
  echo "## Files"
  echo
  (cd "$REPORTS_DIR" && find . -type f ! -name MANIFEST.md | sort | sed 's|^\./|- |')
} > "$REPORTS_DIR/MANIFEST.md"

for w in "${warnings[@]+"${warnings[@]}"}"; do echo "warning: $w"; done

(cd "$WORK_DIR" && zip -qr "$ZIP" 30_documentation_source)
echo "Produced ${ZIP#"$REPO_ROOT"/}:"
unzip -l "$ZIP"

if [ "$failures" -gt 0 ]; then
  echo "error: $failures document(s) could not be generated" >&2
  exit 1
fi
