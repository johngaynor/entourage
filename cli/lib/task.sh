# Tasks: a card an agent writes up, then a worktree of each repo on one
# branch. Sourced by cli/entourage.

# A task is one piece of work in a project, usually a Linear card. A person
# runs two commands, in this order:
#   task new    an agent writes the card up, in a tab in the project's space
#   task start  a worktree of each repo on the card's branch, in a tab of its own
# The agent runs `task handoff` as each step ends, and `task log` shows what
# it recorded. Both are in handoff.sh.

# A card ID is a team key and a number, like ABC-122.
CARD_RE='^[A-Za-z][A-Za-z0-9]*-[0-9]+$'
# The skills the agent writes a card up with, in the order it uses them.
CARD_SKILLS='sdlc-define sdlc-plan sdlc-breakdown'
# The agent's first message. {card} and {project} are filled in.
CARD_PROMPT=$REPO/prompts/task-new.md
# The agent a new task's tab runs: one word, a command on PATH.
AGENT=${ENTOURAGE_AGENT:-claude}

# Start writing a card up: a tab in the project's space, in the project's
# folder, running an agent whose first message names the card and the skills.
# It makes no branch, worktree or task folder; `task start` does that once the
# card has a type.
task_new() {
  local name=${1:-} card=${2:-} dir skill prompt
  dir=$(project_dir "$name")
  [ -n "$card" ] ||
    die "which card? Usage: entourage task new $name <card>, like: entourage task new $name ABC-122"
  [[ $card =~ $CARD_RE ]] ||
    die "'$card' is not a card ID like ABC-122. To make a worktree for a branch, use: entourage task start $name <type>/<description>"
  card=$(printf '%s' "$card" | tr '[:lower:]' '[:upper:]')
  # The agent runs in a tab, so Herdr has to be there before anything is opened.
  require_herdr
  herdr_running || die "Herdr is not running. Open it, then run this again."
  command -v "$AGENT" >/dev/null 2>&1 ||
    die "'$AGENT' is not on your PATH, so there is no agent to start. Install it, or set ENTOURAGE_AGENT to the one you use."
  for skill in $CARD_SKILLS; do
    [ -f "$SKILLS_HOME/$skill/SKILL.md" ] ||
      die "the $skill skill is not in $SKILLS_HOME, so the agent could not use it. Run: entourage update"
  done
  [ -f "$CARD_PROMPT" ] || die "the agent's first message is missing from $CARD_PROMPT"
  prompt=$(sed -e "s/{card}/$card/g" -e "s/{project}/$name/g" "$CARD_PROMPT")

  sync_links "$dir"
  # `project new` does this too. Here it covers a project made before it did,
  # or on a day Claude Code's file could not be written. It comes before the
  # tab, because the agent meets the trust question the moment it starts.
  trust_project "$name"
  (show_space "$name" "$dir") ||
    die "could not show the space for '$name', so no agent was started."
  # No `space` argument: the tab goes in the selected space, which show_space
  # has just selected or made. argv is the agent and task is its first message.
  herdr_app do tab.new "{\"name\":\"$card\",\"folder\":\"$(json_str "$dir")\",\"argv\":[\"$(json_str "$AGENT")\"],\"task\":\"$(json_str "$prompt")\"}" >/dev/null 2>&1 ||
    die "could not open a tab for $card. Is Herdr open?"
  record_start "$name" "$card"
  say "Started $card in the space for '$name'"
  say "The agent writes the card up, then asks you to approve it."
}

# `task start` makes a folder in a project's tasks/ folder, named after its
# branch's description, holding one git worktree per repo of the project:
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

# What the current `task start` is in the middle of making, so that it can be
# removed if the run fails or is interrupted. Empty when nothing is half-made.
UNDO_DIR='' UNDO_BRANCH=''
MADE=()   # the repos a worktree has been started in

# Remove a half-made task. The task folder and the branch did not exist before
# the run (task_start checks both), so this never removes someone's work.
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

# Get a new task ready to work in: type `just setup` into its tab's shell for
# every repo that provides the recipe (see recipes.sh). It runs there, not
# here, so that `task start` returns at once and the install is on screen
# where the work will happen. Nothing in this step can fail the task: by now
# it exists and its tab is open.
#   $1 the task's folder   $2 what `tab.new` printed   $3... the task's repos
run_setup() {
  local tdir=$1 tab=$2 repo name line='' term count ready=() groups i=0
  shift 2
  count=$#
  if ! have_just; then
    say "  setup     skipped: just is not installed (https://just.systems)"
    return 0
  fi
  for repo in "$@"; do
    name=${repo##*/}
    # This repo's groups, if its target named any: handed to its recipe as is.
    groups=${TASK_GROUPS[$i]:-}; i=$((i + 1))
    case $(recipe_state "$tdir/$name" setup) in
      ok)
        ready+=("$name${groups:+ $groups}")
        # One repo: the tab is already in its worktree. Several: the tab is in
        # the task folder above them, and they run one after another. The ./
        # keeps the shell's CDPATH, and a name starting with a dash, from
        # sending cd somewhere else.
        if [ "$count" -eq 1 ]; then line="just setup${groups:+ $groups}"
        else line=${line:+$line && }"(cd ./$(sh_quote "$name") && just setup${groups:+ $groups})"
        fi
        ;;
      no-justfile) say "  setup     $name skipped: no justfile" ;;
      no-recipe) say "  setup     $name skipped: its justfile has no setup recipe" ;;
      *) say "  setup     $name skipped: its justfile could not be read by just" ;;
    esac
  done
  [ -n "$line" ] || return 0
  # tab.new prints the address of the terminal it made, as "terminal": "t8".
  term=$(printf '%s\n' "$tab" | sed -n 's/.*"terminal": *"\([^"]*\)".*/\1/p' | head -n 1) || term=
  # hc types the line once the new shell has gone quiet: a second or two.
  if [ -n "$term" ] && have_hc && hc_cmd send "$term" "$line" >/dev/null 2>&1; then
    for name in "${ready[@]}"; do say "  setup     $name (running in the tab)"; done
    return 0
  fi
  say "  setup     could not be started; run it yourself in the tab: $line"
}

# A group is a part of a repo, named by the repo itself: a plain word, because
# it is typed into the tab's shell. Lowercase letters, digits and dashes, not
# starting with a dash. Every allowed character is spelled out: a range like
# a-z means different things in different locales, and in some it lets
# uppercase letters and shell punctuation through.
valid_group() {
  case ${1:-} in
    '' | -* | *[!abcdefghijklmnopqrstuvwxyz0123456789-]*) return 1 ;;
  esac
}

# What `task start` was asked to work on, from its targets:
#   TARGET_REPOS   the repo each target names
#   TARGET_GROUPS  that target's groups, separated by spaces ('' for the whole repo)
# and, once the task's repos are chosen, in the same order as them:
#   TASK_GROUPS    each repo's groups
TARGET_REPOS=() TARGET_GROUPS=() TASK_GROUPS=()

# Read targets of the form <repo>[:<group>[,<group>...]] into TARGET_REPOS and
# TARGET_GROUPS, or stop. entourage checks a group's shape only: what a group
# means, and whether it exists, is the repo's business.
#   $1 the project   $2... the project's repos, then --, then the targets
parse_targets() {
  local name=$1 known=() arg repo groups group found r i
  shift
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do known+=("${1##*/}"); shift; done
  shift
  TARGET_REPOS=() TARGET_GROUPS=()
  for arg in "$@"; do
    repo=${arg%%:*}
    found=0
    for r in "${known[@]}"; do [ "$r" != "$repo" ] || found=1; done
    [ "$found" = 1 ] ||
      die "'$repo' is not a repo in project '$name'. Its repos are: ${known[*]}"
    i=0
    while [ "$i" -lt "${#TARGET_REPOS[@]}" ]; do
      [ "${TARGET_REPOS[$i]}" != "$repo" ] ||
        die "'$repo' is named twice. Give its groups together, separated by a comma, like: $repo:athlete,coach"
      i=$((i + 1))
    done
    groups=''
    case $arg in
      *:*)
        # Split on commas by hand: an empty group (a trailing or doubled
        # comma) has to be caught, not skipped.
        r=${arg#*:},
        while [ -n "$r" ]; do
          group=${r%%,*}; r=${r#*,}
          valid_group "$group" ||
            die "'$group' in '$arg' is not a group name. A group is lowercase letters, digits and dashes, like: $repo:athlete"
          groups=${groups:+$groups }$group
        done
        ;;
    esac
    TARGET_REPOS+=("$repo"); TARGET_GROUPS+=("$groups")
  done
}

task_start() {
  local name=${1:-} branch=${2:-} dir task
  dir=$(project_dir "$name")
  [ -n "$branch" ] ||
    die "which branch? Usage: entourage task start $name <type>/<description> [<repo>[:<group>[,<group>...]] ...] (see https://conventionalbranch.org)"
  valid_branch "$branch" ||
    die "'$branch' is not a branch name entourage accepts. Use <type>/<description>, like: feat/abc-122-short-title (see https://conventionalbranch.org)"
  task=$(task_name "$branch")
  # A task is shown as a tab, so Herdr has to be there before anything is made.
  require_herdr
  herdr_running || die "Herdr is not running. Open it, then run this again."

  # Check everything before making anything.
  local all=() repos=() bases=() repo base i tdir=$dir/tasks/$task
  while IFS= read -r repo; do all+=("$repo"); done < <(project_repos "$dir")
  [ "${#all[@]}" -gt 0 ] ||
    die "project '$name' has no repos. Add one with: entourage project add $name <path>"
  # The task's repos are the ones its targets name, or every repo when there
  # are no targets, always in the order of the project's repos file.
  shift 2
  parse_targets "$name" "${all[@]}" -- "$@"
  TASK_GROUPS=()
  for repo in "${all[@]}"; do
    if [ "${#TARGET_REPOS[@]}" -eq 0 ]; then
      repos+=("$repo"); TASK_GROUPS+=('')
      continue
    fi
    i=0
    while [ "$i" -lt "${#TARGET_REPOS[@]}" ]; do
      if [ "${TARGET_REPOS[$i]}" = "${repo##*/}" ]; then
        repos+=("$repo"); TASK_GROUPS+=("${TARGET_GROUPS[$i]}")
      fi
      i=$((i + 1))
    done
  done
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
  local tab
  tab=$(herdr_app do tab.new "{\"name\":\"$task\",\"folder\":\"$folder\"}" 2>/dev/null) ||
    die "made the task at $folder but could not open its tab. Is Herdr open?"
  run_setup "$tdir" "$tab" "${repos[@]}"
  say "Opened task '$task' on branch $branch"
}

cmd_task() {
  case ${1:-} in
    new) shift; task_new "$@" ;;
    start) shift; task_start "$@" ;;
    handoff) shift; task_handoff "$@" ;;
    log) shift; task_log "$@" ;;
    *) die "usage: entourage task new <project> <card>, or: entourage task start <project> <branch> [<repo>[:<group>[,<group>...]] ...], or: entourage task handoff <project> <card>, or: entourage task log <project> <card> (see: entourage help)" ;;
  esac
}
