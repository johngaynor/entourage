#!/usr/bin/env bash
# Tests for cli/entourage. With no arguments every area runs; name areas to
# run only those:
#   test/run.sh            everything
#   test/run.sh task       only test/task.sh
#   npm test -- project    the same, through npm
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
AREAS="install project task skills"
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
  # shellcheck source=/dev/null
  . "$HERE/$area.sh"
  for c in $CASES; do run_case "$c"; done
done

[ "$failures" = 0 ] && echo "all passed" || { echo "$failures failed"; exit 1; }
