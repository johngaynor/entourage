# Tests for hand-offs: `task handoff`, `task log` and the store behind them.
# They run against the real sqlite3. Sourced by test/run.sh.

STORE() { printf '%s\n' "${ENTOURAGE_HOME:-$HOME/.config/entourage}/entourage.db"; }
# Run one query against the store and print its answer.
q() { sqlite3 "$(STORE)" "$1" 2>/dev/null; }
rows() { q 'select count(*) from handoffs' || true; }

demo() { "$E" project new demo >/dev/null; }
# Hand the block in $1 off for ABC-122 in demo.
hand() { printf '%s\n' "$1" | "$E" task handoff demo ABC-122; }

DONE_BLOCK='phase: define
status: done
next: plan
summary: Set the type to fix.
flags: Not reproduced.'

handoff_records_a_done_step() {
  demo
  out=$(hand "$DONE_BLOCK") || fail "task handoff exited non-zero"
  [ "$out" = "$DONE_BLOCK" ] || fail "did not print the block back: $out"
  [ "$(rows)" = 1 ] || fail "expected one row, got $(rows)"
  got=$(q "select project || '|' || card || '|' || phase || '|' || status || '|' || next || '|' || summary || '|' || flags from handoffs")
  [ "$got" = 'demo|ABC-122|define|done|plan|Set the type to fix.|Not reproduced.' ] || fail "wrong row: $got"
  at=$(q 'select at from handoffs')
  re='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
  [[ $at =~ $re ]] || fail "the time is not UTC in ISO form: $at"
  [ -z "$(q 'select question || options || reason from handoffs')" ] || fail "fields that were not given are not empty"
}

handoff_prints_the_block_in_the_usual_order() {
  demo
  out=$(hand 'flags: Not reproduced.
summary: Set the type to fix.

next: plan
status: done
phase: define') || fail "task handoff exited non-zero"
  [ "$out" = "$DONE_BLOCK" ] || fail "did not put the lines in the usual order: $out"
}

handoff_records_a_question() {
  demo
  block='phase: breakdown
status: needs-human
summary: fix, one piece.
question: Approve ABC-122 as specified, planned and broken down?
options: approve | change breakdown | change plan | change specification'
  out=$(hand "$block") || fail "task handoff exited non-zero"
  [ "$out" = "$block" ] || fail "did not print the block back: $out"
  got=$(q "select status || '|' || question || '|' || options from handoffs")
  [ "$got" = 'needs-human|Approve ABC-122 as specified, planned and broken down?|approve | change breakdown | change plan | change specification' ] ||
    fail "wrong row: $got"
}

handoff_records_a_failure() {
  demo
  hand 'phase: plan
status: failed
reason: The card has no Specification.' >/dev/null || fail "task handoff exited non-zero"
  [ "$(q "select phase || '|' || status || '|' || reason from handoffs")" = 'plan|failed|The card has no Specification.' ] ||
    fail "wrong row: $(q 'select * from handoffs')"
}

# The block in $1 must be refused with a message holding $2, and leave no row.
refused() {
  local out
  if out=$(hand "$1" 2>&1); then fail "accepted a block it should refuse: $1"; fi
  case $out in *"$2"*) ;; *) fail "the refusal does not mention '$2': $out" ;; esac
  [ "$(rows)" = 0 ] || [ -z "$(rows)" ] || fail "recorded a refused hand-off: $1"
}

handoff_refuses_a_missing_line() {
  demo
  refused 'phase: define
status: done
summary: Done.' 'next'
  refused 'phase: define
status: done
next: plan' 'summary'
  refused 'phase: define
status: needs-human
question: Which users?' 'options'
  refused 'phase: define
status: failed' 'reason'
  refused 'phase: define
next: plan
summary: Done.' 'status'
  refused 'status: done
next: plan
summary: Done.' 'phase'
}

handoff_refuses_what_it_does_not_know() {
  demo
  refused 'phase: define
status: finished
next: plan
summary: Done.' 'finished'
  refused 'phase: deploy
status: done
next: plan
summary: Done.' 'deploy'
  refused 'phase: define
status: done
next: ship
summary: Done.' 'ship'
  refused 'phase: define
status: done
next: plan
summary: Done.
note: Something else.' 'note'
}

handoff_refuses_a_line_that_does_not_belong() {
  demo
  refused 'phase: define
status: done
next: plan
summary: Done.
reason: None.' 'reason'
  refused 'phase: define
status: failed
reason: Linear is down.
next: plan' 'next'
  refused 'phase: define
status: needs-human
question: Which users?
options: all | admins
flags: None.' 'flags'
}

handoff_refuses_a_value_on_two_lines() {
  demo
  refused 'phase: define
status: done
next: plan
summary: Set the type to fix
and wrote the Specification.' 'one line'
}

handoff_refuses_a_repeated_or_empty_line() {
  demo
  refused 'phase: define
status: done
next: plan
summary: Done.
summary: Really done.' 'twice'
  refused 'phase: define
status: done
next: plan
summary: Done.
flags:' 'flags'
}

handoff_refuses_an_empty_block() {
  demo
  if out=$("$E" task handoff demo ABC-122 </dev/null 2>&1); then fail "accepted no block at all"; fi
  case $out in *'phase:'*) ;; *) fail "does not show what a block looks like: $out" ;; esac
}

handoff_refuses_unknown_project_and_bad_card() {
  demo
  if out=$(printf '%s\n' "$DONE_BLOCK" | "$E" task handoff nope ABC-122 2>&1); then fail "accepted an unknown project"; fi
  case $out in *"no entourage project called 'nope'"*'not recorded'*) ;; *) fail "unhelpful message: $out" ;; esac
  case $out in *'project new'*) fail "invites the agent to make a project: $out" ;; esac
  if out=$(printf '%s\n' "$DONE_BLOCK" | "$E" task handoff demo not-a-card 2>&1); then fail "accepted a bad card"; fi
  case $out in *'not a card ID'*) ;; *) fail "unhelpful message: $out" ;; esac
  if out=$(printf '%s\n' "$DONE_BLOCK" | "$E" task handoff demo 2>&1); then fail "accepted no card"; fi
  [ ! -e "$(STORE)" ] || [ "$(rows)" = 0 ] || fail "recorded something"
}

# An agent's text is full of quotes, backticks and dollars. None of it may be
# run by a shell or read as SQL: it comes back exactly as it went in.
handoff_keeps_awkward_text() {
  demo
  IFS= read -r text <<'EOF'
It's "done"; ran `ls` and $HOME, then '); drop table handoffs; -- 100% \n .shell true
EOF
  block="phase: define
status: done
next: plan
summary: $text"
  out=$(hand "$block") || fail "task handoff exited non-zero"
  [ "$out" = "$block" ] || fail "printed it back changed: $out"
  [ "$(q 'select summary from handoffs')" = "$text" ] || fail "stored it changed: $(q 'select summary from handoffs')"
  [ "$(rows)" = 1 ] || fail "the table is gone or has extra rows: $(rows)"
}

handoff_takes_a_lowercase_card() {
  demo
  printf '%s\n' "$DONE_BLOCK" | "$E" task handoff demo abc-122 >/dev/null || fail "task handoff exited non-zero"
  [ "$(q 'select card from handoffs')" = ABC-122 ] || fail "did not record the card's usual form"
}

handoff_honors_entourage_home() {
  export ENTOURAGE_HOME=$TMP/elsewhere
  demo
  hand "$DONE_BLOCK" >/dev/null || fail "task handoff exited non-zero"
  [ -f "$TMP/elsewhere/entourage.db" ] || fail "the store is not in ENTOURAGE_HOME"
  [ ! -e "$HOME/.config/entourage/entourage.db" ] || fail "made a store in the default folder too"
}

handoff_without_sqlite_says_so() {
  demo
  export ENTOURAGE_SQLITE=no-such-sqlite3
  if out=$(hand "$DONE_BLOCK" 2>&1); then fail "claimed to record without sqlite3"; fi
  case $out in *'not recorded'*) ;; *) fail "does not say the hand-off was not recorded: $out" ;; esac
  # A block that breaks the rules is still refused for that, so the agent hears it.
  if out=$(hand 'phase: define
status: done' 2>&1); then fail "accepted a broken block"; fi
  case $out in *'next'*) ;; *) fail "did not check the block first: $out" ;; esac
}

# A machine that is set up, as in the task tests: skills linked, an agent on PATH.
started_demo() {
  "$E" install >/dev/null
  demo
  stub claude
  : > "$TMP/herdr-calls.log"
}

task_new_records_the_start() {
  started_demo
  "$E" task new demo abc-122 >/dev/null || fail "task new exited non-zero"
  [ "$(q "select card || '|' || phase || '|' || status || '|' || next from handoffs")" = 'ABC-122|new|done|define' ] ||
    fail "no starting row: $(q 'select * from handoffs')"
}

task_new_starts_without_sqlite() {
  started_demo
  export ENTOURAGE_SQLITE=no-such-sqlite3
  out=$("$E" task new demo ABC-122) || fail "task new exited non-zero without sqlite3"
  grep -q '^do tab\.new ' "$TMP/herdr-calls.log" || fail "did not open the tab"
  case $out in *sqlite3*) ;; *) fail "did not say hand-offs are not recorded: $out" ;; esac
}

status_notes_missing_sqlite() {
  "$E" install >/dev/null
  demo
  # Fill the doc in, so the project itself is not a problem.
  printf '# demo\n' > "$P/demo/PROJECT.md"
  out=$("$E" status) || true
  case $out in *sqlite3*) fail "noted sqlite3 though it is installed: $out" ;; esac
  export ENTOURAGE_SQLITE=no-such-sqlite3
  out=$("$E" status) || true
  case $out in *'sqlite3 is not installed'*) ;; *) fail "no note about sqlite3: $out" ;; esac
}

log_lists_a_cards_handoffs_in_order() {
  demo
  hand "$DONE_BLOCK" >/dev/null
  hand 'phase: plan
status: needs-human
question: Reuse the invoice export?
options: yes | write a new one' >/dev/null
  printf 'phase: define\nstatus: done\nnext: plan\nsummary: Another card entirely.\n' |
    "$E" task handoff demo ABC-9 >/dev/null
  "$E" project new other >/dev/null
  printf 'phase: define\nstatus: done\nnext: plan\nsummary: Another project entirely.\n' |
    "$E" task handoff other ABC-122 >/dev/null
  out=$("$E" task log demo abc-122) || fail "task log exited non-zero"
  first=$(printf '%s\n' "$out" | grep -n 'define' | head -1 | cut -d: -f1)
  second=$(printf '%s\n' "$out" | grep -n 'needs-human' | head -1 | cut -d: -f1)
  [ -n "$first" ] && [ -n "$second" ] && [ "$first" -lt "$second" ] || fail "not in the order they happened: $out"
  # Each field under its own name. The second row has no next, summary or
  # flags: fields that are empty in the middle must not shift the ones after.
  for want in 'define     done, then plan' '    summary: Set the type to fix.' '    flags: Not reproduced.' \
    '    question: Reuse the invoice export?' '    options: yes | write a new one'; do
    printf '%s\n' "$out" | grep -qxF -- "$want" ||
      printf '%s\n' "$out" | grep -qF -- "  $want" ||
      fail "the log has no line '$want': $out"
  done
  printf '%s\n' "$out" | grep -Eq 'plan +needs-human( |$)' || fail "the row with no next is printed wrongly: $out"
  case $out in *'Another card entirely.'*) fail "showed another card's hand-off: $out" ;; esac
  case $out in *'Another project entirely.'*) fail "showed another project's hand-off: $out" ;; esac
}

# A store that cannot be read is an error, not an empty history.
log_fails_when_the_store_cannot_be_read() {
  demo
  mkdir -p "$HOME/.config/entourage"
  echo 'not a database' > "$HOME/.config/entourage/entourage.db"
  if out=$("$E" task log demo ABC-122 2>&1); then fail "read a file that is not a database: $out"; fi
  case $out in *'could not read'*) ;; *) fail "does not say it could not read the store: $out" ;; esac
  case $out in *'No hand-offs'*) fail "claimed there are no hand-offs: $out" ;; esac
}

handoff_says_when_it_cannot_write() {
  demo
  mkdir -p "$HOME/.config/entourage/entourage.db"
  if out=$(hand "$DONE_BLOCK" 2>&1); then fail "claimed to record into a folder"; fi
  case $out in *'not recorded'*) ;; *) fail "does not say the hand-off was not recorded: $out" ;; esac
}

task_new_starts_when_the_store_cannot_be_written() {
  started_demo
  mkdir -p "$HOME/.config/entourage/entourage.db"
  out=$("$E" task new demo ABC-122) || fail "task new exited non-zero with a store it cannot write"
  grep -q '^do tab\.new ' "$TMP/herdr-calls.log" || fail "did not open the tab"
  case $out in *'could not record'*) ;; *) fail "did not say the start was not recorded: $out" ;; esac
}

handoff_refuses_two_steps_in_one_value() {
  demo
  refused 'phase: define plan
status: done
next: plan
summary: Done.' 'define plan'
  refused 'phase: define
status: done
next: plan breakdown
summary: Done.' 'plan breakdown'
}

handoff_refuses_a_control_character() {
  demo
  refused "phase: define
status: done
next: plan
summary: A tab$(printf '\t')in the middle." 'control character'
}

handoff_takes_crlf_lines() {
  demo
  printf 'phase: define\r\nstatus: done\r\nnext: plan\r\nsummary: From a Windows editor.\r\n' |
    "$E" task handoff demo ABC-122 >/dev/null || fail "refused a block with CRLF line ends"
  [ "$(q "select phase || '|' || summary from handoffs")" = 'define|From a Windows editor.' ] ||
    fail "kept the carriage returns: $(q 'select hex(summary) from handoffs')"
}

handoff_takes_indented_lines() {
  demo
  out=$(hand '  phase: define
  status: done
  next: plan
  summary: Set the type to fix.
  flags: Not reproduced.') || fail "refused an indented block"
  [ "$out" = "$DONE_BLOCK" ] || fail "did not print it back without the indent: $out"
}

# The skills show each line with a hint in angle brackets. One left in is not
# a hand-off.
handoff_refuses_a_placeholder_left_in() {
  demo
  refused 'phase: define
status: done
next: plan
summary: <one to three sentences on what you did>' 'placeholder'
}

handoff_refuses_a_very_long_line() {
  demo
  long=$(printf 'x%.0s' $(seq 1 5000))
  refused "phase: define
status: done
next: plan
summary: $long" 'characters'
}

# On a Mac the folder demo also answers to Demo. A hand-off under the wrong
# name would never show in the log.
handoff_refuses_a_project_in_the_wrong_case() {
  demo
  if out=$(printf '%s\n' "$DONE_BLOCK" | "$E" task handoff Demo ABC-122 2>&1); then fail "accepted Demo for demo"; fi
  case $out in *'not recorded'*) ;; *) fail "unhelpful message: $out" ;; esac
  [ ! -e "$(STORE)" ] || [ "$(rows)" = 0 ] || fail "recorded a hand-off under the wrong name"
}

log_says_when_nothing_is_recorded() {
  demo
  out=$("$E" task log demo ABC-122) || fail "task log exited non-zero with nothing recorded"
  case $out in *'No hand-offs'*) ;; *) fail "does not say there are none: $out" ;; esac
  hand "$DONE_BLOCK" >/dev/null
  out=$("$E" task log demo ABC-7) || fail "task log exited non-zero for a card with none"
  case $out in *'No hand-offs'*) ;; *) fail "does not say there are none for that card: $out" ;; esac
}

# --- answers and times ------------------------------------------------------

handoff_records_an_answer() {
  demo
  block='phase: breakdown
status: answered
answer: change specification: the athlete app only'
  out=$(hand "$block") || fail "task handoff exited non-zero"
  [ "$out" = "$block" ] || fail "did not print the block back: $out"
  [ "$(q "select phase || '|' || status || '|' || answer from handoffs")" = 'breakdown|answered|change specification: the athlete app only' ] ||
    fail "wrong row: $(q 'select * from handoffs')"
}

handoff_checks_an_answer() {
  demo
  refused 'phase: breakdown
status: answered' "'answer:'"
  refused 'phase: breakdown
status: answered
answer: approve
summary: They approved.' 'summary'
  refused 'phase: define
status: done
next: plan
summary: Done.
answer: approve' "'answer:'"
}

# The block in $1 must be recorded and printed back, and `task log` must then
# show each of the lines after it.
step_logged() {
  local block=$1 out want
  shift
  demo
  # stderr is kept apart: a merge's note on the card goes there.
  out=$(hand "$block" 2>"$TMP/err") || fail "task handoff refused the block: $(cat "$TMP/err")"
  [ "$out" = "$block" ] || fail "did not print the block back: $out"
  out=$("$E" task log demo ABC-122) || fail "task log exited non-zero"
  for want in "$@"; do
    printf '%s\n' "$out" | grep -qF -- "$want" || fail "the log has no line '$want': $out"
  done
}

# The build step hands off as build, with review next when it is done.
handoff_records_a_finished_build() {
  step_logged 'phase: build
status: done
next: review
summary: Built the CSV export and its tests. The tests pass.' \
    'build      done, then review' '    summary: Built the CSV export and its tests. The tests pass.'
}

handoff_records_a_build_that_needs_the_human() {
  step_logged 'phase: build
status: needs-human
question: The Plan names a helper that does not exist. Write it, or reuse the invoice export?
options: reuse the invoice export | write the helper' \
    'build      needs-human' \
    '    question: The Plan names a helper that does not exist. Write it, or reuse the invoice export?'
}

handoff_records_a_failed_build() {
  step_logged 'phase: build
status: failed
reason: The card has no Plan, so nothing was built.' \
    'build      failed' '    reason: The card has no Plan, so nothing was built.'
}

# The review hands off as review. When every Done when item is met, the pull
# request is next; when one is not, the build is.
handoff_records_a_review_that_passes() {
  step_logged 'phase: review
status: done
next: pr
summary: All three Done when items are met, each by its test. The tests pass.' \
    'review     done, then pr' '    summary: All three Done when items are met, each by its test. The tests pass.'
}

handoff_records_a_review_that_sends_the_work_back() {
  step_logged 'phase: review
status: done
next: build
summary: Item 2 is not met: no test checks that the file has one row per order.' \
    'review     done, then build' \
    '    summary: Item 2 is not met: no test checks that the file has one row per order.'
}

handoff_records_a_review_that_needs_the_human() {
  step_logged 'phase: review
status: needs-human
question: Item 2 is still not met after one send-back. Build again, or stop?
options: build again | stop' \
    'review     needs-human' \
    '    question: Item 2 is still not met after one send-back. Build again, or stop?'
}

handoff_records_a_failed_review() {
  step_logged 'phase: review
status: failed
reason: No worktree has commits ahead of main, so nothing was built.' \
    'review     failed' '    reason: No worktree has commits ahead of main, so nothing was built.'
}

# The pull request hands off as pr. It waits on the human to merge it, and
# once every pull request for the card has merged, merged is next: where the
# card ends.
handoff_records_a_pull_request_waiting_to_merge() {
  step_logged 'phase: pr
status: needs-human
question: Merge https://github.com/acme/shop/pull/7, then tell me when it has merged.
options: merged | stop here' \
    'pr         needs-human' \
    '    question: Merge https://github.com/acme/shop/pull/7, then tell me when it has merged.'
}

handoff_records_a_merge() {
  step_logged 'phase: pr
status: done
next: merged
summary: https://github.com/acme/shop/pull/7 has merged into main.' \
    'pr         done, then merged' '    summary: https://github.com/acme/shop/pull/7 has merged into main.'
}

handoff_records_a_pull_request_that_cannot_be_opened() {
  step_logged 'phase: pr
status: failed
reason: gh is not signed in, so nothing was pushed. Run: gh auth login' \
    'pr         failed' '    reason: gh is not signed in, so nothing was pushed. Run: gh auth login'
}

# merged is where a card ends. A step can hand on to it, but nothing hands
# off as it.
handoff_refuses_merged_as_a_phase() {
  demo
  refused 'phase: merged
status: done
next: pr
summary: Merged.' 'merged'
  refused 'phase: merged
status: failed
reason: Not merged.' 'merged'
}

# --- the card moves to done on its merge ------------------------------------

MERGE_BLOCK='phase: pr
status: done
next: merged
summary: https://github.com/acme/shop/pull/7 has merged into main.'

# A Linear that answers with what is given, one answer for each call, and a
# key to ask it with.
linear_for_moves() { export LINEAR_API_KEY=$KEY; stub_linear; linear_answers "$@"; }

# Recording the merge moves the card to its team's first completed status.
# It is recorded with no answer from the human before it, as a watch on the
# pull requests would record it. The block is printed as it is, on stdout,
# and what happened to the card goes to stderr.
handoff_moves_the_card_to_done_on_the_merge() {
  demo
  linear_for_moves "$(move_answer ABC-122 'In Review')" "$(moved_answer Done)"
  out=$(hand "$MERGE_BLOCK" 2>"$TMP/err") || fail "task handoff exited non-zero: $(cat "$TMP/err")"
  [ "$out" = "$MERGE_BLOCK" ] || fail "did not print the block back as it is: $out"
  [ "$(rows)" = 1 ] || fail "expected one row, got $(rows)"
  [ "$(curl_count)" = 2 ] || fail "asked Linear $(curl_count) times, not 2: $(curl_calls)"
  case $(changes_sent) in
    *'"id":"id-ABC-122"'*'"stateId":"s-done"'*) ;;
    *) fail "did not move the card to Done: $(changes_sent)" ;;
  esac
  grep -qxF 'ABC-122 moved to Done in Linear (it was In Review)' "$TMP/err" || fail "did not say the card moved: $(cat "$TMP/err")"
}

# A card that is closed is never moved: not to Done, and never back.
handoff_moves_no_closed_card_on_the_merge() {
  demo
  linear_for_moves "$(move_answer ABC-122 Canceled)"
  out=$(hand "$MERGE_BLOCK" 2>"$TMP/err") || fail "task handoff exited non-zero: $(cat "$TMP/err")"
  [ "$out" = "$MERGE_BLOCK" ] || fail "did not print the block back as it is: $out"
  [ "$(curl_count)" = 1 ] || fail "asked Linear $(curl_count) times, not 1: $(curl_calls)"
  [ -z "$(changes_sent)" ] || fail "asked Linear to change the card: $(changes_sent)"
  grep -qF 'ABC-122 stays in Canceled, which is closed' "$TMP/err" || fail "did not say why the card stays: $(cat "$TMP/err")"
}

# Of the pull request's hand-offs, only the merge moves the card. A pull
# request closed without merging hands off failed, or asks the human, and
# Linear is asked nothing; so does a review or a define that is done. (The
# approval moves the card too: see below.)
handoff_moves_the_card_only_on_the_merge() {
  demo
  linear_for_moves "$(move_answer ABC-122 'In Review')" "$(moved_answer Done)"
  local block
  for block in 'phase: pr
status: failed
reason: https://github.com/acme/shop/pull/7 was closed without merging.' 'phase: pr
status: needs-human
question: https://github.com/acme/shop/pull/7 was closed without merging. Reopen it, or stop here?
options: stop here | reopen it' 'phase: pr
status: answered
answer: stop here' 'phase: review
status: done
next: pr
summary: Every Done when item is met.' "$DONE_BLOCK"; do
    hand "$block" >/dev/null 2>"$TMP/err" || fail "task handoff refused the block: $block: $(cat "$TMP/err")"
    [ ! -s "$TMP/err" ] || fail "said something on stderr for: $block: $(cat "$TMP/err")"
  done
  [ "$(rows)" = 5 ] || fail "expected five rows, got $(rows)"
  [ "$(curl_count)" = 0 ] || fail "asked Linear: $(curl_calls)"
}

# A card that cannot be moved never costs the hand-off: it is recorded and
# printed, the command exits zero, and stderr says why the card was not moved.
handoff_records_the_merge_when_linear_refuses_the_move() {
  demo
  linear_for_moves "$(move_answer ABC-122 'In Review')" "$NO_WRITE"
  linear_status_at 2 400
  out=$(hand "$MERGE_BLOCK" 2>"$TMP/err") || fail "task handoff exited non-zero: $(cat "$TMP/err")"
  [ "$out" = "$MERGE_BLOCK" ] || fail "did not print the block back as it is: $out"
  [ "$(rows)" = 1 ] || fail "expected one row, got $(rows)"
  grep -qxF 'ABC-122 was not moved in Linear: Linear answered with an error: Invalid scope: `write` required' "$TMP/err" ||
    fail "did not say why the card was not moved: $(cat "$TMP/err")"
}

# With no key saved there is no Linear to ask, which is a note too.
handoff_records_the_merge_with_no_key_saved() {
  demo
  stub_linear
  out=$(hand "$MERGE_BLOCK" 2>"$TMP/err") || fail "task handoff exited non-zero: $(cat "$TMP/err")"
  [ "$out" = "$MERGE_BLOCK" ] || fail "did not print the block back as it is: $out"
  [ "$(rows)" = 1 ] || fail "expected one row, got $(rows)"
  [ "$(curl_count)" = 0 ] || fail "asked Linear with no key: $(curl_calls)"
  grep -qF 'ABC-122 was not moved in Linear: no Linear key is saved' "$TMP/err" ||
    fail "did not say why the card was not moved: $(cat "$TMP/err")"
}

# --- closed cards are archived on the merge, when archiving is on -----------

# The settings file, with "archive" set to $1 (true or false).
archiving() {
  mkdir -p "$HOME/.config/entourage"
  printf '{"archive": %s}\n' "$1" > "$HOME/.config/entourage/settings.json"
}
# The demo project, with the Linear teams given (ABC when none is), archiving
# on, and the move to Done answered: the card goes from In Review to Done.
archive_demo() {
  demo
  "$E" project team demo "${@:-ABC}" >/dev/null || fail "could not set the project's teams"
  archiving true
}
# The Linear answers for the merge: the move to Done, then those given.
linear_for_archive() { linear_for_moves "$(move_answer ABC-122 'In Review')" "$(moved_answer Done)" "$@"; }
# Record the merge, which has to exit zero, print the block as it is and be
# recorded, whatever happens to the cards. What it said of them is in
# $TMP/err.
merge_recorded() {
  out=$(hand "$MERGE_BLOCK" 2>"$TMP/err") || fail "task handoff exited non-zero: $(cat "$TMP/err")"
  [ "$out" = "$MERGE_BLOCK" ] || fail "did not print the block back as it is: $out"
  [ "$(rows)" = 1 ] || fail "expected one row, got $(rows)"
}
# Fail unless the hand-off said the line $1, as it is.
said() { grep -qxF -- "$1" "$TMP/err" || fail "did not say '$1': $(cat "$TMP/err")"; }
# The ids of the cards Linear was asked to archive, in order, on one line.
archived_ids() { archives_sent | sed -n 's/.*"variables":{"id":"\([^"]*\)"}.*/\1/p' | tr '\n' ' ' | sed 's/ $//'; }

# With archiving off, the merge asks Linear for the move alone, as before.
handoff_archives_nothing_with_archiving_off() {
  archive_demo
  archiving false
  linear_for_archive
  merge_recorded
  [ "$(curl_count)" = 2 ] || fail "asked Linear $(curl_count) times, not 2: $(curl_calls)"
  [ -z "$(archives_sent)" ] || fail "asked Linear to archive a card: $(archives_sent)"
  [ "$(cat "$TMP/err")" = 'ABC-122 moved to Done in Linear (it was In Review)' ] ||
    fail "said something of archiving: $(cat "$TMP/err")"
}

# With archiving on, the merged card is archived once the move has put it in
# Done: archived, not deleted, so no trash is asked for.
handoff_archives_the_merged_card() {
  archive_demo
  linear_for_archive "$(archive_card_answer ABC-122 Done)" "$ARCHIVED" "$(closed_page '[]')"
  merge_recorded
  [ "$(curl_count)" = 5 ] || fail "asked Linear $(curl_count) times, not 5: $(curl_calls)"
  [ "$(archived_ids)" = id-ABC-122 ] || fail "did not archive the card alone: $(archives_sent)"
  case $(archives_sent) in *trash*) fail "asked Linear to put the card in the trash: $(archives_sent)" ;; esac
  curl_calls | sed -n 3p | grep -qF '"variables":{"team":"ABC","number":122}' ||
    fail "did not ask Linear about ABC-122: $(curl_calls | sed -n 3p)"
  [ "$(cat "$TMP/err")" = 'ABC-122 moved to Done in Linear (it was In Review)
ABC-122 archived in Linear
Archived 0 other closed cards of ABC in Linear' ] || fail "did not say what was archived: $(cat "$TMP/err")"
}

# Every other card of the project's teams that is done, canceled or a
# duplicate is archived too, from every page Linear has, one call each.
handoff_archives_the_teams_other_closed_cards() {
  archive_demo ABC XYZ
  linear_for_archive "$(archive_card_answer ABC-122 Done)" "$ARCHIVED" \
    "$(closed_page "[$(closed_card ABC-1 Done),$(closed_card ABC-2 Canceled),$(closed_card XYZ-3 Duplicate)]" cursor-1)" \
    "$(closed_page "[$(closed_card ABC-4 Done)]")" "$ARCHIVED"
  merge_recorded
  [ "$(curl_count)" = 10 ] || fail "asked Linear $(curl_count) times, not 10: $(curl_calls)"
  [ "$(archived_ids)" = 'id-ABC-122 id-ABC-1 id-ABC-2 id-XYZ-3 id-ABC-4' ] ||
    fail "did not archive each card once, in order: $(archived_ids)"
  local page
  page=$(curl_calls | sed -n 5p)
  case $page in
    *'"teams":["ABC","XYZ"]'*'"types":["completed","canceled"]'*'"after":null'*) ;;
    *) fail "the first page did not ask for the closed cards of ABC and XYZ: $page" ;;
  esac
  curl_calls | sed -n 6p | grep -qF '"after":"cursor-1"' || fail "did not ask for the second page: $(curl_calls | sed -n 6p)"
  said 'ABC-122 archived in Linear'
  said 'Archived 4 other closed cards of ABC, XYZ in Linear'
}

# A card with a parent or sub-issues is left as it is, whether it is the
# merged card or another closed one; the note names each, and why.
handoff_archives_no_card_with_a_parent_or_sub_issues() {
  archive_demo
  linear_for_archive "$(archive_card_answer ABC-122 Done ABC-100)" \
    "$(closed_page "[$(closed_card ABC-7 Done '' '["ABC-8"]'),$(closed_card ABC-9 Canceled ABC-7),$(closed_card ABC-10 Done)]")" \
    "$ARCHIVED"
  merge_recorded
  [ "$(archived_ids)" = id-ABC-10 ] || fail "archived a card with a parent or sub-issues: $(archives_sent)"
  [ "$(cat "$TMP/err")" = 'ABC-122 moved to Done in Linear (it was In Review)
ABC-122 was not archived in Linear: it is a sub-issue of ABC-100, and a card with a parent or sub-issues is never archived
ABC-7 was not archived in Linear: it has sub-issues, and a card with a parent or sub-issues is never archived
ABC-9 was not archived in Linear: it is a sub-issue of ABC-7, and a card with a parent or sub-issues is never archived
Archived 1 other closed card of ABC in Linear' ] || fail "did not say what happened to each card: $(cat "$TMP/err")"
}

# A merged card the move left open is not archived, and the other closed
# cards still are.
handoff_archives_no_merged_card_left_open() {
  archive_demo
  linear_for_moves "$(move_answer ABC-122 'In Review')" "$NO_WRITE" "$(archive_card_answer ABC-122 'In Review')" \
    "$(closed_page "[$(closed_card ABC-1 Done)]")" "$ARCHIVED"
  linear_status_at 2 400
  merge_recorded
  [ "$(archived_ids)" = id-ABC-1 ] || fail "did not archive the closed card alone: $(archives_sent)"
  said 'ABC-122 was not archived in Linear: it is in In Review, which is not closed'
  said 'Archived 1 other closed card of ABC in Linear'
}

# With no key saved there is no Linear to ask, which is a note.
handoff_archives_nothing_with_no_key_saved() {
  archive_demo
  stub_linear
  merge_recorded
  [ "$(curl_count)" = 0 ] || fail "asked Linear with no key: $(curl_calls)"
  said 'ABC-122 was not archived in Linear: no Linear key is saved, so entourage cannot read Linear'
  said 'The other closed cards were not archived in Linear: archiving stopped at ABC-122, and the next merge tries again'
}

# A key that cannot write is refused at the first archive, and archiving
# stops there: the others would be refused the same way.
handoff_archives_nothing_when_the_key_cannot_write() {
  archive_demo
  linear_for_archive "$(archive_card_answer ABC-122 Done)" "$NO_WRITE"
  linear_status_at 4 400
  merge_recorded
  [ "$(curl_count)" = 4 ] || fail "asked Linear $(curl_count) times, not 4: $(curl_calls)"
  said 'ABC-122 was not archived in Linear: Linear answered with an error: Invalid scope: `write` required'
  said 'The other closed cards were not archived in Linear: archiving stopped at ABC-122, and the next merge tries again'
}

# Linear going out of reach part way through stops archiving at the card it
# was on, and says how many were archived.
handoff_archives_until_linear_is_out_of_reach() {
  archive_demo
  linear_for_archive "$(archive_card_answer ABC-122 Done)" "$ARCHIVED" \
    "$(closed_page "[$(closed_card ABC-1 Done),$(closed_card ABC-2 Done),$(closed_card ABC-3 Done)]")" "$ARCHIVED"
  linear_gone_from 7
  merge_recorded
  [ "$(curl_count)" = 7 ] || fail "asked Linear $(curl_count) times, not 7: $(curl_calls)"
  [ "$(archived_ids)" = 'id-ABC-122 id-ABC-1 id-ABC-2' ] || fail "did not stop at ABC-2: $(archived_ids)"
  said 'ABC-2 was not archived in Linear: could not reach Linear (curl: (6) Could not resolve host: api.linear.app)'
  said 'Archived 1 other closed card of ABC in Linear, and stopped at ABC-2: the next merge tries the rest'
}

# Linear out of reach while the closed cards are listed archives none of
# them, and says so.
handoff_archives_none_when_the_list_cannot_be_had() {
  archive_demo
  linear_for_archive "$(archive_card_answer ABC-122 Done)" "$ARCHIVED" \
    "$(closed_page "[$(closed_card ABC-1 Done)]" cursor-1)"
  linear_gone_from 6
  merge_recorded
  [ "$(archived_ids)" = id-ABC-122 ] || fail "archived a card from a list cut short: $(archives_sent)"
  said 'The other closed cards of ABC were not archived in Linear: could not reach Linear (curl: (6) Could not resolve host: api.linear.app)'
}

# A project with no Linear team has no other cards to archive.
handoff_archives_only_the_card_with_no_team() {
  demo
  archiving true
  linear_for_archive "$(archive_card_answer ABC-122 Done)" "$ARCHIVED"
  merge_recorded
  [ "$(curl_count)" = 4 ] || fail "asked Linear $(curl_count) times, not 4: $(curl_calls)"
  [ "$(archived_ids)" = id-ABC-122 ] || fail "did not archive the card: $(archives_sent)"
  said "The other closed cards were not archived in Linear: project 'demo' has no Linear team"
}

# Linear lists so many closed cards a time. Past that many pages, the cards
# listed are archived, and the rest wait for the next merge.
handoff_archives_what_linear_lists_at_most() {
  archive_demo
  local answers=() i
  for i in $(seq 1 50); do answers+=("$(closed_page "[$(closed_card ABC-1 Done)]" "cursor-$i")"); done
  linear_for_archive "$(archive_card_answer ABC-122 Done ABC-100)" "${answers[@]}" "$ARCHIVED"
  merge_recorded
  [ "$(curl_count)" = 54 ] || fail "asked Linear $(curl_count) times, not 54: $(curl_calls | tail -n 3)"
  [ "$(archived_ids)" = id-ABC-1 ] || fail "did not archive the card listed once: $(archived_ids)"
  said 'Archived 1 other closed card of ABC in Linear; Linear has more, which the next merge archives'
}

# A page with a card on it that cannot be read did not come from Linear, so
# no card on it is archived. A status's name is anyone's text: a line break
# in it is a space in the note.
handoff_archives_nothing_from_an_unreadable_answer() {
  archive_demo
  linear_for_archive \
    '{"data":{"issues":{"nodes":[{"id":"id-ABC-122","identifier":"ABC-122","state":{"name":"In\nReview","type":"started"},"parent":null,"children":{"nodes":[]}}]}}}' \
    '{"data":{"issues":{"nodes":[{"id":"id-ABC-1","identifier":"ABC-1","state":{"name":"Done","type":"completed"},"parent":null,"children":{"nodes":[]}},{"id":"id-ABC-2","identifier":"ABC-2","state":"Done","parent":null,"children":{"nodes":[]}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}' \
    "$ARCHIVED"
  merge_recorded
  [ -z "$(archives_sent)" ] || fail "archived a card from an answer that cannot be read: $(archives_sent)"
  said 'ABC-122 was not archived in Linear: it is in In Review, which is not closed'
  said "The other closed cards of ABC were not archived in Linear: Linear's answer was not one entourage can read"
}

# Settings that cannot be read archive nothing, and say why.
handoff_archives_nothing_when_the_settings_are_broken() {
  archive_demo
  printf '{"archive": "yes"}\n' > "$HOME/.config/entourage/settings.json"
  linear_for_archive
  merge_recorded
  [ "$(curl_count)" = 2 ] || fail "asked Linear $(curl_count) times, not 2: $(curl_calls)"
  said "ABC-122 was not archived in Linear: $HOME/.config/entourage/settings.json is not valid settings: its \"archive\" is \"yes\", which is not true or false"
}

# --- the card and its slices move to not-started on approval ----------------

APPROVE_BLOCK='phase: breakdown
status: done
next: start
summary: Approved as one piece.'

# Recording the approval moves the card to its team's first not-started
# status, Todo in Lab. The question asks for the card's sub-issues too. The
# block is printed as it is, on stdout, and what happened to the card goes to
# stderr.
handoff_moves_the_card_to_todo_on_approval() {
  demo
  linear_for_moves "$(move_answer ABC-122 Backlog)" "$(moved_answer Todo)"
  out=$(hand "$APPROVE_BLOCK" 2>"$TMP/err") || fail "task handoff exited non-zero: $(cat "$TMP/err")"
  [ "$out" = "$APPROVE_BLOCK" ] || fail "did not print the block back as it is: $out"
  [ "$(rows)" = 1 ] || fail "expected one row, got $(rows)"
  [ "$(curl_count)" = 2 ] || fail "asked Linear $(curl_count) times, not 2: $(curl_calls)"
  curl_calls | head -n 1 | grep -qF 'children' || fail "did not ask Linear for the card's sub-issues: $(curl_calls | head -n 1)"
  case $(changes_sent) in
    *'"id":"id-ABC-122"'*'"stateId":"s-todo"'*) ;;
    *) fail "did not move the card to Todo: $(changes_sent)" ;;
  esac
  [ "$(cat "$TMP/err")" = 'ABC-122 moved to Todo in Linear (it was Backlog)' ] ||
    fail "did not say the card moved: $(cat "$TMP/err")"
}

# In a team like PHY's, a card starts in Triage, and its first not-started
# status by place is Ready for Dev, whatever order Linear lists them in.
handoff_moves_a_triage_card_to_ready_for_dev_on_approval() {
  demo
  linear_for_moves "$(move_answer ABC-122 Triage "$PHY_STATUSES")" "$(moved_answer 'Ready for Dev' "$PHY_STATUSES")"
  out=$(hand "$APPROVE_BLOCK" 2>"$TMP/err") || fail "task handoff exited non-zero: $(cat "$TMP/err")"
  [ "$out" = "$APPROVE_BLOCK" ] || fail "did not print the block back as it is: $out"
  case $(changes_sent) in
    *'"stateId":"p-ready"'*) ;;
    *) fail "did not move the card to Ready for Dev: $(changes_sent)" ;;
  esac
  grep -qxF 'ABC-122 moved to Ready for Dev in Linear (it was Triage)' "$TMP/err" ||
    fail "did not say the card moved: $(cat "$TMP/err")"
}

# A sliced card's sub-issues move after it, each to its own team's first
# not-started status, and each change is read back.
handoff_moves_the_card_and_its_slices_on_approval() {
  demo
  linear_for_moves "$(move_answer ABC-122 Backlog '' "[$(move_card ABC-123 Backlog),$(move_card PHY-8 Backlog "$PHY_STATUSES")]")" \
    "$(moved_answer Todo)" "$(moved_answer Todo)" "$(moved_answer 'Ready for Dev' "$PHY_STATUSES")"
  out=$(hand "$APPROVE_BLOCK" 2>"$TMP/err") || fail "task handoff exited non-zero: $(cat "$TMP/err")"
  [ "$out" = "$APPROVE_BLOCK" ] || fail "did not print the block back as it is: $out"
  [ "$(curl_count)" = 4 ] || fail "asked Linear $(curl_count) times, not 4: $(curl_calls)"
  case $(changes_sent | tr '\n' ' ') in
    *'"id":"id-ABC-122"'*'"stateId":"s-todo"'*'"id":"id-ABC-123"'*'"stateId":"s-todo"'*'"id":"id-PHY-8"'*'"stateId":"p-ready"'*) ;;
    *) fail "did not move the card, then each sub-issue, to its team's first not-started status: $(changes_sent)" ;;
  esac
  [ "$(cat "$TMP/err")" = 'ABC-122 moved to Todo in Linear (it was Backlog)
ABC-123 moved to Todo in Linear (it was Backlog)
PHY-8 moved to Ready for Dev in Linear (it was Backlog)' ] || fail "did not say each card moved: $(cat "$TMP/err")"
}

# The rules of a move hold for each card on its own: one already there, one
# further along and one that is closed stay where they are, and the others
# still move.
handoff_moves_no_slice_back_on_approval() {
  demo
  linear_for_moves "$(move_answer ABC-122 Todo '' "[$(move_card ABC-123 Backlog),$(move_card ABC-124 'In Progress'),$(move_card ABC-125 Canceled)]")" \
    "$(moved_answer Todo)"
  out=$(hand "$APPROVE_BLOCK" 2>"$TMP/err") || fail "task handoff exited non-zero: $(cat "$TMP/err")"
  [ "$out" = "$APPROVE_BLOCK" ] || fail "did not print the block back as it is: $out"
  [ "$(curl_count)" = 2 ] || fail "asked Linear $(curl_count) times, not 2: $(curl_calls)"
  [ "$(changes_sent | grep -c '')" = 1 ] || fail "asked Linear for more than one change: $(changes_sent)"
  case $(changes_sent) in
    *'"id":"id-ABC-123"'*'"stateId":"s-todo"'*) ;;
    *) fail "did not move the sub-issue in Backlog to Todo: $(changes_sent)" ;;
  esac
  [ "$(cat "$TMP/err")" = 'ABC-122 is in Todo already
ABC-123 moved to Todo in Linear (it was Backlog)
ABC-124 stays in In Progress, which is past Todo: a card only moves forward
ABC-125 stays in Canceled, which is closed: a card that is done or canceled is never moved' ] ||
    fail "did not say what happened to each card: $(cat "$TMP/err")"
}

# A card that cannot be moved never costs the approval: it is recorded and
# printed, the command exits zero, and stderr says why the card was not moved.
handoff_records_the_approval_when_linear_is_out_of_reach() {
  demo
  linear_for_moves
  echo 6 > "$TMP/linear/exit"
  out=$(hand "$APPROVE_BLOCK" 2>"$TMP/err") || fail "task handoff exited non-zero: $(cat "$TMP/err")"
  [ "$out" = "$APPROVE_BLOCK" ] || fail "did not print the block back as it is: $out"
  [ "$(rows)" = 1 ] || fail "expected one row, got $(rows)"
  [ "$(cat "$TMP/err")" = 'ABC-122 was not moved in Linear: could not reach Linear (curl: (6) Could not resolve host: api.linear.app)' ] ||
    fail "did not say why the card was not moved: $(cat "$TMP/err")"
}

# When Linear refuses the changes, the note names each card that was not
# moved, and why.
handoff_records_the_approval_when_linear_refuses_the_moves() {
  demo
  linear_for_moves "$(move_answer ABC-122 Backlog '' "[$(move_card ABC-123 Backlog)]")" "$NO_WRITE" "$NO_WRITE"
  linear_status_at 2 400; linear_status_at 3 400
  out=$(hand "$APPROVE_BLOCK" 2>"$TMP/err") || fail "task handoff exited non-zero: $(cat "$TMP/err")"
  [ "$out" = "$APPROVE_BLOCK" ] || fail "did not print the block back as it is: $out"
  [ "$(rows)" = 1 ] || fail "expected one row, got $(rows)"
  [ "$(curl_count)" = 3 ] || fail "did not try each card: asked Linear $(curl_count) times, not 3: $(curl_calls)"
  [ "$(cat "$TMP/err")" = 'ABC-122 was not moved in Linear: Linear answered with an error: Invalid scope: `write` required
ABC-123 was not moved in Linear: Linear answered with an error: Invalid scope: `write` required' ] ||
    fail "did not name each card that was not moved, and why: $(cat "$TMP/err")"
}

# Only the approval moves the card: asking for it, the human's answer and a
# breakdown that fails ask Linear nothing.
handoff_moves_the_card_only_on_approval() {
  demo
  linear_for_moves "$(move_answer ABC-122 Backlog)" "$(moved_answer Todo)"
  local block
  for block in 'phase: breakdown
status: needs-human
question: Approve ABC-122 as specified, planned and broken down?
options: approve | change breakdown | change plan | change specification' 'phase: breakdown
status: answered
answer: approve' 'phase: breakdown
status: failed
reason: Could not create the sub-issues.'; do
    hand "$block" >/dev/null 2>"$TMP/err" || fail "task handoff refused the block: $block: $(cat "$TMP/err")"
    [ ! -s "$TMP/err" ] || fail "said something on stderr for: $block: $(cat "$TMP/err")"
  done
  [ "$(rows)" = 3 ] || fail "expected three rows, got $(rows)"
  [ "$(curl_count)" = 0 ] || fail "asked Linear: $(curl_calls)"
}

# The step after breakdown is called start, as the row `entourage task start`
# records is. Breakdown hands on to it, but only that command records it, and
# setup, its old name, is no step at all.
handoff_takes_start_only_as_next() {
  demo
  local steps='The steps are: define plan breakdown start build review pr merged.'
  refused 'phase: breakdown
status: done
next: setup
summary: Approved as one piece.' "'setup' is not a step that can come next. $steps"
  refused 'phase: setup
status: done
next: build
summary: Set up.' "'setup' is not a step. $steps"
  refused 'phase: start
status: done
next: build
summary: Started.' 'entourage task start'
  refused 'phase: start
status: failed
reason: Could not start.' 'entourage task start'
  hand 'phase: breakdown
status: done
next: start
summary: Approved as one piece.' >/dev/null 2>&1 || fail "task handoff refused breakdown with next: start"
  [ "$(q "select phase || '|' || status || '|' || next from handoffs")" = 'breakdown|done|start' ] ||
    fail "wrong row: $(q 'select * from handoffs')"
}

# A store as the version before answers made it: no column for them, one row.
older_store() {
  mkdir -p "$HOME/.config/entourage"
  sqlite3 "$(STORE)" "create table handoffs (
    id integer primary key, at text not null, project text not null,
    card text not null, phase text not null, status text not null,
    next text, summary text, flags text, question text, options text, reason text);
    insert into handoffs (at, project, card, phase, status, next, summary)
    values ('2026-01-01T10:00:00Z', 'demo', 'ABC-122', 'define', 'done', 'plan', 'From the older store.');"
}

# The first hand-off into an older store adds the column and keeps what was
# there. Nothing reads the store first here, so only the hand-off can add it.
an_older_store_gains_the_answer_column() {
  demo; older_store
  hand 'phase: breakdown
status: answered
answer: approve' >/dev/null || fail "could not record an answer in an older store"
  [ "$(q 'select count(*) from handoffs')" = 2 ] || fail "expected the old row and the new one: $(rows)"
  [ "$(q "select answer from handoffs where status = 'answered'")" = approve ] || fail "the answer was not kept"
  [ "$(q "select summary from handoffs where phase = 'define'")" = 'From the older store.' ] || fail "lost the older row"
}

# Reading never changes the store: an older one is read as it is, even when
# the file cannot be written.
log_reads_an_older_store_without_changing_it() {
  demo; older_store
  chmod 444 "$(STORE)"
  out=$("$E" task log demo ABC-122) || fail "task log failed on an older, read-only store: $out"
  case $out in *'From the older store.'*) ;; *) fail "did not show the older row: $out" ;; esac
  chmod 644 "$(STORE)"
  if q 'select answer from handoffs limit 0' >/dev/null; then fail "task log changed the store"; fi
}

# Two tasks can hand off into an older store at the same moment. Both try to
# add the column, one loses, and its hand-off must still be recorded.
hand_offs_at_once_into_an_older_store_are_all_recorded() {
  demo; older_store
  local i
  for i in 1 2 3 4 5 6; do
    printf 'phase: plan\nstatus: done\nnext: breakdown\nsummary: Writer %s.\n' "$i" |
      "$E" task handoff demo "ABC-$i" >/dev/null 2>&1 &
  done
  wait
  [ "$(q "select count(*) from handoffs where phase = 'plan'")" = 6 ] ||
    fail "expected six hand-offs, got $(q "select count(*) from handoffs where phase = 'plan'")"
}

# Put a row for ABC-122 straight into the store at a set time. The store has
# to exist first, so each case that uses this records one row for another card.
#   put <time> <phase> <status> [<next>] [<answer>]
put() {
  q "insert into handoffs (at, project, card, phase, status, next, answer)
     values ('$1', 'demo', 'ABC-122', '$2', '$3', nullif('${4:-}', ''), nullif('${5:-}', ''));"
}
make_store() { printf '%s\n' "$DONE_BLOCK" | "$E" task handoff demo ABC-1 >/dev/null; }
# Does the log in $out have a line matching the extended regex in $1?
log_has() { printf '%s\n' "$out" | grep -Eq -- "$1" || fail "the log has no line like '$1': $out"; }

log_shows_how_long_each_step_took() {
  demo; make_store
  put 2026-01-01T10:00:00Z new done define
  put 2026-01-01T10:00:50Z define done plan
  put 2026-01-01T10:02:34Z plan done breakdown
  put 2026-01-01T10:02:39Z breakdown needs-human
  put 2026-01-01T10:09:43Z breakdown answered '' 'change specification'
  put 2026-01-01T10:10:03Z define done plan
  put 2026-01-01T11:12:03Z plan done breakdown
  out=$("$E" task log demo ABC-122) || fail "task log exited non-zero"
  log_has 'new +done, then define$'
  log_has 'define +done, then plan +50s$'
  log_has 'plan +done, then breakdown +1m 44s$'
  log_has 'breakdown +needs-human +5s$'
  # The wait is a line of its own, and the step after it counts only its own time.
  log_has 'breakdown +answered +waited 7m 04s$'
  log_has '^    answer: change specification$'
  log_has 'define +done, then plan +20s$'
  log_has 'plan +done, then breakdown +1h 02m$'
  case $out in *'waiting on the human for'*) fail "says it is waiting, though the last row is not a question: $out" ;; esac
}

# Each review has its own time, after the build before it, and so does the
# wait on the human once the work has been sent back.
log_shows_how_long_each_review_took() {
  demo; make_store
  put 2026-01-01T10:00:00Z build done review
  put 2026-01-01T10:03:20Z review failed
  put 2026-01-01T10:10:00Z build done review
  put 2026-01-01T10:12:30Z review done build
  put 2026-01-01T10:30:30Z build done review
  put 2026-01-01T10:32:15Z review needs-human
  put 2026-01-01T10:39:15Z review answered '' 'build again'
  put 2026-01-01T10:39:25Z review done build
  put 2026-01-01T10:54:25Z build done review
  put 2026-01-01T10:56:25Z review done pr
  out=$("$E" task log demo ABC-122) || fail "task log exited non-zero"
  log_has 'review +failed +3m 20s$'
  log_has 'review +done, then build +2m 30s$'
  log_has 'review +needs-human +1m 45s$'
  log_has 'review +answered +waited 7m 00s$'
  log_has 'review +done, then build +10s$'
  log_has 'review +done, then pr +2m 00s$'
}

# The pull request is a step with a time of its own, after the review. The
# time it waits for the human to merge it is a wait, counted in no step, and
# so is the wait after a "merged" that came too soon. Once it has merged, the
# card stands at merged, in its own view, in the list and in their JSON.
log_shows_a_pull_request_through_to_its_merge() {
  demo; make_store
  put 2026-01-01T10:00:00Z start done build
  put 2026-01-01T10:20:00Z build done review
  put 2026-01-01T10:25:00Z review done pr
  put 2026-01-01T10:26:30Z pr needs-human
  put 2026-01-01T10:46:30Z pr answered '' merged
  put 2026-01-01T10:46:45Z pr needs-human
  put 2026-01-01T11:16:45Z pr answered '' merged
  put 2026-01-01T11:17:00Z pr done merged
  out=$("$E" task log demo ABC-122) || fail "task log exited non-zero"
  log_has 'review +done, then pr +5m 00s$'
  log_has 'pr +needs-human +1m 30s$'
  log_has 'pr +answered +waited 20m 00s$'
  log_has 'pr +needs-human +15s$'
  log_has 'pr +answered +waited 30m 00s$'
  log_has 'pr +done, then merged +15s$'
  out=$("$E" task log demo ABC-122 --json) || fail "task log --json exited non-zero"
  j_is .state merged; j_is .waiting null
  j_is '.steps[4].kind' wait; j_is '.steps[4].took' 'waited 20m 00s'
  j_is '.steps[7].label' 'pr done'; j_is '.steps[7].next' merged; j_is '.steps[7].took' 15s
  out=$("$E" task log demo) || fail "task log with no card exited non-zero"
  log_has '^ABC-122 +merged +for '
  out=$("$E" task log demo --json) || fail "task log --json with no card exited non-zero"
  j_is '[.cards[] | select(.card == "ABC-122") | .state] | join(" ")' merged
  j_is '[.cards[] | select(.card == "ABC-122") | .next] | join(" ")' merged
}

# Rows from before answers were recorded: the step after a question cannot be
# told from the wait before it, and the log says so.
log_marks_a_step_that_includes_waiting() {
  demo; make_store
  put 2026-01-01T10:02:39Z breakdown needs-human
  put 2026-01-01T10:10:03Z define done plan
  out=$("$E" task log demo ABC-122) || fail "task log exited non-zero"
  log_has 'define +done, then plan +7m 24s, includes waiting on the human$'
  # The view also gives the time alone, for a reader with room for little.
  out=$("$E" task log demo ABC-122 --json)
  j_is '.steps[1].took' '7m 24s, includes waiting on the human'; j_is '.steps[1].short' '7m 24s'
}

log_shows_a_question_still_waiting() {
  demo; make_store
  put 2026-01-01T10:00:00Z plan done breakdown
  q "insert into handoffs (at, project, card, phase, status, question, options)
     values (strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-125 seconds'), 'demo', 'ABC-122', 'breakdown', 'needs-human', 'Approve?', 'approve | change plan');"
  out=$("$E" task log demo ABC-122) || fail "task log exited non-zero"
  log_has '^    waiting on the human for 2m [0-5][0-9]s$'
}

# --- the view as JSON, for Herdr --------------------------------------------

# The same rows as log_shows_how_long_each_step_took.
seven_rows() {
  put 2026-01-01T10:00:00Z new done define
  put 2026-01-01T10:00:50Z define done plan
  put 2026-01-01T10:02:34Z plan done breakdown
  put 2026-01-01T10:02:39Z breakdown needs-human
  put 2026-01-01T10:09:43Z breakdown answered '' 'change specification'
  put 2026-01-01T10:10:03Z define done plan
  put 2026-01-01T11:12:03Z plan done breakdown
}
# Read one value out of the JSON in $out.
j() { printf '%s' "$out" | jq -r "$1"; }
# The value at jq path $1 must be $2.
j_is() { [ "$(j "$1")" = "$2" ] || fail "$1 is '$(j "$1")', not '$2'"; }

log_json_is_the_same_view_on_one_line() {
  demo; make_store; seven_rows
  out=$("$E" task log demo abc-122 --json) || fail "task log --json exited non-zero"
  [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] || fail "not one line: $out"
  printf '%s' "$out" | jq -e . >/dev/null || fail "not JSON: $out"
  j_is .project demo; j_is .card ABC-122; j_is '.steps | length' 7
  # Every label and time is worked out already: the reader formats nothing.
  j_is '.steps[0].label' started;                      j_is '.steps[0].took' '';  j_is '.steps[0].kind' start
  j_is '.steps[1].label' 'define done';                j_is '.steps[1].took' 50s; j_is '.steps[1].seconds' 50
  j_is '.steps[2].took' '1m 44s'
  j_is '.steps[3].label' 'breakdown asked a question'; j_is '.steps[3].took' 5s
  j_is '.steps[4].label' answered;                     j_is '.steps[4].took' 'waited 7m 04s'
  j_is '.steps[4].kind' wait;                          j_is '.steps[4].answer' 'change specification'
  j_is '.steps[0].short' '';  j_is '.steps[1].short' 50s;  j_is '.steps[4].short' '7m 04s'
  j_is '.steps[5].took' 20s;                           j_is '.steps[5].kind' step
  j_is '.steps[6].took' '1h 02m';                      j_is '.steps[6].next' breakdown
  j_is .state 'plan done, then breakdown';             j_is .waiting null
  j_is 'has("waiting")' true;                          j_is .run 1
  # And it says what the plain log says.
  text=$("$E" task log demo ABC-122)
  for i in 1 2 3 4 5 6; do
    took=$(j ".steps[$i].took")
    case $text in *"$took"*) ;; *) fail "the plain log does not show '$took': $text" ;; esac
  done
}

log_json_with_nothing_recorded() {
  demo
  out=$("$E" task log demo ABC-122 --json) || fail "task log --json exited non-zero with no store"
  none=$out
  # An empty list, not a missing one, and every key a reader looks for.
  j_is '.steps | type' array; j_is '.steps | length' 0; j_is .card ABC-122; j_is .state null
  j_is '[has("project", "card", "state", "waiting", "run", "steps")] | all' true
  make_store
  out=$("$E" task log demo ABC-122 --json) || fail "task log --json exited non-zero for a card with none"
  j_is '.steps | type' array; j_is '.steps | length' 0; j_is .project demo
  # No store and a store with nothing for this card look the same to a reader.
  [ "$(j -S .)" = "$(printf '%s' "$none" | jq -S .)" ] || fail "no store gives $none, an empty one gives $out"
}

log_json_says_when_a_question_is_still_waiting() {
  demo; make_store
  q "insert into handoffs (at, project, card, phase, status, question, options)
     values (strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-125 seconds'), 'demo', 'ABC-122', 'breakdown', 'needs-human', 'Approve?', 'approve | change plan');"
  out=$("$E" task log demo ABC-122 --json) || fail "task log --json exited non-zero"
  j_is .state 'waiting on the human'
  j .waiting | grep -Eq '^waiting on the human for 2m [0-5][0-9]s$' || fail "wrong waiting line: $(j .waiting)"
  j_is '.steps[0].question' 'Approve?'
}

log_json_keeps_awkward_text() {
  demo
  IFS= read -r text <<'EOF'
It's "done" \ back\\slash, a `tick`, $HOME, <b>, café 日本語 and a 100% {brace}
EOF
  hand "phase: define
status: done
next: plan
summary: $text" >/dev/null || fail "task handoff exited non-zero"
  out=$("$E" task log demo ABC-122 --json) || fail "task log --json exited non-zero"
  [ "$(j '.steps[0].summary')" = "$text" ] || fail "the summary changed: $(j '.steps[0].summary')"
}

# A card can be written up more than once. The row that starts a run has no
# step before it, so it shows no time, however long ago the run before ended.
a_start_row_shows_no_time() {
  demo; make_store
  put 2026-01-01T10:00:00Z new done define
  put 2026-01-01T10:00:50Z define done plan
  put 2026-01-01T10:24:02Z new done define
  put 2026-01-01T10:24:48Z define done plan
  out=$("$E" task log demo ABC-122) || fail "task log exited non-zero"
  [ "$(printf '%s\n' "$out" | grep -Ec 'new +done, then define$')" = 2 ] || fail "a start row shows a time: $out"
  log_has 'define +done, then plan +46s$'
  out=$("$E" task log demo ABC-122 --json)
  j_is '.steps[2].took' ''; j_is '.steps[2].seconds' null; j_is '.steps[3].took' 46s
  j_is '.steps[2] | has("seconds")' true
  # Each step says which run it belongs to, and the view names the latest,
  # so a reader can show that one alone.
  j_is '.steps[0].run' 1; j_is '.steps[1].run' 1; j_is '.steps[2].run' 2; j_is '.steps[3].run' 2
  j_is .run 2
}

# `task start` records a start row. It shows as started, with no time, as a
# write-up's start does, but it begins no new run: the write-up's steps stay
# in the run beside the build's, and the build is timed from it.
a_task_start_row_keeps_the_run() {
  demo; make_store
  put 2026-01-01T10:00:00Z new done define
  put 2026-01-01T10:00:50Z define done plan
  put 2026-01-01T10:02:34Z plan done breakdown
  put 2026-01-01T10:05:00Z breakdown done start
  put 2026-01-01T11:00:00Z start done build
  out=$("$E" task log demo ABC-122 --json)
  j_is '.steps[3].next' start
  j_is '.steps[4].kind' start; j_is '.steps[4].label' started; j_is '.steps[4].seconds' null
  j_is '.steps[4].run' 1; j_is .run 1; j_is .state started
  out=$("$E" task log demo) || fail "task log exited non-zero"
  log_has '^ABC-122 +started +for '
  put 2026-01-01T11:20:00Z build done review
  out=$("$E" task log demo ABC-122) || fail "task log exited non-zero"
  log_has 'start +done, then build$'
  log_has 'build +done, then review +20m 00s$'
  log_has 'define +done, then plan +50s$'
  out=$("$E" task log demo ABC-122 --json)
  j_is '.steps[5].run' 1; j_is .run 1
}

# A hand-off recorded before the step after breakdown was called start keeps
# the name it was recorded with, and the log still reads a store that holds one.
an_old_setup_row_is_kept() {
  demo; make_store
  put 2026-01-01T10:02:34Z plan done breakdown
  put 2026-01-01T10:05:00Z breakdown done setup
  out=$("$E" task log demo ABC-122) || fail "task log exited non-zero on a store with an old setup row"
  log_has 'breakdown +done, then setup +2m 26s$'
  out=$("$E" task log demo) || fail "task log with no card exited non-zero"
  log_has '^ABC-122 +breakdown done, then setup +for '
  out=$("$E" task log demo ABC-122 --json) || fail "task log --json exited non-zero"
  j_is '.steps[1].next' setup; j_is .state 'breakdown done, then setup'
  out=$("$E" task log demo --json) || fail "task log --json with no card exited non-zero"
  j_is '[.cards[] | select(.card == "ABC-122") | .next] | join(" ")' setup
  [ "$(q "select phase || '|' || status || '|' || next from handoffs where card = 'ABC-122' order by id desc limit 1")" = 'breakdown|done|setup' ] ||
    fail "the old row was changed: $(q "select * from handoffs where card = 'ABC-122'")"
}

log_json_fails_as_the_plain_log_does() {
  demo
  mkdir -p "$HOME/.config/entourage"
  echo 'not a database' > "$HOME/.config/entourage/entourage.db"
  if out=$("$E" task log demo ABC-122 --json 2>&1); then fail "read a file that is not a database: $out"; fi
  case $out in *'could not read'*) ;; *) fail "does not say it could not read the store: $out" ;; esac
  if out=$("$E" task log demo --yaml ABC-122 2>&1); then fail "took an option it does not have"; fi
  case $out in *'--json'*) ;; *) fail "does not say which options there are: $out" ;; esac
}

# --- the project's cards ----------------------------------------------------

# Put a row for any card of demo straight into the store at a set time.
#   put_for <card> <time> <phase> <status> [<next>]
put_for() {
  q "insert into handoffs (at, project, card, phase, status, next)
     values ('$2', 'demo', '$1', '$3', '$4', nullif('${5:-}', ''));"
}
# Three cards of demo, put in so that the order their first rows came in is
# not the order their latest rows came in. ABC-3 is still waiting on a
# question asked 125 seconds ago. The store is made by a hand-off for another
# project's card, which must not be listed.
three_cards() {
  "$E" project new other >/dev/null
  printf 'phase: define\nstatus: done\nnext: plan\nsummary: Another project entirely.\n' |
    "$E" task handoff other ABC-9 >/dev/null
  put_for ABC-2 2026-01-01T09:00:00Z new done define
  put_for ABC-1 2026-01-01T10:00:00Z new done define
  put_for ABC-1 2026-01-01T10:01:00Z define done plan
  put_for ABC-1 2026-01-01T10:05:00Z plan done breakdown
  put_for ABC-3 2026-01-01T10:30:00Z new done define
  put_for ABC-2 2026-01-01T11:00:00Z define failed
  q "insert into handoffs (at, project, card, phase, status, question, options)
     values (strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-125 seconds'), 'demo', 'ABC-3', 'define', 'needs-human', 'Approve?', 'approve | change');"
}

log_lists_the_projects_cards_newest_first() {
  demo; three_cards
  out=$("$E" task log demo) || fail "task log with no card exited non-zero"
  [ "$(printf '%s\n' "$out" | grep -Eo 'ABC-[0-9]+' | tr '\n' ' ')" = 'ABC-3 ABC-2 ABC-1 ' ] ||
    fail "not newest first by each card's latest row, or another project's card is shown: $out"
  # Where each stands, and for how long. A time of a day or more is in days.
  log_has '^ABC-3 +waiting on the human +for 2m [0-5][0-9]s$'
  log_has '^ABC-2 +define failed +for [0-9]+d [0-9]{2}h$'
  log_has '^ABC-1 +plan done, then breakdown +for [0-9]+d [0-9]{2}h$'
  text=$out

  out=$("$E" task log demo --json) || fail "task log --json with no card exited non-zero"
  [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] || fail "not one line: $out"
  printf '%s' "$out" | jq -e . >/dev/null || fail "not JSON: $out"
  j_is .project demo; j_is '[.cards[].card] | join(" ")' 'ABC-3 ABC-2 ABC-1'
  j_is '.cards[0].state' 'waiting on the human'; j_is '.cards[0].status' needs-human
  j .cards[0].waiting | grep -Eq '^waiting on the human for 2m [0-5][0-9]s$' || fail "wrong waiting line: $(j .cards[0].waiting)"
  j_is '.cards[1].state' 'define failed';        j_is '.cards[1].waiting' null
  j_is '.cards[1] | has("waiting")' true
  j_is '.cards[2].state' 'plan done, then breakdown'; j_is '.cards[2].next' breakdown
  j_is '.cards[2].at' 2026-01-01T10:05:00Z
  [ "$(j '.cards[2].seconds')" -gt 86400 ] 2>/dev/null || fail "ABC-1 has stood there for $(j '.cards[2].seconds') seconds"
  # How long, as the plain list words it. Each time is still running, so one
  # read is not compared with another's.
  j '.cards[0].for' | grep -Eq '^2m [0-5][0-9]s$' || fail "ABC-3 has stood there for '$(j '.cards[0].for')'"
  j '.cards[2].for' | grep -Eq '^[0-9]+d [0-9]{2}h$' || fail "ABC-1 has stood there for '$(j '.cards[2].for')'"
  # The plain list says where each card stands as the JSON does, and that
  # is what the card's own view says.
  local i card
  for i in 0 1 2; do
    card=$(j ".cards[$i].card")
    printf '%s\n' "$text" | grep -Eq "^$card +$(j ".cards[$i].state") +for " ||
      fail "the plain list does not say $card is '$(j ".cards[$i].state")': $text"
    [ "$("$E" task log demo "$card" --json | jq -r .state)" = "$(j ".cards[$i].state")" ] ||
      fail "$card's own view does not say '$(j ".cards[$i].state")'"
  done
}

log_list_with_nothing_recorded() {
  demo
  out=$("$E" task log demo) || fail "task log with no card exited non-zero with no store"
  case $out in *"No hand-offs recorded in 'demo'."*) ;; *) fail "does not say there are none: $out" ;; esac
  out=$("$E" task log demo --json) || fail "task log --json with no card exited non-zero with no store"
  none=$out
  j_is .project demo; j_is '.cards | type' array; j_is '.cards | length' 0
  # A store with only another project's cards looks the same to a reader.
  "$E" project new other >/dev/null
  printf '%s\n' "$DONE_BLOCK" | "$E" task handoff other ABC-1 >/dev/null
  out=$("$E" task log demo) || fail "task log with no card exited non-zero"
  case $out in *"No hand-offs recorded in 'demo'."*) ;; *) fail "does not say there are none: $out" ;; esac
  out=$("$E" task log demo --json)
  [ "$(j -S .)" = "$(printf '%s' "$none" | jq -S .)" ] || fail "no store gives $none, an empty one gives $out"
}

log_list_fails_when_the_store_cannot_be_read() {
  demo
  mkdir -p "$HOME/.config/entourage"
  echo 'not a database' > "$HOME/.config/entourage/entourage.db"
  for json in '' --json; do
    if out=$("$E" task log demo $json 2>&1); then fail "read a file that is not a database: $out"; fi
    case $out in *'could not read'*) ;; *) fail "does not say it could not read the store: $out" ;; esac
    case $out in *'No hand-offs'*|*'"cards":[]'*) fail "claimed there are no hand-offs: $out" ;; esac
  done
  if out=$("$E" task log demo ABC-1 ABC-2 2>&1); then fail "took two cards"; fi
  case $out in *'[<card>]'*) ;; *) fail "the usage does not say the card can be left out: $out" ;; esac
}

CASES="handoff_records_a_done_step handoff_prints_the_block_in_the_usual_order
  handoff_records_a_question handoff_records_a_failure handoff_refuses_a_missing_line
  handoff_refuses_what_it_does_not_know handoff_refuses_a_line_that_does_not_belong
  handoff_refuses_a_value_on_two_lines handoff_refuses_a_repeated_or_empty_line
  handoff_refuses_an_empty_block handoff_refuses_unknown_project_and_bad_card
  handoff_keeps_awkward_text handoff_takes_a_lowercase_card handoff_honors_entourage_home
  handoff_without_sqlite_says_so task_new_records_the_start task_new_starts_without_sqlite
  status_notes_missing_sqlite log_lists_a_cards_handoffs_in_order
  log_says_when_nothing_is_recorded log_fails_when_the_store_cannot_be_read
  handoff_says_when_it_cannot_write task_new_starts_when_the_store_cannot_be_written
  handoff_refuses_two_steps_in_one_value handoff_refuses_a_control_character
  handoff_takes_crlf_lines handoff_takes_indented_lines
  handoff_refuses_a_placeholder_left_in handoff_refuses_a_very_long_line
  handoff_refuses_a_project_in_the_wrong_case handoff_records_an_answer
  handoff_checks_an_answer handoff_records_a_finished_build
  handoff_records_a_build_that_needs_the_human handoff_records_a_failed_build
  handoff_records_a_review_that_passes handoff_records_a_review_that_sends_the_work_back
  handoff_records_a_review_that_needs_the_human handoff_records_a_failed_review
  handoff_records_a_pull_request_waiting_to_merge handoff_records_a_merge
  handoff_records_a_pull_request_that_cannot_be_opened handoff_refuses_merged_as_a_phase
  handoff_moves_the_card_to_done_on_the_merge handoff_moves_no_closed_card_on_the_merge
  handoff_moves_the_card_only_on_the_merge handoff_records_the_merge_when_linear_refuses_the_move
  handoff_records_the_merge_with_no_key_saved
  handoff_archives_nothing_with_archiving_off handoff_archives_the_merged_card
  handoff_archives_the_teams_other_closed_cards handoff_archives_no_card_with_a_parent_or_sub_issues
  handoff_archives_no_merged_card_left_open handoff_archives_nothing_with_no_key_saved
  handoff_archives_nothing_when_the_key_cannot_write handoff_archives_until_linear_is_out_of_reach
  handoff_archives_none_when_the_list_cannot_be_had handoff_archives_only_the_card_with_no_team
  handoff_archives_what_linear_lists_at_most handoff_archives_nothing_from_an_unreadable_answer
  handoff_archives_nothing_when_the_settings_are_broken
  handoff_moves_the_card_to_todo_on_approval handoff_moves_a_triage_card_to_ready_for_dev_on_approval
  handoff_moves_the_card_and_its_slices_on_approval handoff_moves_no_slice_back_on_approval
  handoff_records_the_approval_when_linear_is_out_of_reach
  handoff_records_the_approval_when_linear_refuses_the_moves handoff_moves_the_card_only_on_approval
  handoff_takes_start_only_as_next an_old_setup_row_is_kept
  an_older_store_gains_the_answer_column
  log_reads_an_older_store_without_changing_it
  hand_offs_at_once_into_an_older_store_are_all_recorded
  log_shows_how_long_each_step_took log_shows_how_long_each_review_took
  log_shows_a_pull_request_through_to_its_merge
  log_marks_a_step_that_includes_waiting
  log_shows_a_question_still_waiting
  log_json_is_the_same_view_on_one_line log_json_with_nothing_recorded
  log_json_says_when_a_question_is_still_waiting log_json_keeps_awkward_text
  a_start_row_shows_no_time a_task_start_row_keeps_the_run log_json_fails_as_the_plain_log_does
  log_lists_the_projects_cards_newest_first log_list_with_nothing_recorded
  log_list_fails_when_the_store_cannot_be_read"
