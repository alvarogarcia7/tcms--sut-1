#!/usr/bin/env bash
# Shallow-clones a tcms repo at a given ref.
# Usage: scripts/clone-repo.sh REPO_URL REF DEST_DIR
# Uses TCMS_READ_TOKEN (read_repository scope) when set, else the CI job token.
set -euo pipefail

if [ $# -ne 3 ]; then
  echo "usage: $0 REPO_URL REF DEST_DIR" >&2
  exit 64
fi
url="$1"; ref="$2"; dest="$3"

auth="gitlab-ci-token:${CI_JOB_TOKEN:-}"
if [ -n "${TCMS_READ_TOKEN:-}" ]; then
  auth="oauth2:${TCMS_READ_TOKEN}"
fi
# Runners can reuse a workspace, so a previous clone may still be there.
rm -rf "$dest"
git clone --depth 1 --branch "$ref" "https://${auth}@${url#https://}" "$dest"
