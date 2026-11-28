# Tests for the test runner itself. Sourced by test/run.sh.

# A copy of the runner and its helpers with tiny areas of its own, so that the
# runner can be run on cases that fail, die or wait on purpose. The copy sits
# beside links to the real cli/, herdr/, skills/, prompts/, agents/ and
# .claude/, which its cases' setup copies from. Every area starts with no cases, which the
# runner refuses, so a case here writes the areas it wants and names them when
# it runs the copy. A case in the copy can leave notes in $FAKE.
fake_suite() {
  local area d
  R=$TMP/suite
  mkdir -p "$R/test"
  cp "$ROOT/test/run.sh" "$ROOT/test/helpers.sh" "$R/test/"
  for d in cli herdr skills prompts agents .claude; do ln -s "$ROOT/$d" "$R/$d"; done
  for area in $AREAS; do echo 'CASES=' > "$R/test/$area.sh"; done
  export FAKE=$TMP/notes
  mkdir -p "$FAKE"
  # As many at a time as the machine allows, unless a case says otherwise.
  unset ENTOURAGE_TEST_JOBS
}

# Run the copy. Its output, errors included, is in $out and its exit code in $code.
run_suite() { out=$("$R/test/run.sh" "$@" 2>&1); code=$?; }

# Two cases that each leave a note and wait for the other's. Only cases that
# run at the same time can both find one. $FAKE_WAITS is how many tenths of a
# second each waits.
meeting_cases() {
  cat > "$R/test/install.sh" <<'EOF'
meet() {
  local mine=$1 theirs=$2 n=0
  : > "$FAKE/$mine"
  until [ -e "$FAKE/$theirs" ]; do
    n=$((n + 1))
    [ "$n" -le "$FAKE_WAITS" ] || { fail "ran alone"; return; }
    sleep 0.1
  done
}
left() { meet left right; }
right() { meet right left; }
CASES="left right"
EOF
}

# With no area named, every area runs, in the runner's own order.
runner_runs_every_area_by_default() {
  fake_suite
  local area want=
  for area in $AREAS; do
    echo "in_$area() { :; }; CASES=in_$area" > "$R/test/$area.sh"
    want="${want}PASS: in_$area
"
  done
  run_suite
  [ "$code" = 0 ] || fail "exited $code: $out"
  [ "$out" = "${want}all passed" ] || fail "wrong output: $out"
}

# The slow case is listed first and finishes last.
runner_reports_cases_in_the_order_listed() {
  fake_suite
  cat > "$R/test/install.sh" <<'EOF'
slow() { sleep 1; }
quick() { :; }
CASES="slow quick"
EOF
  cat > "$R/test/task.sh" <<'EOF'
last() { :; }
CASES="last"
EOF
  export ENTOURAGE_TEST_JOBS=3
  run_suite install task
  [ "$out" = "PASS: slow
PASS: quick
PASS: last
all passed" ] || fail "wrong output: $out"
}

# What a case prints stays with that case, above its own result.
runner_counts_failures_and_exits_non_zero() {
  fake_suite
  cat > "$R/test/install.sh" <<'EOF'
good() { :; }
bad() { echo "something it printed"; fail "first thing"; fail "second thing"; }
after() { :; }
CASES="good bad after"
EOF
  run_suite install
  [ "$code" = 1 ] || fail "exited $code, not 1: $out"
  [ "$out" = "PASS: good
something it printed
FAIL: bad: first thing
FAIL: bad: second thing
PASS: after
2 failed" ] || fail "wrong output: $out"
}

runner_runs_only_the_areas_named() {
  fake_suite
  echo 'a() { :; }; CASES=a' > "$R/test/install.sh"
  echo 'b() { :; }; CASES=b' > "$R/test/space.sh"
  echo 'c() { :; }; CASES=c' > "$R/test/task.sh"
  run_suite task install
  [ "$out" = "PASS: c
PASS: a
all passed" ] || fail "wrong output: $out"
}

runner_refuses_an_unknown_area() {
  fake_suite
  echo 'a() { :; }; CASES=a' > "$R/test/install.sh"
  run_suite nope
  [ "$code" = 2 ] || fail "exited $code, not 2: $out"
  case $out in *"no test area called 'nope'"*) ;; *) fail "did not say which area is unknown: $out" ;; esac
  case $out in *PASS*) fail "ran cases anyway: $out" ;; esac
}

# An area that lists no cases, or does not load, would otherwise run nothing
# and count as passing.
runner_refuses_an_area_with_no_cases() {
  fake_suite
  echo 'a() { :; }; CASES=a' > "$R/test/install.sh"
  run_suite install task
  [ "$code" = 1 ] || fail "exited $code, not 1: $out"
  case $out in *"test/task.sh lists no cases"*) ;; *) fail "did not say which area is empty: $out" ;; esac
  case $out in *"all passed"*) fail "said all passed: $out" ;; esac
}

runner_refuses_an_area_that_does_not_load() {
  fake_suite
  echo 'a() { :; }; CASES=a; return 1' > "$R/test/install.sh"
  run_suite install
  [ "$code" = 1 ] || fail "exited $code, not 1: $out"
  case $out in *"could not load test/install.sh"*) ;; *) fail "did not say which area did not load: $out" ;; esac
  case $out in *"all passed"*) fail "said all passed: $out" ;; esac
}

# A case that is killed never reports. That must count as a failure, and the
# cases after it must still run.
runner_notices_a_case_that_dies() {
  fake_suite
  cat > "$R/test/install.sh" <<'EOF'
before() { :; }
dies() { kill -9 $$; }
after() { :; }
CASES="before dies after"
EOF
  run_suite install
  [ "$code" = 1 ] || fail "exited $code, not 1: $out"
  case $out in
    *"PASS: before"*"FAIL: dies: "*"PASS: after"*"1 failed") ;;
    *) fail "wrong output: $out" ;;
  esac
}

# What one case exports or changes must not reach the next, even one at a time.
runner_keeps_a_case_to_itself() {
  fake_suite
  cat > "$R/test/install.sh" <<'EOF'
leaks() { export LEAKED=yes; }
clean() { [ -z "${LEAKED:-}" ] || fail "saw what the case before exported"; }
CASES="leaks clean"
EOF
  export ENTOURAGE_TEST_JOBS=1
  run_suite install
  [ "$code" = 0 ] || fail "exited $code: $out"
}

runner_runs_cases_side_by_side() {
  fake_suite
  meeting_cases
  export ENTOURAGE_TEST_JOBS=2 FAKE_WAITS=50
  run_suite install
  [ "$code" = 0 ] || fail "the two cases did not overlap: $out"
}

# ENTOURAGE_TEST_JOBS=1 is for looking at one case at a time.
runner_runs_one_at_a_time_when_asked() {
  fake_suite
  meeting_cases
  export ENTOURAGE_TEST_JOBS=1 FAKE_WAITS=10
  run_suite install
  [ "$code" = 1 ] || fail "exited $code, not 1: $out"
  case $out in
    *"FAIL: left: ran alone"*"PASS: right"*"1 failed") ;;
    *) fail "the two cases overlapped: $out" ;;
  esac
}

runner_refuses_a_bad_job_count() {
  fake_suite
  echo 'a() { :; }; CASES=a' > "$R/test/install.sh"
  local n
  for n in 0 -1 two 1.5; do
    export ENTOURAGE_TEST_JOBS=$n
    run_suite install
    [ "$code" = 2 ] || fail "accepted ENTOURAGE_TEST_JOBS='$n' (exit $code): $out"
    case $out in *ENTOURAGE_TEST_JOBS*) ;; *) fail "did not name the setting for '$n': $out" ;; esac
  done
}

CASES="runner_runs_every_area_by_default runner_reports_cases_in_the_order_listed
  runner_counts_failures_and_exits_non_zero runner_runs_only_the_areas_named
  runner_refuses_an_unknown_area runner_refuses_an_area_with_no_cases
  runner_refuses_an_area_that_does_not_load runner_notices_a_case_that_dies
  runner_keeps_a_case_to_itself runner_runs_cases_side_by_side
  runner_runs_one_at_a_time_when_asked runner_refuses_a_bad_job_count"
