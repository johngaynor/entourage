#!/usr/bin/env bash
# Tests for cli/entourage. With no arguments every area runs; name areas to
# run only those:
#   test/run.sh            everything
#   test/run.sh task       only test/task.sh
#   npm test -- project    the same, through npm
#
# Cases run side by side, each in a process of its own, and are reported in
# the order they are listed. ENTOURAGE_TEST_JOBS is how many run at a time;
# the default is one per processor. Set it to 1 to run one case at a time.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
AREAS="install project task skills handoff linear runner release guard after-merge"
# shellcheck source=/dev/null
. "$HERE/helpers.sh"

# --- the two things a run starts for each case ------------------------------

# run.sh --case <area> <case> <count file>: run one case in this process, and
# leave its number of failures in the count file. A case that dies leaves none.
if [ "${1:-}" = --case ]; then
  CASES=
  # A file that does not load leaves no count, which the run reports as a failure.
  # shellcheck source=/dev/null
  . "$HERE/$2.sh" || exit 1
  run_case "$3"
  echo "$failures" > "$4"
  exit 0
fi

# run.sh --worker <folder> <number> <area> <case>: what xargs starts. It keeps
# everything the case prints in one file, this shell's own word on a case that
# was killed included, and marks the case as over. It always exits zero, so
# that xargs carries on whatever happens to the case.
if [ "${1:-}" = --worker ]; then
  exec > "$2/$3.out" 2>&1
  "$HERE/run.sh" --case "$4" "$5" "$2/$3.count"
  : > "$2/$3.done"
  exit 0
fi

# --- the run ----------------------------------------------------------------

# shellcheck disable=SC2086
[ "$#" -gt 0 ] || set -- $AREAS
for area in "$@"; do
  case " $AREAS " in
    *" $area "*) ;;
    *) echo "no test area called '$area' (there are: $AREAS)" >&2; exit 2 ;;
  esac
done

JOBS=${ENTOURAGE_TEST_JOBS:-}
if [ -z "$JOBS" ]; then
  JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null) || JOBS=
  case $JOBS in '' | *[!0-9]* | 0*) JOBS=4 ;; esac
fi
case $JOBS in
  *[!0-9]* | 0*)
    echo "ENTOURAGE_TEST_JOBS is how many cases run at a time: a whole number, 1 or more (it is '$JOBS')" >&2
    exit 2
    ;;
esac

# Where each case's output waits until it is its turn to be shown.
OUT=$(mktemp -d)
xpid=
# shellcheck disable=SC2317
finish() { [ -z "$xpid" ] || kill "$xpid" 2>/dev/null; rm -rf "$OUT"; }
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Each area file defines its cases and lists them, in the order to run, in
# CASES. The list is one case per line: its number, its area, its name.
n=0
for area in "$@"; do
  CASES=
  # A file that does not load would otherwise run no cases and count as passing.
  # shellcheck source=/dev/null
  . "$HERE/$area.sh" || { echo "could not load test/$area.sh" >&2; exit 1; }
  [ -n "$CASES" ] || { echo "test/$area.sh lists no cases" >&2; exit 1; }
  for c in $CASES; do n=$((n + 1)); echo "$n $area $c"; done
done > "$OUT/list"

xargs -P "$JOBS" -L 1 "$HERE/run.sh" --worker "$OUT" < "$OUT/list" &
xpid=$!

# Show each case when it is over, in the order listed, and add up the failures.
while read -r n area c; do
  until [ -e "$OUT/$n.done" ]; do
    # No workers left, so this case will never be over.
    kill -0 "$xpid" 2>/dev/null || break
    sleep 0.05
  done
  [ ! -f "$OUT/$n.out" ] || cat "$OUT/$n.out"
  if [ -f "$OUT/$n.count" ]; then
    failures=$((failures + $(cat "$OUT/$n.count")))
  else
    echo "FAIL: $c: did not finish"
    failures=$((failures + 1))
  fi
done < "$OUT/list"
wait "$xpid" 2>/dev/null

[ "$failures" = 0 ] && echo "all passed" || { echo "$failures failed"; exit 1; }
