# Finishing a task: once its work has merged, remove what `task start` made
# for it. Sourced by cli/entourage.

# `task finish` removes a task's worktrees, its branch in each repo and its
# folder, then closes its tab. Like `task start`, it checks everything before
# it changes anything, and here the checks are what keep work safe. It
# removes nothing when that would lose work, and names every problem in every
# repo of the task in one go. What would be lost:
#   - changes that are not committed: staged, unstaged or untracked;
#   - commits on the branch that are not in the remote's default branch, even
#     pushed ones, such as a fix pushed after the pull request merged;
#   - ignored files that the repo's setup does not make again (setup_makes,
#     in recipes.sh), which `git worktree remove` deletes without a word;
#   - anything in the task folder outside its worktrees.
# scripts/after-merge makes the same checks for Claude Code's own worktrees.
# A task that would lose work is still removed by hand.

# Lines on stdin, indented under a heading: at most 20, then how many more.
listed() { awk 'NR <= 20 { print "    " $0 } END { if (NR > 20) print "    and " NR - 20 " more" }'; }

# Print the folder of a card's task, or stop when it has none on this
# machine: tasks/<card>-<short name>, or tasks/<card> for a title with no
# plain words, as `task build` finds it. Linear is not asked.
#   $1 the project's folder   $2 the card, in upper case
task_folder() {
  local dir=$1 card=$2 low f found=()
  low=$(printf '%s' "$card" | tr '[:upper:]' '[:lower:]')
  for f in "$dir/tasks/$low" "$dir/tasks/$low-"*; do
    [ ! -d "$f" ] || found+=("$f")
  done
  case ${#found[@]} in
    0) die "$card has no task on this machine: there is no folder for it in $dir/tasks. Nothing was changed." ;;
    1) printf '%s\n' "${found[0]}" ;;
    *) die "$card has more than one task folder in $dir/tasks: ${found[*]##*/}. Remove the ones that are not its task by hand, then run this again. Nothing was changed." ;;
  esac
}

# Print git's record of a worktree, from `git worktree list --porcelain` in
# its repo: its worktree and HEAD lines, branch or detached, and locked when
# it is locked. Nothing when git has no record of it.
#   $1 the repo   $2 the worktree's real path
worktree_record() {
  local repo=$1 want=$2 line on=0
  while IFS= read -r line; do
    case $line in
      'worktree '*)
        on=0
        [ "$(cd -P "${line#worktree }" 2>/dev/null && pwd)" != "$want" ] || on=1
        ;;
    esac
    [ "$on" = 0 ] || printf '%s\n' "$line"
  done < <(git -C "$repo" worktree list --porcelain 2>/dev/null)
}

# What check_worktree found: the problems, as lines under the worktree's name,
# and the repo, branch and commit to remove once there are none.
FOUND='' WT_REPO='' WT_BRANCH='' WT_HEAD=''
add_problem() { FOUND=$FOUND$*$'\n'; }
add_list() { FOUND=$FOUND$(listed)$'\n'; }

# Check one worktree of a task for what removing it would lose. It changes
# nothing but the repo's copy of origin, which it fetches.
#   $1 the worktree   $2 the task's name   $3 a folder for the checks' files
check_worktree() {
  local wt=$1 task=$2 scratch=$3 common record out base why
  FOUND='' WT_REPO='' WT_BRANCH='' WT_HEAD=''
  # git names the worktree's repo. A .git file that leads nowhere names none.
  common=$(cd "$wt" 2>/dev/null && c=$(git rev-parse --git-common-dir 2>/dev/null) && [ -n "$c" ] &&
    cd "$c" 2>/dev/null && pwd -P) || common=
  if [ -z "$common" ]; then
    add_problem "  git cannot read it as a worktree, so what removing it would lose is not known"
    return 0
  fi
  WT_REPO=$common
  [ "${common##*/}" != .git ] || WT_REPO=${common%/.git}
  record=$(worktree_record "$WT_REPO" "$(cd -P "$wt" && pwd)")
  if [ -z "$record" ]; then
    add_problem "  $WT_REPO has no record of it as a worktree, so what removing it would lose is not known"
    return 0
  fi
  WT_HEAD=$(printf '%s\n' "$record" | sed -n 's/^HEAD //p')
  WT_BRANCH=$(printf '%s\n' "$record" | sed -n 's|^branch refs/heads/||p')

  if printf '%s\n' "$record" | grep -q '^locked\( \|$\)'; then
    why=$(printf '%s\n' "$record" | sed -n 's/^locked \{0,1\}//p')
    add_problem "  it is locked${why:+ ($why)}: something may still be working in it"
  fi
  if [ -z "$WT_BRANCH" ]; then
    add_problem "  it is not on a branch, so it is not on the task's branch"
  elif ! valid_branch "$WT_BRANCH" || [ "$(task_name "$WT_BRANCH")" != "$task" ]; then
    add_problem "  it is on the branch $WT_BRANCH, not on the task's branch"
  fi

  # Every commit up to the worktree's HEAD has to be in the remote's default
  # branch: ancestry, since pull requests here merge with a merge commit. A
  # branch merged by squash or rebase is refused, which loses nothing. A fetch
  # that fails leaves what is local, which can only refuse more.
  if has_origin "$WT_REPO" && ! git -C "$WT_REPO" fetch -q origin 2>/dev/null; then
    say "  warning: could not fetch ${wt##*/}; checking it against what is local"
  fi
  base=$(base_ref "$WT_REPO" 2>/dev/null) || base=
  if [ -z "$base" ] || [ "$base" = "$WT_BRANCH" ] || ! resolves "$WT_REPO" "$base"; then
    add_problem "  it has no default branch to check the branch's commits against"
  elif ! git -C "$WT_REPO" merge-base --is-ancestor "$WT_HEAD" "$base" 2>/dev/null; then
    out=$(git -C "$WT_REPO" log --oneline "$base..$WT_HEAD" 2>&1) || true
    add_problem "  commits that are not in $base:"
    add_list <<< "$out"
  fi

  # Changed, staged and untracked files, each one by name.
  if ! out=$(git -C "$wt" status --porcelain --untracked-files=all 2>&1); then
    add_problem "  git status failed, so what is not committed is not known:"
    add_list <<< "$out"
  elif [ -n "$out" ]; then
    add_problem "  changes that are not committed:"
    add_list <<< "$out"
  fi

  # Ignored files, file by file: each counts as work unless it is, or is in,
  # something the patterns that setup_makes prints match. git quotes an odd
  # name the same way in both lists, so they can be compared line by line.
  if ! git -C "$wt" ls-files --others --ignored --exclude-standard > "$scratch/ignored" 2>/dev/null; then
    add_problem "  git could not list its ignored files, so what removing it would lose is not known"
  elif [ -s "$scratch/ignored" ]; then
    why=''
    if setup_makes "$wt" > "$scratch/patterns" 2> "$scratch/why"; then
      git -C "$wt" ls-files --others --ignored --exclude-from="$scratch/patterns" > "$scratch/made" 2>/dev/null ||
        { why="git could not read what its made-by-setup recipe printed"; : > "$scratch/made"; }
    else
      why=$(head -n 1 "$scratch/why"); : > "$scratch/made"
    fi
    out=$(awk 'FILENAME == ARGV[1] { made[$0]; next } !($0 in made)' "$scratch/made" "$scratch/ignored")
    if [ -n "$out" ]; then
      if [ -n "$why" ]; then add_problem "  ignored files, all of them counted as work since $why:"
      else add_problem "  ignored files that its setup does not make again:"
      fi
      add_list <<< "$out"
    fi
  fi
}

# Close a task's tab: the one named after the task, in the project's space.
# It is the last thing `task finish` does, because run in that tab, closing
# it ends the command. No `confirmed`, so Herdr asks first when it is the
# space's last tab, since closing that one closes the space.
#   $1 the project   $2 its folder   $3 the task's name
close_task_tab() {
  local name=$1 dir=$2 task=$3 id
  if ! herdr_running; then
    say "  tab       not closed: Herdr is not running"
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    say "  tab       not closed: jq is not installed, so the tab could not be found. Close the tab $task yourself."
    return 0
  fi
  id=$(herdr_app ls 2>/dev/null | jq -r --arg dir "$dir" --arg task "$task" \
    'first(.spaces[]? | select(.folder == $dir) | .tabs[]? | select(.name == $task) | .id | strings) // empty' \
    2>/dev/null) || id=
  if [ -z "$id" ]; then
    say "  tab       none to close: no tab named $task is open in the space for '$name'"
    return 0
  fi
  say "  tab       closing $task"
  # Not in a subshell: run in this tab, the command ends here.
  herdr_app do tab.close "{\"id\":\"$(json_str "$id")\"}" >/dev/null 2>&1 ||
    say "  tab       could not close $task. Close it yourself."
}

task_finish() {
  local name=${1:-} card=${2:-} dir tdir task
  dir=$(project_dir "$name")
  [ -n "$card" ] ||
    die "which card? Usage: entourage task finish $name <card>, like: entourage task finish $name ABC-122"
  [[ $card =~ $CARD_RE ]] || die "'$card' is not a card ID like ABC-122."
  [ "$#" -le 2 ] || die "usage: entourage task finish <project> <card>"
  card=$(printf '%s' "$card" | tr '[:lower:]' '[:upper:]')
  tdir=$(task_folder "$dir" "$card") || exit 1
  task=${tdir##*/}

  # What the task folder holds: a worktree of each repo, and with several
  # repos the links to the project's doc. Anything else, hidden or not, would
  # be lost with the folder.
  local f wts=() others=()
  for f in "$tdir"/* "$tdir"/.[!.]* "$tdir"/..?*; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    if [ -f "$f/.git" ] && [ ! -L "$f" ]; then wts+=("$f"); continue; fi
    case ${f##*/} in CLAUDE.md | AGENTS.md) [ ! -L "$f" ] || continue ;; esac
    others+=("${f##*/}")
  done

  # Check everything before removing anything.
  local scratch wt problems='' repos=() branches=() heads=()
  scratch=$(mktemp -d) || die "could not make a folder for the checks. Nothing was changed."
  trap "rm -rf $(sh_quote "$scratch")" EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  for wt in ${wts[@]+"${wts[@]}"}; do
    check_worktree "$wt" "$task" "$scratch"
    [ -z "$FOUND" ] || problems=$problems"${wt##*/}, in ${wt#"$dir"/}:"$'\n'$FOUND
    repos+=("$WT_REPO"); branches+=("$WT_BRANCH"); heads+=("$WT_HEAD")
  done
  if [ "${#others[@]}" -gt 0 ]; then
    problems=$problems"the task folder, ${tdir#"$dir"/}, outside its worktrees:"$'\n'
    problems=$problems$(printf '%s\n' "${others[@]}" | listed)$'\n'
  fi
  rm -rf "$scratch"
  trap - EXIT INT TERM
  if [ -n "$problems" ]; then
    printf "Task '%s' was not finished: finishing it would lose this.\n%s" "$task" "$problems" >&2
    die "nothing was removed. Keep that work first: commit it, push it and merge it into the default branch, or move it out of the task. Then run this again. To throw it away instead, remove the task by hand (see \"Finishing a task\" in herdr/README.md)."
  fi

  # The command may be running in a worktree it is about to remove.
  cd "$dir"
  say "Finishing task '$task' in $tdir"
  local i=0 repo branch head
  for wt in ${wts[@]+"${wts[@]}"}; do
    repo=${repos[$i]} branch=${branches[$i]} head=${heads[$i]}
    i=$((i + 1))
    # No --force: git's own refusal, for changes made since the checks, stays
    # as a second safety net.
    git -C "$repo" worktree remove "$wt" ||
      die "could not remove the worktree $wt (git says why above). Everything listed before this was removed; the rest of the task is as it was."
    say "  worktree  ${wt##*/} removed"
    # -D, since the check above is what keeps the branch's work safe: -d
    # passes any branch whose upstream has it. Only while the branch is still
    # on the commit that was checked.
    if [ "$(git -C "$repo" rev-parse -q --verify "refs/heads/$branch" 2>/dev/null)" = "$head" ] &&
       git -C "$repo" branch -q -D "$branch" 2>/dev/null; then
      say "  branch    $branch deleted in ${wt##*/}"
    else
      say "  branch    $branch kept in ${wt##*/}: it moved after it was checked, or git would not delete it"
    fi
  done
  for f in CLAUDE.md AGENTS.md; do
    [ ! -L "$tdir/$f" ] || rm -f "$tdir/$f"
  done
  # rmdir, never rm -rf: what is still there was not checked.
  rmdir "$tdir" 2>/dev/null ||
    die "removed the task's worktrees, but not its folder $tdir: something was put in it after the checks. Look at what is there, then remove it yourself."
  say "  folder    ${tdir#"$dir"/} removed"
  say "Finished task '$task'"
  close_task_tab "$name" "$dir" "$task"
}
