#!/usr/bin/env bash
# Puts the tcms-cli tools in tools/ for the pipeline.
#
# 1. Prebuilt: the newest tcms-cli release with a linux-amd64 zip whose version is at
#    least TCMS_CLI_MIN_VERSION. The binaries come from the zip; schemas/ and data/ come
#    from the same tag (tcms-cli needs them at run time and the zip does not ship them).
# 2. Fallback: clone TCMS_CLI_REF and build it from source.
# If both fail the script exits non-zero and the pipeline stops.
#
# Environment:
#   TCMS_CLI_API          GitLab API root (default https://gitlab.crypto.tii.ae/api/v4)
#   TCMS_CLI_PROJECT_ID   tcms-cli project id (default 361)
#   TCMS_CLI_MIN_VERSION  minimum prebuilt version, X.Y.Z (default 0.0.2)
#   TCMS_CLI_REF          tag built from source when no prebuilt qualifies (default v0.0.2-rc1)
#   TCMS_CLI_URL          tcms-cli clone URL (used by the fallback)
#   TCMS_READ_TOKEN       optional read_api token; otherwise CI_JOB_TOKEN is sent as JOB-TOKEN
set -euo pipefail

if [ -n "${TCMS_READ_TOKEN:-}" ]; then
  AUTH_HEADER="PRIVATE-TOKEN: ${TCMS_READ_TOKEN}"
else
  AUTH_HEADER="JOB-TOKEN: ${CI_JOB_TOKEN:?no token: set TCMS_READ_TOKEN or run in CI}"
fi
API="${TCMS_CLI_API:-https://gitlab.crypto.tii.ae/api/v4}"
PROJECT="${TCMS_CLI_PROJECT_ID:-361}"
MIN="${TCMS_CLI_MIN_VERSION:-0.0.2}"
REF="${TCMS_CLI_REF:-v0.0.2-rc1}"
URL="${TCMS_CLI_URL:-https://gitlab.crypto.tii.ae/int/test-case-management-system/tcms-cli.git}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
mkdir -p tools/bin tools/tcms-cli tools/download

# Finds the newest qualifying release. Prints "TAG<TAB>ZIP_URL" or nothing.
select_release() {
  local json
  json="$(curl -sSf -H "$AUTH_HEADER" "$API/projects/$PROJECT/releases?per_page=100")"
  printf '%s' "$json" | jq -r --arg min "$MIN" '
    def ver: capture("^v?(?<a>[0-9]+)\\.(?<b>[0-9]+)\\.(?<c>[0-9]+)")
      | [(.a|tonumber), (.b|tonumber), (.c|tonumber)];
    ($min | split(".") | map(tonumber)) as $minv
    | [ .[]
        | . as $r
        | (try ($r.tag_name | ver) catch null) as $v
        | select($v != null and $v >= $minv)
        | ([$r.assets.links[]? | select(.name | endswith("linux-amd64.zip"))] | first) as $zip
        | select($zip != null)
        | {v: $v, tag: $r.tag_name, url: $zip.url} ]
    | sort_by(.v) | reverse | first
    | if . == null then empty else "\(.tag)\t\(.url)" end
  ' || true
}

fetch_prebuilt() {
  local selected tag url zip
  selected="$(select_release)"
  if [ -z "$selected" ]; then
    echo "prebuilt: no linux-amd64 release at or above $MIN"
    return 1
  fi
  tag="${selected%%$'\t'*}"
  url="${selected#*$'\t'}"
  echo "prebuilt: using $tag"

  zip="tools/download/tcms-cli-$tag-linux-amd64.zip"
  curl -sSfL -H "$AUTH_HEADER" -o "$zip" "$url"
  rm -rf tools/download/extract && mkdir -p tools/download/extract
  if command -v unzip >/dev/null 2>&1; then
    unzip -oq "$zip" -d tools/download/extract
  else
    python3 -m zipfile -e "$zip" tools/download/extract
  fi
  for bin in tcms verifier test-executor validate-yaml; do
    [ -f "tools/download/extract/$bin" ] || { echo "prebuilt: $bin missing from $zip"; return 1; }
    cp "tools/download/extract/$bin" tools/bin/
    chmod +x "tools/bin/$bin"
  done

  # Schemas and result-container data from the same tag, without a full clone.
  for path in schemas data/testcase_results_container; do
    curl -sSfL -H "$AUTH_HEADER" \
      "$API/projects/$PROJECT/repository/archive.tar.gz?sha=$tag&path=$path" \
      | tar -xz -C tools/download --strip-components=1
  done
  rm -rf tools/tcms-cli/schemas tools/tcms-cli/data
  mkdir -p tools/tcms-cli/data
  mv tools/download/schemas tools/tcms-cli/schemas
  mv tools/download/data/testcase_results_container tools/tcms-cli/data/
  rm -rf tools/download/data
  echo "prebuilt: $tag installed"
}

build_from_source() {
  echo "source: building $REF"
  scripts/clone-repo.sh "$URL" "$REF" tools/src/tcms-cli
  (
    cd tools/src/tcms-cli
    cargo build --release -p tcms -p verifier -p test-executor -p validate-yaml
  )
  for bin in tcms verifier test-executor validate-yaml; do
    cp "tools/src/tcms-cli/target/release/$bin" tools/bin/
  done
  rm -rf tools/tcms-cli/schemas tools/tcms-cli/data
  mkdir -p tools/tcms-cli/data
  cp -R tools/src/tcms-cli/schemas tools/tcms-cli/
  cp -R tools/src/tcms-cli/data/testcase_results_container tools/tcms-cli/data/
  echo "source: $REF built"
}

if fetch_prebuilt; then
  :
elif build_from_source; then
  :
else
  echo "error: neither a prebuilt release nor a source build of $REF worked" >&2
  exit 1
fi

for bin in test-executor verifier validate-yaml; do
  "tools/bin/$bin" --version
done
