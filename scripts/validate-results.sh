#!/usr/bin/env bash
# Checks a run written by run-tests.sh against the tcms-schemas JSON schemas:
#   test-run.yaml              -> test-run.schema.json
#   verification-results.yaml  -> verification-result.schema.json (each test_results[] entry)
#
# Usage: scripts/validate-results.sh build/runs/<RUN_ID> PATH_TO_TCMS_SCHEMAS_REPO
# Needs python3 with PyYAML and jsonschema.
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: $0 RUN_DIR TCMS_SCHEMAS_DIR" >&2
  exit 64
fi
RUN_DIR="$1"
SCHEMAS="$2/schemas/tcms"

python3 -I - "$RUN_DIR" "$SCHEMAS" <<'PY'
import json
import sys

import jsonschema
import yaml

run_dir, schemas = sys.argv[1], sys.argv[2]


def load_schema(name):
    with open(f"{schemas}/{name}") as f:
        return json.load(f)


def check(label, document, schema):
    try:
        jsonschema.validate(document, schema)
    except jsonschema.ValidationError as e:
        print(f"FAIL {label}: {e.message}")
        return False
    print(f"OK   {label}")
    return True


ok = True
with open(f"{run_dir}/test-run.yaml") as f:
    test_run = yaml.safe_load(f)
ok &= check("test-run.yaml", test_run, load_schema("test-run.schema.json"))

with open(f"{run_dir}/verification-results.yaml") as f:
    container = yaml.safe_load(f)
result_schema = load_schema("verification-result.schema.json")
for entry in container.get("test_results", []):
    ok &= check(f"verification {entry['test_case_id']}", entry, result_schema)

sys.exit(0 if ok else 1)
PY
