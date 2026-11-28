# Tasks: a card an agent writes up, then a worktree of each repo on one
# branch. Sourced by cli/entourage.

# A task is one piece of work in a project, usually a Linear card. A person
# runs two commands, in this order:
#   task new    an agent writes the card up, in a tab in the project's space
#   task start  a worktree of each repo on the card's branch, in a tab of its
#               own, where it types `task build` to start the agent that
#               builds the card
# The agent runs `task handoff` as each step ends, and `task log` shows what
# it recorded. Both are in handoff.sh. While the pull requests wait on the
# human, `task watch` watches them on GitHub; it is in watch.sh. Once the work
# has merged, `task finish` removes the task; it is in finish.sh.

# A card ID is a team key and a number, like ABC-122.
CARD_RE='^[A-Za-z][A-Za-z0-9]*-[0-9]+$'
# The skills the agent writes a card up with, in the order it uses them.
CARD_SKILLS='sdlc-define sdlc-plan sdlc-breakdown'
# The agent's first message. {card} and {project} are filled in.
CARD_PROMPT=$REPO/prompts/task-new.md
# The skills the agent builds a card with, in the order it uses them: the
# build, then the review, which sends what it finds not met back to the build,
# then the pull request, which waits for the human to merge it.
BUILD_SKILLS='sdlc-build sdlc-review sdlc-pr'
# The build agent's first message. {card} and {project} are filled in.
BUILD_PROMPT=$REPO/prompts/task-build.md
# The agent a new task's tab runs: one word, a command on PATH.
AGENT=${ENTOURAGE_AGENT:-claude}
# The profiles claude starts with: Claude Code agent definitions in agents/,
# linked into Claude Code's agents folder. Each gives the session only the
# tools its steps use. The write-up's is for `task new`, the build's for
# `task build`, whose one session also reviews the build. Each runs on the
# model and effort the settings file names for it, under the name after it
# (settings.sh).
CARD_PROFILE=entourage-write-up CARD_SETTINGS=write-up
BUILD_PROFILE=entourage-build BUILD_SETTINGS=build
# The MCP servers a profile's session has, and no others: Linear's own, under
# the name the profiles' tools are given with.
PROFILE_MCP=$REPO/agents/linear-mcp.json

# The flags that start claude with a profile, in PROFILE_ARGS, or stop when
# the profile is not linked or the settings file is not valid settings.
# Another agent is started as it is, with none, and the settings file is not
# read. Each flag holds its value after an =, because --mcp-config takes
# several values and would take the first message as one of them. --model=
# and --effort= beat the profile's own model and the human's own Claude Code
# settings; only CLAUDE_CODE_EFFORT_LEVEL beats --effort=.
#   $1 the profile   $2 its name in the settings file
PROFILE_ARGS=()
profile_args() {
  local profile=$1 settings=$2
  PROFILE_ARGS=()
  [ "${AGENT##*/}" = claude ] || return 0
  [ -f "$AGENTS_HOME/$profile.md" ] ||
    die "the $profile agent profile is not in $AGENTS_HOME, so the agent could not start with it. Run: entourage update"
  settings_check
  PROFILE_ARGS=("--agent=$profile" --strict-mcp-config "--mcp-config=$PROFILE_MCP"
    "--model=$(profile_model "$settings")" "--effort=$(profile_effort "$settings")")
}

# Stop if Linear has no such card, before an agent is started on it: a
# mistyped ID is caught now, not by the agent after it has looked for the card.
# Only a definite no stops it. With no key saved, Linear is not asked; when it
# cannot be asked, the card starts as before, with a note saying why.
check_card() {
  local card=$1 why rc=0
  why=$(linear_card_known "$card" 2>&1 >/dev/null) || rc=$?
  case $rc in
    0 | 2) ;;
    1) die "Linear has no card $card that the saved key can see. Check the ID, then run this again." ;;
    # Only the first sentence of why: the rest of linear_ask's message is
    # advice for a command that stops, such as to run it again, which here
    # would start a second agent on the card.
    *) why=$(first_sentence "$why")
       say "  note      could not check $card with Linear${why:+: $why}. Starting it anyway." ;;
  esac
}

# Start writing a card up: a tab in the project's space, in the project's
# folder, running an agent whose first message names the card and the skills.
# It makes no branch, worktree or task folder; `task start` does that once the
# card has a type.
task_new() {
  local name=${1:-} card=${2:-} dir skill prompt arg argv
  dir=$(project_dir "$name")
  [ -n "$card" ] ||
    die "which card? Usage: entourage task new $name <card>, like: entourage task new $name ABC-122"
  [[ $card =~ $CARD_RE ]] ||
    die "'$card' is not a card ID like ABC-122. Give the card's ID: once it is written up, entourage task start $name <card> names its branch."
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
  profile_args "$CARD_PROFILE" "$CARD_SETTINGS"
  [ -f "$CARD_PROMPT" ] || die "the agent's first message is missing from $CARD_PROMPT"
  prompt=$(sed -e "s/{card}/$card/g" -e "s/{project}/$name/g" "$CARD_PROMPT")
  check_card "$card"

  sync_links "$dir"
  # `project new` does this too. Here it covers a project made before it did,
  # or on a day Claude Code's file could not be written. It comes before the
  # tab, because the agent meets the trust question the moment it starts.
  trust_project "$name"
  (show_space "$name" "$dir") ||
    die "could not show the space for '$name', so no agent was started."
  # No `space` argument: the tab goes in the selected space, which show_space
  # has just selected or made. argv is the agent and its profile's flags, and
  # task is its first message.
  argv="\"$(json_str "$AGENT")\""
  for arg in ${PROFILE_ARGS[@]+"${PROFILE_ARGS[@]}"}; do argv="$argv,\"$(json_str "$arg")\""; done
  herdr_app do tab.new "{\"name\":\"$card\",\"folder\":\"$(json_str "$dir")\",\"argv\":[$argv],\"task\":\"$(json_str "$prompt")\"}" >/dev/null 2>&1 ||
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

# The first four words of a card's title, on stdin, in lowercase and joined
# by hyphens: "Export orders as CSV" is export-orders-as-csv. a, an and the
# are left out, and an apostrophe joins its word ("Ada's" is adas). Anything
# else that is not a plain letter or digit ends a word, because a branch name
# cannot hold it. Every letter is spelled out, as in valid_group, and the
# bytes are read in the C locale, so no locale changes what a letter is.
short_name() {
  local word short='' n=0
  for word in $(LC_ALL=C sed -e "s/'//g" -e "s/’//g" |
      LC_ALL=C tr -c 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789' ' ' |
      LC_ALL=C tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz'); do
    case $word in a | an | the) continue ;; esac
    short=${short:+$short-}$word
    n=$((n + 1))
    [ "$n" -lt 4 ] || break
  done
  printf '%s' "$short"
}

# Print the branch a card's task is on, <type>/<card ID>-<short name>, named
# from the card in Linear: like feat/abc-122-export-orders-as-csv. It stops
# before anything is made when Linear cannot be asked, has no such card, or
# the card has no type.
#   card_branch <project> <card ID, in upper case>
card_branch() {
  local name=$1 card=$2 found type short branch
  found=$(linear_card "$card") || exit 1
  type=$(printf '%s' "$found" | jq -r '.type // empty')
  [ -n "$type" ] ||
    die "$card has no type in Linear, so its branch cannot be named. Write the card up first: entourage task new $name $card"
  short=$(printf '%s' "$found" | jq -r '.title' | short_name)
  branch=$type/$(printf '%s' "$card" | tr '[:upper:]' '[:lower:]')${short:+-$short}
  valid_branch "$branch" ||
    die "$card's type in Linear is '$type', which is not a branch type, so its branch cannot be named. Set its type to feat, fix or chore (see https://conventionalbranch.org)."
  printf '%s\n' "$branch"
}

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

# The commands that get a new task ready to work in, for the line typed into
# its tab: `just setup` for every repo that provides the recipe (see
# recipes.sh). They go in SETUP_LINE, empty when there is nothing to run, and
# the repos they run for in SETUP_READY. Nothing in this step can fail the
# task: by now it exists and its tab is open.
#
# Setup is off unless ENTOURAGE_SETUP is 1, while the local environment each
# task gets is still being worked out: a recipe that starts a whole stack
# should not run for every task in the meantime.
#   $1 the task's folder   $2... the task's repos
SETUP_LINE='' SETUP_READY=()
setup_line() {
  local tdir=$1 repo name count groups i=0
  shift
  count=$#
  SETUP_LINE='' SETUP_READY=()
  if [ "${ENTOURAGE_SETUP:-}" != 1 ]; then
    say "  setup     not run: it is off for now (ENTOURAGE_SETUP=1 turns it on)"
    return 0
  fi
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
        SETUP_READY+=("$name${groups:+ $groups}")
        # One repo: the tab is already in its worktree. Several: the tab is in
        # the task folder above them, and they run one after another. The ./
        # keeps the shell's CDPATH, and a name starting with a dash, from
        # sending cd somewhere else. The subshells leave the tab in the task
        # folder for what comes after them.
        if [ "$count" -eq 1 ]; then SETUP_LINE="just setup${groups:+ $groups}"
        else SETUP_LINE=${SETUP_LINE:+$SETUP_LINE && }"(cd ./$(sh_quote "$name") && just setup${groups:+ $groups})"
        fi
        ;;
      no-justfile) say "  setup     $name skipped: no justfile" ;;
      no-recipe) say "  setup     $name skipped: its justfile has no setup recipe" ;;
      *) say "  setup     $name skipped: its justfile could not be read by just" ;;
    esac
  done
}

# Type a new task's line into its tab's shell: the setup commands, if there
# are any, then `entourage task build`, which starts the agent on the card. It
# runs there, not here, so that `task start` returns at once, setup is on
# screen where the work will happen, and the agent cannot start before setup
# has finished. Nothing in this step can fail the task.
#   $1 what `tab.new` printed   $2 the project   $3 the card
start_in_tab() {
  local tab=$1 build="entourage task build $2 $3" line term name
  line=${SETUP_LINE:+$SETUP_LINE && }$build
  # tab.new prints the address of the terminal it made, as "terminal": "t8".
  term=$(printf '%s\n' "$tab" | sed -n 's/.*"terminal": *"\([^"]*\)".*/\1/p' | head -n 1) || term=
  # hc types the line once the new shell has gone quiet: a second or two.
  if [ -n "$term" ] && have_hc && hc_cmd send "$term" "$line" >/dev/null 2>&1; then
    for name in ${SETUP_READY[@]+"${SETUP_READY[@]}"}; do say "  setup     $name (running in the tab)"; done
    say "  agent     starting in the tab: $build"
    return 0
  fi
  say "  agent     could not be started; run it yourself in the tab: $line"
}

# Say when Claude Code will ask whether to trust a task's tab. A worktree takes
# the trust of its repo's own checkout, never of a folder above it, and
# entourage never answers for a repo (see trust.sh), so this only reads.
#   $1 the repo whose worktree the tab is in
repo_trust_note() {
  local repo name=${1##*/}
  repo=$(cd -P "$1" 2>/dev/null && pwd) || return 0
  if [ -e "$CLAUDE_STATE" ] && command -v jq >/dev/null 2>&1; then
    ! trust_recorded "$repo" "$CLAUDE_STATE" || return 0
    say "  note      Claude Code will ask once in the tab whether to trust $name. It asks once for each repo."
  else
    say "  note      Claude Code may ask once in the tab whether to trust $name."
  fi
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
  local name=${1:-} card=${2:-} dir branch task
  dir=$(project_dir "$name")
  [ -n "$card" ] ||
    die "which card? Usage: entourage task start $name <card> [<repo>[:<group>[,<group>...]] ...], like: entourage task start $name ABC-122"
  case $card in
    */*) die "task start takes the card now, not a branch, and names the branch from the card's type and title in Linear. Give the card's ID, like: entourage task start $name ABC-122" ;;
  esac
  [[ $card =~ $CARD_RE ]] ||
    die "'$card' is not a card ID like ABC-122. Usage: entourage task start $name <card> [<repo>[:<group>[,<group>...]] ...]"
  card=$(printf '%s' "$card" | tr '[:lower:]' '[:upper:]')
  # A task is shown as a tab, so Herdr has to be there before anything is made.
  require_herdr
  herdr_running || die "Herdr is not running. Open it, then run this again."

  # Check everything before making anything.
  local all=() repos=() bases=() repo base i tdir
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
  # Linear names the branch, once everything here has been checked.
  branch=$(card_branch "$name" "$card") || exit 1
  task=$(task_name "$branch")
  tdir=$dir/tasks/$task
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

  say "Making task '$task' for $card on branch $branch, in $tdir"
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
  setup_line "$tdir" "${repos[@]}"
  start_in_tab "$tab" "$name" "$card"
  [ "${#repos[@]}" -gt 1 ] || repo_trust_note "${repos[0]}"
  record_start "$name" "$card" start
  # The work has started, so the card shows it in Linear. The task is made and
  # open by now, so a card that cannot be moved is a note, never a failure.
  local moved
  if moved=$(linear_move_note "$card" started); then say "  card      $moved"
  else say "  note      $moved"
  fi
  say "Opened task '$task' on branch $branch"
}

# Start the build agent on a card, in its task: `task start` types this into
# the task's tab, after setup when setup runs. The first message has the agent
# build the card, review the build and open its pull request. Run it again in
# the tab to start a new agent when the first one has stopped.
task_build() {
  local name=${1:-} card=${2:-} dir here low skill prompt
  dir=$(project_dir "$name")
  [ -n "$card" ] ||
    die "which card? Usage: entourage task build $name <card>, like: entourage task build $name ABC-122"
  [[ $card =~ $CARD_RE ]] || die "'$card' is not a card ID like ABC-122."
  [ "$#" -le 2 ] || die "usage: entourage task build <project> <card>"
  card=$(printf '%s' "$card" | tr '[:lower:]' '[:upper:]')
  low=$(printf '%s' "$card" | tr '[:upper:]' '[:lower:]')
  # The agent works in the folder it starts in, so that has to be this card's
  # task: tasks/<card>-<short name>, or tasks/<card> for a title with no plain
  # words, or a worktree inside it. tasks/abc-12-… is not ABC-1's.
  here=$(pwd -P)
  case $here/ in
    "$dir/tasks/$low/"* | "$dir/tasks/$low-"*/*) ;;
    *) die "run this in $card's task, the folder task start made for it in $dir/tasks. To make it: entourage task start $name $card" ;;
  esac
  command -v "$AGENT" >/dev/null 2>&1 ||
    die "'$AGENT' is not on your PATH, so there is no agent to start. Install it, or set ENTOURAGE_AGENT to the one you use."
  for skill in $BUILD_SKILLS; do
    [ -f "$SKILLS_HOME/$skill/SKILL.md" ] ||
      die "the $skill skill is not in $SKILLS_HOME, so the agent could not use it. Run: entourage update"
  done
  profile_args "$BUILD_PROFILE" "$BUILD_SETTINGS"
  [ -f "$BUILD_PROMPT" ] || die "the agent's first message is missing from $BUILD_PROMPT"
  prompt=$(sed -e "s/{card}/$card/g" -e "s/{project}/$name/g" "$BUILD_PROMPT")
  # The first message goes last, after the profile's flags.
  exec "$AGENT" ${PROFILE_ARGS[@]+"${PROFILE_ARGS[@]}"} "$prompt"
}

# List the open cards of a project's Linear teams, grouped by status: the
# cards `task new` can be given. Linear itself is asked in linear.sh. --json
# prints the list as one line for programs; the cards mod reads it.
task_ls() {
  local name=${1:-} json=0 dir team keys list
  local -a teams=()
  dir=$(project_dir "$name")
  case ${2:-} in
    --json) json=1 ;;
    '') ;;
    *) die "unknown option for task ls: $2" ;;
  esac
  [ "$#" -le 2 ] || die "usage: entourage task ls <project> [--json]"
  # Read first, so that a bad line in the teams file stops it with its own
  # message, not one saying there is no team.
  keys=$(project_teams "$dir") || exit 1
  while IFS= read -r team; do [ -z "$team" ] || teams+=("$team"); done <<< "$keys"
  [ "${#teams[@]}" -gt 0 ] ||
    die "project '$name' has no Linear team, so there are no cards to list. Set it with: entourage project team $name <team key>, like: entourage project team $name ABC"
  list=$(linear_open_cards "$name" "${teams[@]}") || exit 1
  if [ "$json" = 1 ]; then
    printf '%s\n' "$list"
    return
  fi
  # Titles and status names are anyone's text. In the list, a newline would
  # start what looks like another card, and an escape sequence would reach the
  # terminal, so every control character becomes a space. No regex, so any jq
  # does it. --json above keeps the text as it is.
  printf '%s' "$list" |
    jq -r 'def plain: explode | map(if . < 32 or (. > 126 and . < 160) then 32 else . end) | implode;
      .statuses[] | "\(.name | plain) (\(.cards | length))", (.cards[] | "  \(.id | plain)  \(.title | plain)")'
}

cmd_task() {
  case ${1:-} in
    new) shift; task_new "$@" ;;
    ls | list) shift; task_ls "$@" ;;
    start) shift; task_start "$@" ;;
    build) shift; task_build "$@" ;;
    finish) shift; task_finish "$@" ;;
    watch) shift; task_watch "$@" ;;
    handoff) shift; task_handoff "$@" ;;
    log) shift; task_log "$@" ;;
    *) die "usage: entourage task ls <project> [--json], or: entourage task new <project> <card>, or: entourage task start <project> <card> [<repo>[:<group>[,<group>...]] ...], or: entourage task build <project> <card>, or: entourage task finish <project> <card>, or: entourage task watch <project> <card> [--once], or: entourage task handoff <project> <card>, or: entourage task log <project> [<card>] [--json] (see: entourage help)" ;;
  esac
}
