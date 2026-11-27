# Folders Claude Code starts in without asking. Sourced by cli/entourage.

# Claude Code asks "do you trust this folder?" the first time it starts in one,
# and keeps the answer in its own file, $CLAUDE_STATE, as
#   .projects["<the folder's real path>"].hasTrustDialogAccepted
# A folder cannot answer for itself. entourage answers for the folders it made
# itself (a project's folder), so that an agent `task new` starts there is not
# left waiting on the question. It never answers for a repo.
#
# The file is Claude Code's. It holds much more than this, and every running
# session rewrites it. So this is the only place that writes it, it changes one
# value, and what it cannot do cleanly it leaves undone and says so.

# The jq test for "this folder is trusted". $d is the folder.
TRUST_TEST='.projects[$d].hasTrustDialogAccepted == true'

trust_note() { say "  note      Claude Code will ask to trust $1 the first time: $2"; }

# Record a folder as trusted. The folder is a real path, as project_dir prints
# it, because that is what Claude Code looks up. Always returns 0: a project or
# a task is never held up by this.
trust_folder() {
  local dir=$1 file=$CLAUDE_STATE lock tmp tries=0 ok=0
  lock=$file.lock
  tmp=$file.entourage.$$
  # A link is checked first, since -f follows links. Replacing one with a plain
  # file would break whatever keeps the real file somewhere else.
  if [ -L "$file" ]; then trust_note "$dir" "$file is a link, so it was left alone"; return 0; fi
  if [ ! -f "$file" ]; then trust_note "$dir" "there is no $file yet"; return 0; fi
  if ! command -v jq >/dev/null 2>&1; then trust_note "$dir" "jq is not installed"; return 0; fi
  if jq -e --arg d "$dir" "$TRUST_TEST" "$file" >/dev/null 2>&1; then return 0; fi

  # Claude Code's own lock: a folder beside the file, held while it writes. It
  # clears a lock that nobody refreshes, so a run killed in here does no
  # lasting harm. A lock someone else holds is waited for, never removed.
  until mkdir "$lock" 2>/dev/null; do
    tries=$((tries + 1))
    if [ "$tries" -ge 10 ]; then trust_note "$dir" "$file is in use, so it was left alone"; return 0; fi
    sleep 0.1
  done
  # cp -p gives the new file the old one's permissions. The new file is checked
  # before it replaces the old one: jq prints nothing for an empty file and
  # still exits zero.
  if cp -p "$file" "$tmp" 2>/dev/null &&
    jq --arg d "$dir" 'if type == "object" then .projects[$d].hasTrustDialogAccepted = true else error("not an object") end' \
      "$file" > "$tmp" 2>/dev/null &&
    jq -e --arg d "$dir" "$TRUST_TEST" "$tmp" >/dev/null 2>&1 &&
    mv -f "$tmp" "$file" 2>/dev/null; then
    ok=1
  fi
  rm -f "$tmp"
  rmdir "$lock" 2>/dev/null || true

  if [ "$ok" = 1 ]; then
    say "  trusted   $dir (Claude Code will not ask to trust it)"
  else
    trust_note "$dir" "$file could not be updated, so it was left alone"
  fi
  return 0
}
