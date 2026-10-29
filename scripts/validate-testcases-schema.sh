#!/usr/bin/env bash
# Validates every test case in testcases/ against tcms-schemas test-case-main.schema.json.
# Usage: scripts/validate-testcases-schema.sh TCMS_SCHEMAS_DIR
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 TCMS_SCHEMAS_DIR" >&2
  exit 64
fi
SCHEMA="$1/schemas/tcms/test-case-main.schema.json"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

python3 -I - "$SCHEMA" testcases/*.yml <<'PY'
import json
import sys

import jsonschema
import yaml

schema_path, files = sys.argv[1], sys.argv[2:]
with open(schema_path) as f:
    validator = jsonschema.Draft7Validator(json.load(f))

failed = 0
for path in files:
    with open(path) as f:
        document = yaml.safe_load(f)
    errors = sorted(validator.iter_errors(document), key=lambda e: list(e.path))
    if errors:
        failed += 1
        print(f"FAIL {path}")
        for e in errors:
            print(f"     {list(e.absolute_path)}: {e.message}")
    else:
        print(f"OK   {path}")
sys.exit(1 if failed else 0)
PY
