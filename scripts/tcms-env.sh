#!/usr/bin/env bash
# Locates the tcms-cli binaries and the schema/data folders built from the tcms-cli source.
# Sourced by the other scripts. Override with TCMS_BIN_DIR and TCMS_SRC_DIR.
#
# TCMS_BIN_DIR  folder holding test-executor, verifier, validate-yaml (default: tools/bin)
# TCMS_SRC_DIR  tcms-cli source tree with schemas/ and data/ (default: tools/tcms-cli)

TCMS_BIN_DIR="${TCMS_BIN_DIR:-$REPO_ROOT/tools/bin}"
TCMS_SRC_DIR="${TCMS_SRC_DIR:-$REPO_ROOT/tools/tcms-cli}"

TEST_EXECUTOR="$TCMS_BIN_DIR/test-executor"
VERIFIER="$TCMS_BIN_DIR/verifier"
VALIDATE_YAML="$TCMS_BIN_DIR/validate-yaml"
RESULT_SCHEMA="$TCMS_SRC_DIR/data/testcase_results_container/schema.json"

for bin in "$TEST_EXECUTOR" "$VERIFIER" "$VALIDATE_YAML"; do
  if [ ! -x "$bin" ]; then
    echo "error: missing tcms-cli binary: $bin (run the build-tcms job or set TCMS_BIN_DIR)" >&2
    exit 1
  fi
done
if [ ! -f "$RESULT_SCHEMA" ]; then
  echo "error: missing result schema: $RESULT_SCHEMA (set TCMS_SRC_DIR)" >&2
  exit 1
fi

# tcms-cli looks for schemas/ in the working directory. Link them from the source tree
# (both paths are gitignored) so the scripts work from the repo root.
for dir in schemas; do
  if [ ! -e "$REPO_ROOT/$dir" ]; then
    ln -s "$TCMS_SRC_DIR/$dir" "$REPO_ROOT/$dir"
  fi
done
