#!/usr/bin/env bash
# Fake SUT: password strength check.
# A password is "strong" when it has at least 8 characters, one digit and one uppercase letter.
set -euo pipefail

usage() { echo "usage: passcheck.sh PASSWORD" >&2; exit 64; }

[ $# -eq 1 ] || usage
pw="$1"

if [ "${#pw}" -lt 8 ]; then
  echo "weak: too short"
  exit 1
fi
case "$pw" in
  *[0-9]*) ;;
  *) echo "weak: no digit"; exit 1 ;;
esac
case "$pw" in
  *[A-Z]*) ;;
  *) echo "weak: no uppercase letter"; exit 1 ;;
esac
echo "strong"
