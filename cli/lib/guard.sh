# The guard on a worktree's copy of entourage. Sourced by cli/entourage.

# A copy of entourage in a linked git worktree is a change being built, not
# the copy this machine runs. Run without being asked to act on the real
# machine, it runs only the commands that read, and stops before any other
# does anything: a slip must not open a real tab, make a real task, change a
# card in Linear, or change the human's projects, hand-offs, links or skills.
# ENTOURAGE_LIVE=1, set for the run, lets it act on the machine for real. The
# file cannot set it (see load_env in cli/entourage), so it is never left on
# for every run. The main checkout and an npm install are never guarded.

# 1 while this run is a worktree's copy that was not asked to act on the real
# machine. guard_worktree sets it; `store` in handoff.sh then opens the
# hand-off store read-only, so that a read cannot change it either.
GUARDED=0

# Whether this copy is in a linked git worktree. Its .git is then a file whose
# gitdir: line names a folder in the worktrees/ folder of the repo it was made
# from. The main checkout has a .git folder, an npm install has no .git, and
# a submodule's .git file points into modules/. The shell reads the file, so
# no git is needed. Only where this script is counts, never the folder it is
# run from, so plain `entourage` run inside a worktree is not guarded.
is_worktree_copy() {
  local line='' re='^gitdir:[[:space:]]*(.*/)?worktrees/[^/]+/?$'
  [ -f "$REPO/.git" ] || return 1
  { IFS= read -r line || [ -n "$line" ]; } < "$REPO/.git" 2>/dev/null || return 1
  line=${line%$'\r'}
  [[ $line =~ $re ]]
}

# Whether a command line only reads. The list names what may run, not what
# may not, so a command added later is refused until it is added here as a
# read. Each of these leaves the machine as it was, the hand-off store
# included; `task ls` asks Linear, and `task watch` asks GitHub, and both
# only read. `profile ls` reads the settings file; `profile set` changes it,
# and the review subagents in Claude Code's agents folder. `linear archive`
# alone, or with --json, reads whether archiving is on; with on or off it
# changes the settings file.
is_read() {
  case ${1:-help} in
    help | -h | --help | status) return 0 ;;
    project)
      case ${2:-} in
        ls | list) return 0 ;;
        # With keys after the name it writes the project's teams.
        team) [ "$#" -le 3 ] ;;
        *) return 1 ;;
      esac
      ;;
    profile)
      case ${2:-} in
        ls | list) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    linear)
      [ "${2:-}" = archive ] || return 1
      case $# in
        2) return 0 ;;
        3) [ "$3" = --json ] ;;
        *) return 1 ;;
      esac
      ;;
    task)
      case ${2:-} in
        ls | list | log | watch) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    *) return 1 ;;
  esac
}

# A command line as a shell would read it back, each word quoted only when it
# needs to be.
shell_words() {
  local w out=''
  for w in "$@"; do
    case $w in
      '' | *[!A-Za-z0-9_./:=@%+,-]*) w=$(sh_quote "$w") ;;
    esac
    out="$out${out:+ }$w"
  done
  printf '%s' "$out"
}

# Stop a worktree's copy before a command that would change the machine, and
# say which copy to run instead. Run before the command is dispatched.
guard_worktree() {
  is_worktree_copy || return 0
  [ "${ENTOURAGE_LIVE:-}" != 1 ] || return 0
  GUARDED=1
  ! is_read "$@" || return 0
  die "this is the copy of entourage in the worktree $REPO. It runs only the commands that read (help, status, project ls, project team <name>, profile ls, linear archive, task ls, task log and task watch), so \`$(shell_words "$@")\` was not run: it could change this machine's Herdr, projects and tasks, hand-offs, Linear key or cards, or Claude Code's skills, agents and trust file.
  - For the card's own steps, such as recording a hand-off, run plain \`entourage\`: the copy this machine runs, not this one.
  - To try a command that changes the machine, write a test case for it, in test/.
  - To run it on this machine for real, only when that is wanted:
      ENTOURAGE_LIVE=1 $(shell_words "$REPO/cli/entourage" "$@")"
}
