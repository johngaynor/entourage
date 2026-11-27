#!/usr/bin/env bash
# Tests for cli/entourage. With no arguments every area runs; name areas to
# run only those:
#   test/run.sh            everything
#   test/run.sh task       only test/task.sh
#   npm test -- project    the same, through npm
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
AREAS="install project task skills handoff"
# shellcheck source=/dev/null
. "$HERE/helpers.sh"

# shellcheck disable=SC2086
[ "$#" -gt 0 ] || set -- $AREAS
for area in "$@"; do
  case " $AREAS " in
    *" $area "*) ;;
    *) echo "no test area called '$area' (there are: $AREAS)" >&2; exit 2 ;;
  esac
done

# Each area file defines its cases and lists them, in the order to run, in CASES.
for area in "$@"; do
  CASES=
  # A file that does not load would otherwise run no cases and count as passing.
  # shellcheck source=/dev/null
  . "$HERE/$area.sh" || { echo "could not load test/$area.sh" >&2; exit 1; }
  [ -n "$CASES" ] || { echo "test/$area.sh lists no cases" >&2; exit 1; }
  for c in $CASES; do run_case "$c"; done
done

[ "$failures" = 0 ] && echo "all passed" || { echo "$failures failed"; exit 1; }
