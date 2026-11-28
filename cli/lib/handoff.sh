# Hand-offs: how each step of a task ended, recorded on this machine. Sourced
# by cli/entourage.

# A step of the lifecycle ends with a handoff block: which step it was, how it
# ended and what comes next. An agent runs `task handoff` with the block on
# stdin each time a step ends or pauses. The rules for a block are here, once;
# the skills only say to run the command.

# The store: one SQLite file beside the spaces, so it is never published and
# an npm reinstall does not delete it.
STORE=$ENT_HOME/entourage.db
# The command that reads and writes it: one word, a command on PATH.
SQLITE=${ENTOURAGE_SQLITE:-sqlite3}

# The lines a block can have, in the order they are printed.
HANDOFF_KEYS='step status next summary flags question options answer reason'
# The steps a block can name as its step or as what comes next. start is the
# step after breakdown: `entourage task start`, which records its own row as
# start (record_start). Breakdown hands on to it once the human approves the
# card, but it is only ever what comes next in a block, since it is a command
# that records its own row, not a skill: the write-up agent runs it, or the
# human does when they hold the build phase for later. A review that finds the work done hands on to pr, the step that pushes
# the task's branch, opens its pull requests and waits for the human to merge
# them. merged is where a card ends: pr hands on to it once every pull request
# has merged. It too is only ever what comes next, since nothing runs after it.
HANDOFF_STEPS='define plan breakdown start build review pr merged'
# A block is a summary. A line longer than this is not one, and a very long
# line is slow to check and too big to hand to sqlite3 as an argument.
HANDOFF_LINE_MAX=2000

HANDOFF_USAGE="Usage: entourage task handoff <space> <card>, with the block on stdin:

entourage task handoff <space> <card> <<'EOF'
step: define
status: done
next: plan
summary: One to three sentences on what was done.
EOF

status is done (needs next and summary, may have flags), needs-human (needs
question and options, may have summary), answered (needs answer: what the
human replied to a needs-human hand-off) or failed (needs reason). step and
next are one of: $HANDOFF_STEPS.
start and merged are only ever next: \`entourage task start\` records start,
and merged is where a card ends. Every value goes on one line."

have_sqlite() { command -v "$SQLITE" >/dev/null 2>&1; }

# Run one statement against the store.
# -init /dev/null: a person's own ~/.sqliterc must not change how answers are
# printed. .timeout: wait for another task's write to finish, not fail at once.
# -readonly in a worktree's copy that was not asked to act on the machine
# (guard.sh), so that nothing it runs can change the store, by mistake or not.
store() {
  local ro=()
  [ "$GUARDED" != 1 ] || ro=(-readonly)
  "$SQLITE" -init /dev/null -batch -cmd '.timeout 5000' ${ro[@]+"${ro[@]}"} "$@" 2>/dev/null
}

# Print a value as an SQL string literal, or NULL when it is empty. Doubling
# the quote is SQLite's only escape, and no value holds a newline, so nothing
# in a value can end the literal or start a sqlite3 dot-command.
# LC_ALL=C: sed must not give up on text that is not valid in this locale.
sql_str() {
  [ -n "$1" ] || { printf 'NULL'; return; }
  printf "'%s'" "$(printf '%s' "$1" | LC_ALL=C sed "s/'/''/g")"
}

has_answer_column() { store "$STORE" 'select answer from handoffs limit 0;' >/dev/null; }
has_step_column() { store "$STORE" 'select step from handoffs limit 0;' >/dev/null; }

# Bring a store made by an older entourage up to date, keeping every row:
#   - one made before answers were recorded has no column for them: add it.
#   - one made before the rename keeps each hand-off's step in a column called
#     phase: rename it to step.
# Two hand-offs can get here at the same moment: one changes the store and
# the other's attempt fails, so look again before calling that a failure.
store_upgrade() {
  {
    has_answer_column ||
      store "$STORE" 'alter table handoffs add column answer text;' ||
      has_answer_column
  } && {
    has_step_column ||
      store "$STORE" 'alter table handoffs rename column phase to step;' ||
      has_step_column
  }
}

# Make the store if this is its first use, and bring an older one up to date.
store_ready() {
  mkdir -p "$ENT_HOME"
  store "$STORE" 'create table if not exists handoffs (
    id integer primary key, at text not null, project text not null,
    card text not null, step text not null, status text not null,
    next text, summary text, flags text, question text, options text,
    answer text, reason text);' && store_upgrade
}

# Record one hand-off, timed now in UTC:
#   store_handoff <space> <card> <step> <status> <next> <summary> <flags> <question> <options> <answer> <reason>
store_handoff() {
  local at values='' v
  at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  for v in "$at" "$@"; do values="$values${values:+, }$(sql_str "$v")"; done
  store "$STORE" "insert into handoffs
    (at, project, card, step, status, next, summary, flags, question, options, answer, reason)
    values ($values);"
}

# Note that work on a card has begun, so the first step's length can be read
# from the store. `task new` records a `new` row, which starts a run of the
# card, with define next. `task start` records a `start` row, with build next:
# it starts no run, so the write-up and the build are one run of the card.
# Neither command is ever failed by it: it only says when it could not record.
#   record_start <space> <card> [start]
record_start() {
  local step=new next=define
  [ "${3:-}" != start ] || step=start next=build
  if ! have_sqlite; then
    say "  note      $SQLITE is not installed, so hand-offs are not recorded"
    return 0
  fi
  { store_ready && store_handoff "$1" "$2" "$step" done "$next" '' '' '' '' '' ''; } ||
    say "  note      could not record the start in $STORE"
}

# Is $1 one of the words in $2? A value with a space in it never is, so
# "define plan" does not pass as a step.
in_list() {
  case $1 in '' | *[[:space:]]*) return 1 ;; esac
  case " $2 " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# Is there a space folder with exactly this name? On a Mac the folder demo
# also answers to Demo, and a hand-off recorded as Demo would never show in
# demo's log.
space_named() {
  local d
  for d in "$SPACES"/*/; do
    d=${d%/}
    [ "${d##*/}" != "$1" ] || return 0
  done
  return 1
}

# Check a card ID as the task commands take it, and print it in its usual
# upper-case form.
handoff_card() {
  local name=$1 card=$2 what=$3
  [ -n "$card" ] || die "which card? Usage: entourage task $what $name <card>, like: entourage task $what $name ABC-122"
  [[ $card =~ $CARD_RE ]] || die "'$card' is not a card ID like ABC-122."
  printf '%s' "$card" | tr '[:lower:]' '[:upper:]'
}

# Read a handoff block on stdin, refuse one that breaks the rules, record it
# and print it back with its lines in the usual order.
task_handoff() {
  local name=${1:-} card=${2:-}
  [ -n "$name" ] || die "$HANDOFF_USAGE"
  # Not space_dir: its advice is to make the space, which is not for an
  # agent to do in the middle of a step.
  space_named "$name" ||
    die "there is no entourage space called '$name', so the hand-off was not recorded. Write the block in your message instead."
  card=$(handoff_card "$name" "$card" handoff) || exit 1
  [ "$#" -le 2 ] || die "$HANDOFF_USAGE"
  [ ! -t 0 ] || die "$HANDOFF_USAGE"

  local step='' status='' next='' summary='' flags='' question='' options='' answer='' reason=''
  local line key value n=0 seen=' '
  local re='^[[:space:]]*([a-z]+):[[:space:]]*(.*)$' blank='^[[:space:]]*$' hint='^<.*>$'
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    [ "${#line}" -le "$HANDOFF_LINE_MAX" ] ||
      die "line $n of the block is ${#line} characters long. A block is a summary: keep each line under $HANDOFF_LINE_MAX characters."
    line=${line%$'\r'}
    [[ $line =~ $blank ]] && continue
    [[ $line =~ $re ]] ||
      die "line $n of the block is not 'key: value'. Every value goes on one line."
    key=${BASH_REMATCH[1]} value=${BASH_REMATCH[2]}
    # Drop spaces after the value.
    value=${value%"${value##*[![:space:]]}"}
    # The line was called phase before it was called step.
    [ "$key" != phase ] ||
      die "a block names its step in a 'step:' line, not 'phase:': write 'step:' in its place."
    in_list "$key" "$HANDOFF_KEYS" ||
      die "a handoff block has no '$key:' line. Its lines are: $HANDOFF_KEYS."
    ! in_list "$key" "$seen" || die "the block has '$key:' twice."
    seen="$seen$key "
    [ -n "$value" ] || die "'$key:' is empty. Leave the line out when there is nothing to say."
    case $value in *[[:cntrl:]]*) die "'$key:' has a tab or another control character in it. Use plain text on one line." ;; esac
    ! [[ $value =~ $hint ]] ||
      die "'$key:' still holds a placeholder in angle brackets. Write what happened, or leave the line out."
    printf -v "$key" '%s' "$value"
  done
  [ "$seen" != ' ' ] || die "there is no block on stdin. $HANDOFF_USAGE"

  [ -n "$step" ] || die "the block has no 'step:' line, the step that is handing off."
  in_list "$step" "$HANDOFF_STEPS" || die "'$step' is not a step. The steps are: $HANDOFF_STEPS."
  [ "$step" != merged ] ||
    die "'merged' is where a card ends, so it can only come next. The step that hands on to it is pr."
  [ "$step" != start ] ||
    die "'start' is recorded by \`entourage task start\`, so it can only come next. The step that hands on to it is breakdown."
  [ -n "$status" ] || die "the block has no 'status:' line. Use done, needs-human, answered or failed."
  local need allow
  case $status in
    done) need='next summary' allow='flags' ;;
    needs-human) need='question options' allow='summary' ;;
    answered) need='answer' allow='' ;;
    failed) need='reason' allow='' ;;
    *) die "'$status' is not a status. Use done, needs-human, answered or failed." ;;
  esac
  for key in $need; do
    [ -n "${!key}" ] || die "a hand-off with status $status needs a '$key:' line."
  done
  for key in next summary flags question options answer reason; do
    [ -z "${!key}" ] || in_list "$key" "$need $allow" ||
      die "a hand-off with status $status has no '$key:' line. Take it out."
  done
  [ -z "$next" ] || in_list "$next" "$HANDOFF_STEPS" ||
    die "'$next' is not a step that can come next. The steps are: $HANDOFF_STEPS."

  have_sqlite ||
    die "$SQLITE is not installed, so the hand-off was not recorded. Write the block in your message instead."
  { store_ready && store_handoff "$name" "$card" "$step" "$status" "$next" "$summary" "$flags" "$question" "$options" "$answer" "$reason"; } ||
    die "the hand-off was not recorded: could not write to $STORE. Write the block in your message instead."
  for key in $HANDOFF_KEYS; do
    [ -z "${!key}" ] || printf '%s: %s\n' "$key" "${!key}"
  done
  # The card moves in Linear at two hand-offs. The hand-off is recorded by
  # now, so a card that cannot be moved is a note, never a failure. It goes to
  # stderr, so that stdout is the block as it was recorded.
  #   - The human has approved the card, and its sub-issues exist when it was
  #     sliced: sdlc-breakdown records this only then. The card, and each of
  #     its sub-issues, moves to its team's first not-started status.
  #   - Every pull request for the card has merged, so its work is finished.
  #     Whatever records the merge, a human's answer or a watch on the pull
  #     requests, moves the card to its team's first completed status.
  if [ "$status" = done ] && [ "$step" = breakdown ] && [ "$next" = start ]; then
    linear_move_note "$card" approved >&2 || true
  elif [ "$status" = done ] && [ "$next" = merged ]; then
    linear_move_note "$card" completed >&2 || true
  fi
}

# --- the log ----------------------------------------------------------------

# One query works out a card's view: each hand-off with its label, how long it
# took, whether it is a wait, and where the card stood after it. The plain log
# and the JSON both read it, so they cannot disagree, and a Herdr mod that
# draws the JSON formats nothing. With no card it works out the view of every
# card in the space at once, and the list of cards is each one's latest row.
#
# Nothing about time is stored beyond each row's own. A step's time is from
# the row before it to its own row. The time from a needs-human row to its
# answered row is waiting on the human and belongs to no step. A needs-human
# row with nothing after it is still waiting, measured to now. A `new` row
# starts a run, so it has no time, however long ago the run before it ended.
# A `start` row, from `task start`, shows as a `new` row does but starts no
# run: the time before it was the human's, and the build is timed from it.
# A card whose row is done with merged next stands at merged: its pull
# requests have merged, and nothing comes after.
#
# What Herdr says about each card's agent (agents.sh) is read for each run of
# the log and never stored: it is joined onto the view, as the table agents,
# after the view has worked out every step and its time, so no row and no
# step's time depends on it.

# SQL for a number of seconds as text: 50s, 1m 44s, 1h 02m, 3d 04h. @ stands
# for the column that holds the seconds.
sql_took() {
  local t="case when @ < 60 then @ || 's'
    when @ < 3600 then (@ / 60) || 'm ' || printf('%02d', @ % 60) || 's'
    when @ < 86400 then (@ / 3600) || 'h ' || printf('%02d', @ % 3600 / 60) || 'm'
    else (@ / 86400) || 'd ' || printf('%02d', @ % 86400 / 3600) || 'h' end"
  printf '%s' "${t//@/$1}"
}

# SQL that starts a query on one card's view, or on every card's in the
# space, as the table `shown`. Each card's rows are worked out on their own.
# The store's column for the space is still called project. The step column
# is step, or phase in a store from before the rename; either is read as step.
#   log_view <space> <card, or empty for all> <answer column, or null in a store without one> <step column>
log_view() {
  local cards=''
  [ -z "$2" ] || cards="and card = $(sql_str "$2")"
  printf "with base as (
      select id, at, card, %s as step, status, next, summary, flags, question, options,
        %s as answer, reason,
        lag(at) over w as prev_at, lag(status) over w as before, lead(id) over w as after,
        sum(case when %s = 'new' then 1 else 0 end) over w as run
      from handoffs where project = %s %s
      window w as (partition by card order by id)),
    timed as (
      select *,
        case when step in ('new', 'start') or prev_at is null then null
          else max(cast(strftime('%%s', at) - strftime('%%s', prev_at) as integer), 0) end as seconds,
        case when after is null and status = 'needs-human'
          then max(cast(strftime('%%s', 'now') - strftime('%%s', at) as integer), 0) end as open_seconds
      from base),
    labeled as (
      select *,
        case when step in ('new', 'start') then 'start'
          when status = 'answered' and before = 'needs-human' then 'wait'
          else 'step' end as kind,
        status || case when next is null then '' else ', then ' || next end as what,
        case when step in ('new', 'start') then 'started'
          when status = 'done' then step || ' done'
          when status = 'needs-human' then step || ' asked a question'
          when status = 'answered' then 'answered'
          when status = 'failed' then step || ' failed'
          else step || ' ' || status end as label,
        case when seconds is null then '' else (%s) end as short,
        case when seconds is null then ''
          when status = 'answered' and before = 'needs-human' then 'waited ' || (%s)
          when before = 'needs-human' then (%s) || ', includes waiting on the human'
          else (%s) end as took,
        case when open_seconds is null then ''
          else 'waiting on the human for ' || (%s) end as waiting
      from timed),
    shown as (
      select *,
        case when status = 'needs-human' then 'waiting on the human'
          when step in ('new', 'start') then 'started'
          when status = 'done' and next = 'merged' then 'merged'
          else label || substr(what, length(status) + 1) end as state
      from labeled)" \
    "$4" "$3" "$4" "$(sql_str "$1")" "$cards" \
    "$(sql_took seconds)" "$(sql_took seconds)" "$(sql_took seconds)" "$(sql_took seconds)" \
    "$(sql_took open_seconds)"
}

LOG_USAGE='usage: entourage task log <space> [<card>] [--json]'

# The space's cards that have hand-offs, newest first by their latest row:
# where each stands and how long it has stood there, or what its agent is
# doing when Herdr says it is stuck or has stopped. With --json, the same as
# one line of JSON, with the agent beside where the card stands.
#   log_cards <space> <json: 1 or 0> <view>
log_cards() {
  local name=$1 json=$2 list
  # Each card's latest row is the one with nothing after it.
  list="$3, latest as (
      select *, max(cast(strftime('%s', 'now') - strftime('%s', at) as integer), 0) as since
      from shown where after is null), $AGENTS_SQL"
  if [ "$json" = 1 ]; then
    if [ ! -e "$STORE" ]; then
      printf '{"project":"%s","cards":[]}\n' "$(json_str "$name")"
      return
    fi
    store "$STORE" "$list
      select json_object('project', $(sql_str "$name"),
        'cards', (select json_group_array(json(c)) from (
          select json_object('card', card, 'at', at, 'state', state,
            'waiting', nullif(waiting, ''), 'for', $(sql_took since), 'seconds', since,
            'run', run, 'step', step, 'status', status, 'next', next,
            'agent', json(agent)) as c
          from latest left join agents using (card) order by at desc, id desc)));" ||
      die "could not read the hand-offs in $STORE. It may not be entourage's store."
    return
  fi

  local sep=$'\x1f' found='' count=0 card state for
  if [ -e "$STORE" ]; then
    found=$(store -separator "$sep" "$STORE" "$list
      select card, coalesce(json_extract(agent, '\$.label'), state),
        coalesce(json_extract(agent, '\$.for'), $(sql_took since))
      from latest left join agents using (card) order by at desc, id desc;") ||
      die "could not read the hand-offs in $STORE. It may not be entourage's store."
  fi
  while IFS=$sep read -r card state for; do
    [ -n "$card" ] || continue
    [ "$count" -gt 0 ] || say "Cards in '$name' with hand-offs, newest first"
    count=$((count + 1))
    printf '%-10s %-28s for %s\n' "$card" "$state" "$for"
  done <<< "$found"
  [ "$count" -gt 0 ] || say "No hand-offs recorded in '$name'."
}

# List a card's hand-offs, oldest first, with how long each step took. With
# no card, list the space's cards instead. With --json, the same view as
# one line of JSON.
task_log() {
  local json=0 a
  local args=()
  for a in "$@"; do
    case $a in
      --json) json=1 ;;
      -*) die "$LOG_USAGE" ;;
      *) args+=("$a") ;;
    esac
  done
  set -- ${args[@]+"${args[@]}"}
  local name=${1:-} card=${2:-}
  [ -n "$name" ] || die "$LOG_USAGE"
  space_named "$name" || die "there is no entourage space called '$name'. See: entourage space ls"
  [ "$#" -le 2 ] || die "$LOG_USAGE"
  [ -z "$card" ] || card=$(handoff_card "$name" "$card" log) || exit 1
  have_sqlite || die "$SQLITE is not installed, so no hand-offs have been recorded on this machine."

  # Reading never changes the store, so an older one is read as it is: one
  # with no answer column without one, and one from before the rename by its
  # phase column, which is read as the step.
  local answer_column=null step_column=step view='' found=''
  if [ -e "$STORE" ]; then
    ! has_answer_column || answer_column=answer
    has_step_column || step_column=phase
    view=$(log_view "$name" "$card" "$answer_column" "$step_column")
  fi
  # What each card's agent is doing, from Herdr, as the table agents.
  agents_table "$view" "$(cd -P "$SPACES/$name" && pwd)"
  if [ -z "$card" ]; then
    log_cards "$name" "$json" "$view"
    return
  fi

  if [ "$json" = 1 ]; then
    if [ ! -e "$STORE" ]; then
      printf '{"project":"%s","card":"%s","state":null,"waiting":null,"run":null,"agent":null,"steps":[]}\n' \
        "$(json_str "$name")" "$(json_str "$card")"
      return
    fi
    # SQLite builds the JSON, so no value is escaped by hand. A store that
    # cannot be read is an error, not an empty history.
    store "$STORE" "$view, $AGENTS_SQL
      select json_object('project', $(sql_str "$name"), 'card', $(sql_str "$card"),
        'state', (select state from shown order by id desc limit 1),
        'waiting', (select nullif(waiting, '') from shown order by id desc limit 1),
        'run', (select max(run) from shown),
        'agent', json((select agent from agents limit 1)),
        'steps', (select json_group_array(json(entry)) from (
          select json_object('run', run, 'at', at, 'clock', strftime('%H:%M', at, 'localtime'),
            'step', step, 'status', status, 'next', next, 'kind', kind, 'label', label,
            'took', took, 'short', short, 'seconds', seconds, 'waiting', nullif(waiting, ''),
            'summary', summary, 'flags', flags, 'question', question, 'options', options,
            'answer', answer, 'reason', reason) as entry
          from shown order by id)));" ||
      die "could not read the hand-offs in $STORE. It may not be entourage's store."
    return
  fi

  # The unit separator: no value can hold it, and unlike a tab it does not let
  # `read` run two empty fields together.
  local sep=$'\x1f' count=0 key
  local at step what took summary flags question options answer reason waiting
  if [ -e "$STORE" ]; then
    found=$(store -separator "$sep" "$STORE" "$view
      select at, step, what, took, coalesce(summary, ''), coalesce(flags, ''),
        coalesce(question, ''), coalesce(options, ''), coalesce(answer, ''),
        coalesce(reason, ''), waiting
      from shown order by id;") ||
      die "could not read the hand-offs in $STORE. It may not be entourage's store."
  fi
  while IFS=$sep read -r at step what took summary flags question options answer reason waiting; do
    [ -n "$at" ] || continue
    [ "$count" -gt 0 ] || say "$card in '$name'"
    count=$((count + 1))
    if [ -n "$took" ]; then printf '%s  %-10s %-22s %s\n' "$at" "$step" "$what" "$took"
    else printf '%s  %-10s %s\n' "$at" "$step" "$what"
    fi
    for key in summary flags question options answer reason; do
      [ -z "${!key}" ] || printf '    %s: %s\n' "$key" "${!key}"
    done
    [ -z "$waiting" ] || printf '    %s\n' "$waiting"
  done <<< "$found"
  [ "$count" -gt 0 ] || say "No hand-offs recorded for $card in '$name'."
  # Last, what the card's agent is doing, when Herdr says it is stuck or has
  # stopped. An agent is only ever worked out with jq to hand.
  if [ "$count" -gt 0 ] && [ -n "$AGENT_LAST" ]; then
    printf '    now: %s\n' "$(printf '%s' "$AGENT_LAST" | jq -r '"\(.label), for \(.for)"')"
  fi
}
