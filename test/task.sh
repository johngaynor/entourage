# Tests for tasks. Sourced by test/run.sh.

# --- tasks: writing a card up -----------------------------------------------

# The project "demo" on a machine that is set up: skills linked, an agent on PATH.
card_demo() {
  "$E" install >/dev/null
  "$E" project new demo >/dev/null
  stub claude
  : > "$TMP/herdr-calls.log"
}
tab_calls() { grep -c '^do tab\.new ' "$TMP/herdr-calls.log" 2>/dev/null || true; }

task_new_starts_an_agent() {
  card_demo
  "$E" task new demo ABC-122 >/dev/null || fail "task new exited non-zero"
  call=$(last_call)
  case $call in
    "do tab.new {\"name\":\"ABC-122\",\"folder\":\"$P/demo\",\"argv\":[\"claude\"],\"task\":\""*"\"}") ;;
    *) fail "wrong last call: $call" ;;
  esac
  for want in "Linear card ABC-122" sdlc-define sdlc-plan sdlc-breakdown "entourage task start demo ABC-122"; do
    case $call in *"$want"*) ;; *) fail "the first message does not mention '$want': $call" ;; esac
  done
  case $call in *"{card}"* | *"{project}"*) fail "a placeholder was left in the first message: $call" ;; esac
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
    printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "\n" in d["task"] and d["argv"]==["claude"]' ||
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

task_new_refuses_unknown_project() {
  card_demo
  "$E" task new nope ABC-122 >/dev/null 2>&1 && fail "accepted a project that does not exist"
  [ ! -e "$P/nope" ] || fail "made a project folder"
  [ "$(tab_calls)" = 0 ] || fail "opened a tab"
}

task_new_needs_the_skills_linked() {
  "$E" project new demo >/dev/null
  stub claude
  "$E" task new demo ABC-122 >/dev/null 2>"$TMP/err" && fail "started an agent with no skills linked"
  grep -q 'entourage update' "$TMP/err" || fail "did not say how to link the skills: $(cat "$TMP/err")"
  [ "$(tab_calls)" = 0 ] || fail "opened a tab"
}

task_new_needs_an_agent() {
  "$E" install >/dev/null
  "$E" project new demo >/dev/null
  : > "$TMP/herdr-calls.log"
  "$E" task new demo ABC-122 >/dev/null 2>"$TMP/err" && fail "exited zero with no agent on PATH"
  grep -q 'ENTOURAGE_AGENT' "$TMP/err" || fail "did not name the setting: $(cat "$TMP/err")"
  [ "$(tab_calls)" = 0 ] || fail "opened a tab"
}

task_new_honors_the_agent_setting() {
  card_demo
  stub codex
  ENTOURAGE_AGENT=codex "$E" task new demo ABC-122 >/dev/null || fail "task new exited non-zero"
  case $(last_call) in *'"argv":["codex"]'*) ;; *) fail "did not start the chosen agent: $(last_call)" ;; esac
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

# The agent starts in the project's folder, so Claude Code has to trust it by
# then. `project new` does that; `task new` checks again.

task_new_trusts_a_project_made_before() {
  card_demo
  claude_state
  "$E" task new demo ABC-122 >/dev/null || fail "task new exited non-zero"
  is_trusted "$P/demo" || fail "the project's folder is not trusted: $(cat "$HOME/.claude.json")"
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
  is_trusted "$P/demo" || fail "project new did not trust the folder"
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

# A project name that is a link leads to a folder entourage did not make,
# perhaps a repo. entourage answers only for folders it made.
task_new_does_not_trust_a_linked_project() {
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

task_start_refuses_unknown_project() {
  "$E" task start nope ABC-1 >/dev/null 2>&1 && fail "accepted a project that does not exist"
  [ ! -e "$P/nope" ] || fail "made a project folder"
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

# The project "demo" with a real repo for each name given, and a Linear that
# has the card ABC-1, titled X, of type feat: its task is on feat/abc-1-x.
task_demo() {
  local r
  "$E" project new demo >/dev/null
  for r in "$@"; do
    make_git_repo "$HOME/Dev/$r"
    "$E" project add demo "$HOME/Dev/$r" >/dev/null
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
# message holds $1. The rest are task start's arguments after the project.
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

# The branch's type is the card's, whichever of them it is.
task_start_takes_the_cards_type() {
  task_demo api
  linear_answers "$(card_answer ABC-1 X feat)" "$(card_answer ABC-2 X fix)" "$(card_answer ABC-3 X chore)"
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
  "$E" task start demo ABC-1 >/dev/null 2>&1 && fail "accepted a project with no repos"
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
  is_link_to "$T/abc-1-x/CLAUDE.md" ../../PROJECT.md || fail "CLAUDE.md not linked to the project doc"
  is_link_to "$T/abc-1-x/AGENTS.md" ../../PROJECT.md || fail "AGENTS.md not linked to the project doc"
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
  "$E" project new demo >/dev/null
  make_git_repo "$HOME/Dev/my api"
  "$E" project add demo "$HOME/Dev/my api" >/dev/null
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
  "$E" project add demo "$HOME/Dev/web" >/dev/null
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
task_new_takes_the_agent_from_the_env_file() {
  card_demo; stub myagent
  echo 'ENTOURAGE_AGENT=myagent' > "$(env_file)"
  "$E" task new demo ABC-122 >/dev/null || fail "task new exited non-zero"
  case $(last_call) in
    *'"argv":["myagent"]'*) ;;
    *) fail "did not start the agent the env file names: $(last_call)" ;;
  esac
}

task_new_prefers_an_exported_agent_to_the_env_file() {
  card_demo; stub myagent; stub other
  echo 'ENTOURAGE_AGENT=myagent' > "$(env_file)"
  ENTOURAGE_AGENT=other "$E" task new demo ABC-122 >/dev/null || fail "task new exited non-zero"
  case $(last_call) in
    *'"argv":["other"]'*) ;;
    *) fail "did not start the exported agent: $(last_call)" ;;
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
  # The stand-in curl goes first on PATH, before jq is hidden.
  card_demo; saved_key; stub_linear; hide_jq
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

CARD_CASES="task_new_refuses_a_card_linear_does_not_have task_new_starts_a_card_linear_has
  task_new_asks_linear_nothing_without_a_key task_new_starts_anyway_when_linear_is_out_of_reach
  task_new_starts_anyway_with_a_key_linear_rejects task_new_starts_anyway_when_the_answer_lists_no_cards
  task_new_starts_anyway_without_curl task_new_starts_anyway_without_jq
  task_new_takes_the_agent_from_the_env_file task_new_prefers_an_exported_agent_to_the_env_file
  task_new_starts_an_agent task_new_sends_one_line_of_json task_new_takes_a_lowercase_card
  task_new_makes_no_task_folder task_new_selects_an_open_space task_new_refuses_a_branch
  task_new_refuses_a_bad_card task_new_refuses_unknown_project task_new_needs_the_skills_linked
  task_new_needs_an_agent task_new_honors_the_agent_setting task_new_needs_herdr_running
  task_new_says_when_the_tab_fails task_new_escapes_the_folder
  task_new_trusts_a_project_made_before task_new_trusts_before_the_tab_opens
  task_new_leaves_trusted_claude_state_alone task_new_starts_when_trust_cannot_be_written
  task_new_does_not_trust_a_linked_project"

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
  task_start_runs_setup_several_repos task_start_skips_setup_without_a_recipe
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

# A worktree takes the trust of its repo's own checkout, never of the project
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

# With several repos the tab is in the task folder, inside the project folder
# that project new trusts.
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

task_start_starts_when_the_store_cannot_be_written() {
  task_demo api
  mkdir -p "$HOME/.config/entourage/entourage.db"
  out=$("$E" task start demo ABC-1) || fail "task start exited non-zero with a store it cannot write"
  [ -d "$T/abc-1-x/api" ] || fail "no worktree"
  case $out in *"could not record"*) ;; *) fail "did not say the start was not recorded: $out" ;; esac
}

# The project "demo" as task start leaves it for the card ABC-1: skills
# linked, the task's folder with a worktree's folder in it, and an agent on
# PATH that notes where it ran and what it was told.
build_demo() {
  "$E" install >/dev/null
  "$E" project new demo >/dev/null
  cat > "$TMP/bin/claude" <<EOF
#!/usr/bin/env bash
pwd -P > "$TMP/agent-folder"
printf '%s' "\$*" > "$TMP/agent-message"
EOF
  chmod +x "$TMP/bin/claude"
  WT=$P/demo/tasks/abc-1-x/api
  mkdir -p "$WT"
}
agent_ran() { [ -e "$TMP/agent-folder" ]; }

task_build_starts_the_agent() {
  build_demo
  (cd "$WT" && "$E" task build demo abc-1) || fail "task build exited non-zero"
  agent_ran || fail "the agent did not start"
  [ "$(cat "$TMP/agent-folder")" = "$WT" ] || fail "the agent started in $(cat "$TMP/agent-folder")"
  local msg want d
  msg=$(cat "$TMP/agent-message")
  for want in "Linear card ABC-1" "entourage project \`demo\`" sdlc-build sdlc-review "entourage task handoff demo ABC-1"; do
    case $msg in *"$want"*) ;; *) fail "the first message does not mention '$want': $msg" ;; esac
  done
  case $msg in *"{card}"* | *"{project}"*) fail "a placeholder was left in the first message: $msg" ;; esac
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

task_build_needs_an_agent() {
  build_demo
  rm "$TMP/bin/claude"
  (cd "$WT" && "$E" task build demo ABC-1) >/dev/null 2>"$TMP/err" && fail "exited zero with no agent on PATH"
  grep -q ENTOURAGE_AGENT "$TMP/err" || fail "did not name the setting: $(cat "$TMP/err")"
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
  agent_ran && fail "the agent started"
}

BUILD_CASES="task_start_starts_the_agent_in_the_tab task_start_says_how_to_start_the_agent_without_hc
  task_start_notes_a_repo_claude_code_has_not_trusted task_start_says_nothing_of_a_trusted_repo
  task_start_says_nothing_of_trust_for_several_repos task_start_records_the_start
  task_start_starts_when_the_store_cannot_be_written task_build_starts_the_agent
  task_build_refuses_outside_the_cards_task task_build_needs_an_agent task_build_needs_the_skills_linked"

# --- tasks: targets ---------------------------------------------------------

task_start_one_target_with_a_group() {
  setup_on
  stub_just; stub_hc; task_demo api web; give_setup api
  out=$("$E" task start demo ABC-1 api:athlete) || fail "task start exited non-zero"
  [ "$(branch_of "$T/abc-1-x/api")" = feat/abc-1-x ] || fail "no worktree for the named repo"
  [ ! -e "$T/abc-1-x/web" ] || fail "made a worktree for a repo that was not named"
  has_branch "$HOME/Dev/web" feat/abc-1-x && fail "made a branch in a repo that was not named"
  [ ! -e "$T/abc-1-x/CLAUDE.md" ] && [ ! -L "$T/abc-1-x/CLAUDE.md" ] || fail "linked the project doc beside one repo"
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
  is_link_to "$T/abc-1-x/CLAUDE.md" ../../PROJECT.md || fail "no project doc link for a task of several repos"
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
  grep -q api "$TMP/err" && grep -q web "$TMP/err" || fail "did not list the project's repos: $(cat "$TMP/err")"
}

TARGET_CASES="task_start_refuses_bad_groups_in_any_locale task_start_does_not_fetch_an_unnamed_repo
  task_start_one_target_with_a_group task_start_several_groups task_start_several_targets
  task_start_a_target_without_a_group task_start_ignores_an_unnamed_broken_repo
  task_start_refuses_bad_targets task_start_refuses_a_repo_named_twice
  task_start_lists_repos_for_an_unknown_target"

CASES="$TARGET_CASES $SETUP_CASES $BUILD_CASES $CARD_CASES $CARD_START_CASES
  task_start_refuses_a_repo_with_no_commits task_start_undoes_an_interrupted_run
  task_start_keeps_the_task_when_the_space_fails task_start_branch_has_no_upstream
  task_start_refusal_keeps_the_first_task task_start_refusal_keeps_an_existing_branch
  task_start_over_a_folder_deleted_by_hand task_start_leaves_other_worktrees_alone
  task_start_opens_a_tab_one_repo task_start_opens_a_tab_several_repos task_start_selects_an_open_space
  task_start_needs_herdr_running task_start_repo_path_with_a_space task_start_keeps_the_task_when_the_tab_fails
  task_start_several_repos task_start_one_repo_has_no_links task_start_undoes_a_failed_run
  task_start_refuses_unknown_project task_usage_on_unknown_subcommand
  task_start_makes_a_worktree task_start_starts_from_the_latest_default_branch
  task_start_works_offline task_start_without_origin_uses_local_default task_start_refuses_no_repos
  task_start_refuses_missing_repo task_start_refuses_existing_task task_start_refuses_existing_branch
  task_start_refuses_branch_on_origin task_start_leaves_the_main_checkout_alone task_start_after_hand_deletion"
