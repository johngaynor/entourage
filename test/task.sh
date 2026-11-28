# Tests for tasks. Sourced by test/run.sh.

# --- tasks: writing a card up -----------------------------------------------

# The space "demo" on a machine that is set up: skills linked, an agent on PATH.
card_demo() {
  "$E" install >/dev/null
  "$E" space new demo >/dev/null
  stub claude
  : > "$TMP/herdr-calls.log"
}
tab_calls() { grep -c '^do tab\.new ' "$TMP/herdr-calls.log" 2>/dev/null || true; }

task_new_starts_an_agent() {
  card_demo
  "$E" task new demo ABC-122 >/dev/null || fail "task new exited non-zero"
  call=$(last_call)
  case $call in
    "do tab.new {\"name\":\"ABC-122\",\"folder\":\"$P/demo\",\"argv\":[\"claude\",\"--agent=entourage-write-up\",\"--strict-mcp-config\",\"--mcp-config=$REPO/agents/linear-mcp.json\",\"--model=opus\",\"--effort=xhigh\"],\"task\":\""*"\"}") ;;
    *) fail "wrong last call: $call" ;;
  esac
  for want in "Linear card ABC-122" sdlc-define sdlc-plan sdlc-breakdown "entourage task start demo ABC-122"; do
    case $call in *"$want"*) ;; *) fail "the first message does not mention '$want': $call" ;; esac
  done
  case $call in *"{card}"* | *"{space}"* | *"{project}"*) fail "a placeholder was left in the first message: $call" ;; esac
  sed '$d' "$TMP/herdr-calls.log" | grep -qF "do space.new {\"name\":\"demo\",\"folder\":\"$P/demo\"}" ||
    fail "did not make the space before the tab: $(cat "$TMP/herdr-calls.log")"
}

# The first message has several lines; the call must still be one line of JSON.
task_new_sends_one_line_of_json() {
  card_demo
  "$E" task new demo ABC-122 >/dev/null || fail "task new exited non-zero"
  [ "$(tab_calls)" = 1 ] || fail "expected one tab.new line, got $(tab_calls)"
  json=$(last_call); json=${json#do tab.new }
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "\n" in d["task"] and d["argv"]==["claude","--agent=entourage-write-up","--strict-mcp-config","--mcp-config="+sys.argv[1]+"/agents/linear-mcp.json","--model=opus","--effort=xhigh"]' "$REPO" ||
      fail "the call is not valid JSON with a multi-line task: $json"
  fi
}

task_new_takes_a_lowercase_card() {
  card_demo
  "$E" task new demo abc-122 >/dev/null || fail "task new exited non-zero"
  case $(last_call) in *'"name":"ABC-122"'*"Linear card ABC-122"*) ;; *) fail "did not use the card's usual form: $(last_call)" ;; esac
}

task_new_makes_no_task_folder() {
  card_demo
  "$E" task new demo ABC-122 >/dev/null || fail "task new exited non-zero"
  [ ! -e "$P/demo/tasks" ] || fail "made a tasks folder"
}

task_new_selects_an_open_space() {
  card_demo
  cat > "$TMP/herdr-ls.json" <<EOF
{
  "spaces": [
    {
      "id": "spcmine",
      "name": "demo",
      "folder": "$P/demo",
      "tabs": []
    }
  ],
  "recent": []
}
EOF
  "$E" task new demo ABC-122 >/dev/null || fail "task new exited non-zero"
  grep -qF 'do space.select {"id":"spcmine"}' "$TMP/herdr-calls.log" || fail "did not select the open space"
  grep -q 'space.new' "$TMP/herdr-calls.log" && fail "made a second space"
  case $(last_call) in "do tab.new "*) ;; *) fail "the tab was not opened last: $(last_call)" ;; esac
}

# A branch is what `task start` takes. Say so, and start nothing.
task_new_refuses_a_branch() {
  card_demo
  "$E" task new demo feat/abc-122-x >/dev/null 2>"$TMP/err" && fail "took a branch as a card"
  grep -q 'entourage task start demo' "$TMP/err" || fail "did not point to task start: $(cat "$TMP/err")"
  [ "$(tab_calls)" = 0 ] || fail "opened a tab for a refused card"
}

task_new_refuses_a_bad_card() {
  card_demo
  for c in "" 122 abc abc- -122 "abc 122" abc_122 ABC-12x 'ABC-1"2'; do
    "$E" task new demo "$c" >/dev/null 2>&1 && fail "accepted the card '$c'"
  done
  [ "$(tab_calls)" = 0 ] || fail "opened a tab for a refused card"
}

task_new_refuses_unknown_space() {
  card_demo
  "$E" task new nope ABC-122 >/dev/null 2>&1 && fail "accepted a space that does not exist"
  [ ! -e "$P/nope" ] || fail "made a space folder"
  [ "$(tab_calls)" = 0 ] || fail "opened a tab"
}

task_new_needs_the_skills_linked() {
  "$E" space new demo >/dev/null
  stub claude
  "$E" task new demo ABC-122 >/dev/null 2>"$TMP/err" && fail "started an agent with no skills linked"
  grep -q 'entourage update' "$TMP/err" || fail "did not say how to link the skills: $(cat "$TMP/err")"
  [ "$(tab_calls)" = 0 ] || fail "opened a tab"
}

task_new_needs_a_harness() {
  "$E" install >/dev/null
  "$E" space new demo >/dev/null
  : > "$TMP/herdr-calls.log"
  "$E" task new demo ABC-122 >/dev/null 2>"$TMP/err" && fail "exited zero with no harness on PATH"
  grep -q 'ENTOURAGE_HARNESS' "$TMP/err" || fail "did not name the setting: $(cat "$TMP/err")"
  [ "$(tab_calls)" = 0 ] || fail "opened a tab"
}

# Another harness starts as it always has: no profile, and none needed.
task_new_honors_the_harness_setting() {
  card_demo
  stub codex
  rm "$AG/entourage-write-up.md"
  # Nor are the profiles' settings read: a broken file does not stop it.
  echo 'not json' > "$HOME/.config/entourage/settings.json"
  ENTOURAGE_HARNESS=codex "$E" task new demo ABC-122 >/dev/null || fail "task new exited non-zero"
  case $(last_call) in *'"argv":["codex"],'*) ;; *) fail "did not start the chosen harness alone: $(last_call)" ;; esac
}

# claude starts with the write-up profile, so without it nothing is started.
task_new_needs_the_write_up_profile_linked() {
  card_demo
  rm "$AG/entourage-write-up.md"
  "$E" task new demo ABC-122 >/dev/null 2>"$TMP/err" && fail "started an agent with no write-up profile linked"
  grep -q entourage-write-up "$TMP/err" && grep -q 'entourage update' "$TMP/err" ||
    fail "did not say the write-up profile is missing: $(cat "$TMP/err")"
  [ "$(tab_calls)" = 0 ] || fail "opened a tab"
  ! grep -q '^do space\.' "$TMP/herdr-calls.log" || fail "showed the space first: $(cat "$TMP/herdr-calls.log")"
}

task_new_needs_herdr_running() {
  card_demo
  printf '#!/usr/bin/env bash\necho "$*" >> "%s"\nexit 0\n' "$TMP/herdr-calls.log" > "$TMP/bin/herdr-app"
  "$E" task new demo ABC-122 >/dev/null 2>"$TMP/err" && fail "exited zero with Herdr not running"
  grep -q 'not running' "$TMP/err" || fail "did not say Herdr is not running: $(cat "$TMP/err")"
  [ "$(tab_calls)" = 0 ] || fail "opened a tab"
}

task_new_says_when_the_tab_fails() {
  card_demo
  cat > "$TMP/bin/herdr-app" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$TMP/herdr-calls.log"
[ "\$1" = status ] && echo '  "layout": "test",'
[ "\$2" = tab.new ] && exit 1
exit 0
EOF
  "$E" task new demo ABC-122 >/dev/null 2>"$TMP/err" && fail "exited zero when the tab could not be opened"
  grep -q 'ABC-122' "$TMP/err" || fail "did not name the card: $(cat "$TMP/err")"
}

# A folder name with a quote and a space must still give valid JSON.
task_new_escapes_the_folder() {
  export ENTOURAGE_HOME="$TMP/od\"d home"
  card_demo
  "$E" task new demo ABC-122 >/dev/null || fail "task new exited non-zero"
  case $(last_call) in
    *"\"folder\":\"$TMP/od\\\"d home/projects/demo\""*) ;;
    *) fail "the folder was not escaped: $(last_call)" ;;
  esac
}

# The agent starts in the space's folder, so Claude Code has to trust it by
# then. `space new` does that; `task new` checks again.

task_new_trusts_a_space_made_before() {
  card_demo
  claude_state
  "$E" task new demo ABC-122 >/dev/null || fail "task new exited non-zero"
  is_trusted "$P/demo" || fail "the space's folder is not trusted: $(cat "$HOME/.claude.json")"
  [ "$(tab_calls)" = 1 ] || fail "no tab was opened"
  no_trust_litter
}

task_new_trusts_before_the_tab_opens() {
  card_demo
  claude_state
  # A stub Herdr that notes whether the folder is trusted when a tab is asked for.
  cat > "$TMP/bin/herdr-app" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$TMP/herdr-calls.log"
[ "\$1" = status ] && echo '  "layout": "test",'
if [ "\$2" = tab.new ]; then
  jq -e --arg d "$P/demo" '.projects[\$d].hasTrustDialogAccepted == true' "$HOME/.claude.json" >/dev/null 2>&1 &&
    : > "$TMP/trusted-at-tab"
  echo '  "terminal": "t9"'
fi
exit 0
EOF
  "$E" task new demo ABC-122 >/dev/null || fail "task new exited non-zero"
  [ "$(tab_calls)" = 1 ] || fail "no tab was opened"
  [ -e "$TMP/trusted-at-tab" ] || fail "the tab was opened before the folder was trusted"
}

task_new_leaves_trusted_claude_state_alone() {
  claude_state
  card_demo
  is_trusted "$P/demo" || fail "space new did not trust the folder"
  local before out
  before=$(ls -i "$HOME/.claude.json")
  out=$("$E" task new demo ABC-122) || fail "task new exited non-zero"
  [ "$(ls -i "$HOME/.claude.json")" = "$before" ] || fail "rewrote a state file that already trusts the folder"
  case $out in
    # The words of the two trust lines, not any note: another part of the CLI
    # may have a note of its own to print, as it does without sqlite3.
    *"Claude Code may ask to trust"* | *"Claude Code will not ask to trust"*)
      fail "spoke of trust when there was nothing to do: $out" ;;
  esac
}

# A space name that is a link leads to a folder entourage did not make,
# perhaps a repo. entourage answers only for folders it made.
task_new_does_not_trust_a_linked_space() {
  card_demo
  mv "$P/demo" "$TMP/elsewhere"
  ln -s "$TMP/elsewhere" "$P/demo"
  claude_state
  cp "$HOME/.claude.json" "$TMP/before"
  "$E" task new demo ABC-122 >/dev/null || fail "task new exited non-zero"
  [ "$(tab_calls)" = 1 ] || fail "no tab was opened"
  cmp -s "$HOME/.claude.json" "$TMP/before" ||
    fail "trusted a folder entourage did not make: $(cat "$HOME/.claude.json")"
}

task_new_starts_when_trust_cannot_be_written() {
  card_demo
  printf '{broken' > "$HOME/.claude.json"
  local out
  out=$("$E" task new demo ABC-122) || fail "task new exited non-zero"
  [ "$(tab_calls)" = 1 ] || fail "no tab was opened"
  [ "$(cat "$HOME/.claude.json")" = '{broken' ] || fail "the state file changed"
  case $out in *"could not be updated"*) ;; *) fail "did not say why the folder is not trusted: $out" ;; esac
}

# --- tasks: starting the work -----------------------------------------------

task_start_refuses_unknown_space() {
  "$E" task start nope ABC-1 >/dev/null 2>&1 && fail "accepted a space that does not exist"
  [ ! -e "$P/nope" ] || fail "made a space folder"
}

task_usage_on_unknown_subcommand() {
  "$E" task >/dev/null 2>&1 && fail "bare 'task' exited zero"
  "$E" task frob >/dev/null 2>&1 && fail "'task frob' exited zero"
}

# A real repo at $1 with one commit on main, cloned from a bare origin at $1.origin.git.
make_git_repo() {
  mkdir -p "$(dirname "$1")"
  git init -q -b main "$1.seed"
  git -C "$1.seed" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  git clone -q --bare "$1.seed" "$1.origin.git"
  git clone -q "$1.origin.git" "$1"
  rm -rf "$1.seed"
}
branch_of() { git -C "$1" rev-parse --abbrev-ref HEAD; }
head_of() { git -C "$1" rev-parse "${2:-HEAD}"; }
has_branch() { git -C "$1" show-ref --verify --quiet "refs/heads/$2"; }

# The space "demo" with a real repo for each name given, and a Linear that
# has the card ABC-1, titled X, of type feat: its task is on feat/abc-1-x.
task_demo() {
  local r
  "$E" space new demo >/dev/null
  for r in "$@"; do
    make_git_repo "$HOME/Dev/$r"
    "$E" space add demo "$HOME/Dev/$r" >/dev/null
  done
  API=$HOME/Dev/api T=$P/demo/tasks
  linear_has_card ABC-1 X feat
}

task_start_makes_a_worktree() {
  task_demo api
  linear_answers "$(card_answer ABC-122 'Insert task here' feat)"
  "$E" task start demo ABC-122 >/dev/null || fail "task start exited non-zero"
  local wt=$T/abc-122-insert-task-here/api
  [ -d "$wt" ] || fail "no worktree at tasks/<task>/<repo>"
  [ "$(branch_of "$wt")" = feat/abc-122-insert-task-here ] || fail "worktree is on $(branch_of "$wt")"
  [ "$(head_of "$wt")" = "$(head_of "$API" origin/main)" ] || fail "not cut from origin/main"
}

# --- tasks: the card a task is started from ---------------------------------

# task start must stop before it makes anything, and say what to do: its
# message holds $1. The rest are task start's arguments after the space.
start_refused() {
  local want=$1 out
  shift
  if out=$("$E" task start demo "$@" 2>&1); then fail "task start exited zero: $out"; fi
  case $out in *"$want"*) ;; *) fail "the message does not say '$want': $out" ;; esac
  [ ! -e "$P/demo/tasks" ] || fail "made a tasks folder"
  ! grep -q '^do tab\.new ' "$TMP/herdr-calls.log" 2>/dev/null || fail "asked Herdr for a tab"
}

# The branch is named from the card in Linear: the type its label gives, its
# ID, and the first four words of its title, in lowercase with hyphens. a, an
# and the are left out, and so is anything a branch name cannot hold.
task_start_names_the_branch_from_the_card() {
  task_demo api
  linear_answers "$(card_answer ABC-122 "The project's \`task start\` takes a Card, at last!" feat)"
  out=$("$E" task start demo ABC-122) || fail "task start exited non-zero: $out"
  local task=abc-122-projects-task-start-takes
  [ "$(branch_of "$T/$task/api")" = "feat/$task" ] || fail "the worktree is not on feat/$task: $(ls "$T" 2>&1)"
  [ "$(last_call)" = "do tab.new {\"name\":\"$task\",\"folder\":\"$T/$task/api\"}" ] || fail "wrong last call: $(last_call)"
  case $out in *"feat/$task"*) ;; *) fail "did not say which branch: $out" ;; esac
}

# The branch's type is the card's, whichever of them it is. After each card
# comes the move's question, about a card in progress already.
task_start_takes_the_cards_type() {
  task_demo api
  linear_answers "$(card_answer ABC-1 X feat)" "$(move_answer ABC-1 'In Progress')" \
    "$(card_answer ABC-2 X fix)" "$(move_answer ABC-2 'In Progress')" "$(card_answer ABC-3 X chore)"
  local n=0 type
  for type in feat fix chore; do
    n=$((n + 1))
    "$E" task start demo "ABC-$n" >/dev/null 2>&1 || fail "task start exited non-zero for a $type card"
    [ "$(branch_of "$T/abc-$n-x/api")" = "$type/abc-$n-x" ] || fail "the $type card's task is not on $type/abc-$n-x"
  done
}

# A title with nothing a branch name can hold leaves the card's ID alone.
task_start_with_a_title_of_no_plain_words() {
  task_demo api
  linear_answers "$(card_answer ABC-1 '✨ — a ✨' feat)"
  "$E" task start demo ABC-1 >/dev/null || fail "task start exited non-zero"
  [ "$(branch_of "$T/abc-1/api")" = feat/abc-1 ] || fail "the task is not abc-1 on feat/abc-1: $(ls "$T" 2>&1)"
}

task_start_takes_a_lowercase_card() {
  task_demo api
  "$E" task start demo abc-1 >/dev/null || fail "task start exited non-zero"
  [ "$(branch_of "$T/abc-1-x/api")" = feat/abc-1-x ] || fail "no task for the card"
}

# A branch was what task start took before. Say what it takes now.
task_start_refuses_a_branch() {
  task_demo api
  start_refused 'entourage task start demo ABC-122' feat/abc-122-short-title
  start_refused 'takes the card' fix/x
  [ "$(curl_count)" = 0 ] || fail "asked Linear about a branch"
}

task_start_refuses_a_bad_card() {
  task_demo api
  start_refused 'which card' ''
  local c
  for c in abc ABC- -1 'ABC 1' ABC-1x '1-ABC'; do
    start_refused 'not a card ID like ABC-122' "$c"
  done
  [ "$(curl_count)" = 0 ] || fail "asked Linear about something that is not a card"
}

task_start_refuses_a_card_linear_does_not_have() {
  task_demo api
  linear_answers "$NO_CARD"
  start_refused 'Linear has no card ABC-1' ABC-1
}

task_start_refuses_a_card_with_no_type() {
  task_demo api
  linear_answers "$(card_answer ABC-1 X)"
  start_refused 'entourage task new demo ABC-1' ABC-1
  start_refused 'has no type' ABC-1
}

task_start_refuses_a_type_that_is_not_a_branch_type() {
  task_demo api
  linear_answers "$(card_answer ABC-1 X docs)"
  start_refused "'docs'" ABC-1
}

task_start_needs_a_saved_key() {
  task_demo api
  unset LINEAR_API_KEY
  start_refused 'entourage linear key' ABC-1
  [ "$(curl_count)" = 0 ] || fail "asked Linear with no key"
}

task_start_stops_when_linear_is_out_of_reach() {
  task_demo api
  echo 6 > "$TMP/linear/exit"
  start_refused 'could not reach Linear' ABC-1
}

# The targets after the card work as they did after a branch.
task_start_takes_targets_after_the_card() {
  task_demo api web
  "$E" task start demo ABC-1 web >/dev/null || fail "task start exited non-zero"
  [ "$(branch_of "$T/abc-1-x/web")" = feat/abc-1-x ] || fail "no worktree for the named repo"
  [ ! -e "$T/abc-1-x/api" ] || fail "made a worktree for a repo that was not named"
}

# Everything Linear is asked comes before anything is made, so a card it
# cannot find leaves no branch behind either.
task_start_asks_linear_before_it_makes_a_branch() {
  task_demo api
  linear_answers "$NO_CARD"
  "$E" task start demo ABC-1 >/dev/null 2>&1 && fail "task start exited zero"
  [ -z "$(git -C "$API" branch --list 'feat/*')" ] || fail "made a branch: $(git -C "$API" branch --list)"
}

# --- tasks: the card moves to its team's first started status ---------------

# Make each call to Linear note, in tabs-at-call.log, how many tabs Herdr had
# been asked for by then.
tabs_at_each_call() {
  mv "$TMP/bin/curl" "$TMP/bin/curl-stub"
  cat > "$TMP/bin/curl" <<EOF
#!/usr/bin/env bash
n=\$(grep -c '^do tab\.new ' "$TMP/herdr-calls.log" 2>/dev/null) || true
echo "\${n:-0}" >> "$TMP/tabs-at-call.log"
exec "$TMP/bin/curl-stub" "\$@"
EOF
  chmod +x "$TMP/bin/curl"
}

# Once the task is made and its tab open, the card moves to the started
# status that comes first in its team's order, not the first Linear lists.
task_start_moves_the_card_to_started() {
  task_demo api
  tabs_at_each_call
  linear_answers "$(card_answer ABC-1 X feat)" "$(move_answer ABC-1 Todo)" "$(moved_answer 'In Progress')"
  out=$("$E" task start demo ABC-1) || fail "task start exited non-zero: $out"
  [ -d "$T/abc-1-x/api" ] || fail "no worktree"
  [ "$(curl_count)" = 3 ] || fail "asked Linear $(curl_count) times, not 3: $(curl_calls)"
  case $(changes_sent) in
    *'"id":"id-ABC-1"'*'"stateId":"s-progress"'*) ;;
    *) fail "did not move the card to In Progress: $(changes_sent)" ;;
  esac
  [ "$(tr '\n' ' ' < "$TMP/tabs-at-call.log")" = '0 1 1 ' ] ||
    fail "the card was not moved after its tab was opened: $(tr '\n' ' ' < "$TMP/tabs-at-call.log")"
  case $out in *"card      ABC-1 moved to In Progress in Linear (it was Todo)"*) ;; *) fail "did not say the card moved: $out" ;; esac
}

# The status is picked by its kind and its place, whatever the team calls it.
task_start_moves_the_card_in_a_team_of_other_names() {
  task_demo api
  linear_answers "$(card_answer ABC-1 X feat)" "$(move_answer ABC-1 Waiting "$OTHER_STATUSES")" \
    "$(moved_answer Doing "$OTHER_STATUSES")"
  out=$("$E" task start demo ABC-1) || fail "task start exited non-zero: $out"
  case $(changes_sent) in *'"stateId":"o-doing"'*) ;; *) fail "did not move the card to Doing: $(changes_sent)" ;; esac
  case $out in *"ABC-1 moved to Doing in Linear (it was Waiting)"*) ;; *) fail "did not say the card moved: $out" ;; esac
}

# A card further along, in review or done, is never moved back.
task_start_moves_no_card_back() {
  task_demo api
  linear_answers "$(card_answer ABC-1 X feat)" "$(move_answer ABC-1 'In Review')" \
    "$(card_answer ABC-2 Y feat)" "$(move_answer ABC-2 Done)"
  out=$("$E" task start demo ABC-1) || fail "task start exited non-zero for a card in review: $out"
  case $out in *"ABC-1 stays in In Review, which is past In Progress"*) ;; *) fail "did not say why the card in review stays: $out" ;; esac
  out=$("$E" task start demo ABC-2) || fail "task start exited non-zero for a card that is done: $out"
  case $out in *"ABC-2 stays in Done, which is closed"*) ;; *) fail "did not say why the card that is done stays: $out" ;; esac
  [ "$(curl_count)" = 4 ] || fail "asked Linear $(curl_count) times, not 4: $(curl_calls)"
  [ -z "$(changes_sent)" ] || fail "asked Linear to change a card: $(changes_sent)"
}

# The task is made before the card moves, so a move that fails is a note.
task_start_goes_on_when_the_card_cannot_be_moved() {
  task_demo api
  linear_gone_from 2
  out=$("$E" task start demo ABC-1 2>&1) || fail "task start exited non-zero when the move could not be made: $out"
  [ -d "$T/abc-1-x/api" ] || fail "no worktree"
  [ "$(last_call)" = "do tab.new {\"name\":\"abc-1-x\",\"folder\":\"$T/abc-1-x/api\"}" ] || fail "did not open the tab: $(last_call)"
  case $out in
    *"note      ABC-1 was not moved in Linear: could not reach Linear (curl: (6) Could not resolve host: api.linear.app)"$'\n'*) ;;
    *) fail "did not say the card was not moved, and why: $out" ;;
  esac
  case $out in *"run this again"*) fail "said to run task start again: $out" ;; esac
  case $out in *"Opened task 'abc-1-x'"*) ;; *) fail "did not say the task was opened: $out" ;; esac
}

CARD_MOVE_CASES="task_start_moves_the_card_to_started task_start_moves_the_card_in_a_team_of_other_names
  task_start_moves_no_card_back task_start_goes_on_when_the_card_cannot_be_moved"

CARD_START_CASES="task_start_names_the_branch_from_the_card task_start_takes_the_cards_type
  task_start_with_a_title_of_no_plain_words task_start_takes_a_lowercase_card
  task_start_refuses_a_branch task_start_refuses_a_bad_card
  task_start_refuses_a_card_linear_does_not_have task_start_refuses_a_card_with_no_type
  task_start_refuses_a_type_that_is_not_a_branch_type task_start_needs_a_saved_key
  task_start_stops_when_linear_is_out_of_reach task_start_takes_targets_after_the_card
  task_start_asks_linear_before_it_makes_a_branch"

# --- tasks: starting the work, continued ------------------------------------

task_start_starts_from_the_latest_default_branch() {
  task_demo api
  git clone -q "$API.origin.git" "$TMP/other"
  git -C "$TMP/other" -c user.name=t -c user.email=t@t commit -q --allow-empty -m newer
  git -C "$TMP/other" push -q origin main
  "$E" task start demo ABC-1 >/dev/null || fail "task start exited non-zero"
  [ "$(head_of "$T/abc-1-x/api")" = "$(head_of "$TMP/other")" ] || fail "did not start from the fetched commit"
}

task_start_works_offline() {
  task_demo api
  git -C "$API" remote set-url origin "$TMP/gone.git"
  local out
  out=$("$E" task start demo ABC-1 2>/dev/null) || fail "task start exited non-zero offline"
  case $out in *warning*) ;; *) fail "no warning about the failed fetch: $out" ;; esac
  [ -d "$T/abc-1-x/api" ] || fail "no worktree made offline"
}

task_start_without_origin_uses_local_default() {
  task_demo api
  git -C "$API" remote remove origin
  "$E" task start demo ABC-1 >/dev/null || fail "task start exited non-zero with no origin"
  [ "$(head_of "$T/abc-1-x/api")" = "$(head_of "$API" main)" ] || fail "not cut from local main"
}

task_start_refuses_no_repos() {
  task_demo
  "$E" task start demo ABC-1 >/dev/null 2>&1 && fail "accepted a space with no repos"
  [ ! -e "$T" ] || fail "made a tasks folder"
}

task_start_refuses_missing_repo() {
  task_demo api
  echo "$HOME/Dev/gone" >> "$P/demo/repos"
  "$E" task start demo ABC-1 >/dev/null 2>&1 && fail "accepted a missing repo"
  [ ! -e "$T" ] || fail "made a tasks folder"
  has_branch "$API" feat/abc-1-x && fail "made a branch in the repo that exists"
}

# The second time, the card's type has changed: the task's name is the same,
# and its branch is not.
task_start_refuses_existing_task() {
  task_demo api
  linear_answers "$(card_answer ABC-1 X feat)" "$(card_answer ABC-1 X fix)"
  "$E" task start demo ABC-1 >/dev/null || fail "first task start exited non-zero"
  "$E" task start demo ABC-1 >/dev/null 2>&1 && fail "made a second task with the same name"
  has_branch "$API" fix/abc-1-x && fail "made the second task's branch"
}

task_start_refuses_existing_branch() {
  task_demo api
  git -C "$API" branch feat/abc-1-x
  "$E" task start demo ABC-1 >/dev/null 2>&1 && fail "reused an existing branch"
  [ ! -e "$T/abc-1-x" ] || fail "made a task folder"
}

task_start_refuses_branch_on_origin() {
  task_demo api
  git -C "$API.origin.git" branch feat/abc-1-x
  "$E" task start demo ABC-1 >/dev/null 2>&1 && fail "reused a branch that is on origin"
  [ ! -e "$T/abc-1-x" ] || fail "made a task folder"
  has_branch "$API" feat/abc-1-x && fail "made a local branch"
}

task_start_leaves_the_main_checkout_alone() {
  task_demo api
  git -C "$API" checkout -q -b wip
  echo mine > "$API/untracked.txt"
  local before
  before=$(branch_of "$API"):$(git -C "$API" status --porcelain)
  "$E" task start demo ABC-1 >/dev/null || fail "task start exited non-zero"
  [ "$(branch_of "$API"):$(git -C "$API" status --porcelain)" = "$before" ] || fail "the main checkout changed"
}

task_start_after_hand_deletion() {
  task_demo api
  "$E" task start demo ABC-1 >/dev/null || fail "first task start exited non-zero"
  rm -rf "$T/abc-1-x"
  git -C "$API" branch -q -D feat/abc-1-x 2>/dev/null || { git -C "$API" worktree prune; git -C "$API" branch -q -D feat/abc-1-x; }
  "$E" task start demo ABC-1 >/dev/null 2>&1 || fail "could not remake a task deleted by hand"
  [ -d "$T/abc-1-x/api" ] || fail "no worktree after remaking"
}

task_start_several_repos() {
  task_demo api web
  "$E" task start demo ABC-1 >/dev/null || fail "task start exited non-zero"
  [ "$(branch_of "$T/abc-1-x/api")" = feat/abc-1-x ] || fail "api worktree not on feat/abc-1-x"
  [ "$(branch_of "$T/abc-1-x/web")" = feat/abc-1-x ] || fail "web worktree not on feat/abc-1-x"
  is_link_to "$T/abc-1-x/CLAUDE.md" ../../PROJECT.md || fail "CLAUDE.md not linked to the space doc"
  is_link_to "$T/abc-1-x/AGENTS.md" ../../PROJECT.md || fail "AGENTS.md not linked to the space doc"
  [ -f "$T/abc-1-x/CLAUDE.md" ] || fail "the CLAUDE.md link does not resolve"
}

task_start_one_repo_has_no_links() {
  task_demo api
  "$E" task start demo ABC-1 >/dev/null || fail "task start exited non-zero"
  [ ! -e "$T/abc-1-x/CLAUDE.md" ] && [ ! -L "$T/abc-1-x/CLAUDE.md" ] || fail "linked CLAUDE.md beside a single repo"
}

task_start_undoes_a_failed_run() {
  task_demo api web
  # A file where git keeps its worktrees makes `git worktree add` fail in web.
  : > "$HOME/Dev/web/.git/worktrees"
  "$E" task start demo ABC-1 >/dev/null 2>&1 && fail "exited zero when a worktree could not be made"
  rm -f "$HOME/Dev/web/.git/worktrees"
  [ ! -e "$T/abc-1-x" ] || fail "left the task folder behind"
  has_branch "$API" feat/abc-1-x && fail "left the branch behind in api"
  has_branch "$HOME/Dev/web" feat/abc-1-x && fail "left the branch behind in web"
  [ "$(git -C "$API" worktree list | wc -l | tr -d ' ')" = 1 ] || fail "left the worktree behind in api"
}

task_start_opens_a_tab_one_repo() {
  task_demo api
  "$E" task start demo ABC-1 >/dev/null || fail "task start exited non-zero"
  [ "$(last_call)" = "do tab.new {\"name\":\"abc-1-x\",\"folder\":\"$T/abc-1-x/api\"}" ] || fail "wrong last call: $(last_call)"
  sed '$d' "$TMP/herdr-calls.log" | grep -qF "do space.new {\"name\":\"demo\",\"folder\":\"$P/demo\"}" ||
    fail "did not make the space before the tab: $(cat "$TMP/herdr-calls.log")"
}

task_start_opens_a_tab_several_repos() {
  task_demo api web
  "$E" task start demo ABC-1 >/dev/null || fail "task start exited non-zero"
  [ "$(last_call)" = "do tab.new {\"name\":\"abc-1-x\",\"folder\":\"$T/abc-1-x\"}" ] || fail "wrong last call: $(last_call)"
}

task_start_selects_an_open_space() {
  task_demo api
  cat > "$TMP/herdr-ls.json" <<EOF
{
  "spaces": [
    {
      "id": "spcmine",
      "name": "demo",
      "folder": "$P/demo",
      "tabs": []
    }
  ],
  "recent": []
}
EOF
  "$E" task start demo ABC-1 >/dev/null || fail "task start exited non-zero"
  grep -qF 'do space.select {"id":"spcmine"}' "$TMP/herdr-calls.log" || fail "did not select the open space"
  grep -q 'space.new' "$TMP/herdr-calls.log" && fail "made a second space"
  case $(last_call) in "do tab.new "*) ;; *) fail "the tab was not opened last: $(last_call)" ;; esac
}

task_start_needs_herdr_running() {
  task_demo api
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/herdr-app"
  "$E" task start demo ABC-1 >/dev/null 2>"$TMP/err" && fail "exited zero with Herdr not running"
  grep -q 'not running' "$TMP/err" || fail "did not say Herdr is not running: $(cat "$TMP/err")"
  [ ! -e "$T" ] || fail "made a tasks folder"
  has_branch "$API" feat/abc-1-x && fail "made a branch"
}

task_start_repo_path_with_a_space() {
  "$E" space new demo >/dev/null
  make_git_repo "$HOME/Dev/my api"
  "$E" space add demo "$HOME/Dev/my api" >/dev/null
  linear_has_card ABC-1 X feat
  "$E" task start demo ABC-1 >/dev/null || fail "task start exited non-zero"
  [ "$(branch_of "$P/demo/tasks/abc-1-x/my api")" = feat/abc-1-x ] || fail "no worktree at a path with a space"
  [ "$(last_call)" = "do tab.new {\"name\":\"abc-1-x\",\"folder\":\"$P/demo/tasks/abc-1-x/my api\"}" ] || fail "wrong last call: $(last_call)"
}

# The tab could not be opened: the task is kept, and the message says where it is.
task_start_keeps_the_task_when_the_tab_fails() {
  task_demo api
  cat > "$TMP/bin/herdr-app" <<'EOF'
#!/usr/bin/env bash
[ "$1" = status ] && echo '  "layout": "test",'
[ "$2" = tab.new ] && exit 1
exit 0
EOF
  "$E" task start demo ABC-1 >/dev/null 2>"$TMP/err" && fail "exited zero when the tab could not be opened"
  [ -d "$T/abc-1-x/api" ] || fail "removed the task"
  grep -qF "$T/abc-1-x/api" "$TMP/err" || fail "did not say where the task is: $(cat "$TMP/err")"
}

# --- tasks: what must survive, and what must not be left half-made ----------

task_start_refuses_a_repo_with_no_commits() {
  task_demo api
  git init -q -b main "$HOME/Dev/web"
  "$E" space add demo "$HOME/Dev/web" >/dev/null
  "$E" task start demo ABC-1 >/dev/null 2>&1 && fail "accepted a repo with no commits"
  [ ! -e "$T" ] || fail "left a tasks folder behind"
  has_branch "$API" feat/abc-1-x && fail "left the branch behind in api"
}

# web's post-checkout hook interrupts entourage while it is making worktrees.
task_start_undoes_an_interrupted_run() {
  task_demo api web
  mkdir -p "$HOME/Dev/web/.git/hooks"
  printf '#!/bin/sh\nkill -TERM "$(ps -o ppid= -p $PPID | tr -d " ")"\n' > "$HOME/Dev/web/.git/hooks/post-checkout"
  chmod +x "$HOME/Dev/web/.git/hooks/post-checkout"
  "$E" task start demo ABC-1 >/dev/null 2>&1 && fail "exited zero after being interrupted"
  [ ! -e "$T" ] || fail "left a tasks folder behind: $(ls "$T" "$T"/* 2>/dev/null | tr '\n' ' ')"
  has_branch "$API" feat/abc-1-x && fail "left the branch behind in api"
  has_branch "$HOME/Dev/web" feat/abc-1-x && fail "left the branch behind in web"
}

# The space could not be shown: the task is kept, and the message says where it is.
task_start_keeps_the_task_when_the_space_fails() {
  task_demo api
  cat > "$TMP/bin/herdr-app" <<'STUB'
#!/usr/bin/env bash
[ "$1" = status ] && echo '  "layout": "test",'
[ "$2" = space.new ] && exit 1
exit 0
STUB
  "$E" task start demo ABC-1 >/dev/null 2>"$TMP/err" && fail "exited zero when the space could not be shown"
  [ -d "$T/abc-1-x/api" ] || fail "removed the task"
  grep -qF "$T/abc-1-x/api" "$TMP/err" || fail "did not say where the task is: $(cat "$TMP/err")"
}

task_start_branch_has_no_upstream() {
  task_demo api
  "$E" task start demo ABC-1 >/dev/null || fail "task start exited non-zero"
  git -C "$T/abc-1-x/api" rev-parse -q --verify '@{u}' >/dev/null 2>&1 && fail "the new branch tracks $(git -C "$T/abc-1-x/api" rev-parse --abbrev-ref '@{u}')"
}

task_start_refusal_keeps_the_first_task() {
  task_demo api
  linear_answers "$(card_answer ABC-1 X feat)" "$(card_answer ABC-1 X fix)"
  "$E" task start demo ABC-1 >/dev/null || fail "first task start exited non-zero"
  echo work > "$T/abc-1-x/api/work.txt"
  "$E" task start demo ABC-1 >/dev/null 2>&1 && fail "made a second task with the same name"
  [ "$(cat "$T/abc-1-x/api/work.txt" 2>/dev/null)" = work ] || fail "the first task's work is gone"
  [ "$(branch_of "$T/abc-1-x/api")" = feat/abc-1-x ] || fail "the first task's worktree is gone"
}

task_start_refusal_keeps_an_existing_branch() {
  task_demo api
  git -C "$API" branch feat/abc-1-x
  local before
  before=$(head_of "$API" feat/abc-1-x)
  "$E" task start demo ABC-1 >/dev/null 2>&1 && fail "reused an existing branch"
  has_branch "$API" feat/abc-1-x || fail "deleted the branch that was already there"
  [ "$(head_of "$API" feat/abc-1-x)" = "$before" ] || fail "moved the branch that was already there"
}

# A task folder deleted by hand leaves git thinking its worktree is still there.
task_start_over_a_folder_deleted_by_hand() {
  task_demo api
  linear_answers "$(card_answer ABC-1 X feat)" "$(card_answer ABC-1 X fix)"
  "$E" task start demo ABC-1 >/dev/null || fail "first task start exited non-zero"
  rm -rf "$T/abc-1-x"
  "$E" task start demo ABC-1 >/dev/null 2>&1 || fail "could not make a task where one was deleted by hand"
  [ "$(branch_of "$T/abc-1-x/api")" = fix/abc-1-x ] || fail "no worktree on fix/abc-1-x"
}

# A worktree whose folder is away for a while (an unmounted drive) must still work when it is back.
task_start_leaves_other_worktrees_alone() {
  task_demo api
  mkdir -p "$TMP/drive"
  git -C "$API" worktree add -q -b other "$TMP/drive/other" main
  echo staged > "$TMP/drive/other/f.txt"; git -C "$TMP/drive/other" add f.txt
  mv "$TMP/drive" "$TMP/drive.away"
  "$E" task start demo ABC-1 >/dev/null || fail "task start exited non-zero"
  mv "$TMP/drive.away" "$TMP/drive"
  [ "$(git -C "$TMP/drive/other" status --porcelain 2>/dev/null)" = "A  f.txt" ] || fail "another worktree was broken: $(git -C "$TMP/drive/other" status --porcelain 2>&1)"
}

# entourage's variables can be set in its env file. Herdr starts commands
# without a shell's exports, so the file is the only place a mod's run of
# `task new` can find them.
task_new_takes_the_harness_from_the_env_file() {
  card_demo; stub myharness
  echo 'ENTOURAGE_HARNESS=myharness' > "$(env_file)"
  "$E" task new demo ABC-122 >/dev/null || fail "task new exited non-zero"
  case $(last_call) in
    *'"argv":["myharness"]'*) ;;
    *) fail "did not start the harness the env file names: $(last_call)" ;;
  esac
}

task_new_prefers_an_exported_harness_to_the_env_file() {
  card_demo; stub myharness; stub other
  echo 'ENTOURAGE_HARNESS=myharness' > "$(env_file)"
  ENTOURAGE_HARNESS=other "$E" task new demo ABC-122 >/dev/null || fail "task new exited non-zero"
  case $(last_call) in
    *'"argv":["other"]'*) ;;
    *) fail "did not start the exported harness: $(last_call)" ;;
  esac
}

# ENTOURAGE_HARNESS took the place of ENTOURAGE_AGENT, which is not read at
# all: a machine that still sets it gets claude, with the write-up profile.
task_new_ignores_the_old_agent_setting() {
  card_demo; stub codex
  echo 'ENTOURAGE_AGENT=codex' > "$(env_file)"
  "$E" task new demo ABC-122 >/dev/null || fail "task new exited non-zero"
  case $(last_call) in
    *'"argv":["claude","--agent=entourage-write-up",'*) ;;
    *) fail "did not start claude with the write-up profile: $(last_call)" ;;
  esac
}

# --- task new checks the card with Linear -----------------------------------

# What Linear answers when it has the card. NO_CARD, for when it has none, is
# in helpers.sh.
HAS_CARD=$(card_answer ABC-122 'Export orders as CSV' feat)

# A mistyped card ID stops it before anything is opened, so no agent is left
# looking for a card that is not there.
task_new_refuses_a_card_linear_does_not_have() {
  card_demo; saved_key; stub_linear; linear_answers "$NO_CARD"
  out=$("$E" task new demo ABC-999 2>&1) && fail "exited zero for a card Linear does not have"
  case $out in *"Linear has no card ABC-999"*) ;; *) fail "did not say Linear has no such card: $out" ;; esac
  [ "$(tab_calls)" = 0 ] || fail "opened a tab: $(cat "$TMP/herdr-calls.log")"
  ! grep -q '^do space\.' "$TMP/herdr-calls.log" || fail "showed the space first: $(cat "$TMP/herdr-calls.log")"
}

# The card is looked up by its team's key and its number, as Linear keeps it.
task_new_starts_a_card_linear_has() {
  card_demo; saved_key; stub_linear; linear_answers "$HAS_CARD"
  "$E" task new demo abc-122 >/dev/null || fail "task new exited non-zero"
  [ "$(tab_calls)" = 1 ] || fail "expected one tab, got $(tab_calls)"
  [ "$(curl_count)" = 1 ] || fail "asked Linear $(curl_count) times, not once"
  case $(curl_calls) in
    *'"team":"ABC"'*'"number":122'*) ;;
    *) fail "did not ask for team ABC and number 122: $(curl_calls)" ;;
  esac
  # The stand-in answers the same whatever is asked, so the question itself is
  # checked: one card, of that team, with exactly that number.
  case $(curl_calls) in
    *'filter: {team: {key: {eq: $team}}, number: {eq: $number}}'*) ;;
    *) fail "did not filter on the team's key and the number: $(curl_calls)" ;;
  esac
}

# With no key saved, Linear is not asked, and the card starts as before: no
# note, even on a machine without curl.
task_new_asks_linear_nothing_without_a_key() {
  card_demo; stub_linear; linear_answers "$NO_CARD"
  out=$("$E" task new demo ABC-122 2>&1) || fail "task new exited non-zero: $out"
  [ "$(tab_calls)" = 1 ] || fail "expected one tab, got $(tab_calls)"
  [ "$(curl_count)" = 0 ] || fail "asked Linear with no key saved: $(curl_calls)"
  case $out in *"could not check"*) fail "printed a note with no key saved: $out" ;; esac
  hide_curl
  out=$("$E" task new demo ABC-122 2>&1) || fail "task new exited non-zero without curl: $out"
  case $out in *"could not check"*) fail "printed a note with no key saved and no curl: $out" ;; esac
}

# An answer with no list of cards in it is not Linear saying it has none. Only
# something answering in Linear's place sends one, and the card starts.
task_new_starts_anyway_when_the_answer_lists_no_cards() {
  card_demo; saved_key; stub_linear
  for answer in '{"data":{}}' '{"data":{"issues":null}}' '{"data":{"issues":{"nodes":null}}}' '{"data":{"issues":{"nodes":{}}}}'; do
    linear_answers "$answer"; : > "$TMP/herdr-calls.log"
    out=$("$E" task new demo ABC-122 2>&1) || fail "stopped on the answer $answer: $out"
    [ "$(tab_calls)" = 1 ] || fail "opened no tab on the answer $answer"
    case $out in *"could not check ABC-122"*) ;; *) fail "did not say the card was not checked on $answer: $out" ;; esac
  done
}

task_new_starts_anyway_without_curl() {
  card_demo; saved_key; hide_curl
  out=$("$E" task new demo ABC-122 2>&1) || fail "task new exited non-zero: $out"
  [ "$(tab_calls)" = 1 ] || fail "expected one tab, got $(tab_calls)"
  case $out in *"could not check ABC-122 with Linear: curl is not installed"*) ;; *) fail "did not say curl is missing: $out" ;; esac
}

task_new_starts_anyway_without_jq() {
  # The stand-in curl goes first on PATH, before jq is hidden. With a
  # settings file and no jq it stops (task_new_needs_jq_only_for_a_settings_file).
  card_demo; saved_key; stub_linear; hide_jq
  rm "$HOME/.config/entourage/settings.json"
  out=$("$E" task new demo ABC-122 2>&1) || fail "task new exited non-zero: $out"
  [ "$(tab_calls)" = 1 ] || fail "expected one tab, got $(tab_calls)"
  [ "$(curl_count)" = 0 ] || fail "asked Linear with no jq to read the answer: $(curl_calls)"
  case $out in *"could not check ABC-122 with Linear: jq is not installed"*) ;; *) fail "did not say jq is missing: $out" ;; esac
}

# Only a definite no stops it. When Linear cannot be asked, the card starts
# with a note: the network is no reason to keep an agent from starting.
task_new_starts_anyway_when_linear_is_out_of_reach() {
  card_demo; saved_key; stub_linear; echo 6 > "$TMP/linear/exit"
  out=$("$E" task new demo ABC-122 2>&1) || fail "task new exited non-zero: $out"
  [ "$(tab_calls)" = 1 ] || fail "expected one tab, got $(tab_calls)"
  case $out in *"could not check ABC-122"*) ;; *) fail "did not say the card was not checked: $out" ;; esac
  # The card has started, so advice to run it again would open a second agent.
  case $out in *"run this again"*) fail "said to run it again, though the card started: $out" ;; esac
  case $out in *..*) fail "the note has a doubled full stop: $out" ;; esac
}

task_new_starts_anyway_with_a_key_linear_rejects() {
  card_demo; saved_key; stub_linear
  linear_answers '{"errors":[{"message":"Authentication required, not authenticated","extensions":{"type":"authentication error"}}]}'
  linear_status 401
  out=$("$E" task new demo ABC-122 2>&1) || fail "task new exited non-zero: $out"
  [ "$(tab_calls)" = 1 ] || fail "expected one tab, got $(tab_calls)"
  case $out in *"could not check ABC-122"*rejected*) ;; *) fail "did not say why the card was not checked: $out" ;; esac
  case $out in *"$KEY"*) fail "printed the key: $out" ;; esac
}

# --- tasks: the profile's model and effort ----------------------------------

# The argv of the last tab task new opened, as one line of JSON.
tab_argv() { last_call | sed 's/^do tab\.new //' | jq -c '.argv' 2>&1; }

# The write-up runs on the write-up's model and effort from the settings
# file, the defaults when there is no file, and never on the build's.
task_new_starts_with_the_write_up_settings() {
  card_demo
  local mcp="--mcp-config=$REPO/agents/linear-mcp.json"
  rm "$HOME/.config/entourage/settings.json"
  "$E" task new demo ABC-122 >/dev/null || fail "task new exited non-zero with no settings file"
  [ "$(tab_argv)" = "[\"claude\",\"--agent=entourage-write-up\",\"--strict-mcp-config\",\"$mcp\",\"--model=opus\",\"--effort=xhigh\"]" ] ||
    fail "with no settings file the write-up did not start on opus at xhigh: $(tab_argv)"
  "$E" profile set write-up model sonnet >/dev/null && "$E" profile set write-up effort high >/dev/null &&
    "$E" profile set build model haiku >/dev/null && "$E" profile set build effort low >/dev/null ||
    fail "could not set the profiles"
  "$E" task new demo ABC-123 >/dev/null || fail "task new exited non-zero"
  [ "$(tab_argv)" = "[\"claude\",\"--agent=entourage-write-up\",\"--strict-mcp-config\",\"$mcp\",\"--model=sonnet\",\"--effort=high\"]" ] ||
    fail "the write-up did not start on sonnet at high: $(tab_argv)"
}

# A file that is not valid settings stops it before anything is opened, and
# says which file and what is wrong.
task_new_stops_on_a_broken_settings_file() {
  card_demo
  local f=$HOME/.config/entourage/settings.json body want
  while IFS='|' read -r body want; do
    printf '%s\n' "$body" > "$f"
    : > "$TMP/herdr-calls.log"
    "$E" task new demo ABC-122 >/dev/null 2>"$TMP/err" && fail "task new exited zero with the file '$body'"
    grep -qF "$f is not valid settings: $want" "$TMP/err" || fail "the file '$body' did not give '$want': $(cat "$TMP/err")"
    [ "$(tab_calls)" = 0 ] || fail "opened a tab with the file '$body'"
    ! grep -q '^do space\.' "$TMP/herdr-calls.log" || fail "showed the space first: $(cat "$TMP/herdr-calls.log")"
  done <<'EOF'
not json|it is not JSON
{"profiles":{"write-up":{"effort":"extreme"}}}|the effort of write-up is "extreme"
EOF
}

# Without jq the file cannot be read, so it stops; with no file there is
# nothing to read, and it starts on the defaults.
task_new_needs_jq_only_for_a_settings_file() {
  card_demo
  hide_jq
  "$E" task new demo ABC-122 >/dev/null 2>"$TMP/err" && fail "task new exited zero with a settings file and no jq"
  grep -q 'jq is not installed' "$TMP/err" || fail "did not say jq is missing: $(cat "$TMP/err")"
  [ "$(tab_calls)" = 0 ] || fail "opened a tab"
  rm "$HOME/.config/entourage/settings.json"
  "$E" task new demo ABC-122 >/dev/null 2>"$TMP/err" || fail "task new exited non-zero with no settings file and no jq: $(cat "$TMP/err")"
  case $(last_call) in *'"--model=opus","--effort=xhigh"]'*) ;; *) fail "did not start on the defaults: $(last_call)" ;; esac
}

PROFILE_CASES="task_new_starts_with_the_write_up_settings task_new_stops_on_a_broken_settings_file
  task_new_needs_jq_only_for_a_settings_file task_build_starts_with_the_build_settings
  task_build_stops_on_a_broken_settings_file"

CARD_CASES="task_new_refuses_a_card_linear_does_not_have task_new_starts_a_card_linear_has
  task_new_asks_linear_nothing_without_a_key task_new_starts_anyway_when_linear_is_out_of_reach
  task_new_starts_anyway_with_a_key_linear_rejects task_new_starts_anyway_when_the_answer_lists_no_cards
  task_new_starts_anyway_without_curl task_new_starts_anyway_without_jq
  task_new_takes_the_harness_from_the_env_file task_new_prefers_an_exported_harness_to_the_env_file
  task_new_ignores_the_old_agent_setting
  task_new_starts_an_agent task_new_sends_one_line_of_json task_new_takes_a_lowercase_card
  task_new_makes_no_task_folder task_new_selects_an_open_space task_new_refuses_a_branch
  task_new_refuses_a_bad_card task_new_refuses_unknown_space task_new_needs_the_skills_linked
  task_new_needs_a_harness task_new_honors_the_harness_setting task_new_needs_the_write_up_profile_linked
  task_new_needs_herdr_running
  task_new_says_when_the_tab_fails task_new_escapes_the_folder
  task_new_trusts_a_space_made_before task_new_trusts_before_the_tab_opens
  task_new_leaves_trusted_claude_state_alone task_new_starts_when_trust_cannot_be_written
  task_new_does_not_trust_a_linked_space"

# --- tasks: setup -----------------------------------------------------------

# Give a repo made by task_demo a justfile on its default branch, here and on
# its origin. $2 is the justfile's text; the default has a setup recipe.
give_setup() {
  local repo=$HOME/Dev/$1
  printf '%b' "${2:-setup:\n\techo\n}" > "$repo/justfile"
  git -C "$repo" add justfile
  git -C "$repo" -c user.name=t -c user.email=t@t commit -q -m justfile
  git -C "$repo" push -q origin main
}

# Setup is off unless ENTOURAGE_SETUP is 1. The cases about what it does turn
# it on.
setup_on() { export ENTOURAGE_SETUP=1; }

task_start_leaves_setup_off() {
  stub_just; stub_hc; task_demo api; give_setup api
  linear_answers "$(card_answer ABC-1 X feat)" "$(card_answer ABC-2 Y feat)"
  out=$("$E" task start demo ABC-1) || fail "task start exited non-zero"
  [ -d "$T/abc-1-x/api" ] || fail "no worktree"
  [ "$(last_call)" = "do tab.new {\"name\":\"abc-1-x\",\"folder\":\"$T/abc-1-x/api\"}" ] || fail "did not open the tab: $(last_call)"
  [ "$(hc_calls)" = "send t9 entourage task build demo ABC-1" ] || fail "typed setup into the tab: $(hc_calls)"
  case $out in *"setup     not run"*"ENTOURAGE_SETUP=1"*) ;; *) fail "did not say setup is off: $out" ;; esac
  case $out in *"running in the tab"*) fail "said setup is running: $out" ;; esac
  # Only 1 turns it on.
  ENTOURAGE_SETUP=0 "$E" task start demo ABC-2 >/dev/null || fail "task start exited non-zero with ENTOURAGE_SETUP=0"
  [ "$(hc_calls | tail -n 1)" = "send t9 entourage task build demo ABC-2" ] || fail "ENTOURAGE_SETUP=0 typed setup into the tab: $(hc_calls)"
}

task_start_turns_setup_on_from_the_env_file() {
  stub_just; stub_hc; task_demo api; give_setup api
  mkdir -p "$(dirname "$(env_file)")"
  echo 'ENTOURAGE_SETUP=1' > "$(env_file)"; chmod 600 "$(env_file)"
  "$E" task start demo ABC-1 >/dev/null || fail "task start exited non-zero"
  [ "$(hc_calls)" = "send t9 just setup && entourage task build demo ABC-1" ] || fail "the env file did not turn setup on: $(hc_calls)"
}

task_start_runs_setup_one_repo() {
  setup_on
  stub_just; stub_hc; task_demo api; give_setup api
  out=$("$E" task start demo ABC-1) || fail "task start exited non-zero"
  [ "$(hc_calls)" = "send t9 just setup && entourage task build demo ABC-1" ] || fail "wrong hc calls: $(hc_calls)"
  case $out in *"setup     api (running in the tab)"*) ;; *) fail "did not report setup: $out" ;; esac
}

task_start_sends_setup_to_the_new_tab() {
  setup_on
  stub_just; stub_hc; task_demo api; give_setup api
  cat > "$TMP/bin/herdr-app" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$TMP/herdr-calls.log"
[ "\$1" = status ] && echo '  "layout": "test",'
[ "\$2" = tab.new ] && printf '{\n  "space": "sp1",\n  "tab": "tb1",\n  "terminal": "t42"\n}\n'
exit 0
EOF
  "$E" task start demo ABC-1 >/dev/null || fail "task start exited non-zero"
  [ "$(hc_calls)" = "send t42 just setup && entourage task build demo ABC-1" ] || fail "did not use the terminal tab.new named: $(hc_calls)"
}

task_start_runs_setup_several_repos() {
  setup_on
  stub_just; stub_hc; task_demo api web docs; give_setup api; give_setup docs
  out=$("$E" task start demo ABC-1) || fail "task start exited non-zero"
  [ "$(hc_calls)" = "send t9 (cd ./'api' && just setup) && (cd ./'docs' && just setup) && entourage task build demo ABC-1" ] || fail "wrong hc calls: $(hc_calls)"
  case $out in *"setup     web skipped: no justfile"*) ;; *) fail "did not report the skipped repo: $out" ;; esac
  case $out in *"setup     docs (running in the tab)"*) ;; *) fail "did not report docs: $out" ;; esac
}

# entourage's own repo provides what it asks of others: with its justfile, a
# task on it types `just setup` into the tab and skips nothing. Without the
# file, give_setup would fall back to its own recipe, so the case checks first.
task_start_runs_entourages_own_setup() {
  setup_on
  [ -f "$ROOT/justfile" ] || { fail "entourage has no justfile at its root"; return; }
  stub_just; stub_hc; task_demo entourage; give_setup entourage "$(cat "$ROOT/justfile")"
  out=$("$E" task start demo ABC-1) || fail "task start exited non-zero"
  [ "$(hc_calls)" = "send t9 just setup && entourage task build demo ABC-1" ] || fail "did not type just setup into the tab: $(hc_calls)"
  case $out in *"setup     entourage (running in the tab)"*) ;; *) fail "did not report setup: $out" ;; esac
  case $out in *skipped*) fail "said setup was skipped: $out" ;; esac
}

task_start_skips_setup_without_a_recipe() {
  setup_on
  stub_just; stub_hc; task_demo api; give_setup api 'setup-db:\n\techo\npresetup:\n\techo\n'
  out=$("$E" task start demo ABC-1) || fail "task start exited non-zero"
  [ "$(hc_calls)" = "send t9 entourage task build demo ABC-1" ] || fail "typed into the tab: $(hc_calls)"
  case $out in *"setup     api skipped: its justfile has no setup recipe"*) ;; *) fail "did not say why: $out" ;; esac
}

task_start_skips_an_unreadable_justfile() {
  setup_on
  stub_just; stub_hc; task_demo api; give_setup api 'BROKEN\nsetup:\n\techo\n'
  out=$("$E" task start demo ABC-1) || fail "task start exited non-zero"
  [ "$(hc_calls)" = "send t9 entourage task build demo ABC-1" ] || fail "typed into the tab: $(hc_calls)"
  case $out in *"setup     api skipped: its justfile could not be read by just"*) ;; *) fail "did not say why: $out" ;; esac
}

task_start_ignores_a_parent_justfile() {
  setup_on
  export ENTOURAGE_HOME=$TMP/outer
  mkdir -p "$ENTOURAGE_HOME"
  printf 'setup:\n\techo\n' > "$ENTOURAGE_HOME/justfile"
  stub_just; stub_hc; task_demo api
  out=$("$E" task start demo ABC-1) || fail "task start exited non-zero"
  [ -d "$ENTOURAGE_HOME/projects/demo/tasks/abc-1-x/api" ] || fail "no worktree"
  [ "$(hc_calls)" = "send t9 entourage task build demo ABC-1" ] || fail "ran a justfile from above the task: $(hc_calls)"
  case $out in *"setup     api skipped: no justfile"*) ;; *) fail "did not report the skip: $out" ;; esac
}

task_start_quotes_repo_names() {
  setup_on
  stub_just; stub_hc; task_demo "my api" "it's"; give_setup "my api"; give_setup "it's"
  "$E" task start demo ABC-1 >/dev/null || fail "task start exited non-zero"
  [ "$(hc_calls)" = "send t9 (cd ./'my api' && just setup) && (cd ./'it'\\''s' && just setup) && entourage task build demo ABC-1" ] || fail "wrong hc calls: $(hc_calls)"
}

task_start_without_just() {
  setup_on
  stub_hc; task_demo api; give_setup api
  out=$("$E" task start demo ABC-1) || fail "task start exited non-zero without just"
  [ -d "$T/abc-1-x/api" ] || fail "no worktree"
  [ "$(hc_calls)" = "send t9 entourage task build demo ABC-1" ] || fail "typed into the tab: $(hc_calls)"
  case $out in *"just is not installed"*"https://just.systems"*) ;; *) fail "did not say just is missing: $out" ;; esac
}

task_start_without_hc() {
  setup_on
  stub_just; task_demo api; give_setup api
  out=$("$E" task start demo ABC-1) || fail "task start exited non-zero without hc"
  [ -d "$T/abc-1-x/api" ] || fail "no worktree"
  case $out in *"run it yourself in the tab: just setup && entourage task build demo ABC-1"*) ;; *) fail "did not say what to run: $out" ;; esac
}

task_start_without_a_terminal() {
  setup_on
  stub_just; stub_hc; task_demo api; give_setup api
  cat > "$TMP/bin/herdr-app" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$TMP/herdr-calls.log"
[ "\$1" = status ] && echo '  "layout": "test",'
exit 0
EOF
  out=$("$E" task start demo ABC-1) || fail "task start exited non-zero with no terminal"
  [ -z "$(hc_calls)" ] || fail "typed somewhere without a terminal: $(hc_calls)"
  [ -d "$T/abc-1-x/api" ] || fail "no worktree"
  case $out in *"run it yourself in the tab: just setup && entourage task build demo ABC-1"*) ;; *) fail "did not say what to run: $out" ;; esac
}

task_start_when_hc_send_fails() {
  setup_on
  stub_just; stub_hc 1; task_demo api; give_setup api
  out=$("$E" task start demo ABC-1) || fail "task start exited non-zero when hc failed"
  [ -d "$T/abc-1-x/api" ] || fail "no worktree"
  case $out in *"run it yourself in the tab: just setup && entourage task build demo ABC-1"*) ;; *) fail "did not say what to run: $out" ;; esac
  case $out in *"running in the tab"*) fail "said setup is running when it could not be started: $out" ;; esac
}

SETUP_CASES="task_start_leaves_setup_off task_start_turns_setup_on_from_the_env_file
  task_start_runs_setup_one_repo task_start_sends_setup_to_the_new_tab
  task_start_runs_setup_several_repos task_start_runs_entourages_own_setup
  task_start_skips_setup_without_a_recipe
  task_start_skips_an_unreadable_justfile task_start_ignores_a_parent_justfile
  task_start_quotes_repo_names task_start_without_just task_start_without_hc
  task_start_without_a_terminal task_start_when_hc_send_fails"

# --- tasks: the agent in the task's tab -------------------------------------

# task start types `entourage task build` into the task's tab, after setup when
# setup runs, so the agent starts on the card with no one typing there.
task_start_starts_the_agent_in_the_tab() {
  stub_hc; task_demo api
  out=$("$E" task start demo abc-1) || fail "task start exited non-zero"
  [ "$(hc_calls)" = "send t9 entourage task build demo ABC-1" ] || fail "wrong hc calls: $(hc_calls)"
  case $out in *"agent     starting in the tab"*) ;; *) fail "did not say the agent is starting: $out" ;; esac
}

task_start_says_how_to_start_the_agent_without_hc() {
  task_demo api
  out=$("$E" task start demo ABC-1) || fail "task start exited non-zero without hc"
  [ -d "$T/abc-1-x/api" ] || fail "no worktree"
  case $out in *"run it yourself in the tab: entourage task build demo ABC-1"*) ;; *) fail "did not say what to run: $out" ;; esac
  case $out in *"starting in the tab"*) fail "said the agent is starting: $out" ;; esac
}

# A worktree takes the trust of its repo's own checkout, never of the space
# folder above it. task start only reads Claude Code's file, and says when the
# agent will be asked.
task_start_notes_a_repo_claude_code_has_not_trusted() {
  claude_state; task_demo api
  cp "$HOME/.claude.json" "$TMP/before"
  out=$("$E" task start demo ABC-1) || fail "task start exited non-zero"
  case $out in *"Claude Code will ask once in the tab whether to trust api"*) ;; *) fail "did not say Claude Code will ask: $out" ;; esac
  cmp -s "$HOME/.claude.json" "$TMP/before" || fail "wrote Claude Code's file: $(cat "$HOME/.claude.json")"
}

task_start_says_nothing_of_a_trusted_repo() {
  task_demo api
  claude_state "{\"projects\":{\"$HOME/Dev/api\":{\"hasTrustDialogAccepted\":true}}}"
  out=$("$E" task start demo ABC-1) || fail "task start exited non-zero"
  case $out in *"whether to trust"*) fail "spoke of trust for a repo Claude Code trusts: $out" ;; esac
}

# With several repos the tab is in the task folder, inside the space folder
# that space new trusts.
task_start_says_nothing_of_trust_for_several_repos() {
  claude_state; task_demo api web
  out=$("$E" task start demo ABC-1) || fail "task start exited non-zero"
  case $out in *"whether to trust"*) fail "spoke of trust for a tab in the task folder: $out" ;; esac
}

# The log shows when the work was started, and a store that cannot be written
# never stops the task.
task_start_records_the_start() {
  task_demo api
  "$E" task start demo ABC-1 >/dev/null || fail "task start exited non-zero"
  out=$("$E" task log demo ABC-1) || fail "task log exited non-zero"
  case $out in *"start      done, then build"*) ;; *) fail "the log does not show the start: $out" ;; esac
}

# The log reads straight through from the approval to the build: breakdown
# hands on to start, and start is the row task start records.
task_start_follows_breakdown_by_one_name() {
  task_demo api
  printf 'step: breakdown\nstatus: done\nnext: start\nsummary: Approved as one piece.\n' |
    "$E" task handoff demo ABC-1 >/dev/null 2>&1 || fail "task handoff refused breakdown with next: start"
  out=$("$E" task log demo) || fail "task log with no card exited non-zero"
  printf '%s\n' "$out" | grep -Eq '^ABC-1 +breakdown done, then start +for ' ||
    fail "the card list does not show breakdown done, then start: $out"
  "$E" task start demo ABC-1 >/dev/null || fail "task start exited non-zero"
  out=$("$E" task log demo ABC-1) || fail "task log exited non-zero"
  printf '%s\n' "$out" | grep -Eq '  breakdown  done, then start( |$)' ||
    fail "the log does not show breakdown done, then start: $out"
  printf '%s\n' "$out" | grep -Eq '  start      done, then build$' ||
    fail "the log does not show start done, then build: $out"
  [ "$(printf '%s\n' "$out" | grep -Eo '(breakdown|start) +done, then [a-z]+' | tr -s ' ' | tr '\n' '|')" = \
    'breakdown done, then start|start done, then build|' ] || fail "not breakdown, then start, in that order: $out"
}

task_start_starts_when_the_store_cannot_be_written() {
  task_demo api
  mkdir -p "$HOME/.config/entourage/entourage.db"
  out=$("$E" task start demo ABC-1) || fail "task start exited non-zero with a store it cannot write"
  [ -d "$T/abc-1-x/api" ] || fail "no worktree"
  case $out in *"could not record"*) ;; *) fail "did not say the start was not recorded: $out" ;; esac
}

# The space "demo" as task start leaves it for the card ABC-1: skills
# linked, the task's folder with a worktree's folder in it, and an agent on
# PATH that notes where it ran and what it was told.
build_demo() {
  "$E" install >/dev/null
  "$E" space new demo >/dev/null
  agent_stub claude
  WT=$P/demo/tasks/abc-1-x/api
  mkdir -p "$WT"
}
agent_ran() { [ -e "$TMP/agent-folder" ]; }

# An agent on PATH, named $1, that notes where it ran, how many arguments it
# was given, each one in agent-arg.<n>, and its last, the first message, in
# agent-message.
agent_stub() {
  cat > "$TMP/bin/$1" <<EOF
#!/usr/bin/env bash
pwd -P > "$TMP/agent-folder"
rm -f "$TMP"/agent-arg.*
echo "\$#" > "$TMP/agent-argc"
n=0
for a in "\$@"; do n=\$((n + 1)); printf '%s' "\$a" > "$TMP/agent-arg.\$n"; done
printf '%s' "\$a" > "$TMP/agent-message"
EOF
  chmod +x "$TMP/bin/$1"
}
agent_arg() { cat "$TMP/agent-arg.$1" 2>/dev/null; }

task_build_starts_the_agent() {
  build_demo
  (cd "$WT" && "$E" task build demo abc-1) || fail "task build exited non-zero"
  agent_ran || fail "the agent did not start"
  [ "$(cat "$TMP/agent-folder")" = "$WT" ] || fail "the agent started in $(cat "$TMP/agent-folder")"
  local msg want d
  # The build profile, the Linear server alone, the build's model and
  # effort, then the first message last.
  [ "$(cat "$TMP/agent-argc")" = 6 ] || fail "the agent was given $(cat "$TMP/agent-argc") arguments, not 6"
  [ "$(agent_arg 1)" = --agent=entourage-build ] || fail "the first argument is '$(agent_arg 1)'"
  [ "$(agent_arg 2)" = --strict-mcp-config ] || fail "the second argument is '$(agent_arg 2)'"
  [ "$(agent_arg 3)" = "--mcp-config=$REPO/agents/linear-mcp.json" ] || fail "the third argument is '$(agent_arg 3)'"
  [ "$(agent_arg 4)" = --model=opus ] || fail "the fourth argument is '$(agent_arg 4)'"
  [ "$(agent_arg 5)" = --effort=xhigh ] || fail "the fifth argument is '$(agent_arg 5)'"
  msg=$(cat "$TMP/agent-message")
  [ "$(agent_arg 6)" = "$msg" ] || fail "the first message is not the last argument"
  for want in "Linear card ABC-1" "entourage space \`demo\`" sdlc-build sdlc-review sdlc-pr "entourage task handoff demo ABC-1"; do
    case $msg in *"$want"*) ;; *) fail "the first message does not mention '$want': $msg" ;; esac
  done
  case $msg in *"{card}"* | *"{space}"* | *"{project}"*) fail "a placeholder was left in the first message: $msg" ;; esac
  # The task folder of several repos, and that of a card whose title had no
  # plain words, are the card's too.
  mkdir -p "$P/demo/tasks/abc-1"
  for d in "$P/demo/tasks/abc-1-x" "$P/demo/tasks/abc-1"; do
    (cd "$d" && "$E" task build demo ABC-1) || fail "task build refused $d"
    [ "$(cat "$TMP/agent-folder")" = "$d" ] || fail "the agent started in $(cat "$TMP/agent-folder"), not $d"
  done
}

# The agent works where it starts, so that has to be the card's own task.
task_build_refuses_outside_the_cards_task() {
  build_demo
  mkdir -p "$P/demo/tasks/abc-2-y" "$P/demo/tasks/abc-12-z" "$TMP/elsewhere"
  local d
  for d in "$P/demo" "$P/demo/tasks" "$P/demo/tasks/abc-2-y" "$P/demo/tasks/abc-12-z" "$TMP/elsewhere"; do
    (cd "$d" && "$E" task build demo ABC-1) >/dev/null 2>"$TMP/err" && fail "started the agent in $d"
    grep -qF 'entourage task start demo ABC-1' "$TMP/err" || fail "did not say how to start the task, in $d: $(cat "$TMP/err")"
  done
  agent_ran && fail "the agent started"
}

task_build_needs_a_harness() {
  build_demo
  rm "$TMP/bin/claude"
  (cd "$WT" && "$E" task build demo ABC-1) >/dev/null 2>"$TMP/err" && fail "exited zero with no harness on PATH"
  grep -q ENTOURAGE_HARNESS "$TMP/err" || fail "did not name the setting: $(cat "$TMP/err")"
}

task_build_needs_the_skills_linked() {
  build_demo
  rm "$SK/sdlc-review"
  (cd "$WT" && "$E" task build demo ABC-1) >/dev/null 2>"$TMP/err" && fail "started the agent without sdlc-review"
  grep -q sdlc-review "$TMP/err" && grep -q 'entourage update' "$TMP/err" || fail "did not say sdlc-review is missing: $(cat "$TMP/err")"
  ln -s "$REPO/skills/sdlc-review" "$SK/sdlc-review"
  rm "$SK/sdlc-build"
  (cd "$WT" && "$E" task build demo ABC-1) >/dev/null 2>"$TMP/err" && fail "started the agent without sdlc-build"
  grep -q sdlc-build "$TMP/err" && grep -q 'entourage update' "$TMP/err" || fail "did not say sdlc-build is missing: $(cat "$TMP/err")"
  ln -s "$REPO/skills/sdlc-build" "$SK/sdlc-build"
  rm "$SK/sdlc-pr"
  (cd "$WT" && "$E" task build demo ABC-1) >/dev/null 2>"$TMP/err" && fail "started the agent without sdlc-pr"
  grep -q sdlc-pr "$TMP/err" && grep -q 'entourage update' "$TMP/err" || fail "did not say sdlc-pr is missing: $(cat "$TMP/err")"
  agent_ran && fail "the agent started"
}

# claude starts with the build profile, so without it nothing is started.
task_build_needs_the_build_profile_linked() {
  build_demo
  rm "$AG/entourage-build.md"
  (cd "$WT" && "$E" task build demo ABC-1) >/dev/null 2>"$TMP/err" && fail "started the agent with no build profile linked"
  grep -q entourage-build "$TMP/err" && grep -q 'entourage update' "$TMP/err" ||
    fail "did not say the build profile is missing: $(cat "$TMP/err")"
  agent_ran && fail "the agent started"
}

# Another harness starts as it always has: the first message alone, no
# profile, and none needed.
task_build_starts_another_harness_with_no_profile() {
  build_demo
  agent_stub codex
  rm "$AG/entourage-build.md"
  # Nor are the profiles' settings read: a broken file does not stop it.
  echo 'not json' > "$HOME/.config/entourage/settings.json"
  (cd "$WT" && ENTOURAGE_HARNESS=codex "$E" task build demo ABC-1) || fail "task build exited non-zero"
  agent_ran || fail "the harness did not start"
  [ "$(cat "$TMP/agent-argc")" = 1 ] || fail "codex was given $(cat "$TMP/agent-argc") arguments, not the first message alone: $(agent_arg 1)"
  case $(cat "$TMP/agent-message") in *"Linear card ABC-1"*) ;; *) fail "codex was not given the first message: $(cat "$TMP/agent-message")" ;; esac
}

# The env file names the harness for `task build` too. claude is taken off
# PATH, so only the harness the file names can start.
task_build_takes_the_harness_from_the_env_file() {
  build_demo
  agent_stub myharness
  rm "$TMP/bin/claude"
  echo 'ENTOURAGE_HARNESS=myharness' > "$(env_file)"
  (cd "$WT" && "$E" task build demo ABC-1) 2>"$TMP/err" || fail "task build exited non-zero: $(cat "$TMP/err")"
  agent_ran || fail "the harness did not start"
  [ "$(cat "$TMP/agent-argc")" = 1 ] || fail "myharness was given $(cat "$TMP/agent-argc") arguments, not the first message alone: $(agent_arg 1)"
}

# An exported ENTOURAGE_AGENT is not read either: claude starts, with the
# build profile, and the program it names is never run.
task_build_ignores_the_old_agent_setting() {
  build_demo
  stub codex
  (cd "$WT" && ENTOURAGE_AGENT=codex "$E" task build demo ABC-1) || fail "task build exited non-zero"
  [ ! -e "$TMP/codex-calls.log" ] || fail "started codex: $(cat "$TMP/codex-calls.log")"
  agent_ran || fail "claude did not start"
  [ "$(agent_arg 1)" = --agent=entourage-build ] || fail "claude did not start with the build profile: '$(agent_arg 1)'"
}

# The build runs on the build's model and effort from the settings file, and
# never on the write-up's.
task_build_starts_with_the_build_settings() {
  build_demo
  "$E" profile set build model sonnet >/dev/null && "$E" profile set build effort high >/dev/null &&
    "$E" profile set write-up model haiku >/dev/null && "$E" profile set write-up effort low >/dev/null ||
    fail "could not set the profiles"
  (cd "$WT" && "$E" task build demo ABC-1) || fail "task build exited non-zero"
  [ "$(cat "$TMP/agent-argc")" = 6 ] || fail "the agent was given $(cat "$TMP/agent-argc") arguments, not 6"
  [ "$(agent_arg 4)" = --model=sonnet ] || fail "the fourth argument is '$(agent_arg 4)', not --model=sonnet"
  [ "$(agent_arg 5)" = --effort=high ] || fail "the fifth argument is '$(agent_arg 5)', not --effort=high"
}

task_build_stops_on_a_broken_settings_file() {
  build_demo
  local f=$HOME/.config/entourage/settings.json
  printf '%s\n' '{"profiles":{"build":{"model":"gpt-5"}}}' > "$f"
  (cd "$WT" && "$E" task build demo ABC-1) >/dev/null 2>"$TMP/err" && fail "task build exited zero with a broken settings file"
  grep -qF "$f is not valid settings: the model of build is \"gpt-5\"" "$TMP/err" || fail "did not say what is wrong: $(cat "$TMP/err")"
  agent_ran && fail "the agent started"
}

BUILD_CASES="task_start_starts_the_agent_in_the_tab task_start_says_how_to_start_the_agent_without_hc
  task_start_notes_a_repo_claude_code_has_not_trusted task_start_says_nothing_of_a_trusted_repo
  task_start_says_nothing_of_trust_for_several_repos task_start_records_the_start
  task_start_follows_breakdown_by_one_name
  task_start_starts_when_the_store_cannot_be_written task_build_starts_the_agent
  task_build_refuses_outside_the_cards_task task_build_needs_a_harness task_build_needs_the_skills_linked
  task_build_needs_the_build_profile_linked task_build_starts_another_harness_with_no_profile
  task_build_takes_the_harness_from_the_env_file task_build_ignores_the_old_agent_setting"

# --- tasks: targets ---------------------------------------------------------

task_start_one_target_with_a_group() {
  setup_on
  stub_just; stub_hc; task_demo api web; give_setup api
  out=$("$E" task start demo ABC-1 api:athlete) || fail "task start exited non-zero"
  [ "$(branch_of "$T/abc-1-x/api")" = feat/abc-1-x ] || fail "no worktree for the named repo"
  [ ! -e "$T/abc-1-x/web" ] || fail "made a worktree for a repo that was not named"
  has_branch "$HOME/Dev/web" feat/abc-1-x && fail "made a branch in a repo that was not named"
  [ ! -e "$T/abc-1-x/CLAUDE.md" ] && [ ! -L "$T/abc-1-x/CLAUDE.md" ] || fail "linked the space doc beside one repo"
  [ "$(hc_calls)" = "send t9 just setup athlete && entourage task build demo ABC-1" ] || fail "wrong hc calls: $(hc_calls)"
  [ "$(last_call)" = "do tab.new {\"name\":\"abc-1-x\",\"folder\":\"$T/abc-1-x/api\"}" ] || fail "the tab is not in the worktree: $(last_call)"
  case $out in *"setup     api athlete (running in the tab)"*) ;; *) fail "did not report the group: $out" ;; esac
}

task_start_several_groups() {
  setup_on
  stub_just; stub_hc; task_demo api; give_setup api
  "$E" task start demo ABC-1 api:athlete,coach >/dev/null || fail "task start exited non-zero"
  [ "$(hc_calls)" = "send t9 just setup athlete coach && entourage task build demo ABC-1" ] || fail "wrong hc calls: $(hc_calls)"
}

task_start_several_targets() {
  setup_on
  stub_just; stub_hc; task_demo api web docs; give_setup api; give_setup web
  "$E" task start demo ABC-1 web:coach api >/dev/null || fail "task start exited non-zero"
  [ "$(hc_calls)" = "send t9 (cd ./'api' && just setup) && (cd ./'web' && just setup coach) && entourage task build demo ABC-1" ] || fail "wrong hc calls: $(hc_calls)"
  [ -d "$T/abc-1-x/api" ] && [ -d "$T/abc-1-x/web" ] || fail "missing a named repo's worktree"
  [ ! -e "$T/abc-1-x/docs" ] || fail "made a worktree for a repo that was not named"
  is_link_to "$T/abc-1-x/CLAUDE.md" ../../PROJECT.md || fail "no space doc link for a task of several repos"
  [ "$(last_call)" = "do tab.new {\"name\":\"abc-1-x\",\"folder\":\"$T/abc-1-x\"}" ] || fail "the tab is not in the task folder: $(last_call)"
}

task_start_a_target_without_a_group() {
  setup_on
  stub_just; stub_hc; task_demo api web; give_setup web
  "$E" task start demo ABC-1 web >/dev/null || fail "task start exited non-zero"
  [ "$(hc_calls)" = "send t9 just setup && entourage task build demo ABC-1" ] || fail "wrong hc calls: $(hc_calls)"
  [ ! -e "$T/abc-1-x/api" ] || fail "made a worktree for a repo that was not named"
}

# A repo the task did not name can be broken without stopping it.
task_start_ignores_an_unnamed_broken_repo() {
  task_demo api web
  rm -rf "$HOME/Dev/web"
  "$E" task start demo ABC-1 api >/dev/null 2>&1 || fail "a missing repo that was not named stopped the task"
  [ -d "$T/abc-1-x/api" ] || fail "no worktree"
}

task_start_refuses_bad_targets() {
  task_demo api web
  local t
  for t in nope api:athlete,nope/x "api:" "api:a,,b" "api:Athlete" "api:a b" "api:a;b" 'api:$x' "api:a'b" "api:-a" ":athlete" \
           "api:a:b" "api:a
b" "api:a
"; do
    "$E" task start demo ABC-1 "$t" >/dev/null 2>&1 && fail "accepted the target '$t'"
    [ ! -e "$T" ] || { fail "made a tasks folder for the target '$t'"; rm -rf "$T"; }
    has_branch "$API" feat/abc-1-x && fail "made a branch for the target '$t'"
  done
}

# What counts as a letter must not depend on the caller's locale: in some, a
# range like a-z takes in uppercase letters and even shell punctuation.
task_start_refuses_bad_groups_in_any_locale() {
  task_demo api
  local loc t
  for loc in en_US.ISO8859-1 en_US.US-ASCII kk_KZ.PT154; do
    for t in "api:Athlete" 'api:a$(id)' "api:a|b" "api:a&&b"; do
      LC_ALL=$loc "$E" task start demo ABC-1 "$t" >/dev/null 2>&1 && fail "accepted '$t' under $loc"
      [ ! -e "$T" ] || { fail "made a tasks folder for '$t' under $loc"; rm -rf "$T"; git -C "$API" worktree prune; git -C "$API" branch -q -D feat/abc-1-x; }
    done
  done
}

# A repo the task did not name is not fetched either.
task_start_does_not_fetch_an_unnamed_repo() {
  task_demo api web
  git clone -q "$HOME/Dev/web.origin.git" "$TMP/other"
  git -C "$TMP/other" -c user.name=t -c user.email=t@t commit -q --allow-empty -m newer
  git -C "$TMP/other" push -q origin main
  local before
  before=$(head_of "$HOME/Dev/web" origin/main)
  "$E" task start demo ABC-1 api >/dev/null || fail "task start exited non-zero"
  [ "$(head_of "$HOME/Dev/web" origin/main)" = "$before" ] || fail "fetched a repo that was not named"
}

task_start_refuses_a_repo_named_twice() {
  task_demo api web
  "$E" task start demo ABC-1 api:athlete api:coach >/dev/null 2>"$TMP/err" && fail "accepted a repo named twice"
  grep -q comma "$TMP/err" || fail "did not say to use a comma: $(cat "$TMP/err")"
  [ ! -e "$T" ] || fail "made a tasks folder"
}

task_start_lists_repos_for_an_unknown_target() {
  task_demo api web
  "$E" task start demo ABC-1 nope >/dev/null 2>"$TMP/err" && fail "accepted an unknown repo"
  grep -q api "$TMP/err" && grep -q web "$TMP/err" || fail "did not list the space's repos: $(cat "$TMP/err")"
}

TARGET_CASES="task_start_refuses_bad_groups_in_any_locale task_start_does_not_fetch_an_unnamed_repo
  task_start_one_target_with_a_group task_start_several_groups task_start_several_targets
  task_start_a_target_without_a_group task_start_ignores_an_unnamed_broken_repo
  task_start_refuses_bad_targets task_start_refuses_a_repo_named_twice
  task_start_lists_repos_for_an_unknown_target"

# --- tasks: finishing -------------------------------------------------------

# Commit a file on the branch of the worktree $1: $2 is the file, $3 the
# commit's message.
commit_in() {
  mkdir -p "$(dirname "$1/$2")"
  echo "$2" > "$1/$2"
  git -C "$1" add "$2"
  git -C "$1" -c user.name=t -c user.email=t@t commit -q -m "${3:-add $2}"
}

# Push the branch of the worktree $1 to origin, then merge it there with a
# merge commit, as GitHub merges a pull request.
merge_on_origin() {
  local branch clone=$TMP/merging
  branch=$(branch_of "$1")
  git -C "$1" push -q origin "HEAD:refs/heads/$branch"
  git clone -q "$(git -C "$1" remote get-url origin)" "$clone"
  git -C "$clone" -c user.name=t -c user.email=t@t merge -q --no-ff -m "Merge $branch" "origin/$branch"
  git -C "$clone" push -q origin main
  rm -rf "$clone"
}

# Herdr shows the space with the card's write-up tab and the task's
# tab, tbtask. A space with another folder has a tab of the same name, and so
# does a closed space in "recent": neither is the task's.
herdr_shows_the_task() {
  cat > "$TMP/herdr-ls.json" <<EOF
{
  "spaces": [
    {
      "id": "spother",
      "name": "other",
      "folder": "$TMP/elsewhere",
      "tabs": [{"id": "tbother", "name": "abc-1-x"}]
    },
    {
      "id": "spdemo",
      "name": "demo",
      "folder": "$P/demo",
      "tabs": [{"id": "tbcard", "name": "ABC-1"}, {"id": "tbtask", "name": "abc-1-x"}]
    }
  ],
  "recent": [
    {"id": "spold", "name": "demo", "folder": "$P/demo", "tabs": [{"id": "tbold", "name": "abc-1-x"}]}
  ]
}
EOF
}
tab_closes() { grep -c '^do tab\.close ' "$TMP/herdr-calls.log" 2>/dev/null || true; }
worktrees_of() { git -C "$1" worktree list | wc -l | tr -d ' '; }

# The space demo with the repos named, and the task for ABC-1 started on them.
finish_demo() {
  task_demo "$@"
  "$E" task start demo ABC-1 >/dev/null || fail "task start exited non-zero"
}

# Give a repo made by task_demo a .gitignore and a justfile on its default
# branch, here and on its origin, before its task is started. $2 is the
# justfile's text.
give_ignores() {
  local repo=$HOME/Dev/$1
  printf 'node_modules/\n.env\ndocs/\n' > "$repo/.gitignore"
  printf '%b' "$2" > "$repo/justfile"
  git -C "$repo" add .gitignore justfile
  git -C "$repo" -c user.name=t -c user.email=t@t commit -q -m ignores
  git -C "$repo" push -q origin main
}

task_finish_removes_the_task() {
  finish_demo api
  local wt=$T/abc-1-x/api out
  commit_in "$wt" f.txt
  merge_on_origin "$wt"
  herdr_shows_the_task
  out=$("$E" task finish demo ABC-1 2>&1) || fail "task finish exited non-zero: $out"
  [ ! -e "$T/abc-1-x" ] || fail "the task folder is still there: $(ls -A "$T/abc-1-x" 2>&1)"
  [ "$(worktrees_of "$API")" = 1 ] || fail "git still lists the worktree: $(git -C "$API" worktree list)"
  has_branch "$API" feat/abc-1-x && fail "the branch is still there"
  [ "$(branch_of "$API")" = main ] || fail "the repo's own checkout moved to $(branch_of "$API")"
  [ "$(last_call)" = 'do tab.close {"id":"tbtask"}' ] || fail "did not close the task's tab last: $(last_call)"
  [ "$(tab_closes)" = 1 ] || fail "closed more than the task's tab: $(cat "$TMP/herdr-calls.log")"
  case $out in *"Finished task 'abc-1-x'"*) ;; *) fail "did not say it finished: $out" ;; esac
}

task_finish_removes_a_task_of_two_repos() {
  finish_demo api web
  local web=$HOME/Dev/web out
  commit_in "$T/abc-1-x/api" a.txt; merge_on_origin "$T/abc-1-x/api"
  commit_in "$T/abc-1-x/web" w.txt; merge_on_origin "$T/abc-1-x/web"
  herdr_shows_the_task
  out=$("$E" task finish demo ABC-1 2>&1) || fail "task finish exited non-zero: $out"
  [ ! -e "$T/abc-1-x" ] && [ ! -L "$T/abc-1-x/CLAUDE.md" ] || fail "the task folder or its links are still there: $(ls -A "$T/abc-1-x" 2>&1)"
  [ "$(worktrees_of "$API")" = 1 ] && [ "$(worktrees_of "$web")" = 1 ] || fail "git still lists a worktree"
  has_branch "$API" feat/abc-1-x && fail "the branch is still there in api"
  has_branch "$web" feat/abc-1-x && fail "the branch is still there in web"
  [ -f "$P/demo/PROJECT.md" ] || fail "the space doc the links pointed to is gone"
  [ "$(last_call)" = 'do tab.close {"id":"tbtask"}' ] || fail "did not close the task's tab last: $(last_call)"
}

# A task whose branch has no commits of its own loses nothing. With no tab
# open for it, it says so and finishes.
task_finish_removes_a_branch_with_no_commits() {
  finish_demo api
  local out
  out=$("$E" task finish demo ABC-1 2>&1) || fail "task finish exited non-zero: $out"
  [ ! -e "$T/abc-1-x" ] || fail "the task folder is still there"
  has_branch "$API" feat/abc-1-x && fail "the branch is still there"
  [ "$(tab_closes)" = 0 ] || fail "closed a tab that is not the task's: $(cat "$TMP/herdr-calls.log")"
  case $out in *"tab"*"abc-1-x"*) ;; *) fail "did not say the task had no tab: $out" ;; esac
}

task_finish_refuses_uncommitted_changes() {
  finish_demo api
  local wt=$T/abc-1-x/api out
  commit_in "$wt" tracked.txt
  merge_on_origin "$wt"
  echo changed >> "$wt/tracked.txt"
  echo staged > "$wt/staged.txt"; git -C "$wt" add staged.txt
  mkdir -p "$wt/new"; echo untracked > "$wt/new/untracked.txt"
  echo notes > "$T/abc-1-x/notes.md"
  out=$("$E" task finish demo ABC-1 2>&1) && fail "finished a task with changes that are not committed"
  local change
  for change in " M tracked.txt" "A  staged.txt" "?? new/untracked.txt"; do
    case $out in *api*"$change"*) ;; *) fail "did not name api and the change '$change': $out" ;; esac
  done
  case $out in *"task folder"*"notes.md"*) ;; *) fail "did not name the file outside any worktree: $out" ;; esac
  [ "$(cat "$wt/new/untracked.txt" 2>/dev/null)" = untracked ] || fail "the untracked file is gone"
  [ -f "$T/abc-1-x/notes.md" ] || fail "the file in the task folder is gone"
  has_branch "$API" feat/abc-1-x || fail "deleted the branch"
}

# The branch was merged, then a fix was pushed to it (the PR 22 case): the
# fix is on origin's copy of the branch but not in main. Another repo has a
# commit that was never pushed at all.
task_finish_refuses_unmerged_commits() {
  finish_demo api web
  local a=$T/abc-1-x/api w=$T/abc-1-x/web out late local_
  commit_in "$a" one.txt; merge_on_origin "$a"
  commit_in "$a" late.txt "fix: pushed after the merge"
  git -C "$a" push -q origin HEAD:refs/heads/feat/abc-1-x
  commit_in "$w" local.txt "feat: never pushed"
  late=$(git -C "$a" rev-parse --short HEAD) local_=$(git -C "$w" rev-parse --short HEAD)
  out=$("$E" task finish demo ABC-1 2>&1) && fail "finished a task with commits that are not in main"
  case $out in *api*"$late fix: pushed after the merge"*web*"$local_ feat: never pushed"*) ;; *) fail "did not name each repo and its commits: $out" ;; esac
  case $out in *"origin/main"*) ;; *) fail "did not say what the commits are not in: $out" ;; esac
  case $out in *"one.txt"*) fail "named a commit that is in main: $out" ;; esac
  has_branch "$API" feat/abc-1-x && has_branch "$HOME/Dev/web" feat/abc-1-x || fail "deleted a branch"
  [ -d "$a" ] && [ -d "$w" ] || fail "removed a worktree"
}

task_finish_refuses_ignored_files() {
  stub_just; task_demo api
  give_ignores api 'made-by-setup:\n\t@echo node_modules/\n'
  "$E" task start demo ABC-1 >/dev/null || fail "task start exited non-zero"
  local wt=$T/abc-1-x/api out
  mkdir -p "$wt/node_modules/pkg" "$wt/docs"
  echo x > "$wt/node_modules/pkg/index.js"; echo secret > "$wt/.env"; echo notes > "$wt/docs/notes.md"
  out=$("$E" task finish demo ABC-1 2>&1) && fail "finished a task with ignored files that are work"
  case $out in *api*".env"*) ;; *) fail "did not name api and .env: $out" ;; esac
  case $out in *"docs/notes.md"*) ;; *) fail "did not name docs/notes.md: $out" ;; esac
  case $out in *node_modules*) fail "named what setup makes again: $out" ;; esac
  [ "$(cat "$wt/.env" 2>/dev/null)" = secret ] || fail "the ignored file is gone"
  [ -f "$wt/node_modules/pkg/index.js" ] || fail "removed what setup makes before refusing"
}

task_finish_removes_what_setup_makes() {
  stub_just; task_demo api
  give_ignores api 'setup:\n\t@echo installing\n\nmade-by-setup:\n\t@echo node_modules/\n'
  "$E" task start demo ABC-1 >/dev/null || fail "task start exited non-zero"
  local wt=$T/abc-1-x/api out
  mkdir -p "$wt/node_modules/pkg/lib"; echo x > "$wt/node_modules/pkg/lib/index.js"
  out=$("$E" task finish demo ABC-1 2>&1) || fail "task finish exited non-zero: $out"
  [ ! -e "$T/abc-1-x" ] || fail "the task folder is still there"
  has_branch "$API" feat/abc-1-x && fail "the branch is still there"
  grep -qx -- "--justfile $wt/justfile made-by-setup" "$TMP/just-calls.log" ||
    fail "did not run the worktree's made-by-setup recipe: $(cat "$TMP/just-calls.log")"
  case $out in *node_modules*) fail "said a word about what setup makes again: $out" ;; esac
}

task_finish_without_just_keeps_ignored_files() {
  task_demo api
  give_ignores api 'made-by-setup:\n\t@echo node_modules/\n'
  "$E" task start demo ABC-1 >/dev/null || fail "task start exited non-zero"
  local wt=$T/abc-1-x/api out
  mkdir -p "$wt/node_modules/pkg"; echo x > "$wt/node_modules/pkg/index.js"
  out=$("$E" task finish demo ABC-1 2>&1) && fail "finished a task with ignored files and no just to ask"
  case $out in *api*"node_modules/pkg/index.js"*) ;; *) fail "did not name the ignored file: $out" ;; esac
  case $out in *"just is not installed"*) ;; *) fail "did not say why every ignored file counts: $out" ;; esac
  [ -f "$wt/node_modules/pkg/index.js" ] || fail "removed the ignored file"
}

# A locked worktree may have something still working in it, and a worktree on
# another branch is not the task's to delete.
task_finish_refuses_a_locked_or_moved_worktree() {
  finish_demo api web
  local out
  git -C "$API" worktree lock --reason "a session is in it" "$T/abc-1-x/api"
  git -C "$T/abc-1-x/web" switch -q -c other
  out=$("$E" task finish demo ABC-1 2>&1) && fail "finished a locked worktree and one on another branch"
  case $out in *api*"locked (a session is in it)"*web*"other"*) ;; *) fail "did not name the lock and the branch: $out" ;; esac
  has_branch "$HOME/Dev/web" other && has_branch "$HOME/Dev/web" feat/abc-1-x || fail "deleted a branch"
  [ -d "$T/abc-1-x/api" ] && [ -d "$T/abc-1-x/web" ] || fail "removed a worktree"
}

# Problems in two repos are both named in one run, and nothing changes: the
# task folder, each repo's worktrees and branches, and the tab.
task_finish_refusal_changes_nothing() {
  finish_demo api web
  local a=$T/abc-1-x/api w=$T/abc-1-x/web web=$HOME/Dev/web out before
  commit_in "$a" f.txt "feat: not merged"
  echo x > "$w/untracked.txt"
  herdr_shows_the_task
  snapshot() {
    (cd "$T" && find . -print | LC_ALL=C sort)
    git -C "$API" worktree list --porcelain; git -C "$web" worktree list --porcelain
    git -C "$API" for-each-ref refs/heads; git -C "$web" for-each-ref refs/heads
  }
  before=$(snapshot)
  out=$("$E" task finish demo ABC-1 2>&1) && fail "finished a task that would lose work"
  case $out in *api*"feat: not merged"*web*"untracked.txt"*) ;; *) fail "did not name both repos' problems in one run: $out" ;; esac
  case $out in *"othing was removed"*) ;; *) fail "did not say that nothing was removed: $out" ;; esac
  [ "$(snapshot)" = "$before" ] || fail "something changed: $(diff <(echo "$before") <(snapshot))"
  [ "$(tab_closes)" = 0 ] || fail "closed the tab: $(cat "$TMP/herdr-calls.log")"
}

# Closing the tab the command runs in hangs up its shell, and the command with
# it. Everything else has been done by then, and said.
task_finish_from_its_own_tab() {
  finish_demo api
  local wt=$T/abc-1-x/api rc=0
  commit_in "$wt" f.txt
  merge_on_origin "$wt"
  herdr_shows_the_task
  cat > "$TMP/bin/herdr-app" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$TMP/herdr-calls.log"
[ "\$1" = status ] && echo '  "layout": "test",'
[ "\$1" = ls ] && cat "$TMP/herdr-ls.json"
[ "\$2" = tab.close ] && kill -HUP "\$PPID"
exit 0
EOF
  (cd "$wt" && "$E" task finish demo ABC-1) > "$TMP/out" 2>&1 || rc=$?
  [ "$rc" = 129 ] || fail "the command was not hung up by its tab closing (exit $rc): $(cat "$TMP/out")"
  [ ! -e "$T/abc-1-x" ] || fail "the task folder is still there"
  [ "$(worktrees_of "$API")" = 1 ] || fail "git still lists the worktree"
  has_branch "$API" feat/abc-1-x && fail "the branch is still there"
  grep -q "Finished task 'abc-1-x'" "$TMP/out" || fail "did not say it finished before its tab closed: $(cat "$TMP/out")"
  [ "$(last_call)" = 'do tab.close {"id":"tbtask"}' ] || fail "closing the tab was not the last call: $(last_call)"
}

task_finish_with_no_task() {
  task_demo api
  # ABC-12's task is not ABC-1's.
  linear_answers "$(card_answer ABC-12 Y feat)"
  "$E" task start demo ABC-12 >/dev/null || fail "task start exited non-zero"
  local before out
  before=$(machine_snapshot)
  out=$("$E" task finish demo ABC-1 2>&1) && fail "task finish exited zero with no task"
  case $out in *ABC-1[!0-9]*) ;; *) fail "the message does not name the card: $out" ;; esac
  [ "$(machine_snapshot)" = "$before" ] || fail "changed the machine"
  [ -d "$T/abc-12-y/api" ] || fail "touched another card's task"
}

# --- tasks: watching the pull requests --------------------------------------

API_PR=https://github.com/acme/api/pull/7
WEB_PR=https://github.com/acme/web/pull/8

# The space demo with the repos named, the task for ABC-1 started on them,
# and stand-ins for gh and sleep.
watch_demo() {
  finish_demo "$@"
  stub_gh
  stub_sleep
}

# Run the watch with the arguments given after the card, leaving what it
# printed in WATCH_OUT, what it said on stderr in WATCH_ERR, and its exit
# code in WATCH_CODE.
watch() {
  WATCH_CODE=0
  WATCH_OUT=$("$E" task watch demo ABC-1 "$@" 2>"$TMP/watch-err") || WATCH_CODE=$?
  WATCH_ERR=$(cat "$TMP/watch-err")
}

# Between checks it sleeps by the age of the pull request: a minute while it
# is under 10 minutes old, 5 minutes while it is under 70, then half an hour.
# Each check asks gh once, in the worktree, for its branch's pull request.
task_watch_sleeps_on_the_schedule() {
  watch_demo api
  local pair ago want
  for pair in 300:60 1800:300 7200:1800; do
    ago=${pair%%:*} want=${pair#*:}
    gh_reset
    gh_answers api "$(pr_answer OPEN "$API_PR" "$ago")" "$(pr_answer MERGED "$API_PR" "$ago")"
    watch
    [ "$WATCH_CODE" = 0 ] || fail "opened ${ago}s ago, the watch exited $WATCH_CODE: $WATCH_OUT $WATCH_ERR"
    [ "$(sleeps)" = "$want" ] || fail "opened ${ago}s ago, it slept '$(sleeps)', not $want"
    [ "$(gh_count)" = 2 ] || fail "opened ${ago}s ago, gh was asked $(gh_count) times in two checks: $(gh_calls)"
  done
  [ "$(gh_calls | sort -u)" = "api pr list --head feat/abc-1-x --state all --json url,state,mergeable,createdAt" ] ||
    fail "did not ask gh for the branch's pull request in the worktree: $(gh_calls)"
}

# --once checks once and never sleeps: 2 while a pull request is open, 0 once
# every one has merged.
task_watch_once_checks_once() {
  watch_demo api
  gh_answers api "$(pr_answer OPEN "$API_PR" 60)"
  watch --once
  [ "$WATCH_CODE" = 2 ] || fail "exited $WATCH_CODE, not 2, with the pull request open: $WATCH_OUT $WATCH_ERR"
  [ "$WATCH_OUT" = "open $API_PR" ] || fail "did not print the open pull request: $WATCH_OUT"
  [ "$(gh_count)" = 1 ] || fail "gh was asked $(gh_count) times: $(gh_calls)"
  [ -z "$(sleeps)" ] || fail "slept: $(sleeps)"
  gh_reset
  gh_answers api "$(pr_answer MERGED "$API_PR" 60)"
  watch --once
  [ "$WATCH_CODE" = 0 ] || fail "exited $WATCH_CODE, not 0, with the pull request merged: $WATCH_OUT $WATCH_ERR"
  [ "$WATCH_OUT" = "merged $API_PR" ] || fail "did not print the merged pull request: $WATCH_OUT"
}

# With two repos, the second merging a check after the first, it ends only
# once both have, with a line for each. The schedule counts from the newer.
task_watch_ends_when_every_pull_request_has_merged() {
  watch_demo api web
  gh_answers api "$(pr_answer MERGED "$API_PR" 7200)"
  gh_answers web "$(pr_answer OPEN "$WEB_PR" 300)" "$(pr_answer MERGED "$WEB_PR" 300)"
  watch
  [ "$WATCH_CODE" = 0 ] || fail "exited $WATCH_CODE, not 0, with both merged: $WATCH_OUT $WATCH_ERR"
  [ "$WATCH_OUT" = "merged $API_PR
open $WEB_PR
merged $API_PR
merged $WEB_PR" ] || fail "did not print each check: $WATCH_OUT"
  [ "$(gh_count)" = 4 ] || fail "gh was asked $(gh_count) times in two checks of two repos: $(gh_calls)"
  [ "$(sleeps)" = 60 ] || fail "slept '$(sleeps)', not 60 from the newer pull request"
}

# A pull request closed without merging ends it with 3, though another is
# still open.
task_watch_ends_when_a_pull_request_is_closed() {
  watch_demo api web
  gh_answers api "$(pr_answer OPEN "$API_PR" 60)"
  gh_answers web "$(pr_answer OPEN "$WEB_PR" 60)" "$(pr_answer CLOSED "$WEB_PR" 60)"
  watch
  [ "$WATCH_CODE" = 3 ] || fail "exited $WATCH_CODE, not 3, with one closed: $WATCH_OUT $WATCH_ERR"
  case $WATCH_OUT in *"open $API_PR"$'\n'"closed $WEB_PR") ;; *) fail "did not end with the closed one: $WATCH_OUT" ;; esac
  [ "$(sleeps)" = 60 ] || fail "slept '$(sleeps)', not once"
}

# A pull request in conflict with its default branch ends it with 4 and a
# conflict line, though another is still open. UNKNOWN, which GitHub answers
# while it works out whether one can be merged, counts as open. With --once
# it is 4 too, and UNKNOWN alone is still 2.
task_watch_ends_on_a_conflict() {
  watch_demo api web
  # Both merge at the third check, so a watch that missed the conflict ends
  # there, with 0, rather than running on.
  gh_answers api "$(pr_answer OPEN "$API_PR" 60 UNKNOWN)" "$(pr_answer OPEN "$API_PR" 60 UNKNOWN)" \
    "$(pr_answer MERGED "$API_PR" 60)"
  gh_answers web "$(pr_answer OPEN "$WEB_PR" 60)" "$(pr_answer OPEN "$WEB_PR" 60 CONFLICTING)" \
    "$(pr_answer MERGED "$WEB_PR" 60)"
  watch
  [ "$WATCH_CODE" = 4 ] || fail "exited $WATCH_CODE, not 4, with one in conflict: $WATCH_OUT $WATCH_ERR"
  [ "$WATCH_OUT" = "open $API_PR
open $WEB_PR
open $API_PR
conflict $WEB_PR" ] || fail "did not print each check, ending with the conflict: $WATCH_OUT"
  [ "$(sleeps)" = 60 ] || fail "slept '$(sleeps)', not once"
  gh_reset
  gh_answers api "$(pr_answer OPEN "$API_PR" 60 UNKNOWN)"
  gh_answers web "$(pr_answer OPEN "$WEB_PR" 60 CONFLICTING)"
  watch --once
  [ "$WATCH_CODE" = 4 ] || fail "with --once, exited $WATCH_CODE, not 4, with one in conflict: $WATCH_OUT $WATCH_ERR"
  [ "$WATCH_OUT" = "open $API_PR
conflict $WEB_PR" ] || fail "with --once, did not print the conflict: $WATCH_OUT"
  # web, with no answer, has no pull request, so api is the only one.
  gh_reset
  gh_answers api "$(pr_answer OPEN "$API_PR" 60 UNKNOWN)"
  watch --once
  [ "$WATCH_CODE" = 2 ] || fail "with --once, exited $WATCH_CODE, not 2, with UNKNOWN alone: $WATCH_OUT $WATCH_ERR"
  [ "$WATCH_OUT" = "open $API_PR" ] || fail "did not count UNKNOWN as open: $WATCH_OUT"
}

# A pull request closed without merging comes before one in conflict, in
# either repo: the human is asked about it first. A closed one that GitHub
# also calls conflicting is closed.
task_watch_puts_a_closed_one_first() {
  watch_demo api web
  local order closed conflict closed_pr conflict_pr once
  for order in "api $API_PR web $WEB_PR" "web $WEB_PR api $API_PR"; do
    read -r closed closed_pr conflict conflict_pr <<< "$order"
    gh_reset
    gh_answers "$closed" "$(pr_answer CLOSED "$closed_pr" 60 CONFLICTING)"
    gh_answers "$conflict" "$(pr_answer OPEN "$conflict_pr" 60 CONFLICTING)"
    for once in '' --once; do
      watch $once
      [ "$WATCH_CODE" = 3 ] ||
        fail "closed in $closed, in conflict in $conflict${once:+, $once}: exited $WATCH_CODE, not 3: $WATCH_OUT $WATCH_ERR"
      case $WATCH_OUT in
        *"closed $closed_pr"*) ;;
        *) fail "closed in $closed${once:+, $once}: did not print it as closed: $WATCH_OUT" ;;
      esac
      case $WATCH_OUT in
        *"conflict $conflict_pr"*) ;;
        *) fail "in conflict in $conflict${once:+, $once}: did not print the conflict: $WATCH_OUT" ;;
      esac
    done
    [ -z "$(sleeps)" ] || fail "closed in $closed: slept '$(sleeps)'"
  done
}

# When gh fails, it says so and asks again at the next check. With --once
# there is no next check, so whether it merged is not known.
task_watch_tries_again_when_gh_fails() {
  watch_demo api
  gh_answers api "$(pr_answer MERGED "$API_PR" 60)"
  gh_fails_at api 1
  watch
  [ "$WATCH_CODE" = 0 ] || fail "exited $WATCH_CODE, not 0, once gh answered: $WATCH_OUT $WATCH_ERR"
  [ "$WATCH_OUT" = "merged $API_PR" ] || fail "printed: $WATCH_OUT"
  case $WATCH_ERR in *"could not ask GitHub"*api*"error connecting to api.github.com"*"Trying again"*) ;; *) fail "did not say gh failed: $WATCH_ERR" ;; esac
  [ "$(sleeps)" = 60 ] || fail "slept '$(sleeps)', not once"
  gh_reset
  gh_fails_at api 1
  watch --once
  [ "$WATCH_CODE" = 1 ] || fail "with --once, exited $WATCH_CODE, not 1, when gh failed: $WATCH_OUT $WATCH_ERR"
  case $WATCH_ERR in *"could not ask GitHub"*"not known"*) ;; *) fail "with --once, did not say gh failed: $WATCH_ERR" ;; esac
}

# A repo whose branch has no pull request is skipped: the work did not change
# it. Of a branch's pull requests, the newest is the one that counts.
task_watch_reads_each_branchs_newest_pull_request() {
  watch_demo api web
  gh_answers api "$(jq -cn --arg old "${API_PR%/*}/3" --arg new "$API_PR" \
    '[{url: $old, state: "CLOSED", createdAt: "2026-01-01T00:00:00Z"},
      {url: $new, state: "MERGED", createdAt: "2026-01-02T00:00:00Z"}]')"
  watch
  [ "$WATCH_CODE" = 0 ] || fail "exited $WATCH_CODE, not 0: $WATCH_OUT $WATCH_ERR"
  [ "$WATCH_OUT" = "merged $API_PR" ] || fail "did not take the newest pull request alone: $WATCH_OUT"
  [ "$(gh_count)" = 2 ] || fail "did not ask about both repos: $(gh_calls)"
}

# A task with no pull request at all, and a card with no task, are errors.
task_watch_needs_a_pull_request() {
  watch_demo api
  watch
  [ "$WATCH_CODE" = 1 ] || fail "exited $WATCH_CODE, not 1, with no pull request: $WATCH_OUT $WATCH_ERR"
  case $WATCH_ERR in *"no pull request"*feat/abc-1-x*) ;; *) fail "did not say there is no pull request: $WATCH_ERR" ;; esac
  [ -z "$(sleeps)" ] || fail "slept: $(sleeps)"
  local out
  out=$("$E" task watch demo ABC-9 2>&1) && fail "exited zero for a card with no task"
  case $out in *"ABC-9 has no task"*) ;; *) fail "did not say ABC-9 has no task: $out" ;; esac
  out=$("$E" task watch demo ABC-1 --twice 2>&1) && fail "exited zero for an unknown option"
  case $out in *"unknown option"*) ;; *) fail "did not refuse --twice: $out" ;; esac
}

# Stopped while it sleeps, it stops at once, and takes its sleep with it.
task_watch_stops_while_it_sleeps() {
  watch_demo api
  gh_answers api "$(pr_answer OPEN "$API_PR" 60)"
  # The real sleep, for a minute: long enough to be stopped in.
  rm -f "$TMP/bin/sleep"
  "$E" task watch demo ABC-1 > "$TMP/watch-out" 2>&1 &
  local pid=$! spid='' n=0
  until spid=$(pgrep -P "$pid" -x sleep) || [ "$n" -ge 100 ]; do /bin/sleep 0.1; n=$((n + 1)); done
  if [ -z "$spid" ]; then
    fail "never started its sleep: $(cat "$TMP/watch-out")"
    kill -9 "$pid" 2>/dev/null
    return
  fi
  kill "$pid"
  n=0
  while kill -0 "$pid" 2>/dev/null && [ "$n" -lt 30 ]; do /bin/sleep 0.1; n=$((n + 1)); done
  if kill -0 "$pid" 2>/dev/null; then
    fail "still running 3 seconds after it was stopped"
    kill -9 "$pid" 2>/dev/null
  fi
  wait "$pid" 2>/dev/null
  /bin/sleep 0.2
  if kill -0 "$spid" 2>/dev/null; then
    fail "left its sleep running"
    kill "$spid" 2>/dev/null
  fi
}

WATCH_CASES="task_watch_sleeps_on_the_schedule task_watch_once_checks_once
  task_watch_ends_when_every_pull_request_has_merged task_watch_ends_when_a_pull_request_is_closed
  task_watch_ends_on_a_conflict task_watch_puts_a_closed_one_first
  task_watch_tries_again_when_gh_fails task_watch_reads_each_branchs_newest_pull_request
  task_watch_needs_a_pull_request task_watch_stops_while_it_sleeps"

FINISH_CASES="task_finish_removes_the_task task_finish_removes_a_task_of_two_repos
  task_finish_removes_a_branch_with_no_commits task_finish_refuses_uncommitted_changes
  task_finish_refuses_unmerged_commits task_finish_refuses_ignored_files
  task_finish_removes_what_setup_makes task_finish_without_just_keeps_ignored_files
  task_finish_refuses_a_locked_or_moved_worktree task_finish_refusal_changes_nothing
  task_finish_from_its_own_tab task_finish_with_no_task"

CASES="$WATCH_CASES $FINISH_CASES $TARGET_CASES $SETUP_CASES $BUILD_CASES $CARD_CASES $CARD_START_CASES $CARD_MOVE_CASES $PROFILE_CASES
  task_start_refuses_a_repo_with_no_commits task_start_undoes_an_interrupted_run
  task_start_keeps_the_task_when_the_space_fails task_start_branch_has_no_upstream
  task_start_refusal_keeps_the_first_task task_start_refusal_keeps_an_existing_branch
  task_start_over_a_folder_deleted_by_hand task_start_leaves_other_worktrees_alone
  task_start_opens_a_tab_one_repo task_start_opens_a_tab_several_repos task_start_selects_an_open_space
  task_start_needs_herdr_running task_start_repo_path_with_a_space task_start_keeps_the_task_when_the_tab_fails
  task_start_several_repos task_start_one_repo_has_no_links task_start_undoes_a_failed_run
  task_start_refuses_unknown_space task_usage_on_unknown_subcommand
  task_start_makes_a_worktree task_start_starts_from_the_latest_default_branch
  task_start_works_offline task_start_without_origin_uses_local_default task_start_refuses_no_repos
  task_start_refuses_missing_repo task_start_refuses_existing_task task_start_refuses_existing_branch
  task_start_refuses_branch_on_origin task_start_leaves_the_main_checkout_alone task_start_after_hand_deletion"
