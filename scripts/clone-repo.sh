#!/usr/bin/env bash
# Shallow-clones a tcms repo at a given ref into a fresh directory.
# Usage: scripts/clone-repo.sh REPO_URL REF DEST_DIR
#   DEST_DIR must be a relative path inside the repo (for example tools/src/tcms-cli).
#   Any existing directory there is removed first, because runners can reuse a workspace.
# Uses TCMS_READ_TOKEN (read_repository scope) when set, else the CI job token.
set -euo pipefail

if [ $# -ne 3 ]; then
  echo "usage: $0 REPO_URL REF DEST_DIR" >&2
  exit 64
fi
url="$1"; ref="$2"; dest="$3"

# Guard the rm below: only a relative path that stays inside the repo.
case "$dest" in
  "" | /* | *..* | .)
    echo "error: refusing to use DEST_DIR '$dest' (must be a relative path inside the repo)" >&2
    exit 1 ;;
esac
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$(dirname "$repo_root/$dest")"
target="$repo_root/$dest"
case "$target" in
  "$repo_root"/*) ;;
  *) echo "error: $target is outside $repo_root" >&2; exit 1 ;;
esac

rm -rf "$target"
auth="gitlab-ci-token:${CI_JOB_TOKEN:-}"
if [ -n "${TCMS_READ_TOKEN:-}" ]; then
  auth="oauth2:${TCMS_READ_TOKEN}"
fi
git clone --depth 1 --branch "$ref" "https://${auth}@${url#https://}" "$target"
