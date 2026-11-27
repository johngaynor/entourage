# Tasks: a worktree of each repo on one branch. Sourced by cli/entourage.

# A task is a folder in a project's tasks/ folder, named after its branch's
# description, holding one git worktree per repo of the project:
#   tasks/abc-122-short-title/api   a worktree of api on feat/abc-122-short-title

# Branch names follow Conventional Branch 1.1.0 (https://conventionalbranch.org):
# <type>/<description>. Trunk names (main, master, develop) have no type, so
# they do not match.
BRANCH_RE='^(feature|feat|bugfix|fix|hotfix|release|chore|ai|claude|codex|copilot|cursor)/[a-z0-9]+(\.[a-z0-9]+)*(-[a-z0-9]+(\.[a-z0-9]+)*)*$'

valid_branch() { [[ ${1:-} =~ $BRANCH_RE ]]; }

# A task's name is its branch without the type.
task_name() { printf '%s\n' "${1#*/}"; }

has_origin() { git -C "$1" remote get-url origin >/dev/null 2>&1; }
resolves() { git -C "$1" rev-parse -q --verify "$2^{commit}" >/dev/null 2>&1; }

# Print the ref a repo's new task branch is cut from: the remote's default
# branch, or the local one in a repo with no origin.
base_ref() {
  local repo=$1 ref
  if has_origin "$repo"; then
    ref=$(git -C "$repo" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null) || ref=
    for ref in ${ref:+"$ref"} origin/main origin/master; do
      if resolves "$repo" "$ref"; then printf '%s\n' "$ref"; return; fi
    done
  fi
  for ref in main master; do
    if resolves "$repo" "refs/heads/$ref"; then printf '%s\n' "$ref"; return; fi
  done
  git -C "$repo" rev-parse --abbrev-ref HEAD
}

# What the current `task new` is in the middle of making, so that it can be
# removed if the run fails or is interrupted. Empty when nothing is half-made.
UNDO_DIR='' UNDO_BRANCH=''
MADE=()   # the repos a worktree has been started in

# Remove a half-made task. The task folder and the branch did not exist before
# the run (task_new checks both), so this never removes someone's work.
task_undo() {
  local tdir=$UNDO_DIR branch=$UNDO_BRANCH repo
  [ -n "$tdir" ] || return 0
  UNDO_DIR=''
  for repo in ${MADE[@]+"${MADE[@]}"}; do
    git -C "$repo" worktree remove --force "$tdir/${repo##*/}" >/dev/null 2>&1 || true
    git -C "$repo" branch -q -D "$branch" >/dev/null 2>&1 || true
  done
  rm -f "$tdir/CLAUDE.md" "$tdir/AGENTS.md"
  rmdir "$tdir" 2>/dev/null || true
  rmdir "${tdir%/*}" 2>/dev/null || true
  [ ! -e "$tdir" ] || printf 'entourage: could not remove everything in %s\n' "$tdir" >&2
}

task_new() {
  local name=${1:-} branch=${2:-} dir task
  dir=$(project_dir "$name")
  [ -n "$branch" ] ||
    die "which branch? Usage: entourage task new $name <type>/<description> (see https://conventionalbranch.org)"
  valid_branch "$branch" ||
    die "'$branch' is not a branch name entourage accepts. Use <type>/<description>, like: feat/abc-122-short-title (see https://conventionalbranch.org)"
  task=$(task_name "$branch")
  # A task is shown as a tab, so Herdr has to be there before anything is made.
  require_herdr
  herdr_running || die "Herdr is not running. Open it, then run this again."

  # Check everything before making anything.
  local repos=() bases=() repo base i tdir=$dir/tasks/$task
  while IFS= read -r repo; do repos+=("$repo"); done < <(project_repos "$dir")
  [ "${#repos[@]}" -gt 0 ] ||
    die "project '$name' has no repos. Add one with: entourage project add $name <path>"
  for repo in "${repos[@]}"; do
    is_repo "$repo" || die "$repo is missing or is not a git repo (see: entourage status)"
  done
  [ ! -e "$tdir" ] || die "task '$task' already exists at $tdir"
  # Fetch first, so that the branch check below sees what is on the remote
  # and the task starts from the latest default branch.
  for repo in "${repos[@]}"; do
    has_origin "$repo" || continue
    git -C "$repo" fetch -q origin 2>/dev/null ||
      say "  warning: could not fetch ${repo##*/}; starting from what is local"
  done
  for repo in "${repos[@]}"; do
    if resolves "$repo" "refs/heads/$branch" || resolves "$repo" "refs/remotes/origin/$branch"; then
      die "branch '$branch' already exists in ${repo##*/}"
    fi
    base=$(base_ref "$repo" 2>/dev/null) && resolves "$repo" "$base" ||
      die "${repo##*/} has no commit to start a branch from"
    bases+=("$base")
  done
  sync_links "$dir"

  say "Making task '$task' in $tdir"
  # From here until the worktrees and links are all made, any failure or
  # interruption removes what was made.
  MADE=() UNDO_DIR=$tdir UNDO_BRANCH=$branch
  trap task_undo EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  mkdir -p "$tdir"
  i=0
  for repo in "${repos[@]}"; do
    base=${bases[$i]}; i=$((i + 1))
    # Recorded before the attempt: a failed `worktree add` can leave its branch.
    MADE+=("$repo")
    # --no-track: the branch is new work, not a copy of the default branch, so
    # a plain push or pull must not go to or from it.
    # -f: reuse a path git still has registered for a folder deleted by hand.
    git -C "$repo" worktree add -q -f --no-track -b "$branch" "$tdir/${repo##*/}" "$base" ||
      die "could not make a worktree in ${repo##*/}; the task was not made"
    say "  worktree  ${repo##*/} (from $base)"
  done
  # With several repos the session starts in the task folder, so the project's
  # doc is linked there for an agent to read.
  if [ "${#repos[@]}" -gt 1 ]; then
    ln -s ../../PROJECT.md "$tdir/CLAUDE.md"
    ln -s ../../PROJECT.md "$tdir/AGENTS.md"
  fi
  UNDO_DIR=''
  trap - EXIT INT TERM

  # One repo: the tab starts in its worktree, where git and the repo's own
  # docs work as usual. Several: it starts in the task folder above them.
  local folder=$tdir
  [ "${#repos[@]}" -gt 1 ] || folder=$tdir/${repos[0]##*/}
  # The task exists now. If Herdr cannot show it, keep it and say where it is.
  (show_space "$name" "$dir") ||
    die "made the task at $folder but could not show it in Herdr. Open that folder in the project's space yourself."
  # No `space` argument: the tab goes in the selected space, which show_space
  # has just selected or made.
  herdr_app do tab.new "{\"name\":\"$task\",\"folder\":\"$folder\"}" >/dev/null 2>&1 ||
    die "made the task at $folder but could not open its tab. Is Herdr open?"
  say "Opened task '$task' on branch $branch"
}

cmd_task() {
  case ${1:-} in
    new) shift; task_new "$@" ;;
    *) die "usage: entourage task new <project> <branch> (see: entourage help)" ;;
  esac
}
