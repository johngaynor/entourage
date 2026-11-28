# Tests for the guard on a worktree's copy of entourage (cli/lib/guard.sh):
# that it runs the commands that read and stops the rest, that it acts on the
# machine when asked, and that the installed copy is never stopped. Sourced by
# test/run.sh.

BLOCK='phase: build
status: done
next: review
summary: Built the export.'

# The hand-offs recorded in the case's store.
handoff_rows() { sqlite3 "$HOME/.config/entourage/entourage.db" 'select count(*) from handoffs' 2>/dev/null || true; }

# A repo at $1 with one commit on main and no origin.
plain_repo() {
  git init -q -b main "$1"
  git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
}

# A machine with something in each place entourage changes, made by the usual
# copy: Herdr's links and the skills, a project with a repo and a team, a
# hand-off, a saved Linear key, Claude Code's own file, an agent, and
# stand-ins for hc and Linear. Linear has the card ABC-122, of type feat. Then
# every call to a stand-in so far is forgotten.
guard_machine() {
  claude_state
  "$E" install >/dev/null
  plain_repo "$HOME/Dev/api"
  "$E" project new demo "$HOME/Dev/api" >/dev/null
  "$E" project team demo ABC >/dev/null
  "$E" task handoff demo ABC-122 <<< "$BLOCK" >/dev/null || fail "could not record a hand-off to start from"
  saved_key
  stub claude
  stub_hc
  stub_linear
  linear_answers "$(card_answer ABC-122 'Insert task here' feat)"
  rm -f "$TMP"/*-calls.log "$TMP/curl-stdin.log"
}

# Run the worktree's copy with the arguments given, and stdin as it is. It has
# to stop with the guard's message and leave the machine as it was: nothing
# changed under HOME, and nothing asked of Herdr, hc, Linear or the agent.
refused() {
  local before after out log
  as_worktree
  before=$(machine_snapshot)
  if out=$("$E" "$@" 2>&1); then fail "\`$*\` exited zero: $out"; fi
  case $out in
    "entourage: this is the copy of entourage in the worktree $REPO."*"ENTOURAGE_LIVE=1"*) ;;
    *) fail "\`$*\` did not stop with the guard's message: $out" ;;
  esac
  after=$(machine_snapshot)
  [ "$after" = "$before" ] ||
    fail "\`$*\` changed the machine: $(diff <(printf '%s\n' "$before") <(printf '%s\n' "$after"))"
  for log in herdr hc curl claude; do
    [ ! -s "$TMP/$log-calls.log" ] || fail "\`$*\` called $log: $(cat "$TMP/$log-calls.log")"
  done
}

# --- what a worktree's copy refuses -----------------------------------------

guard_refuses_install() { guard_machine; refused install; }
guard_refuses_update() { guard_machine; refused update; refused update --no-pull; }
guard_refuses_project_new() { guard_machine; refused project new other; }
guard_refuses_project_add() {
  guard_machine
  plain_repo "$HOME/Dev/web"
  refused project add demo "$HOME/Dev/web"
}
guard_refuses_project_open() { guard_machine; refused project open demo; }
guard_refuses_setting_a_projects_teams() { guard_machine; refused project team demo XYZ; }
guard_refuses_task_new() { guard_machine; refused task new demo ABC-122; }
guard_refuses_task_start() { guard_machine; refused task start demo ABC-122; }
guard_refuses_task_build() {
  guard_machine
  mkdir -p "$P/demo/tasks/abc-122-insert-task-here"
  cd "$P/demo/tasks/abc-122-insert-task-here" || return
  refused task build demo ABC-122
}
guard_refuses_task_handoff() {
  guard_machine
  refused task handoff demo ABC-122 <<< "$BLOCK"
  [ "$(handoff_rows)" = 1 ] || fail "the store has $(handoff_rows) hand-offs, not the one it started with"
}
guard_refuses_linear_key() { guard_machine; refused linear key <<< "lin_api_Other0123456789"; }
# The card skills' writes to Linear: a card's type, and a section on stdin.
guard_refuses_linear_type() { guard_machine; refused linear type ABC-122 feat; }
guard_refuses_linear_section() {
  guard_machine
  refused linear section ABC-122 Plan <<< "**Approach:** Build it."
  refused linear section ABC-122 Plan --replace <<< "**Approach:** Build it."
}
# Moving a card, as sdlc-pr does once its pull requests are open.
guard_refuses_linear_move() {
  guard_machine
  refused linear move ABC-122 review
  refused linear move ABC-122 started
  refused linear move ABC-122 done
}

# The guard lists what may run, so a command it does not know is refused,
# such as one added after it.
guard_refuses_a_command_it_does_not_know() {
  guard_machine
  refused linear nonsense ABC-122
  refused task nonsense demo
  refused project nonsense
  refused nonsense
}

# A copy in a worktree git itself made is a worktree's copy.
guard_knows_a_worktree_git_made() {
  guard_machine
  plain_repo "$TMP/src"
  git -C "$TMP/src" worktree add -q -b wt "$TMP/wt"
  cp -R "$REPO/cli" "$REPO/herdr" "$REPO/skills" "$REPO/prompts" "$TMP/wt/"
  local before out
  before=$(machine_snapshot)
  if out=$("$TMP/wt/cli/entourage" project new other 2>&1); then fail "project new exited zero: $out"; fi
  case $out in *"copy of entourage in the worktree $TMP/wt."*) ;; *) fail "did not stop with the guard's message: $out" ;; esac
  [ "$(machine_snapshot)" = "$before" ] || fail "changed the machine"
}

# --- what a worktree's copy runs --------------------------------------------

# One team's open statuses and one card in each, as Linear answers `task ls`.
TEAM_CARDS='{"data":{
  "teams":{"nodes":[{"key":"ABC"}]},
  "workflowStates":{"nodes":[
    {"name":"Backlog","type":"backlog","position":0,"team":{"key":"ABC"}},
    {"name":"In Progress","type":"started","position":1,"team":{"key":"ABC"}}]},
  "issues":{"nodes":[
    {"identifier":"ABC-2","title":"Second card","url":"https://linear.app/x/issue/ABC-2/second-card","updatedAt":"2024-02-01T00:00:00.000Z","state":{"name":"In Progress","type":"started"}},
    {"identifier":"ABC-1","title":"First card","url":"https://linear.app/x/issue/ABC-1/first-card","updatedAt":"2024-01-01T00:00:00.000Z","state":{"name":"Backlog","type":"backlog"}}],
    "pageInfo":{"hasNextPage":false,"endCursor":null}}}}'

# Every command that only reads, one to a line.
READS='help
status
project ls
project ls --json
project team demo
task ls demo
task ls demo --json
task log demo
task log demo --json
task log demo ABC-122
task log demo ABC-122 --json
task watch demo ABC-122 --once'

# Run every read, and print what each printed and how it exited. How long a
# card has stood where it is counts on from now, so it is left out.
all_reads() {
  local r code
  while IFS= read -r r; do
    printf '$ entourage %s\n' "$r"
    # shellcheck disable=SC2086
    "$E" $r 2>&1 && code=0 || code=$?
    printf '[exit %s]\n' "$code"
  done <<< "$READS" |
    sed -E -e 's/ for [0-9][0-9dhms ]*$/ for (time)/' -e 's/"for":"[^"]*","seconds":[0-9]+/"for":(time)/g'
}

# They print what the usual copy prints, and leave the machine exactly as it
# was, the hand-off store included.
guard_runs_the_reads_and_changes_nothing() {
  guard_machine
  linear_answers "$TEAM_CARDS"
  # A task for ABC-122 whose pull request is open, for `task watch`.
  git -C "$HOME/Dev/api" worktree add -q -b feat/abc-122-insert-task-here "$P/demo/tasks/abc-122-insert-task-here/api"
  stub_gh
  gh_answers api "$(pr_answer OPEN https://github.com/acme/api/pull/7 60)"
  local usual worktree before
  usual=$(all_reads)
  as_worktree
  before=$(machine_snapshot)
  worktree=$(all_reads)
  [ "$(machine_snapshot)" = "$before" ] ||
    fail "the reads changed the machine: $(diff <(printf '%s\n' "$before") <(machine_snapshot))"
  [ "$worktree" = "$usual" ] ||
    fail "a worktree's copy read otherwise: $(diff <(printf '%s\n' "$usual") <(printf '%s\n' "$worktree"))"
  case $usual in *'ABC-2  Second card'*'build done, then review'*'Built the export.'*) ;; *) fail "the reads did not show the cards and the hand-off: $usual" ;; esac
  case $usual in *'open https://github.com/acme/api/pull/7'$'\n''[exit 2]'*) ;; *) fail "the watch did not show the open pull request: $usual" ;; esac
  [ ! -s "$TMP/herdr-calls.log" ] || fail "a read called Herdr: $(cat "$TMP/herdr-calls.log")"
}

# A stand-in for sqlite3 that passes each call on to the real one, and notes
# whether it was asked to open the store read-only.
spy_sqlite() {
  local real
  real=$(command -v sqlite3)
  cat > "$TMP/bin/sqlite3" <<EOF
#!/usr/bin/env bash
ro=rw
for a in "\$@"; do [ "\$a" != -readonly ] || ro=ro; done
echo "\$ro" >> "$TMP/sqlite3-calls.log"
exec "$real" "\$@"
EOF
  chmod +x "$TMP/bin/sqlite3"
}

guard_opens_the_store_read_only() {
  guard_machine
  spy_sqlite
  "$E" task log demo ABC-122 >/dev/null || fail "the usual copy's task log exited non-zero"
  [ -s "$TMP/sqlite3-calls.log" ] || fail "the usual copy did not open the store"
  ! grep -qx ro "$TMP/sqlite3-calls.log" || fail "the usual copy opened the store read-only"
  rm -f "$TMP/sqlite3-calls.log"
  as_worktree
  "$E" task log demo ABC-122 >/dev/null || fail "a worktree's task log exited non-zero"
  "$E" task log demo --json >/dev/null || fail "a worktree's task log --json exited non-zero"
  [ -s "$TMP/sqlite3-calls.log" ] || fail "a worktree's copy did not open the store"
  ! grep -qx rw "$TMP/sqlite3-calls.log" || fail "a worktree's copy opened the store to write: $(cat "$TMP/sqlite3-calls.log")"
}

# --- asked, a worktree's copy acts on the machine ---------------------------

guard_runs_project_new_when_asked() {
  guard_machine
  as_worktree
  ENTOURAGE_LIVE=1 "$E" project new other >/dev/null 2>"$TMP/err" || fail "project new exited non-zero: $(cat "$TMP/err")"
  [ -f "$P/other/PROJECT.md" ] || fail "made no project"
  is_trusted "$P/other" || fail "did not trust the project's folder"
}

guard_runs_task_start_when_asked() {
  guard_machine
  as_worktree
  ENTOURAGE_LIVE=1 "$E" task start demo ABC-122 >/dev/null 2>"$TMP/err" || fail "task start exited non-zero: $(cat "$TMP/err")"
  local wt=$P/demo/tasks/abc-122-insert-task-here/api
  [ -d "$wt" ] || fail "made no worktree"
  [ "$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null)" = feat/abc-122-insert-task-here ] || fail "the worktree is not on the card's branch"
  [ "$(last_call)" = "do tab.new {\"name\":\"abc-122-insert-task-here\",\"folder\":\"$wt\"}" ] || fail "did not ask Herdr for the tab: $(last_call)"
  grep -q 'entourage task build demo ABC-122' "$TMP/hc-calls.log" || fail "did not start the agent in the tab: $(hc_calls)"
}

# Asked, the store is opened to write, so a hand-off is recorded.
guard_records_a_handoff_when_asked() {
  guard_machine
  as_worktree
  ENTOURAGE_LIVE=1 "$E" task handoff demo ABC-122 <<< "$BLOCK" >/dev/null || fail "task handoff exited non-zero"
  [ "$(handoff_rows)" = 2 ] || fail "the store has $(handoff_rows) hand-offs, not 2"
}

# Only 1 asks.
guard_takes_only_1_as_asking() {
  guard_machine
  ENTOURAGE_LIVE=yes refused project new other
  ENTOURAGE_LIVE=0 refused project new other
}

# Asking is for one run. A line in the env file would leave it on for every
# run, so the file cannot set it.
guard_does_not_take_asking_from_the_env_file() {
  guard_machine
  printf 'ENTOURAGE_LIVE=1\n' >> "$(env_file)"
  refused project new other
}

# --- the copy this machine runs is never stopped ----------------------------

# A worktree of some repo, to run commands from.
worktree_folder() {
  plain_repo "$TMP/src"
  git -C "$TMP/src" worktree add -q -b wt "$TMP/wt"
}

# The usual copy, a main checkout's, run from inside a worktree.
guard_never_stops_the_main_checkout() {
  worktree_folder
  cd "$TMP/wt" || return
  "$E" project new demo >/dev/null 2>"$TMP/err" || fail "project new exited non-zero: $(cat "$TMP/err")"
  "$E" task handoff demo ABC-122 <<< "$BLOCK" >/dev/null 2>"$TMP/err" || fail "task handoff exited non-zero: $(cat "$TMP/err")"
  [ "$(handoff_rows)" = 1 ] || fail "the store has $(handoff_rows) hand-offs, not 1"
}

# A copy with no .git, as npm installs it, run from inside a worktree.
guard_never_stops_an_npm_install() {
  rm -rf "$REPO/.git"
  worktree_folder
  cd "$TMP/wt" || return
  "$E" project new demo >/dev/null 2>"$TMP/err" || fail "project new exited non-zero: $(cat "$TMP/err")"
  "$E" task handoff demo ABC-122 <<< "$BLOCK" >/dev/null 2>"$TMP/err" || fail "task handoff exited non-zero: $(cat "$TMP/err")"
  [ "$(handoff_rows)" = 1 ] || fail "the store has $(handoff_rows) hand-offs, not 1"
}

# A .git file that is not a worktree's, such as a submodule's, or one under a
# folder that only happens to be called worktrees, is not guarded.
guard_leaves_other_git_files_alone() {
  rm -rf "$REPO/.git"
  printf 'gitdir: %s\n' "$TMP/super/.git/modules/repo" > "$REPO/.git"
  "$E" project new demo >/dev/null 2>"$TMP/err" || fail "with a submodule's .git: $(cat "$TMP/err")"
  printf 'gitdir: %s\n' "$TMP/worktrees/super/.git/modules/repo" > "$REPO/.git"
  "$E" project new other >/dev/null 2>"$TMP/err" || fail "under a folder called worktrees: $(cat "$TMP/err")"
}

# --- what the message says --------------------------------------------------

# It names the copy to run for the card's own steps, a test case to try a
# command that changes the machine, and the command that runs it for real,
# which does.
guard_says_which_copy_to_run() {
  guard_machine
  as_worktree
  local out want live
  out=$("$E" project new other 2>&1)
  for want in 'run plain `entourage`' 'write a test case' "ENTOURAGE_LIVE=1 $REPO/cli/entourage project new other"; do
    case $out in *"$want"*) ;; *) fail "the message does not say '$want': $out" ;; esac
  done
  # Only that command, so that nothing else the output holds is ever run.
  live=$(printf '%s\n' "$out" | tail -n 1)
  live=${live#"${live%%[![:space:]]*}"}
  [ "$live" = "ENTOURAGE_LIVE=1 $REPO/cli/entourage project new other" ] || { fail "the last line is not the command to run: $out"; return; }
  eval "$live" >/dev/null 2>"$TMP/err" || fail "the command it gives exited non-zero: $live: $(cat "$TMP/err")"
  [ -f "$P/other/PROJECT.md" ] || fail "the command it gives made no project: $live"
}

# A word with a space in it is quoted, so the command can be pasted.
guard_quotes_the_command_it_gives() {
  guard_machine
  as_worktree
  local out
  out=$("$E" project add demo "$HOME/My repos/web" 2>&1)
  case $out in *"ENTOURAGE_LIVE=1 $REPO/cli/entourage project add demo '$HOME/My repos/web'") ;; *) fail "did not quote the path: $out" ;; esac
}

CASES="guard_refuses_install guard_refuses_update guard_refuses_project_new
guard_refuses_project_add guard_refuses_project_open guard_refuses_setting_a_projects_teams
guard_refuses_task_new guard_refuses_task_start guard_refuses_task_build
guard_refuses_task_handoff guard_refuses_linear_key guard_refuses_linear_type guard_refuses_linear_section
guard_refuses_linear_move
guard_refuses_a_command_it_does_not_know
guard_knows_a_worktree_git_made
guard_runs_the_reads_and_changes_nothing guard_opens_the_store_read_only
guard_runs_project_new_when_asked guard_runs_task_start_when_asked guard_records_a_handoff_when_asked
guard_takes_only_1_as_asking guard_does_not_take_asking_from_the_env_file
guard_never_stops_the_main_checkout guard_never_stops_an_npm_install guard_leaves_other_git_files_alone
guard_says_which_copy_to_run guard_quotes_the_command_it_gives"
