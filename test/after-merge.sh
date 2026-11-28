# Tests for scripts/after-merge, the dev script that cleans up once a pull
# request on entourage merges: it removes a Claude Code worktree under
# .claude/worktrees/ and its branch, and updates the live checkout. Each case
# makes the throwaway $REPO a real clone, with a bare origin that stands in
# for GitHub, and merges through a second clone. Sourced by test/run.sh.

AFTER_MERGE=$ROOT/scripts/after-merge

# git as someone with a name: HOME is empty here.
g() { git -c user.name=t -c user.email=t@t "$@"; }
live_git() { g -C "$REPO" "$@"; }
origin_main() { git -C "$TMP/origin.git" rev-parse main; }

# Make $REPO a clone of entourage, as the live checkout is: what `setup`
# copied, the script and the repo's .gitignore, committed on main and pushed
# to a bare origin that main tracks.
live_clone() {
  rmdir "$REPO/.git"
  mkdir -p "$REPO/scripts"
  cp "$AFTER_MERGE" "$REPO/scripts/after-merge"
  cp "$ROOT/.gitignore" "$REPO/.gitignore"
  git init -q -b main "$REPO"
  live_git add -A
  live_git commit -q -m start
  git init -q --bare -b main "$TMP/origin.git"
  live_git remote add origin "$TMP/origin.git"
  live_git push -q -u origin main
}

# The folder of the worktree called $1.
wt() { printf '%s' "$REPO/.claude/worktrees/$1"; }

# A worktree called $1 on a new branch $2, the way a Claude Code session makes
# one, with a commit on it, and the branch pushed. It is pushed without
# setting an upstream, so `git branch -d` checks it against the live HEAD.
claude_worktree() {
  live_git worktree add -q -b "$2" "$(wt "$1")"
  commit_in "$1"
  g -C "$(wt "$1")" push -q origin "$2"
}

# A commit in the worktree $1.
commit_in() {
  echo "$1" >> "$(wt "$1")/$1.txt"
  g -C "$(wt "$1")" add "$1.txt"
  g -C "$(wt "$1")" commit -q -m "feat: $1"
}

# Merge origin's branch $1 into main on origin, from a second clone, as GitHub
# does when the pull request merges.
merge_on_origin() {
  rm -rf "$TMP/other"
  git clone -q "$TMP/origin.git" "$TMP/other"
  g -C "$TMP/other" merge -q --no-ff -m "Merge pull request #1" "origin/$1"
  g -C "$TMP/other" push -q origin main
}

# A worktree called $1 on the branch $2 whose pull request has merged.
merged_worktree() { claude_worktree "$1" "$2"; merge_on_origin "$2"; }

# Run the script as an agent does once it has left the worktree: from the
# live checkout. What it prints goes in $TMP/out, its exit code in $code.
after_merge() {
  code=0
  (cd "$REPO" && scripts/after-merge "$@") > "$TMP/out" 2>&1 || code=$?
}

out_has() {
  grep -qF -- "$1" "$TMP/out" || fail "it did not say '$1'. It said:
$(cat "$TMP/out")"
}

exited() { [ "$code" = "$1" ] || fail "exited $code, not $1. It said:
$(cat "$TMP/out")"; }

has_worktree() {
  [ -d "$(wt "$1")" ] || fail "the worktree's folder is gone"
  live_git worktree list --porcelain | grep -qxF "worktree $(wt "$1")" ||
    fail "git no longer lists the worktree"
}

has_branch() { live_git rev-parse -q --verify "refs/heads/$1" >/dev/null || fail "the branch $1 is gone"; }

# Fail unless the worktree $1 and its branch $2 are as they were, the live
# checkout's HEAD is still $3, and entourage update never ran.
changed_nothing() {
  has_worktree "$1"
  has_branch "$2"
  [ "$(live_git rev-parse HEAD)" = "$3" ] || fail "the live checkout's HEAD moved"
  [ ! -e "$TMP/herdr-calls.log" ] || fail "entourage update ran: $(cat "$TMP/herdr-calls.log")"
}

worktree_is_gone() {
  [ ! -e "$(wt "$1")" ] || fail "the worktree's folder is still there"
  ! live_git worktree list --porcelain | grep -qF "$(wt "$1")" ||
    fail "git still lists the worktree"
}

branch_is_gone() { ! live_git rev-parse -q --verify "refs/heads/$1" >/dev/null || fail "the branch $1 is still there"; }

# --- a merged worktree goes in one call -------------------------------------

after_merge_removes_a_merged_worktree_and_its_branch() {
  live_clone
  merged_worktree w1 feat/w1
  after_merge w1
  exited 0
  worktree_is_gone w1
  branch_is_gone feat/w1
  out_has 'Removed the worktree .claude/worktrees/w1'
  out_has 'Deleted branch feat/w1'
}

after_merge_removes_a_merged_worktree_with_a_detached_head() {
  live_clone
  live_git worktree add -q --detach "$(wt w2)"
  commit_in w2
  g -C "$(wt w2)" push -q origin HEAD:refs/heads/feat/w2
  merge_on_origin feat/w2
  after_merge w2
  exited 0
  worktree_is_gone w2
  out_has 'Removed the worktree .claude/worktrees/w2'
  out_has 'detached HEAD'
}

# --- a branch that is not all in main stays ---------------------------------

after_merge_keeps_a_branch_with_a_commit_not_in_main() {
  live_clone
  merged_worktree w1 feat/w1
  commit_in w1
  local head; head=$(live_git rev-parse HEAD)
  after_merge w1
  exited 1
  changed_nothing w1 feat/w1 "$head"
  out_has 'feat/w1 is not merged'
  out_has 'feat: w1'
}

# --- nothing that removing the worktree would lose --------------------------

after_merge_keeps_a_worktree_with_uncommitted_changes() {
  live_clone
  merged_worktree w1 feat/w1
  echo edited >> "$(wt w1)/w1.txt"
  local head; head=$(live_git rev-parse HEAD)
  after_merge w1
  exited 1
  changed_nothing w1 feat/w1 "$head"
  out_has 'w1.txt'
  [ "$(tail -n 1 "$(wt w1)/w1.txt")" = edited ] || fail "the edit is gone"
}

# git worktree remove deletes ignored files without a word, and design specs
# under docs/ are ignored.
after_merge_keeps_a_worktree_with_ignored_files() {
  live_clone
  merged_worktree w1 feat/w1
  mkdir "$(wt w1)/docs"
  echo spec > "$(wt w1)/docs/spec.md"
  local head; head=$(live_git rev-parse HEAD)
  after_merge w1
  exited 1
  changed_nothing w1 feat/w1 "$head"
  out_has 'docs/spec.md'
  [ -f "$(wt w1)/docs/spec.md" ] || fail "the spec is gone"
}

# --- only from the live checkout, and only once the session has let go ------

after_merge_run_inside_the_worktree_changes_nothing() {
  live_clone
  merged_worktree w1 feat/w1
  local head; head=$(live_git rev-parse HEAD)
  # The worktree's own copy of the script, from the worktree.
  code=0
  (cd "$(wt w1)" && scripts/after-merge w1) > "$TMP/out" 2>&1 || code=$?
  exited 1
  changed_nothing w1 feat/w1 "$head"
  out_has 'worktree'
  out_has "cd $REPO"
  # The live checkout's copy, from the worktree.
  code=0
  (cd "$(wt w1)" && "$REPO/scripts/after-merge" w1) > "$TMP/out" 2>&1 || code=$?
  exited 1
  changed_nothing w1 feat/w1 "$head"
  out_has "cd $REPO"
}

after_merge_run_outside_any_repo_changes_nothing() {
  live_clone
  merged_worktree w1 feat/w1
  local head; head=$(live_git rev-parse HEAD)
  mkdir "$TMP/elsewhere"
  code=0
  (cd "$TMP/elsewhere" && "$REPO/scripts/after-merge" w1) > "$TMP/out" 2>&1 || code=$?
  exited 1
  changed_nothing w1 feat/w1 "$head"
  out_has "cd $REPO"
}

after_merge_leaves_a_locked_worktree_alone() {
  live_clone
  merged_worktree w1 feat/w1
  live_git worktree lock --reason 'claude session 1234' "$(wt w1)"
  local head; head=$(live_git rev-parse HEAD)
  after_merge w1
  exited 1
  changed_nothing w1 feat/w1 "$head"
  out_has 'locked'
  out_has 'claude session 1234'
  live_git worktree list --porcelain | grep -qx 'locked claude session 1234' ||
    fail "the worktree is no longer locked"
}

after_merge_takes_only_a_name_under_claude_worktrees() {
  live_clone
  merged_worktree w1 feat/w1
  local head arg
  head=$(live_git rev-parse HEAD)
  for arg in "$(wt w1)" ../worktrees/w1 .. nope; do
    after_merge "$arg"
    exited 1
    changed_nothing w1 feat/w1 "$head"
  done
  after_merge
  exited 2
  out_has 'Usage: scripts/after-merge <name>'
  changed_nothing w1 feat/w1 "$head"
}

# --- the live checkout ------------------------------------------------------

after_merge_pulls_a_clean_main_then_updates_and_checks() {
  live_clone
  merged_worktree w1 feat/w1
  after_merge w1
  exited 0
  [ "$(live_git rev-parse HEAD)" = "$(origin_main)" ] || fail "the live checkout is not at origin/main"
  grep -q 'layout.switch' "$TMP/herdr-calls.log" 2>/dev/null || fail "entourage update did not refresh Herdr"
  # What entourage update and entourage status print.
  out_has "Pulling $REPO"
  out_has "Repo:  $REPO"
  out_has 'Everything is in order.'
  worktree_is_gone w1
}

after_merge_leaves_a_live_checkout_off_main_alone() {
  live_clone
  live_git checkout -q -b other
  merged_worktree w1 feat/w1
  local head; head=$(live_git rev-parse HEAD)
  after_merge w1
  exited 0
  [ "$(live_git rev-parse HEAD)" = "$head" ] || fail "the live checkout's HEAD moved"
  [ "$(live_git symbolic-ref --short HEAD)" = other ] || fail "the live checkout is no longer on other"
  [ ! -e "$TMP/herdr-calls.log" ] || fail "entourage update ran"
  out_has 'on other, not main'
  worktree_is_gone w1
  # main was not pulled, so git branch -d keeps the branch, and the script
  # says so rather than forcing it.
  has_branch feat/w1
  out_has 'Kept the branch feat/w1'
}

after_merge_leaves_a_live_checkout_with_changes_alone() {
  live_clone
  merged_worktree w1 feat/w1
  echo '{"edited":1}' > "$REPO/herdr/layouts/default.json"
  local head; head=$(live_git rev-parse HEAD)
  after_merge w1
  exited 0
  [ "$(live_git rev-parse HEAD)" = "$head" ] || fail "the live checkout's HEAD moved"
  [ "$(cat "$REPO/herdr/layouts/default.json")" = '{"edited":1}' ] || fail "the edit is gone"
  [ ! -e "$TMP/herdr-calls.log" ] || fail "entourage update ran"
  out_has 'changes'
  out_has 'herdr/layouts/default.json'
  worktree_is_gone w1
}

after_merge_leaves_a_live_main_that_cannot_fast_forward_alone() {
  live_clone
  merged_worktree w1 feat/w1
  live_git commit -q --allow-empty -m 'local only'
  local head; head=$(live_git rev-parse HEAD)
  after_merge w1
  exited 0
  [ "$(live_git rev-parse HEAD)" = "$head" ] || fail "the live checkout's HEAD moved"
  [ ! -e "$TMP/herdr-calls.log" ] || fail "entourage update ran"
  out_has 'cannot fast-forward'
  out_has 'local only'
  worktree_is_gone w1
}

# --- agents are told to use it ----------------------------------------------

after_merge_is_in_the_instructions_for_agents() {
  grep -qF 'scripts/after-merge' "$ROOT/CLAUDE.md" ||
    fail "CLAUDE.md does not tell an agent to run scripts/after-merge"
}

CASES="after_merge_removes_a_merged_worktree_and_its_branch
  after_merge_removes_a_merged_worktree_with_a_detached_head
  after_merge_keeps_a_branch_with_a_commit_not_in_main
  after_merge_keeps_a_worktree_with_uncommitted_changes
  after_merge_keeps_a_worktree_with_ignored_files
  after_merge_run_inside_the_worktree_changes_nothing
  after_merge_run_outside_any_repo_changes_nothing
  after_merge_leaves_a_locked_worktree_alone
  after_merge_takes_only_a_name_under_claude_worktrees
  after_merge_pulls_a_clean_main_then_updates_and_checks
  after_merge_leaves_a_live_checkout_off_main_alone
  after_merge_leaves_a_live_checkout_with_changes_alone
  after_merge_leaves_a_live_main_that_cannot_fast_forward_alone
  after_merge_is_in_the_instructions_for_agents"
