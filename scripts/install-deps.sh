#!/usr/bin/env bash
# Installs the external tools listed in dependencies.txt into tools/ (see that file).
#   tools/bin/        tcms-cli binaries (test-executor, verifier, validate-yaml)
#   tools/tcms-cli/   tcms-cli schemas and result container schema
#   tools/tpdg/tpdg   TPDG binary
#   tools/<name>/     binaries of a dependency installed from source
#
# Usage: scripts/install-deps.sh           install every dependency
#        scripts/install-deps.sh --list    print the resolved dependencies, one per line:
#                                          name, origin, version, method, binaries (tab separated)
#
# Environment:
#   DEPENDENCIES_FILE   manifest to read (default dependencies.txt)
#   <NAME>_VERSION      overrides the version of a dependency, for example TCMS_CLI_VERSION
#   TCMS_READ_TOKEN     token for cloning a source dependency (read_repository); the fetch
#                       scripts read it too
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
MANIFEST="${DEPENDENCIES_FILE:-dependencies.txt}"

# resolve: the manifest rows with the version overrides applied, tab separated.
resolve() {
  local name origin version method bins var override
  while read -r name origin version method bins; do
    case "$name" in "" | \#*) continue ;; esac
    var="$(printf '%s' "$name" | tr 'a-z-' 'A-Z_')_VERSION"
    override="${!var:-}"
    [ -n "$override" ] && version="$override"
    printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$origin" "$version" "$method" "${bins:-}"
  done < "$MANIFEST"
}

install_binary() { # install_binary <name> <version>
  case "$1" in
    tcms-cli) TCMS_CLI_TAGS="$2" scripts/fetch-tcms-cli.sh ;;
    tpdg) TPDG_VERSION="$2" scripts/fetch-tpdg.sh ;;
    *) echo "error: no binary installer for $1" >&2; return 1 ;;
  esac
}

install_source() { # install_source <name> <origin> <version> <binaries>
  local name="$1" origin="$2" version="$3" bins="$4"
  local src="tools/src/$name" token creds b
  rm -rf "$src"
  mkdir -p tools/src "tools/$name"
  token="${TCMS_READ_TOKEN:-}"
  if [ -n "$token" ]; then
    creds="$(printf 'oauth2:%s' "$token" | base64 | tr -d '\n')"
    git -c "http.extraHeader=Authorization: Basic $creds" clone -q --depth 1 --branch "$version" "$origin" "$src"
  else
    git clone -q --depth 1 --branch "$version" "$origin" "$src"
  fi
  (cd "$src" && cargo build --release -q)
  for b in $bins; do
    cp "$src/target/release/$b" "tools/$name/$b"
  done
}

if [ "${1:-}" = "--list" ]; then
  resolve
  exit 0
fi

# Read the rows from a file descriptor so the installers keep their own stdin.
rows="$(mktemp)"
trap 'rm -f "$rows"' EXIT
resolve > "$rows"
exec 3< "$rows"
while IFS="$(printf '\t')" read -r -u 3 name origin version method bins; do
  echo "install: $name $version ($method from $origin)"
  case "$method" in
    binary) install_binary "$name" "$version" ;;
    source) install_source "$name" "$origin" "$version" "$bins" ;;
    *) echo "error: $name: unknown method '$method' (binary or source)" >&2; exit 1 ;;
  esac
done
exec 3<&-
echo "dependencies installed"
