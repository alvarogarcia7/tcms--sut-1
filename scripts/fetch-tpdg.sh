#!/usr/bin/env bash
# Downloads the test-plan-documentation-generator (TPDG) binary from the GitLab release of
# the TPDG project (generic package registry, the assets of the release at a pinned tag),
# checks it against the release SHA256SUMS and installs it as tools/tpdg/tpdg.
# Same logic as scripts/download-tpdg.sh of tcms-cli (tcms-40-glossary-impl).
#
# Environment:
#   TPDG_VERSION     release tag (default v0.1.0-rc.1)
#   TPDG_PROJECT_ID  TPDG project id (default 350, b3/hardware-kms/test-plan-documentation-generator)
#   TPDG_API         GitLab API root (default https://gitlab.crypto.tii.ae/api/v4)
#   TPDG_DIR         install directory (default tools/tpdg)
#   TPDG_TOKEN       masked CI variable: token with read_api on the TPDG project. Tried first.
#   TCMS_READ_TOKEN  tried next when set; then CI_JOB_TOKEN (works only when the TPDG project
#                    allows this project in its job token allowlist).
# Tokens are passed to curl on stdin (never on the command line) and never printed.
set -euo pipefail

TPDG_VERSION="${TPDG_VERSION:-v0.1.0-rc.1}"
TPDG_PROJECT_ID="${TPDG_PROJECT_ID:-350}"
TPDG_API="${TPDG_API:-https://gitlab.crypto.tii.ae/api/v4}"
TPDG_DIR="${TPDG_DIR:-tools/tpdg}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

ZIP_NAME="tpdg-${TPDG_VERSION}-linux-amd64.zip"
BASE_URL="$TPDG_API/projects/$TPDG_PROJECT_ID/packages/generic/tpdg/$TPDG_VERSION"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Candidate credentials, in order: "<label> <header name>" with the value read from the
# environment variable of the same label.
candidates=()
[ -n "${TPDG_TOKEN:-}" ] && candidates+=("TPDG_TOKEN PRIVATE-TOKEN")
[ -n "${TCMS_READ_TOKEN:-}" ] && candidates+=("TCMS_READ_TOKEN PRIVATE-TOKEN")
[ -n "${CI_JOB_TOKEN:-}" ] && candidates+=("CI_JOB_TOKEN JOB-TOKEN")
if [ ${#candidates[@]} -eq 0 ]; then
  echo "error: no credential for the TPDG project $TPDG_PROJECT_ID (set the masked variable TPDG_TOKEN)" >&2
  exit 1
fi

fetch() { # fetch <var> <header> <file>
  printf 'header = "%s: %s"\n' "$2" "${!1}" |
    curl --fail --silent --show-error --location --config - \
      --output "$TMP_DIR/$3" "$BASE_URL/$3"
}

used=""
for c in "${candidates[@]}"; do
  read -r var header <<< "$c"
  if fetch "$var" "$header" SHA256SUMS 2>/dev/null && fetch "$var" "$header" "$ZIP_NAME"; then
    used="$var"
    break
  fi
  echo "tpdg: $var cannot read $BASE_URL, trying the next credential"
done
if [ -z "$used" ]; then
  echo "error: could not download TPDG $TPDG_VERSION from project $TPDG_PROJECT_ID." >&2
  echo "       Set a masked CI/CD variable TPDG_TOKEN (read_api on project $TPDG_PROJECT_ID)," >&2
  echo "       or allow this project in the TPDG project's job token allowlist." >&2
  exit 1
fi
echo "tpdg: downloaded $ZIP_NAME with $used"

expected="$(awk -v f="$ZIP_NAME" '$2 == f {print $1}' "$TMP_DIR/SHA256SUMS")"
actual="$(sha256sum "$TMP_DIR/$ZIP_NAME" | awk '{print $1}')"
if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
  echo "error: checksum mismatch for $ZIP_NAME (expected '${expected:-none}', got $actual)" >&2
  exit 1
fi
echo "tpdg: checksum verified ($actual)"

rm -rf "$TPDG_DIR"
mkdir -p "$TPDG_DIR"
unzip -oq "$TMP_DIR/$ZIP_NAME" tpdg -d "$TPDG_DIR"
chmod +x "$TPDG_DIR/tpdg"
echo "$TPDG_VERSION" > "$TPDG_DIR/.version"
"$TPDG_DIR/tpdg" --help | head -n 1 || true
echo "tpdg: installed $TPDG_DIR/tpdg ($TPDG_VERSION)"
