# Folders Claude Code starts in without asking. Sourced by cli/entourage.

# Claude Code asks "do you trust this folder?" the first time it starts in one,
# and keeps the answer in its own file, $CLAUDE_STATE, as
#   .projects["<the folder's real path>"].hasTrustDialogAccepted
# A folder cannot answer for itself. entourage answers for the folders it made
# itself (a space's folder), so that an agent `task new` starts there is not
# left waiting on the question. It never answers for a repo.
#
# The file is Claude Code's. It holds much more than this, and every running
# session rewrites it. So this is the only place that writes it, it changes one
# value, and what it cannot do cleanly it leaves undone and says so.

# The jq test for "this folder is trusted". $d is the folder.
TRUST_TEST='.projects[$d].hasTrustDialogAccepted == true'

# Whether a state file ($2) says a folder ($1) is trusted. The answer is read
# from what jq prints, never from its exit code: jq 1.6 exits zero for an
# empty file even with -e. One "true" and nothing else is a yes, so a file
# holding two values where there should be one is a no as well.
trust_recorded() { [ "$(jq --arg d "$1" "$TRUST_TEST" "$2" 2>/dev/null)" = true ]; }

# "may ask": not every case below can tell whether the folder is trusted.
trust_note() { say "  note      Claude Code may ask to trust $1: $2"; }

# Record a folder as trusted. The folder is a real path, as space_dir prints
# it, because that is what Claude Code looks up. Always returns 0: a space or
# a task is never held up by this, so every command here that can fail is
# guarded.
trust_folder() {
  local dir=$1 file=$CLAUDE_STATE lock tmp tries=0 ok=0
  lock=$file.lock
  tmp=$file.entourage.$$
  if [ ! -e "$file" ] && [ ! -L "$file" ]; then trust_note "$dir" "there is no $file yet"; return 0; fi
  if ! command -v jq >/dev/null 2>&1; then trust_note "$dir" "jq is not installed"; return 0; fi
  # Reading is harmless, through a link too, so this comes before anything
  # that refuses to write.
  if trust_recorded "$dir" "$file"; then return 0; fi
  # Replacing a link with a plain file would break whatever keeps the real
  # file somewhere else.
  if [ -L "$file" ]; then trust_note "$dir" "$file is a link, so it was left alone"; return 0; fi

  # Claude Code's own lock: a folder beside the file, held while it writes. It
  # clears a lock that nobody refreshes, so a run killed in here does no
  # lasting harm. A lock someone else holds is waited for, never removed.
  until mkdir "$lock" 2>/dev/null; do
    tries=$((tries + 1))
    if [ "$tries" -ge 10 ]; then trust_note "$dir" "$file is in use, so it was left alone"; return 0; fi
    sleep 0.1 || true
  done
  # The new file is made for its owner's eyes only, as Claude Code makes it.
  # It is checked before it replaces the old one: jq prints nothing for an
  # empty file and still exits zero.
  if (umask 077 && jq --arg d "$dir" \
      'if type == "object" then .projects[$d].hasTrustDialogAccepted = true else error("not an object") end' \
      "$file" > "$tmp") 2>/dev/null &&
    trust_recorded "$dir" "$tmp" &&
    mv -f "$tmp" "$file" 2>/dev/null; then
    ok=1
  fi
  rm -f "$tmp" 2>/dev/null || true
  rmdir "$lock" 2>/dev/null || true

  if [ "$ok" = 1 ]; then
    say "  trusted   $dir (Claude Code will not ask to trust it)"
  else
    trust_note "$dir" "$file could not be updated, so it was left alone"
  fi
  return 0
}
