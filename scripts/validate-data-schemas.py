#!/usr/bin/env python3
# Validates YAML data files against the schema each file names in its top-level `schema:` key.
# The schema path is relative to the tcms-schemas repo (for example tcms/test-run.schema.json
# resolves to schemas/tcms/test-run.schema.json). A file without a `schema:` key, a schema
# that does not exist in the repo, or a document that does not match fails.
#
# Two names are written by tcms-cli and are not files of tcms-schemas. They are checked the
# way the pipeline always checked them:
#   tcms/test-case.schema.v1.json              -> test-case-main.schema.json (the whole document)
#   tcms/test-results-container.schema.v1.json -> verification-result.schema.json (each test_results[] entry)
#
# Usage: uv run --project TCMS_SCHEMAS_DIR python scripts/validate-data-schemas.py TCMS_SCHEMAS_DIR FILE...
import json
import os
import sys

import jsonschema
import yaml

USAGE = "usage: validate-data-schemas.py TCMS_SCHEMAS_DIR FILE..."

# tcms-cli schema name -> the tcms-schemas file that validates the same content.
ALIASES = {
    "tcms/test-case.schema.v1.json": "tcms/test-case-main.schema.json",
}
CONTAINER = "tcms/test-results-container.schema.v1.json"
ENTRY_SCHEMA = "tcms/verification-result.schema.json"


def load_schema(schemas_root, name):
    path = os.path.realpath(os.path.join(schemas_root, name.removeprefix("tcms/")))
    if not path.startswith(schemas_root + os.sep) or not os.path.isfile(path):
        raise FileNotFoundError(f"schema not found in tcms-schemas: {name}")
    with open(path) as f:
        return json.load(f)


def errors_for(schemas_root, document, schema_name):
    validator = jsonschema.Draft7Validator(
        load_schema(schemas_root, schema_name),
        format_checker=jsonschema.Draft7Validator.FORMAT_CHECKER,
    )
    return [
        f"{'/'.join(str(p) for p in e.absolute_path) or '<root>'}: {e.message}"
        for e in sorted(validator.iter_errors(document), key=lambda e: list(e.path))
    ]


def check(schemas_root, path):
    with open(path) as f:
        document = yaml.safe_load(f)
    if not isinstance(document, dict) or "schema" not in document:
        return ["no top-level 'schema:' key"]
    name = document["schema"]
    if not isinstance(name, str) or not name.startswith("tcms/"):
        return [f"unsupported schema reference: {name!r}"]

    if name == CONTAINER:
        errors = []
        for i, entry in enumerate(document.get("test_results", [])):
            errors += [f"test_results[{i}] {e}" for e in errors_for(schemas_root, entry, ENTRY_SCHEMA)]
        return errors
    return errors_for(schemas_root, document, ALIASES.get(name, name))


def main(argv):
    if len(argv) < 3:
        print(USAGE, file=sys.stderr)
        return 64

    schemas_root = os.path.realpath(os.path.join(argv[1], "schemas", "tcms"))
    files = argv[2:]
    failed = 0
    for path in files:
        try:
            errors = check(schemas_root, path)
        except (OSError, yaml.YAMLError, FileNotFoundError, json.JSONDecodeError) as e:
            errors = [str(e)]
        if errors:
            failed += 1
            print(f"FAIL {path}")
            for e in errors:
                print(f"     {e}")
        else:
            print(f"OK   {path}")
    print(f"{len(files) - failed}/{len(files)} data files valid")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
