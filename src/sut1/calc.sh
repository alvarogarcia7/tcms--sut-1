#!/usr/bin/env bash
# Fake SUT: integer calculator.
set -euo pipefail

usage() { echo "usage: calc.sh add|sub|div A B" >&2; exit 64; }

[ $# -eq 3 ] || usage
op="$1"; a="$2"; b="$3"

case "$op" in
  add) echo $((a + b)) ;;
  sub) echo $((a - b)) ;;
  div)
    if [ "$b" -eq 0 ]; then
      echo "error: division by zero" >&2
      exit 2
    fi
    echo $((a / b)) ;;
  *) usage ;;
esac
