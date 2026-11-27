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
  for want in "Linear card ABC-122" sdlc-define sdlc-plan sdlc-breakdown "entourage task start demo "; do
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
    *"  trusted   "* | *"  note      "*) fail "spoke of trust when there was nothing to do: $out" ;;
  esac
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

task_start_refuses_bad_branch() {
  "$E" project new demo >/dev/null
  for b in main master develop abc-122-x Feature/Add-Login feature/new--login \
           feature/-new-login feature/new-login- release/v1.-2.0 "fix/header bug" \
           fix/header_bug unknown/some-task feat/ feat/a/b ""; do
    "$E" task start demo "$b" >/dev/null 2>"$TMP/err" && fail "accepted the branch '$b'"
    grep -q conventionalbranch.org "$TMP/err" || fail "no naming hint for '$b'"
  done
  [ ! -e "$P/demo/tasks" ] || fail "made a tasks folder for a refused branch"
}

task_start_refuses_unknown_project() {
  "$E" task start nope feat/abc-1-x >/dev/null 2>&1 && fail "accepted a project that does not exist"
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

# The project "demo" with a real repo for each name given.
task_demo() {
  local r
  "$E" project new demo >/dev/null
  for r in "$@"; do
    make_git_repo "$HOME/Dev/$r"
    "$E" project add demo "$HOME/Dev/$r" >/dev/null
  done
  API=$HOME/Dev/api T=$P/demo/tasks
}

task_start_makes_a_worktree() {
  task_demo api
  "$E" task start demo feat/abc-122-insert-task-here >/dev/null || fail "task start exited non-zero"
  local wt=$T/abc-122-insert-task-here/api
  [ -d "$wt" ] || fail "no worktree at tasks/<task>/<repo>"
  [ "$(branch_of "$wt")" = feat/abc-122-insert-task-here ] || fail "worktree is on $(branch_of "$wt")"
  [ "$(head_of "$wt")" = "$(head_of "$API" origin/main)" ] || fail "not cut from origin/main"
}

task_start_accepts_every_spec_name() {
  task_demo api
  local b
  for b in feature/add-login-page feat/add-login-page2 bugfix/fix-header-bug fix/header-bug \
           hotfix/security-patch release/v1.2.0 chore/upgrade-node-v20.11 \
           feature/issue-123-new-login ai/refactor-auth-flow claude/security-patch2 \
           codex/optimize-query copilot/add-login-page3 cursor/fix-header-bug4; do
    "$E" task start demo "$b" >/dev/null 2>&1 || fail "refused the valid branch '$b'"
    [ -d "$T/${b#*/}/api" ] || fail "no worktree for '$b'"
  done
}

task_start_starts_from_the_latest_default_branch() {
  task_demo api
  git clone -q "$API.origin.git" "$TMP/other"
  git -C "$TMP/other" -c user.name=t -c user.email=t@t commit -q --allow-empty -m newer
  git -C "$TMP/other" push -q origin main
  "$E" task start demo feat/x >/dev/null || fail "task start exited non-zero"
  [ "$(head_of "$T/x/api")" = "$(head_of "$TMP/other")" ] || fail "did not start from the fetched commit"
}

task_start_works_offline() {
  task_demo api
  git -C "$API" remote set-url origin "$TMP/gone.git"
  local out
  out=$("$E" task start demo feat/x 2>/dev/null) || fail "task start exited non-zero offline"
  case $out in *warning*) ;; *) fail "no warning about the failed fetch: $out" ;; esac
  [ -d "$T/x/api" ] || fail "no worktree made offline"
}

task_start_without_origin_uses_local_default() {
  task_demo api
  git -C "$API" remote remove origin
  "$E" task start demo feat/x >/dev/null || fail "task start exited non-zero with no origin"
  [ "$(head_of "$T/x/api")" = "$(head_of "$API" main)" ] || fail "not cut from local main"
}

task_start_refuses_no_repos() {
  task_demo
  "$E" task start demo feat/x >/dev/null 2>&1 && fail "accepted a project with no repos"
  [ ! -e "$T" ] || fail "made a tasks folder"
}

task_start_refuses_missing_repo() {
  task_demo api
  echo "$HOME/Dev/gone" >> "$P/demo/repos"
  "$E" task start demo feat/x >/dev/null 2>&1 && fail "accepted a missing repo"
  [ ! -e "$T" ] || fail "made a tasks folder"
  has_branch "$API" feat/x && fail "made a branch in the repo that exists"
}

task_start_refuses_existing_task() {
  task_demo api
  "$E" task start demo feat/x >/dev/null || fail "first task start exited non-zero"
  "$E" task start demo fix/x >/dev/null 2>&1 && fail "made a second task with the same name"
  has_branch "$API" fix/x && fail "made the second task's branch"
}

task_start_refuses_existing_branch() {
  task_demo api
  git -C "$API" branch feat/x
  "$E" task start demo feat/x >/dev/null 2>&1 && fail "reused an existing branch"
  [ ! -e "$T/x" ] || fail "made a task folder"
}

task_start_refuses_branch_on_origin() {
  task_demo api
  git -C "$API.origin.git" branch feat/x
  "$E" task start demo feat/x >/dev/null 2>&1 && fail "reused a branch that is on origin"
  [ ! -e "$T/x" ] || fail "made a task folder"
  has_branch "$API" feat/x && fail "made a local branch"
}

task_start_leaves_the_main_checkout_alone() {
  task_demo api
  git -C "$API" checkout -q -b wip
  echo mine > "$API/untracked.txt"
  local before
  before=$(branch_of "$API"):$(git -C "$API" status --porcelain)
  "$E" task start demo feat/x >/dev/null || fail "task start exited non-zero"
  [ "$(branch_of "$API"):$(git -C "$API" status --porcelain)" = "$before" ] || fail "the main checkout changed"
}

task_start_after_hand_deletion() {
  task_demo api
  "$E" task start demo feat/x >/dev/null || fail "first task start exited non-zero"
  rm -rf "$T/x"
  git -C "$API" branch -q -D feat/x 2>/dev/null || { git -C "$API" worktree prune; git -C "$API" branch -q -D feat/x; }
  "$E" task start demo feat/x >/dev/null 2>&1 || fail "could not remake a task deleted by hand"
  [ -d "$T/x/api" ] || fail "no worktree after remaking"
}

task_start_several_repos() {
  task_demo api web
  "$E" task start demo feat/x >/dev/null || fail "task start exited non-zero"
  [ "$(branch_of "$T/x/api")" = feat/x ] || fail "api worktree not on feat/x"
  [ "$(branch_of "$T/x/web")" = feat/x ] || fail "web worktree not on feat/x"
  is_link_to "$T/x/CLAUDE.md" ../../PROJECT.md || fail "CLAUDE.md not linked to the project doc"
  is_link_to "$T/x/AGENTS.md" ../../PROJECT.md || fail "AGENTS.md not linked to the project doc"
  [ -f "$T/x/CLAUDE.md" ] || fail "the CLAUDE.md link does not resolve"
}

task_start_one_repo_has_no_links() {
  task_demo api
  "$E" task start demo feat/x >/dev/null || fail "task start exited non-zero"
  [ ! -e "$T/x/CLAUDE.md" ] && [ ! -L "$T/x/CLAUDE.md" ] || fail "linked CLAUDE.md beside a single repo"
}

task_start_undoes_a_failed_run() {
  task_demo api web
  # A file where git keeps its worktrees makes `git worktree add` fail in web.
  : > "$HOME/Dev/web/.git/worktrees"
  "$E" task start demo feat/x >/dev/null 2>&1 && fail "exited zero when a worktree could not be made"
  rm -f "$HOME/Dev/web/.git/worktrees"
  [ ! -e "$T/x" ] || fail "left the task folder behind"
  has_branch "$API" feat/x && fail "left the branch behind in api"
  has_branch "$HOME/Dev/web" feat/x && fail "left the branch behind in web"
  [ "$(git -C "$API" worktree list | wc -l | tr -d ' ')" = 1 ] || fail "left the worktree behind in api"
}

task_start_opens_a_tab_one_repo() {
  task_demo api
  "$E" task start demo feat/x >/dev/null || fail "task start exited non-zero"
  [ "$(last_call)" = "do tab.new {\"name\":\"x\",\"folder\":\"$T/x/api\"}" ] || fail "wrong last call: $(last_call)"
  sed '$d' "$TMP/herdr-calls.log" | grep -qF "do space.new {\"name\":\"demo\",\"folder\":\"$P/demo\"}" ||
    fail "did not make the space before the tab: $(cat "$TMP/herdr-calls.log")"
}

task_start_opens_a_tab_several_repos() {
  task_demo api web
  "$E" task start demo feat/x >/dev/null || fail "task start exited non-zero"
  [ "$(last_call)" = "do tab.new {\"name\":\"x\",\"folder\":\"$T/x\"}" ] || fail "wrong last call: $(last_call)"
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
  "$E" task start demo feat/x >/dev/null || fail "task start exited non-zero"
  grep -qF 'do space.select {"id":"spcmine"}' "$TMP/herdr-calls.log" || fail "did not select the open space"
  grep -q 'space.new' "$TMP/herdr-calls.log" && fail "made a second space"
  case $(last_call) in "do tab.new "*) ;; *) fail "the tab was not opened last: $(last_call)" ;; esac
}

task_start_needs_herdr_running() {
  task_demo api
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/herdr-app"
  "$E" task start demo feat/x >/dev/null 2>"$TMP/err" && fail "exited zero with Herdr not running"
  grep -q 'not running' "$TMP/err" || fail "did not say Herdr is not running: $(cat "$TMP/err")"
  [ ! -e "$T" ] || fail "made a tasks folder"
  has_branch "$API" feat/x && fail "made a branch"
}

task_start_repo_path_with_a_space() {
  "$E" project new demo >/dev/null
  make_git_repo "$HOME/Dev/my api"
  "$E" project add demo "$HOME/Dev/my api" >/dev/null
  "$E" task start demo feat/x >/dev/null || fail "task start exited non-zero"
  [ "$(branch_of "$P/demo/tasks/x/my api")" = feat/x ] || fail "no worktree at a path with a space"
  [ "$(last_call)" = "do tab.new {\"name\":\"x\",\"folder\":\"$P/demo/tasks/x/my api\"}" ] || fail "wrong last call: $(last_call)"
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
  "$E" task start demo feat/x >/dev/null 2>"$TMP/err" && fail "exited zero when the tab could not be opened"
  [ -d "$T/x/api" ] || fail "removed the task"
  grep -qF "$T/x/api" "$TMP/err" || fail "did not say where the task is: $(cat "$TMP/err")"
}

# --- tasks: what must survive, and what must not be left half-made ----------

task_start_refuses_a_repo_with_no_commits() {
  task_demo api
  git init -q -b main "$HOME/Dev/web"
  "$E" project add demo "$HOME/Dev/web" >/dev/null
  "$E" task start demo feat/x >/dev/null 2>&1 && fail "accepted a repo with no commits"
  [ ! -e "$T" ] || fail "left a tasks folder behind"
  has_branch "$API" feat/x && fail "left the branch behind in api"
}

# web's post-checkout hook interrupts entourage while it is making worktrees.
task_start_undoes_an_interrupted_run() {
  task_demo api web
  mkdir -p "$HOME/Dev/web/.git/hooks"
  printf '#!/bin/sh\nkill -TERM "$(ps -o ppid= -p $PPID | tr -d " ")"\n' > "$HOME/Dev/web/.git/hooks/post-checkout"
  chmod +x "$HOME/Dev/web/.git/hooks/post-checkout"
  "$E" task start demo feat/x >/dev/null 2>&1 && fail "exited zero after being interrupted"
  [ ! -e "$T" ] || fail "left a tasks folder behind: $(ls "$T" "$T"/* 2>/dev/null | tr '\n' ' ')"
  has_branch "$API" feat/x && fail "left the branch behind in api"
  has_branch "$HOME/Dev/web" feat/x && fail "left the branch behind in web"
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
  "$E" task start demo feat/x >/dev/null 2>"$TMP/err" && fail "exited zero when the space could not be shown"
  [ -d "$T/x/api" ] || fail "removed the task"
  grep -qF "$T/x/api" "$TMP/err" || fail "did not say where the task is: $(cat "$TMP/err")"
}

task_start_branch_has_no_upstream() {
  task_demo api
  "$E" task start demo feat/x >/dev/null || fail "task start exited non-zero"
  git -C "$T/x/api" rev-parse -q --verify '@{u}' >/dev/null 2>&1 && fail "the new branch tracks $(git -C "$T/x/api" rev-parse --abbrev-ref '@{u}')"
}

task_start_refusal_keeps_the_first_task() {
  task_demo api
  "$E" task start demo feat/x >/dev/null || fail "first task start exited non-zero"
  echo work > "$T/x/api/work.txt"
  "$E" task start demo fix/x >/dev/null 2>&1 && fail "made a second task with the same name"
  [ "$(cat "$T/x/api/work.txt" 2>/dev/null)" = work ] || fail "the first task's work is gone"
  [ "$(branch_of "$T/x/api")" = feat/x ] || fail "the first task's worktree is gone"
}

task_start_refusal_keeps_an_existing_branch() {
  task_demo api
  git -C "$API" branch feat/x
  local before
  before=$(head_of "$API" feat/x)
  "$E" task start demo feat/x >/dev/null 2>&1 && fail "reused an existing branch"
  has_branch "$API" feat/x || fail "deleted the branch that was already there"
  [ "$(head_of "$API" feat/x)" = "$before" ] || fail "moved the branch that was already there"
}

# A task folder deleted by hand leaves git thinking its worktree is still there.
task_start_over_a_folder_deleted_by_hand() {
  task_demo api
  "$E" task start demo feat/x >/dev/null || fail "first task start exited non-zero"
  rm -rf "$T/x"
  "$E" task start demo fix/x >/dev/null 2>&1 || fail "could not make a task where one was deleted by hand"
  [ "$(branch_of "$T/x/api")" = fix/x ] || fail "no worktree on fix/x"
}

# A worktree whose folder is away for a while (an unmounted drive) must still work when it is back.
task_start_leaves_other_worktrees_alone() {
  task_demo api
  mkdir -p "$TMP/drive"
  git -C "$API" worktree add -q -b other "$TMP/drive/other" main
  echo staged > "$TMP/drive/other/f.txt"; git -C "$TMP/drive/other" add f.txt
  mv "$TMP/drive" "$TMP/drive.away"
  "$E" task start demo feat/x >/dev/null || fail "task start exited non-zero"
  mv "$TMP/drive.away" "$TMP/drive"
  [ "$(git -C "$TMP/drive/other" status --porcelain 2>/dev/null)" = "A  f.txt" ] || fail "another worktree was broken: $(git -C "$TMP/drive/other" status --porcelain 2>&1)"
}

CARD_CASES="task_new_starts_an_agent task_new_sends_one_line_of_json task_new_takes_a_lowercase_card
  task_new_makes_no_task_folder task_new_selects_an_open_space task_new_refuses_a_branch
  task_new_refuses_a_bad_card task_new_refuses_unknown_project task_new_needs_the_skills_linked
  task_new_needs_an_agent task_new_honors_the_agent_setting task_new_needs_herdr_running
  task_new_says_when_the_tab_fails task_new_escapes_the_folder
  task_new_trusts_a_project_made_before task_new_trusts_before_the_tab_opens
  task_new_leaves_trusted_claude_state_alone task_new_starts_when_trust_cannot_be_written"

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

task_start_runs_setup_one_repo() {
  stub_just; stub_hc; task_demo api; give_setup api
  out=$("$E" task start demo feat/x) || fail "task start exited non-zero"
  [ "$(hc_calls)" = "send t9 just setup" ] || fail "wrong hc calls: $(hc_calls)"
  case $out in *"setup     api (running in the tab)"*) ;; *) fail "did not report setup: $out" ;; esac
}

task_start_sends_setup_to_the_new_tab() {
  stub_just; stub_hc; task_demo api; give_setup api
  cat > "$TMP/bin/herdr-app" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$TMP/herdr-calls.log"
[ "\$1" = status ] && echo '  "layout": "test",'
[ "\$2" = tab.new ] && printf '{\n  "space": "sp1",\n  "tab": "tb1",\n  "terminal": "t42"\n}\n'
exit 0
EOF
  "$E" task start demo feat/x >/dev/null || fail "task start exited non-zero"
  [ "$(hc_calls)" = "send t42 just setup" ] || fail "did not use the terminal tab.new named: $(hc_calls)"
}

task_start_runs_setup_several_repos() {
  stub_just; stub_hc; task_demo api web docs; give_setup api; give_setup docs
  out=$("$E" task start demo feat/x) || fail "task start exited non-zero"
  [ "$(hc_calls)" = "send t9 (cd ./'api' && just setup) && (cd ./'docs' && just setup)" ] || fail "wrong hc calls: $(hc_calls)"
  case $out in *"setup     web skipped: no justfile"*) ;; *) fail "did not report the skipped repo: $out" ;; esac
  case $out in *"setup     docs (running in the tab)"*) ;; *) fail "did not report docs: $out" ;; esac
}

task_start_skips_setup_without_a_recipe() {
  stub_just; stub_hc; task_demo api; give_setup api 'setup-db:\n\techo\npresetup:\n\techo\n'
  out=$("$E" task start demo feat/x) || fail "task start exited non-zero"
  [ -z "$(hc_calls)" ] || fail "typed into the tab: $(hc_calls)"
  case $out in *"setup     api skipped: its justfile has no setup recipe"*) ;; *) fail "did not say why: $out" ;; esac
}

task_start_skips_an_unreadable_justfile() {
  stub_just; stub_hc; task_demo api; give_setup api 'BROKEN\nsetup:\n\techo\n'
  out=$("$E" task start demo feat/x) || fail "task start exited non-zero"
  [ -z "$(hc_calls)" ] || fail "typed into the tab: $(hc_calls)"
  case $out in *"setup     api skipped: its justfile could not be read by just"*) ;; *) fail "did not say why: $out" ;; esac
}

task_start_ignores_a_parent_justfile() {
  export ENTOURAGE_HOME=$TMP/outer
  mkdir -p "$ENTOURAGE_HOME"
  printf 'setup:\n\techo\n' > "$ENTOURAGE_HOME/justfile"
  stub_just; stub_hc; task_demo api
  out=$("$E" task start demo feat/x) || fail "task start exited non-zero"
  [ -d "$ENTOURAGE_HOME/projects/demo/tasks/x/api" ] || fail "no worktree"
  [ -z "$(hc_calls)" ] || fail "ran a justfile from above the task: $(hc_calls)"
  case $out in *"setup     api skipped: no justfile"*) ;; *) fail "did not report the skip: $out" ;; esac
}

task_start_quotes_repo_names() {
  stub_just; stub_hc; task_demo "my api" "it's"; give_setup "my api"; give_setup "it's"
  "$E" task start demo feat/x >/dev/null || fail "task start exited non-zero"
  [ "$(hc_calls)" = "send t9 (cd ./'my api' && just setup) && (cd ./'it'\\''s' && just setup)" ] || fail "wrong hc calls: $(hc_calls)"
}

task_start_without_just() {
  stub_hc; task_demo api; give_setup api
  out=$("$E" task start demo feat/x) || fail "task start exited non-zero without just"
  [ -d "$T/x/api" ] || fail "no worktree"
  [ -z "$(hc_calls)" ] || fail "typed into the tab: $(hc_calls)"
  case $out in *"just is not installed"*"https://just.systems"*) ;; *) fail "did not say just is missing: $out" ;; esac
}

task_start_without_hc() {
  stub_just; task_demo api; give_setup api
  out=$("$E" task start demo feat/x) || fail "task start exited non-zero without hc"
  [ -d "$T/x/api" ] || fail "no worktree"
  case $out in *"run it yourself in the tab: just setup"*) ;; *) fail "did not say what to run: $out" ;; esac
}

task_start_without_a_terminal() {
  stub_just; stub_hc; task_demo api; give_setup api
  cat > "$TMP/bin/herdr-app" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$TMP/herdr-calls.log"
[ "\$1" = status ] && echo '  "layout": "test",'
exit 0
EOF
  out=$("$E" task start demo feat/x) || fail "task start exited non-zero with no terminal"
  [ -z "$(hc_calls)" ] || fail "typed somewhere without a terminal: $(hc_calls)"
  [ -d "$T/x/api" ] || fail "no worktree"
  case $out in *"run it yourself in the tab: just setup"*) ;; *) fail "did not say what to run: $out" ;; esac
}

task_start_when_hc_send_fails() {
  stub_just; stub_hc 1; task_demo api; give_setup api
  out=$("$E" task start demo feat/x) || fail "task start exited non-zero when hc failed"
  [ -d "$T/x/api" ] || fail "no worktree"
  case $out in *"run it yourself in the tab: just setup"*) ;; *) fail "did not say what to run: $out" ;; esac
  case $out in *"running in the tab"*) fail "said setup is running when it could not be started: $out" ;; esac
}

SETUP_CASES="task_start_runs_setup_one_repo task_start_sends_setup_to_the_new_tab
  task_start_runs_setup_several_repos task_start_skips_setup_without_a_recipe
  task_start_skips_an_unreadable_justfile task_start_ignores_a_parent_justfile
  task_start_quotes_repo_names task_start_without_just task_start_without_hc
  task_start_without_a_terminal task_start_when_hc_send_fails"

# --- tasks: targets ---------------------------------------------------------

task_start_one_target_with_a_group() {
  stub_just; stub_hc; task_demo api web; give_setup api
  out=$("$E" task start demo feat/x api:athlete) || fail "task start exited non-zero"
  [ "$(branch_of "$T/x/api")" = feat/x ] || fail "no worktree for the named repo"
  [ ! -e "$T/x/web" ] || fail "made a worktree for a repo that was not named"
  has_branch "$HOME/Dev/web" feat/x && fail "made a branch in a repo that was not named"
  [ ! -e "$T/x/CLAUDE.md" ] && [ ! -L "$T/x/CLAUDE.md" ] || fail "linked the project doc beside one repo"
  [ "$(hc_calls)" = "send t9 just setup athlete" ] || fail "wrong hc calls: $(hc_calls)"
  [ "$(last_call)" = "do tab.new {\"name\":\"x\",\"folder\":\"$T/x/api\"}" ] || fail "the tab is not in the worktree: $(last_call)"
  case $out in *"setup     api athlete (running in the tab)"*) ;; *) fail "did not report the group: $out" ;; esac
}

task_start_several_groups() {
  stub_just; stub_hc; task_demo api; give_setup api
  "$E" task start demo feat/x api:athlete,coach >/dev/null || fail "task start exited non-zero"
  [ "$(hc_calls)" = "send t9 just setup athlete coach" ] || fail "wrong hc calls: $(hc_calls)"
}

task_start_several_targets() {
  stub_just; stub_hc; task_demo api web docs; give_setup api; give_setup web
  "$E" task start demo feat/x web:coach api >/dev/null || fail "task start exited non-zero"
  [ "$(hc_calls)" = "send t9 (cd ./'api' && just setup) && (cd ./'web' && just setup coach)" ] || fail "wrong hc calls: $(hc_calls)"
  [ -d "$T/x/api" ] && [ -d "$T/x/web" ] || fail "missing a named repo's worktree"
  [ ! -e "$T/x/docs" ] || fail "made a worktree for a repo that was not named"
  is_link_to "$T/x/CLAUDE.md" ../../PROJECT.md || fail "no project doc link for a task of several repos"
  [ "$(last_call)" = "do tab.new {\"name\":\"x\",\"folder\":\"$T/x\"}" ] || fail "the tab is not in the task folder: $(last_call)"
}

task_start_a_target_without_a_group() {
  stub_just; stub_hc; task_demo api web; give_setup web
  "$E" task start demo feat/x web >/dev/null || fail "task start exited non-zero"
  [ "$(hc_calls)" = "send t9 just setup" ] || fail "wrong hc calls: $(hc_calls)"
  [ ! -e "$T/x/api" ] || fail "made a worktree for a repo that was not named"
}

# A repo the task did not name can be broken without stopping it.
task_start_ignores_an_unnamed_broken_repo() {
  task_demo api web
  rm -rf "$HOME/Dev/web"
  "$E" task start demo feat/x api >/dev/null 2>&1 || fail "a missing repo that was not named stopped the task"
  [ -d "$T/x/api" ] || fail "no worktree"
}

task_start_refuses_bad_targets() {
  task_demo api web
  local t
  for t in nope api:athlete,nope/x "api:" "api:a,,b" "api:Athlete" "api:a b" "api:a;b" 'api:$x' "api:a'b" "api:-a" ":athlete" \
           "api:a:b" "api:a
b" "api:a
"; do
    "$E" task start demo feat/x "$t" >/dev/null 2>&1 && fail "accepted the target '$t'"
    [ ! -e "$T" ] || { fail "made a tasks folder for the target '$t'"; rm -rf "$T"; }
    has_branch "$API" feat/x && fail "made a branch for the target '$t'"
  done
}

# What counts as a letter must not depend on the caller's locale: in some, a
# range like a-z takes in uppercase letters and even shell punctuation.
task_start_refuses_bad_groups_in_any_locale() {
  task_demo api
  local loc t
  for loc in en_US.ISO8859-1 en_US.US-ASCII kk_KZ.PT154; do
    for t in "api:Athlete" 'api:a$(id)' "api:a|b" "api:a&&b"; do
      LC_ALL=$loc "$E" task start demo feat/x "$t" >/dev/null 2>&1 && fail "accepted '$t' under $loc"
      [ ! -e "$T" ] || { fail "made a tasks folder for '$t' under $loc"; rm -rf "$T"; git -C "$API" worktree prune; git -C "$API" branch -q -D feat/x; }
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
  "$E" task start demo feat/x api >/dev/null || fail "task start exited non-zero"
  [ "$(head_of "$HOME/Dev/web" origin/main)" = "$before" ] || fail "fetched a repo that was not named"
}

task_start_refuses_a_repo_named_twice() {
  task_demo api web
  "$E" task start demo feat/x api:athlete api:coach >/dev/null 2>"$TMP/err" && fail "accepted a repo named twice"
  grep -q comma "$TMP/err" || fail "did not say to use a comma: $(cat "$TMP/err")"
  [ ! -e "$T" ] || fail "made a tasks folder"
}

task_start_lists_repos_for_an_unknown_target() {
  task_demo api web
  "$E" task start demo feat/x nope >/dev/null 2>"$TMP/err" && fail "accepted an unknown repo"
  grep -q api "$TMP/err" && grep -q web "$TMP/err" || fail "did not list the project's repos: $(cat "$TMP/err")"
}

TARGET_CASES="task_start_refuses_bad_groups_in_any_locale task_start_does_not_fetch_an_unnamed_repo
  task_start_one_target_with_a_group task_start_several_groups task_start_several_targets
  task_start_a_target_without_a_group task_start_ignores_an_unnamed_broken_repo
  task_start_refuses_bad_targets task_start_refuses_a_repo_named_twice
  task_start_lists_repos_for_an_unknown_target"

CASES="$TARGET_CASES $SETUP_CASES $CARD_CASES task_start_refuses_a_repo_with_no_commits task_start_undoes_an_interrupted_run
  task_start_keeps_the_task_when_the_space_fails task_start_branch_has_no_upstream
  task_start_refusal_keeps_the_first_task task_start_refusal_keeps_an_existing_branch
  task_start_over_a_folder_deleted_by_hand task_start_leaves_other_worktrees_alone
  task_start_opens_a_tab_one_repo task_start_opens_a_tab_several_repos task_start_selects_an_open_space
  task_start_needs_herdr_running task_start_repo_path_with_a_space task_start_keeps_the_task_when_the_tab_fails
  task_start_several_repos task_start_one_repo_has_no_links task_start_undoes_a_failed_run
  task_start_refuses_bad_branch task_start_refuses_unknown_project task_usage_on_unknown_subcommand
  task_start_makes_a_worktree task_start_accepts_every_spec_name task_start_starts_from_the_latest_default_branch
  task_start_works_offline task_start_without_origin_uses_local_default task_start_refuses_no_repos
  task_start_refuses_missing_repo task_start_refuses_existing_task task_start_refuses_existing_branch
  task_start_refuses_branch_on_origin task_start_leaves_the_main_checkout_alone task_start_after_hand_deletion"
