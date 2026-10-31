#!/usr/bin/env bash
# Checks the documents written by scripts/traceability-document.sh. For every Markdown and
# AsciiDoc file under REPORTS_DIR:
#   - it is not empty
#   - no template syntax is left ({{ }} or {% %})
#   - it has the traceability matrix and a PASS or FAIL verdict
# Each per-test document (asciidoc/<ID>.adoc, markdown/<ID>.md) names its test case.
# The consolidated documents name every test case in testcases/.
# Usage: scripts/verify-documents.sh REPORTS_DIR
set -uo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 REPORTS_DIR" >&2
  exit 64
fi
REPORTS_DIR="$1"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

failures=0
fail() {
  echo "FAIL  $1"
  failures=$((failures + 1))
}

check_document() { # check_document <file>
  local file="$1"
  if [ ! -s "$file" ]; then
    fail "$file is empty"
    return
  fi
  if grep -q -E '\{\{|\}\}|\{%|%\}' "$file"; then
    fail "$file has template syntax left over"
  fi
  if ! grep -q 'Traceability Matrix' "$file"; then
    fail "$file has no traceability matrix"
  fi
  if ! grep -q -E 'PASS|FAIL' "$file"; then
    fail "$file has no PASS or FAIL verdict"
  fi
}

check_names() { # check_names <file> <id>...: the file names each id
  local file="$1" id
  shift
  for id in "$@"; do
    grep -q -F -- "$id" "$file" || fail "$file does not name test case $id"
  done
}

while IFS= read -r -d '' document; do
  check_document "$document"
done < <(find "$REPORTS_DIR/markdown" "$REPORTS_DIR/asciidoc" "$REPORTS_DIR/consolidated" \
  -type f \( -name '*.md' -o -name '*.adoc' \) -print0 2>/dev/null)

for md in "$REPORTS_DIR"/markdown/*.md; do
  [ -f "$md" ] || { fail "no per-test Markdown documents in $REPORTS_DIR/markdown"; break; }
  check_names "$md" "$(basename "$md" .md)"
done
for adoc in "$REPORTS_DIR"/asciidoc/*.adoc; do
  [ -f "$adoc" ] || { fail "no per-test AsciiDoc documents in $REPORTS_DIR/asciidoc"; break; }
  check_names "$adoc" "$(basename "$adoc" .adoc)"
done

test_case_ids=()
for test_case in "$REPO_ROOT"/testcases/*.yml; do
  test_case_ids+=("$(basename "$test_case" .yml)")
done
for consolidated in "$REPORTS_DIR"/consolidated/all_tests.md "$REPORTS_DIR"/consolidated/all_tests.adoc; do
  if [ ! -f "$consolidated" ]; then
    fail "$consolidated is missing"
    continue
  fi
  check_names "$consolidated" "${test_case_ids[@]}"
done

if [ "$failures" -eq 0 ]; then
  echo "OK    documents in $REPORTS_DIR checked"
fi
[ "$failures" -eq 0 ]
