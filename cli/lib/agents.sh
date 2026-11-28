# The agent on each card's current step, as Herdr sees it: waiting on a
# person in its tab, hit an error, stopped without handing off, or not
# running. `task log` reads it each time it runs and stores none of it.
# Sourced by cli/entourage.
#
# A card's agent is the one running its current phase. That is the write-up
# phase, in the tab `task new` names after the card, until the work starts,
# then the build phase, in the tab `task start` names after the task's
# folder, tasks/<card>-... The card's latest hand-off says which. A tab is found by its name, in the
# space whose folder is the project's, as `task finish` finds the task's tab.
#
# For each terminal in that tab, hc says what its program last reported: its
# status (idle, working, done, blocked or error), the kind of a blocked one
# (permission, question or auth) and when the status last changed. A program
# that reports nothing has no status, and hc clears it when the terminal's own
# shell comes back to the foreground, as when the agent exits. When a tab has
# several terminals with a status, the most urgent counts: blocked, then
# error, working, done, idle.
#
# The rules:
#   - Blocked or error always shows.
#   - While a step is under way, an agent whose turn has ended (done or idle)
#     has stopped without handing off. A step is under way when the latest
#     hand-off is an answer, or done with a step an agent runs next: not
#     start (or setup, its old name), which the human runs, nor merged.
#   - While a step is under way, a tab that is closed, or whose terminals all
#     have their own shell in the foreground and no status, has no agent
#     running: it has exited, or never started.
#   - A program other than the shell that reports no status, or a terminal hc
#     cannot answer for, says nothing: what it is doing is not known.
#   - For the first 15 seconds after `task new` or `task start` records its
#     start, the agent is still starting, so it is neither stopped nor not
#     running yet.
#   - No card gets an agent state when jq or hc is missing, Herdr is not
#     running, or `herdr-app ls` fails.

# The seconds after a start row in which the agent is still starting.
AGENT_START_GRACE=15

# What `herdr-app ls` said about the project's space, read once per run by
# agents_read: one line per tab, its name and its terminals, separated by the
# unit separator. AGENTS_ON is 1 once it has been read.
AGENTS_ON=0
AGENT_TABS=''

# Read Herdr's tabs in the project's space, when there is a Herdr to ask.
#   agents_read <the project's folder>
agents_read() {
  local dir=$1 ls tabs
  AGENTS_ON=0 AGENT_TABS=''
  command -v jq >/dev/null 2>&1 || return 0
  have_hc || return 0
  herdr_running || return 0
  ls=$(herdr_app ls 2>/dev/null) || return 0
  [ -n "$ls" ] || return 0
  tabs=$(printf '%s' "$ls" | jq -r --arg dir "$dir" '
    .spaces[]? | select(.folder == $dir) | .tabs[]? | select(.name | type == "string")
    | [.name, ([.terminals[]?.terminal | strings] | join(" "))] | join("\u001f")' 2>/dev/null) ||
    return 0
  AGENT_TABS=$tabs
  AGENTS_ON=1
}

# Set TOOK to a number of seconds as text, as sql_took words it: 50s,
# 1m 44s, 1h 02m, 3d 04h.
took_text() {
  local s=$1
  if [ "$s" -lt 60 ]; then printf -v TOOK '%ss' "$s"
  elif [ "$s" -lt 3600 ]; then printf -v TOOK '%dm %02ds' $((s / 60)) $((s % 60))
  elif [ "$s" -lt 86400 ]; then printf -v TOOK '%dh %02dm' $((s / 3600)) $((s % 3600 / 60))
  else printf -v TOOK '%dd %02dh' $((s / 86400)) $((s % 86400 / 3600))
  fi
}

# Work out a card's agent from its latest hand-off, as AGENT_JSON: null when
# there is nothing to say, or one line of JSON, {state, kind, tab, label,
# for, seconds}. state is blocked, error, stopped or not running; kind is
# permission, question, auth or null; tab is the tab's name, or null when it
# is closed. for and seconds count from when hc says the status last
# changed, or from the hand-off when it gives no time. It runs for every card
# in the log, so it starts no program for a card with no tab open, and sets
# AGENT_JSON rather than printing it, which would take a subshell.
#   card_agent <card> <the card in lower case> <step> <status> <next>
#              <seconds since the hand-off>
AGENT_JSON=null
card_agent() {
  local card=$1 low=$2 step=$3 status=$4 next=$5 since=$6
  AGENT_JSON=null
  [ "$AGENTS_ON" = 1 ] || return 0

  local under=0
  case $status in
    answered) under=1 ;;
    done) case $next in '' | start | setup | merged) ;; *) under=1 ;; esac ;;
  esac

  # The write-up phase's tab until the work starts, then the task's, named
  # after its folder: the card in lower case, alone or before a dash.
  local writeup=0 sep=$'\x1f' name terms tabs=() termlists=()
  case $step in new | define | plan | breakdown) writeup=1 ;; esac
  while IFS=$sep read -r name terms; do
    [ -n "$name" ] || continue
    if [ "$writeup" = 1 ]; then
      [ "$name" = "$card" ] || continue
    else
      case $name in "$low" | "$low"-*) ;; *) continue ;; esac
    fi
    tabs+=("$name")
    termlists+=("$terms")
  done <<< "$AGENT_TABS"
  # With no tab open, only a step under way has anything to say.
  [ "${#tabs[@]}" -gt 0 ] || [ "$under" = 1 ] || return 0

  # The most urgent of the tabs' terminals: what it says, the kind of a
  # blocked one, when its status changed, and the tab it is in. none is a
  # terminal with its own shell in the foreground and no status: no agent.
  # unknown is one running a program that reports nothing, or that hc cannot
  # answer for.
  local seen=closed kind='' ms='' tab='' i=0 t out wrapped='' failed=0
  if [ "${#tabs[@]}" -gt 0 ]; then
    tab=${tabs[0]}
    while [ "$i" -lt "${#tabs[@]}" ]; do
      for t in ${termlists[$i]}; do
        if out=$(hc_cmd get "$t" --json 2>/dev/null) && [ -n "$out" ]; then
          wrapped="$wrapped{\"tab\":$i,\"hc\":$out}"$'\n'
        else
          failed=1
        fi
      done
      i=$((i + 1))
    done
    seen=$(printf '%s' "$wrapped" | jq -rs '
      {blocked: 0, error: 1, working: 2, done: 3, idle: 4} as $rank
      | [.[] | .tab as $tab | .hc
        | (.status | if type == "object" then .state else null end) as $s
        | if .state == "finished" then {w: "none"}
          elif .status == null then
            (if (.foreground.pid? // null) != null and .foreground.pid != .pid
             then {w: "unknown"} else {w: "none"} end)
          elif ($s | type) == "string" and ($rank | has($s))
          then {w: $s, r: $rank[$s], kind: .status.kind, ms: .status_ms, tab: $tab}
          else {w: "unknown"} end] as $t
      | ([$t[] | select(.r != null)] | sort_by(.r) | first)
        // (if any($t[]; .w == "unknown") then {w: "unknown"} else {w: "none"} end)
      | [.w, (.kind // "" | tostring), (.ms // "" | tostring), (.tab // "" | tostring)]
      | join("\u001f")' 2>/dev/null) || seen=unknown
    IFS=$sep read -r seen kind ms i <<< "$seen"
    case $i in '' | *[!0-9]*) ;; *) [ "$i" -ge "${#tabs[@]}" ] || tab=${tabs[$i]} ;; esac
    [ "$seen" != none ] || [ "$failed" = 0 ] || seen=unknown
  fi

  local state=''
  case $seen in
    blocked | error) state=$seen ;;
    done | idle) [ "$under" = 0 ] || state=stopped ;;
    none | closed) [ "$under" = 0 ] || state='not running' ;;
  esac
  # An agent that `task new` or `task start` has only just started.
  case $state in
    stopped | 'not running')
      case $step in new | start) [ "$since" -ge "$AGENT_START_GRACE" ] || state='' ;; esac
      ;;
  esac

  local label
  case $state in
    blocked)
      case $kind in
        permission) label='agent waiting on a permission prompt' ;;
        question) label='agent asking a question in its tab' ;;
        auth) label='agent waiting for a sign-in' ;;
        *) kind='' label='agent waiting on you in its tab' ;;
      esac
      ;;
    error) kind='' label='agent hit an error' ;;
    stopped) kind='' label='agent stopped without handing off' ;;
    'not running') kind='' label='agent not running' ;;
    *) return 0 ;;
  esac

  local secs=$since now
  case $ms in
    '' | *[!0-9]*) ;;
    *) now=$(date +%s); secs=$((now - ms / 1000)); [ "$secs" -ge 0 ] || secs=0 ;;
  esac
  local k=null tb=null
  [ -z "$kind" ] || k="\"$kind\""
  [ "$seen" = closed ] || tb="\"$(json_str "$tab")\""
  took_text "$secs"
  printf -v AGENT_JSON '{"state":"%s","kind":%s,"tab":%s,"label":"%s","for":"%s","seconds":%s}' \
    "$state" "$k" "$tb" "$label" "$TOOK" "$secs"
}

# Work out the agent of every card in a view of the log, as AGENTS_SQL: the
# SQL for the table agents (card, agent) that the log's query joins, with
# each card whose agent has something to say and its JSON. Herdr is read
# here, once. AGENT_LAST is the last such agent, for the log of one card.
#   agents_table <view> <the project's folder>
AGENTS_SQL='agents (card, agent) as (select null, null where 0)'
AGENT_LAST=''
agents_table() {
  local view=$1 dir=$2 rows sep=$'\x1f' card low step status next since values=''
  AGENTS_SQL='agents (card, agent) as (select null, null where 0)' AGENT_LAST=''
  [ -n "$view" ] || return 0
  agents_read "$dir"
  [ "$AGENTS_ON" = 1 ] || return 0
  rows=$(store -separator "$sep" "$STORE" "$view
    select card, lower(card), step, status, coalesce(next, ''),
      max(cast(strftime('%s', 'now') - strftime('%s', at) as integer), 0)
    from shown where after is null order by id;") || return 0
  while IFS=$sep read -r card low step status next since; do
    [ -n "$card" ] || continue
    card_agent "$card" "$low" "$step" "$status" "$next" "$since" || AGENT_JSON=null
    [ "$AGENT_JSON" != null ] || continue
    values="$values${values:+, }($(sql_str "$card"), $(sql_str "$AGENT_JSON"))"
    AGENT_LAST=$AGENT_JSON
  done <<< "$rows"
  [ -z "$values" ] || AGENTS_SQL="agents (card, agent) as (values $values)"
}
