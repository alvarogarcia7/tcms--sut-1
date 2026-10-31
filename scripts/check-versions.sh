#!/usr/bin/env bash
# Compares the pinned version of each dependency in dependencies.txt with the latest release
# of its origin. Prints one line per dependency:
#   OK:      <name> <version> is the latest release
#   WARNING: <name> pinned <version>, latest release <tag>. Set <NAME>_VERSION in .gitlab-ci.yml.
#   SKIPPED: <name>: <reason>
# A WARNING does not fail the job; it is meant for a reader or an agent to act on.
# Usage: scripts/check-versions.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
API="${DEPENDENCY_API:-https://gitlab.crypto.tii.ae/api/v4}"

if [ -n "${TCMS_READ_TOKEN:-}" ]; then
  auth_header="PRIVATE-TOKEN: $TCMS_READ_TOKEN"
elif [ -n "${TPDG_TOKEN:-}" ]; then
  auth_header="PRIVATE-TOKEN: $TPDG_TOKEN"
else
  auth_header="JOB-TOKEN: ${CI_JOB_TOKEN:-}"
fi

# latest_release <origin>: the tag of the newest release of the project at origin, or nothing.
latest_release() {
  local path encoded body
  path="${1#https://*/}"
  path="${path%.git}"
  encoded="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$path")"
  body="$(printf 'header = "%s"\n' "$auth_header" |
    curl --silent --fail --config - "$API/projects/$encoded/releases?per_page=1")" || return 1
  printf '%s' "$body" | python3 -c 'import json, sys; releases = json.load(sys.stdin); print(releases[0]["tag_name"] if releases else "")'
}

scripts/install-deps.sh --list | while IFS="$(printf '\t')" read -r name origin version method bins; do
  latest="$(latest_release "$origin")" || latest=""
  if [ -z "$latest" ]; then
    echo "SKIPPED: $name: could not read the latest release of $origin"
  elif [ "$latest" = "$version" ]; then
    echo "OK:      $name $version is the latest release"
  else
    echo "WARNING: $name pinned $version, latest release $latest ($origin/-/releases). Set $(printf '%s' "$name" | tr 'a-z-' 'A-Z_')_VERSION in .gitlab-ci.yml."
  fi
done
