#!/usr/bin/env bash
# Validates every test case in testcases/ against its JSON schema with validate-yaml.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# shellcheck source=scripts/tcms-env.sh
. "$SCRIPT_DIR/tcms-env.sh"

"$VALIDATE_YAML" testcases/*.yml --schemas-root "$TCMS_SRC_DIR/schemas"
