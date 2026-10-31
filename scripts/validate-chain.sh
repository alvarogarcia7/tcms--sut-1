#!/usr/bin/env bash
# Single end-to-end check of a test run, from the schemas to the documents:
#   1. test cases match the tcms-schemas test-case schema
#   2. requirements.json matches the tcms-schemas requirement-list schema, and every test
#      case requirement is listed in it
#   3. the run matches the tcms-schemas test-run and verification-result schemas
#   4. the records agree: one result per test case in testcases/, and each verdict in
#      test-run.yaml matches the step results in verification-results.yaml
#   5. the documents are generated from the run and pass scripts/verify-documents.sh
#   6. each document states the same verdict per test case as test-run.yaml, and the
#      traceability matrix states the verdict of each requirement
#
# Usage: scripts/validate-chain.sh RUN_ID TCMS_SCHEMAS_DIR
# The run must be in build/runs/RUN_ID (written by scripts/run-tests.sh). The documents are
# generated with scripts/traceability-document.sh in build mode. Needs python3 with PyYAML and
# jsonschema, yq, jq, zip and unzip, plus the tcms-cli binaries and tpdg (see README).
# Exit code: 0 when every step passes, 1 otherwise.
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: $0 RUN_ID TCMS_SCHEMAS_DIR" >&2
  exit 64
fi
RUN_ID="$1"
SCHEMAS_DIR="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

RUN_DIR="build/runs/$RUN_ID"
DOCS_DIR="build/traceability/30_documentation_source"
[ -d "$RUN_DIR" ] || { echo "error: run $RUN_ID not found at $RUN_DIR" >&2; exit 1; }

step() { echo; echo "== $1"; }

step "1. test cases against the test-case schema"
scripts/validate-testcases-schema.sh "$SCHEMAS_DIR"

step "2. requirements against the requirement-list schema"
scripts/validate-requirements.sh "$SCHEMAS_DIR" vv-tcms/requirements.json

step "3. run records against the tcms-schemas schemas"
scripts/validate-results.sh "$RUN_DIR" "$SCHEMAS_DIR"

step "4. run records agree with each other"
python3 -I - "$RUN_DIR" testcases <<'PY'
import glob
import os
import sys

import yaml

run_dir, testcases_dir = sys.argv[1], sys.argv[2]
ok = True


def fail(message):
    global ok
    print(f"FAIL {message}")
    ok = False


expected = sorted(os.path.splitext(os.path.basename(p))[0]
                  for p in glob.glob(f"{testcases_dir}/*.yml"))
with open(f"{run_dir}/test-run.yaml") as f:
    results = yaml.safe_load(f)["results"]
with open(f"{run_dir}/verification-results.yaml") as f:
    verification = {entry["test_case_id"]: entry for entry in yaml.safe_load(f)["test_results"]}

verdicts = {}
for result in results:
    test_case_id = result["test_case_id"]
    if test_case_id in verdicts:
        fail(f"{test_case_id} has more than one result in test-run.yaml")
    verdicts[test_case_id] = result["verdict"]

if sorted(verdicts) != expected:
    fail(f"test-run.yaml covers {sorted(verdicts)}, testcases/ has {expected}")

for test_case_id, verdict in sorted(verdicts.items()):
    if verdict not in ("pass", "fail"):
        fail(f"{test_case_id} has verdict '{verdict}', expected pass or fail")
    entry = verification.get(test_case_id)
    if entry is None:
        fail(f"{test_case_id} has no entry in verification-results.yaml")
        continue
    all_passed = all(sequence["all_steps_passed"] for sequence in entry["sequences"])
    derived = "pass" if all_passed else "fail"
    if derived != verdict:
        fail(f"{test_case_id}: test-run says {verdict}, step results say {derived}")
    else:
        print(f"OK   {test_case_id}: {verdict} in test-run.yaml and in the step results")

sys.exit(0 if ok else 1)
PY

step "5. documents generated from the run and checked"
TCMS_DOC_FROM_BUILD=1 TCMS_RUN_ID="$RUN_ID" scripts/traceability-document.sh
scripts/verify-documents.sh "$DOCS_DIR"

step "6. documents state the verdicts of the run"
python3 -I - "$RUN_DIR" "$DOCS_DIR" testcases/*.yml <<'PY'
import re
import sys

import yaml

run_dir, docs_dir, *testcase_files = sys.argv[1:]
ok = True


def fail(message):
    global ok
    print(f"FAIL {message}")
    ok = False


with open(f"{run_dir}/test-run.yaml") as f:
    verdicts = {r["test_case_id"]: r["verdict"] for r in yaml.safe_load(f)["results"]}
requirements = {}
for path in testcase_files:
    with open(path) as f:
        test_case = yaml.safe_load(f)
    requirements[test_case["id"]] = test_case["requirement"]

# Markdown writes "**Overall Status**: ✓ PASS", AsciiDoc writes "*Overall Status*: ✓ PASS".
status_re = re.compile(r"Overall Status\*{0,2}: \S+ (PASS|FAIL)")


def statuses(text):
    """Return {test case id: status} from a document's '== / ## Test Case: ID' sections."""
    found = {}
    current = None
    for line in text.splitlines():
        heading = re.match(r"^(#+|=+) Test Case: (\S+)", line)
        if heading:
            current = heading.group(2)
            continue
        status = status_re.search(line)
        if status and current and current not in found:
            found[current] = status.group(1)
    return found


def expected_status(test_case_id):
    return "PASS" if verdicts[test_case_id] == "pass" else "FAIL"


documents = {
    f"{docs_dir}/consolidated/all_tests.md": True,
    f"{docs_dir}/consolidated/all_tests.adoc": True,
}
for test_case_id in verdicts:
    documents[f"{docs_dir}/markdown/{test_case_id}.md"] = False
    documents[f"{docs_dir}/asciidoc/{test_case_id}.adoc"] = False

for path, consolidated in documents.items():
    with open(path, encoding="utf-8") as f:
        text = f.read()
    found = statuses(text)
    wanted = list(verdicts) if consolidated else [p for p in verdicts if p in path]
    for test_case_id in wanted:
        if found.get(test_case_id) != expected_status(test_case_id):
            fail(f"{path}: {test_case_id} is {found.get(test_case_id)}, "
                 f"test-run.yaml says {expected_status(test_case_id)}")
        else:
            print(f"OK   {path}: {test_case_id} {expected_status(test_case_id)}")

# The traceability matrix lists the verdict of each requirement: PASS when every test case
# of the requirement passed.
with open(f"{docs_dir}/consolidated/all_tests.md", encoding="utf-8") as f:
    matrix = f.read().split("## Traceability Matrix", 1)[-1]
for requirement in sorted(set(requirements.values())):
    cases = [tc for tc, req in requirements.items() if req == requirement]
    wanted = "PASS" if all(verdicts[tc] == "pass" for tc in cases) else "FAIL"
    row = re.search(rf"\| Verdict \|(.*)", matrix)
    header = re.search(r"\| Requirement \|(.*)", matrix)
    if not row or not header:
        fail("all_tests.md has no traceability matrix rows")
        break
    columns = [c.strip() for c in header.group(1).split("|")]
    verdict_cells = [c.strip() for c in row.group(1).split("|")]
    if requirement not in columns:
        fail(f"traceability matrix has no column for {requirement}")
        continue
    cell = verdict_cells[columns.index(requirement)]
    if cell != wanted:
        fail(f"traceability matrix says {requirement} is {cell}, expected {wanted}")
    else:
        print(f"OK   traceability matrix: {requirement} {wanted}")

sys.exit(0 if ok else 1)
PY

echo
echo "OK    run $RUN_ID checked from the schemas to the documents"
