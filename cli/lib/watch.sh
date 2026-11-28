# Watching a card's pull requests on GitHub until they have merged. Sourced
# by cli/entourage.

# `task watch` asks GitHub how the pull requests of a card's task stand, on a
# schedule, and ends once that is settled. The sdlc-pr skill runs it in the
# background while the pull requests wait on the human, so that the agent
# learns of the merge without being told in the tab. While it sleeps it costs
# the agent nothing; only its end wakes the agent. It changes nothing, so a
# worktree's copy of entourage runs it too (guard.sh).
#
# Each check asks GitHub, in each worktree of the task, for the pull request of
# that worktree's branch, and prints one line for each: merged, open or closed,
# then its URL. A worktree whose branch has no pull request is skipped, since
# the work did not change that repo. It exits with:
#   0  every pull request has merged
#   3  one was closed without merging
#   2  with --once, while one is still open
#   1  it cannot watch: no task, no pull request at all, no gh or jq, or with
#      --once a check that gh could not make
# A check that gh cannot make is said on stderr, and made again next time.

# How long to sleep before the next check, in seconds, from the age of the
# newest pull request: every minute for its first 10 minutes, every 5 minutes
# for the hour after that, then every half hour. The age comes from GitHub's
# createdAt, which a push does not move, so a later push to the branch does
# not start the schedule again.
#   $1 the age in seconds, or nothing when no check has seen one yet
watch_pause() {
  local age=${1:-0}
  if [ "$age" -lt 600 ]; then echo 60
  elif [ "$age" -lt 4200 ]; then echo 300
  else echo 1800
  fi
}

# A branch's pull requests, as `gh pr list --json url,state,createdAt` gives
# them, read as one line: the state, createdAt in seconds since 1970 (- when
# it cannot be read), and the URL. Nothing when the branch has none. Only its
# newest pull request counts: one closed before another was opened is over.
WATCH_PR='if type != "array" then error("not a list")
  elif length == 0 then empty
  else max_by(.createdAt) | "\(.state) \((.createdAt | fromdateiso8601?) // "-") \(.url)" end'

# What one check found: how many pull requests stand each way, how many
# worktrees it could not tell for, and the newest createdAt it saw ('' none).
CHECK_OPEN=0 CHECK_CLOSED=0 CHECK_MERGED=0 CHECK_FAILED=0 CHECK_NEWEST=''

# Say on stderr that a check could not be made for a worktree, and count it.
#   $1 1 for --once   $2 the worktree   $3 why
check_failed() {
  local then='Trying again at the next check.'
  [ "$1" != 1 ] || then='So whether it has merged is not known.'
  printf 'entourage: could not ask GitHub for the pull request of %s: %s. %s\n' "${2##*/}" "$3" "$then" >&2
  CHECK_FAILED=$((CHECK_FAILED + 1))
}

# Check each worktree's pull request once, and print a line for each.
#   $1 1 for --once   $2 a folder for gh's errors   then each worktree, then
#   --, then the branch of each, in the same order
watch_check() {
  local once=$1 scratch=$2 wts=() wt branch out line state created url why
  shift 2
  while [ "$1" != -- ]; do wts+=("$1"); shift; done
  shift
  CHECK_OPEN=0 CHECK_CLOSED=0 CHECK_MERGED=0 CHECK_FAILED=0 CHECK_NEWEST=''
  for wt in "${wts[@]}"; do
    branch=$1
    shift
    # Run in the worktree, so that gh takes the repo from its origin.
    if ! out=$(cd "$wt" && gh pr list --head "$branch" --state all --json url,state,createdAt 2>"$scratch/err"); then
      why=$(sed -n '/[^[:space:]]/{p;q;}' "$scratch/err" 2>/dev/null) || why=
      check_failed "$once" "$wt" "${why:-gh failed}"
      continue
    fi
    if ! line=$(printf '%s' "$out" | jq -r "$WATCH_PR" 2>/dev/null); then
      check_failed "$once" "$wt" "its answer could not be read"
      continue
    fi
    # No pull request: the work did not change this repo.
    [ -n "$line" ] || continue
    state=${line%% *} line=${line#* }
    created=${line%% *} url=${line#* }
    case $state in
      MERGED) CHECK_MERGED=$((CHECK_MERGED + 1)); say "merged $url" ;;
      CLOSED) CHECK_CLOSED=$((CHECK_CLOSED + 1)); say "closed $url" ;;
      # OPEN, and anything GitHub may add later: it has not merged yet.
      *) CHECK_OPEN=$((CHECK_OPEN + 1)); say "open $url" ;;
    esac
    case $created in
      '' | *[!0-9]*) ;;
      *) [ -n "$CHECK_NEWEST" ] && [ "$CHECK_NEWEST" -ge "$created" ] || CHECK_NEWEST=$created ;;
    esac
  done
}

# The sleep between two checks, while it runs, so that a watch that is
# stopped stops it too.
WATCH_SLEEP=''

task_watch() {
  local name=${1:-} card=${2:-} once=0 dir tdir f branch wts=() branches=()
  dir=$(project_dir "$name")
  [ -n "$card" ] ||
    die "which card? Usage: entourage task watch $name <card> [--once], like: entourage task watch $name ABC-122"
  [[ $card =~ $CARD_RE ]] || die "'$card' is not a card ID like ABC-122."
  case ${3:-} in
    --once) once=1 ;;
    '') ;;
    *) die "unknown option for task watch: $3" ;;
  esac
  [ "$#" -le 3 ] || die "usage: entourage task watch <project> <card> [--once]"
  card=$(printf '%s' "$card" | tr '[:lower:]' '[:upper:]')
  command -v gh >/dev/null 2>&1 ||
    die "gh is not installed, so GitHub cannot be asked about $card's pull requests. Install it (https://cli.github.com), sign in with: gh auth login, then run this again."
  command -v jq >/dev/null 2>&1 ||
    die "jq is not installed, so GitHub's answers cannot be read. Install it, then run this again."
  tdir=$(task_folder "$dir" "$card") || exit 1

  # The task's worktrees, as `task finish` finds them, each on its branch.
  for f in "$tdir"/*; do
    [ -f "$f/.git" ] && [ ! -L "$f" ] || continue
    branch=$(git -C "$f" symbolic-ref -q --short HEAD 2>/dev/null) ||
      die "the worktree ${f#"$dir"/} is not on a branch, so it has no pull request to watch."
    wts+=("$f") branches+=("$branch")
  done
  [ "${#wts[@]}" -gt 0 ] ||
    die "$card's task, ${tdir#"$dir"/}, has no worktrees, so it has no pull request to watch."

  local scratch newest='' now
  scratch=$(mktemp -d) || die "could not make a folder for GitHub's answers."
  trap "rm -rf $(sh_quote "$scratch"); [ -z \"\$WATCH_SLEEP\" ] || kill \"\$WATCH_SLEEP\" 2>/dev/null" EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  while :; do
    watch_check "$once" "$scratch" "${wts[@]}" -- "${branches[@]}"
    # A pull request closed without merging settles it, whatever the rest do.
    [ "$CHECK_CLOSED" = 0 ] || exit 3
    if [ "$CHECK_OPEN" = 0 ] && [ "$CHECK_FAILED" = 0 ]; then
      [ "$CHECK_MERGED" -gt 0 ] ||
        die "GitHub has no pull request for $card's branch, ${branches[0]}, in any repo of its task. Open them first."
      exit 0
    fi
    if [ "$once" = 1 ]; then
      [ "$CHECK_OPEN" = 0 ] || exit 2
      exit 1
    fi
    [ -z "$CHECK_NEWEST" ] || { [ -n "$newest" ] && [ "$newest" -ge "$CHECK_NEWEST" ]; } || newest=$CHECK_NEWEST
    now=$(date +%s)
    # In the background, then waited for: a signal stops a wait at once,
    # where a sleep run in the foreground would hold it for up to half an hour.
    sleep "$(watch_pause "${newest:+$((now - newest))}")" &
    WATCH_SLEEP=$!
    wait "$WATCH_SLEEP" || true
    WATCH_SLEEP=''
  done
}
