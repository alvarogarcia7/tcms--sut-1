#!/usr/bin/env bash
# Checks the requirement list against the tcms-schemas requirement-list schema, then checks the
# requirement of each test case in testcases/ against the IDs in that list.
# The list holds the requirement IDs exported from the requirement source (StrictDoc or Jira).
# Usage: scripts/validate-requirements.sh TCMS_SCHEMAS_DIR REQUIREMENTS_JSON
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: $0 TCMS_SCHEMAS_DIR REQUIREMENTS_JSON" >&2
  exit 64
fi
SCHEMA="$1/schemas/tcms/requirement-list.schema.json"
REQUIREMENTS="$2"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [ ! -f "$REQUIREMENTS" ]; then
  echo "error: requirement list not found: $REQUIREMENTS" >&2
  exit 1
fi

python3 -I - "$SCHEMA" "$REQUIREMENTS" testcases/*.yml <<'PY'
import json
import sys

import jsonschema
import yaml

schema_path, requirements_path, test_cases = sys.argv[1], sys.argv[2], sys.argv[3:]
with open(schema_path) as f:
    schema = json.load(f)
with open(requirements_path) as f:
    requirement_list = json.load(f)

errors = sorted(jsonschema.Draft7Validator(schema).iter_errors(requirement_list), key=lambda e: list(e.path))
if errors:
    for e in errors:
        print(f"FAIL {requirements_path} {list(e.absolute_path)}: {e.message}")
    sys.exit(1)
print(f"OK   {requirements_path}")

known = {requirement["id"] for requirement in requirement_list["requirements"]}
failed = 0
for path in test_cases:
    with open(path) as f:
        requirement = yaml.safe_load(f)["requirement"]
    if requirement in known:
        print(f"OK   {path}: {requirement}")
    else:
        print(f"FAIL {path}: requirement '{requirement}' is not in {requirements_path}")
        failed += 1
sys.exit(1 if failed else 0)
PY
