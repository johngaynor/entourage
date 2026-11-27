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

# Rows from before answers were recorded: the step after a question cannot be
# told from the wait before it, and the log says so.
log_marks_a_step_that_includes_waiting() {
  demo; make_store
  put 2026-01-01T10:02:39Z breakdown needs-human
  put 2026-01-01T10:10:03Z define done plan
  out=$("$E" task log demo ABC-122) || fail "task log exited non-zero"
  log_has 'define +done, then plan +7m 24s, includes waiting on the human$'
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
  j_is '.steps[5].took' 20s;                           j_is '.steps[5].kind' step
  j_is '.steps[6].took' '1h 02m';                      j_is '.steps[6].next' breakdown
  j_is .state 'plan done, then breakdown';             j_is .waiting null
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
  j_is '.steps | length' 0; j_is .card ABC-122; j_is .state null
  make_store
  out=$("$E" task log demo ABC-122 --json) || fail "task log --json exited non-zero for a card with none"
  j_is '.steps | length' 0; j_is .project demo
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
  # Each step says which run it belongs to, and the view names the latest,
  # so a reader can show that one alone.
  j_is '.steps[0].run' 1; j_is '.steps[1].run' 1; j_is '.steps[2].run' 2; j_is '.steps[3].run' 2
  j_is .run 2
}

log_json_fails_as_the_plain_log_does() {
  demo
  mkdir -p "$HOME/.config/entourage"
  echo 'not a database' > "$HOME/.config/entourage/entourage.db"
  if out=$("$E" task log demo ABC-122 --json 2>&1); then fail "read a file that is not a database: $out"; fi
  case $out in *'could not read'*) ;; *) fail "does not say it could not read the store: $out" ;; esac
  if out=$("$E" task log demo ABC-122 --yaml 2>&1); then fail "took an option it does not have"; fi
  case $out in *'--json'*) ;; *) fail "does not say which options there are: $out" ;; esac
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
  handoff_checks_an_answer an_older_store_gains_the_answer_column
  log_reads_an_older_store_without_changing_it
  hand_offs_at_once_into_an_older_store_are_all_recorded
  log_shows_how_long_each_step_took log_marks_a_step_that_includes_waiting
  log_shows_a_question_still_waiting
  log_json_is_the_same_view_on_one_line log_json_with_nothing_recorded
  log_json_says_when_a_question_is_still_waiting log_json_keeps_awkward_text
  a_start_row_shows_no_time log_json_fails_as_the_plain_log_does"
