# Hand-offs: how each step of a task ended, recorded on this machine. Sourced
# by cli/entourage.

# A step of the lifecycle ends with a handoff block: which step it was, how it
# ended and what comes next. An agent runs `task handoff` with the block on
# stdin each time a step ends or pauses. The rules for a block are here, once;
# the skills only say to run the command.

# The store: one SQLite file beside the projects, so it is never published and
# an npm reinstall does not delete it.
STORE=$ENT_HOME/entourage.db
# The command that reads and writes it: one word, a command on PATH.
SQLITE=${ENTOURAGE_SQLITE:-sqlite3}

# The lines a block can have, in the order they are printed.
HANDOFF_KEYS='phase status next summary flags question options answer reason'
# The steps a block can name as its phase or as what comes next.
HANDOFF_STEPS='define plan breakdown setup'
# A block is a summary. A line longer than this is not one, and a very long
# line is slow to check and too big to hand to sqlite3 as an argument.
HANDOFF_LINE_MAX=2000

HANDOFF_USAGE="Usage: entourage task handoff <project> <card>, with the block on stdin:

entourage task handoff <project> <card> <<'EOF'
phase: define
status: done
next: plan
summary: One to three sentences on what was done.
EOF

status is done (needs next and summary, may have flags), needs-human (needs
question and options, may have summary), answered (needs answer: what the
human replied to a needs-human hand-off) or failed (needs reason). phase and
next are one of: $HANDOFF_STEPS. Every value goes on one line."

have_sqlite() { command -v "$SQLITE" >/dev/null 2>&1; }

# Run one statement against the store.
# -init /dev/null: a person's own ~/.sqliterc must not change how answers are
# printed. .timeout: wait for another task's write to finish, not fail at once.
store() { "$SQLITE" -init /dev/null -batch -cmd '.timeout 5000' "$@" 2>/dev/null; }

# Print a value as an SQL string literal, or NULL when it is empty. Doubling
# the quote is SQLite's only escape, and no value holds a newline, so nothing
# in a value can end the literal or start a sqlite3 dot-command.
# LC_ALL=C: sed must not give up on text that is not valid in this locale.
sql_str() {
  [ -n "$1" ] || { printf 'NULL'; return; }
  printf "'%s'" "$(printf '%s' "$1" | LC_ALL=C sed "s/'/''/g")"
}

# A store made before answers were recorded has no column for them. Add it.
store_upgrade() {
  store "$STORE" 'select answer from handoffs limit 0;' >/dev/null ||
    store "$STORE" 'alter table handoffs add column answer text;'
}

# Make the store if this is its first use, and bring an older one up to date.
store_ready() {
  mkdir -p "$ENT_HOME"
  store "$STORE" 'create table if not exists handoffs (
    id integer primary key, at text not null, project text not null,
    card text not null, phase text not null, status text not null,
    next text, summary text, flags text, question text, options text,
    answer text, reason text);' && store_upgrade
}

# Record one hand-off, timed now in UTC:
#   store_handoff <project> <card> <phase> <status> <next> <summary> <flags> <question> <options> <answer> <reason>
store_handoff() {
  local at values='' v
  at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  for v in "$at" "$@"; do values="$values${values:+, }$(sql_str "$v")"; done
  store "$STORE" "insert into handoffs
    (at, project, card, phase, status, next, summary, flags, question, options, answer, reason)
    values ($values);"
}

# Note that a card's write-up has begun, so the first step's length can be
# read from the store. It never fails a `task new`: it only says when it could
# not record.
record_start() {
  if ! have_sqlite; then
    say "  note      $SQLITE is not installed, so hand-offs are not recorded"
    return 0
  fi
  { store_ready && store_handoff "$1" "$2" new done define '' '' '' '' '' ''; } ||
    say "  note      could not record the start in $STORE"
}

# Is $1 one of the words in $2? A value with a space in it never is, so
# "define plan" does not pass as a step.
in_list() {
  case $1 in '' | *[[:space:]]*) return 1 ;; esac
  case " $2 " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# Is there a project folder with exactly this name? On a Mac the folder demo
# also answers to Demo, and a hand-off recorded as Demo would never show in
# demo's log.
project_named() {
  local d
  for d in "$PROJECTS"/*/; do
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
  # Not project_dir: its advice is to make the project, which is not for an
  # agent to do in the middle of a step.
  project_named "$name" ||
    die "there is no entourage project called '$name', so the hand-off was not recorded. Write the block in your message instead."
  card=$(handoff_card "$name" "$card" handoff) || exit 1
  [ "$#" -le 2 ] || die "$HANDOFF_USAGE"
  [ ! -t 0 ] || die "$HANDOFF_USAGE"

  local phase='' status='' next='' summary='' flags='' question='' options='' answer='' reason=''
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

  [ -n "$phase" ] || die "the block has no 'phase:' line, the step that is handing off."
  in_list "$phase" "$HANDOFF_STEPS" || die "'$phase' is not a step. The steps are: $HANDOFF_STEPS."
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
    [ -n "${!key}" ] || die "a $status hand-off needs a '$key:' line."
  done
  for key in next summary flags question options answer reason; do
    [ -z "${!key}" ] || in_list "$key" "$need $allow" ||
      die "a $status hand-off has no '$key:' line. Take it out."
  done
  [ -z "$next" ] || in_list "$next" "$HANDOFF_STEPS" ||
    die "'$next' is not a step that can come next. The steps are: $HANDOFF_STEPS."

  have_sqlite ||
    die "$SQLITE is not installed, so the hand-off was not recorded. Write the block in your message instead."
  { store_ready && store_handoff "$name" "$card" "$phase" "$status" "$next" "$summary" "$flags" "$question" "$options" "$answer" "$reason"; } ||
    die "the hand-off was not recorded: could not write to $STORE. Write the block in your message instead."
  for key in $HANDOFF_KEYS; do
    [ -z "${!key}" ] || printf '%s: %s\n' "$key" "${!key}"
  done
}

# Print a length of time: 50s, 1m 44s, 1h 02m.
took() {
  local s=$1
  [ "$s" -ge 0 ] 2>/dev/null || s=0
  if [ "$s" -lt 60 ]; then printf '%ss' "$s"
  elif [ "$s" -lt 3600 ]; then printf '%dm %02ds' $((s / 60)) $((s % 60))
  else printf '%dh %02dm' $((s / 3600)) $((s % 3600 / 60))
  fi
}

# List a card's hand-offs, oldest first, with how long each step took.
#
# Nothing about time is stored beyond each row's own. A step's time is from
# the row before it to its own row. The time from a needs-human row to its
# answered row is waiting on the human and belongs to no step. A needs-human
# row with nothing after it is still waiting, measured to now.
task_log() {
  local name=${1:-} card=${2:-}
  [ -n "$name" ] || die "usage: entourage task log <project> <card>"
  project_named "$name" || die "there is no entourage project called '$name'. See: entourage project ls"
  card=$(handoff_card "$name" "$card" log) || exit 1
  [ "$#" -le 2 ] || die "usage: entourage task log <project> <card>"
  have_sqlite || die "$SQLITE is not installed, so no hand-offs have been recorded on this machine."

  # The unit separator: no value can hold it, and unlike a tab it does not let
  # `read` run two empty fields together.
  local sep=$'\x1f' count=0 key found='' what time
  local at phase status next summary flags question options answer reason since before last
  if [ -e "$STORE" ]; then
    # An older store has no answer column; without it the query below fails.
    store_upgrade || true
    # A store that cannot be read is an error, not an empty history.
    # since: seconds from the row before. before: that row's status.
    # last: seconds from this row to now, on the last row only.
    found=$(store -separator "$sep" "$STORE" "select at, phase, status, coalesce(next, ''),
      coalesce(summary, ''), coalesce(flags, ''), coalesce(question, ''), coalesce(options, ''),
      coalesce(answer, ''), coalesce(reason, ''),
      coalesce(cast(strftime('%s', at) - strftime('%s', lag(at) over w) as integer), ''),
      coalesce(lag(status) over w, ''),
      case when lead(id) over w is null
        then cast(strftime('%s', 'now') - strftime('%s', at) as integer) else '' end
      from handoffs
      where project = $(sql_str "$name") and card = $(sql_str "$card")
      window w as (order by id) order by id;") ||
      die "could not read the hand-offs in $STORE. It may not be entourage's store."
  fi
  while IFS=$sep read -r at phase status next summary flags question options answer reason since before last; do
    [ -n "$at" ] || continue
    [ "$count" -gt 0 ] || say "$card in '$name'"
    count=$((count + 1))
    what=$status${next:+, then $next}
    time=''
    if [ -n "$since" ]; then
      time=$(took "$since")
      if [ "$status" = answered ] && [ "$before" = needs-human ]; then
        time="waited $time"
      elif [ "$before" = needs-human ]; then
        # No answer was recorded, so the wait cannot be told from the work.
        time="$time, includes waiting on the human"
      fi
    fi
    if [ -n "$time" ]; then printf '%s  %-10s %-22s %s\n' "$at" "$phase" "$what" "$time"
    else printf '%s  %-10s %s\n' "$at" "$phase" "$what"
    fi
    for key in summary flags question options answer reason; do
      [ -z "${!key}" ] || printf '    %s: %s\n' "$key" "${!key}"
    done
    if [ "$status" = needs-human ] && [ -n "$last" ]; then
      printf '    waiting on the human for %s\n' "$(took "$last")"
    fi
  done <<< "$found"
  [ "$count" -gt 0 ] || say "No hand-offs recorded for $card in '$name'."
}
