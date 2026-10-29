#!/usr/bin/env bash
# Downloads the tcms-cli Linux x64 binaries from a GitLab release package and installs
# them with the schemas they need, into tools/ for the pipeline.
#
# Tags are tried in TCMS_CLI_TAGS order; the first one whose binaries install and run wins.
# For each tag:
#   tools/bin/<tool>             test-executor, verifier, validate-yaml (from the zip)
#   tools/tcms-cli/schemas/      tcms-cli schemas (from the tag's repository archive)
#   tools/tcms-cli/data/...      result container schema (from the tag's repository archive)
# If no tag works the script exits non-zero and the pipeline stops.
#
# Environment:
#   TCMS_CLI_API         GitLab API root (default https://gitlab.crypto.tii.ae/api/v4)
#   TCMS_CLI_PROJECT_ID  tcms-cli project id (default 361)
#   TCMS_CLI_TAGS        space-separated tags to try, in order
#   TCMS_READ_TOKEN      optional read_api token; otherwise CI_JOB_TOKEN is sent as JOB-TOKEN
set -euo pipefail

if [ -n "${TCMS_READ_TOKEN:-}" ]; then
  AUTH_HEADER="PRIVATE-TOKEN: ${TCMS_READ_TOKEN}"
else
  AUTH_HEADER="JOB-TOKEN: ${CI_JOB_TOKEN:?no token: set TCMS_READ_TOKEN or run in CI}"
fi
API="${TCMS_CLI_API:-https://gitlab.crypto.tii.ae/api/v4}"
PROJECT="${TCMS_CLI_PROJECT_ID:-361}"
TAGS="${TCMS_CLI_TAGS:-v0.0.2-rc1-MR28-tcms40-glossary-impl_2 v0.0.2-rc1-MR28-tcms40-glossary-impl}"
REQUIRED_BINS="test-executor verifier validate-yaml"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

install_tag() {
  local tag="$1"
  local zip="tools/download/testcase-manager-$tag-linux-amd64.zip"
  local url="$API/projects/$PROJECT/packages/generic/testcase-manager/$tag/testcase-manager-$tag-linux-amd64.zip"

  echo "download: $tag"
  rm -rf tools/download tools/bin tools/tcms-cli
  mkdir -p tools/download/extract tools/bin tools/tcms-cli/data
  curl -sSfL -H "$AUTH_HEADER" -o "$zip" "$url"

  if command -v unzip >/dev/null 2>&1; then
    unzip -oq "$zip" -d tools/download/extract
  else
    python3 -m zipfile -e "$zip" tools/download/extract
  fi
  for bin in $REQUIRED_BINS; do
    [ -f "tools/download/extract/$bin" ] || { echo "  $bin missing from the zip"; return 1; }
    cp "tools/download/extract/$bin" tools/bin/
    chmod +x "tools/bin/$bin"
  done

  # Schemas and the result container schema from the same tag, without a full clone.
  for path in schemas data/testcase_results_container; do
    curl -sSfL -H "$AUTH_HEADER" \
      "$API/projects/$PROJECT/repository/archive.tar.gz?sha=$tag&path=$path" \
      | tar -xz -C tools/download --strip-components=1
  done
  mv tools/download/schemas tools/tcms-cli/schemas
  mv tools/download/data/testcase_results_container tools/tcms-cli/data/
  [ -f tools/tcms-cli/data/testcase_results_container/schema.json ] \
    || { echo "  result container schema missing for $tag"; return 1; }

  # A tool that does not start, or lacks the flags the suite uses, fails the tag.
  for bin in $REQUIRED_BINS; do
    "tools/bin/$bin" --version
  done
  tools/bin/verifier --help | grep -q -- '--test-run' \
    || { echo "  verifier for $tag has no --test-run flag"; return 1; }
  echo "installed: $tag"
}

for tag in $TAGS; do
  if install_tag "$tag"; then
    rm -rf tools/download
    exit 0
  fi
  echo "download: $tag did not install, trying the next tag"
done

echo "error: no tag in TCMS_CLI_TAGS ($TAGS) installed tcms-cli" >&2
exit 1
