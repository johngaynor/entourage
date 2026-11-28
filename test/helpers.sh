# Shared by every test file. Each case runs against a throwaway copy of the
# repo layout, a throwaway HOME, and a stub herdr-app, so nothing real is
# touched. Sourced by test/run.sh.

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
failures=0
TMP=

fail() { printf 'FAIL: %s: %s\n' "$case_name" "$*"; failures=$((failures + 1)); case_failed=1; }

setup() {
  # The case before may have left a PATH inside its own folder, now removed.
  export PATH=/usr/bin:/bin
  TMP=$(mktemp -d)
  TMP=$(cd -P "$TMP" && pwd)
  REPO=$TMP/repo
  export HOME=$TMP/home
  unset HERDR_APP_HOME
  APP=$HOME/.config/herdr-app
  mkdir -p "$REPO/.git" "$REPO/cli" "$REPO/herdr/mods/cpu" "$REPO/herdr/mods/layout-switch" "$REPO/herdr/layouts"
  cp "$ROOT/cli/entourage" "$REPO/cli/entourage"
  cp -R "$ROOT/cli/lib" "$REPO/cli/lib"
  echo x > "$REPO/herdr/mods/cpu/main.js"
  echo x > "$REPO/herdr/mods/layout-switch/main.js"
  echo '{}' > "$REPO/herdr/layouts/default.json"
  echo '{}' > "$REPO/herdr/layouts/test.json"
  mkdir -p "$REPO/herdr/projects/template"
  cp "$ROOT/herdr/projects/template/PROJECT.md" "$REPO/herdr/projects/template/PROJECT.md"
  cp -R "$ROOT/skills" "$REPO/skills"
  cp -R "$ROOT/prompts" "$REPO/prompts"
  cp -R "$ROOT/agents" "$REPO/agents"
  # The reviewer and verifier for work on entourage, which a clone writes
  # into Claude Code's agents folder.
  mkdir -p "$REPO/.claude"
  cp -R "$ROOT/.claude/profiles" "$REPO/.claude/profiles"
  # A key exported in the shell that runs the tests must not reach a case.
  unset CLAUDE_CONFIG_DIR ENTOURAGE_HARNESS ENTOURAGE_SETUP ENTOURAGE_SQLITE LINEAR_API_KEY
  # Nor may a run asking a worktree's copy to act on the real machine.
  unset ENTOURAGE_LIVE
  SK=$HOME/.claude/skills
  AG=$HOME/.claude/agents
  unset ENTOURAGE_HOME
  P=$HOME/.config/entourage/projects
  mkdir -p "$APP/mods" "$APP/layouts" "$TMP/bin"
  # Stub herdr-app: logs calls, reports the "test" layout as shown, and names
  # the terminal of a tab it is asked to make.
  cat > "$TMP/bin/herdr-app" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$TMP/herdr-calls.log"
[ "\$1" = status ] && echo '  "layout": "test",'
[ "\$1" = ls ] && [ -f "$TMP/herdr-ls.json" ] && cat "$TMP/herdr-ls.json"
[ "\$2" = tab.new ] && echo '  "terminal": "t9"'
exit 0
EOF
  chmod +x "$TMP/bin/herdr-app"
  export PATH=$TMP/bin:/usr/bin:/bin
  E=$REPO/cli/entourage
}

run_case() {
  case_name=$1 case_failed=0
  # A name in CASES with no function behind it would otherwise print PASS.
  declare -F "$1" >/dev/null || { fail "there is no test case with this name"; return; }
  setup
  "$1"
  [ "$case_failed" = 0 ] && echo "PASS: $case_name"
  rm -rf "$TMP"
}

is_link_to() { [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ]; }

# A stub command that logs its arguments and exits with the given code.
stub() {
  printf '#!/usr/bin/env bash\necho "$*" >> "%s"\nexit %s\n' "$TMP/$1-calls.log" "${2:-0}" > "$TMP/bin/$1"
  chmod +x "$TMP/bin/$1"
}

# The last thing asked of Herdr.
last_call() { tail -n 1 "$TMP/herdr-calls.log"; }

# A stand-in for `just`, for tests that want it installed. It answers
# `just --justfile <file> --summary` with the file's recipe names on one line,
# and fails for a file that contains the line BROKEN, as just does for a
# justfile it cannot parse. `just --justfile <file> <recipe>` runs a recipe
# whose body is @echo lines, by printing what they echo, and fails for a
# recipe the file does not have. Every call is logged.
stub_just() {
  cat > "$TMP/bin/just" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$TMP/just-calls.log"
[ "\$1" = --justfile ] && [ -n "\${3:-}" ] || exit 2
grep -qx BROKEN "\$2" && { echo "error: could not parse" >&2; exit 1; }
if [ "\$3" = --summary ]; then
  sed -n 's/^\([a-zA-Z0-9_-][a-zA-Z0-9_-]*\):.*/\1/p' "\$2" | tr '\n' ' ' | sed 's/ \$//'
  echo
  exit 0
fi
awk -v r="\$3" '
  index(\$0, r ":") == 1 { on = 1; found = 1; next }
  on && /^[ \t]/ { l = \$0; sub(/^[ \t]+/, "", l)
                   if (sub(/^@echo /, "", l)) { if (l ~ /^".*"\$/) l = substr(l, 2, length(l) - 2); print l }
                   next }
  { on = 0 }
  END { exit !found }' "\$2" || { echo "error: justfile does not contain recipe \$3" >&2; exit 1; }
EOF
  chmod +x "$TMP/bin/just"
}

# A stand-in for Herdr's `hc`, for tests that want it installed. It logs each
# call's arguments on one line and exits with the given code.
stub_hc() {
  printf '#!/usr/bin/env bash\necho "$*" >> "%s"\nexit %s\n' "$TMP/hc-calls.log" "${1:-0}" > "$TMP/bin/hc"
  chmod +x "$TMP/bin/hc"
}
hc_calls() { cat "$TMP/hc-calls.log" 2>/dev/null; }

# --- a worktree's copy ------------------------------------------------------

# Make the case's copy of entourage a worktree's: its .git folder becomes a
# file naming a folder in another repo's worktrees/ folder, as `git worktree
# add` leaves it. The usual copy, with a .git folder, is a main checkout's.
as_worktree() {
  rm -rf "$REPO/.git"
  mkdir -p "$TMP/main/.git/worktrees/repo"
  printf 'gitdir: %s\n' "$TMP/main/.git/worktrees/repo" > "$REPO/.git"
}

# Every folder, file and link under the throwaway HOME, one per line: a file
# with its checksum, a link with where it points. When two snapshots match,
# nothing on the machine changed in between: the projects and their tasks,
# the hand-off store, the env file, Herdr's links, the skills, and Claude
# Code's own file all live under HOME.
machine_snapshot() {
  local f
  (cd "$HOME" && find . -print | LC_ALL=C sort | while IFS= read -r f; do
    if [ -L "$f" ]; then printf 'link %s -> %s\n' "$f" "$(readlink "$f")"
    elif [ -f "$f" ]; then printf 'file %s %s\n' "$f" "$(cksum < "$f")"
    elif [ -d "$f" ]; then printf 'dir  %s\n' "$f"
    else printf 'else %s\n' "$f"
    fi
  done)
}

# --- Claude Code's own file -------------------------------------------------

# Claude Code's own file in the throwaway HOME, holding the given JSON ({} when
# none is given), with the permissions Claude Code gives it.
claude_state() {
  local json=${1:-}
  [ -n "$json" ] || json='{}'
  printf '%s\n' "$json" > "$HOME/.claude.json"
  chmod 600 "$HOME/.claude.json"
}

# Whether Claude Code would start in a folder without asking. $2 is the state
# file, when it is not the one in HOME.
is_trusted() {
  jq -e --arg d "$1" '.projects[$d].hasTrustDialogAccepted == true' "${2:-$HOME/.claude.json}" >/dev/null 2>&1
}

# A PATH with every command but jq, for a machine that does not have it.
hide_jq() {
  mkdir "$TMP/nojq"
  ln -s /usr/bin/* /bin/* "$TMP/nojq/" 2>/dev/null
  rm -f "$TMP/nojq/jq"
  export PATH=$TMP/bin:$TMP/nojq
}

# A stand-in for jq 1.6, which Debian 12 and Ubuntu 22.04 ship. With -e it
# exits zero when it is given no JSON at all, where later versions exit 4.
# This one exits zero wherever the real jq exits 4, which covers that.
old_jq() {
  local real
  real=$(command -v jq)
  cat > "$TMP/bin/jq" <<EOF
#!/usr/bin/env bash
"$real" "\$@"
code=\$?
[ "\$code" = 4 ] && exit 0
exit "\$code"
EOF
  chmod +x "$TMP/bin/jq"
}

# Fail if a run left a temp file or a lock beside the state file. $1 is the
# folder the state file is in, when it is not HOME.
no_trust_litter() {
  local f
  for f in "${1:-$HOME}"/.claude.json.*; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    fail "left behind: $f"
  done
}

# --- Linear -----------------------------------------------------------------

# A Linear API key for tests. No test reaches Linear, so it opens nothing.
KEY=lin_api_Test0123456789

# entourage's own environment file in the throwaway HOME.
env_file() { printf '%s' "$HOME/.config/entourage/.env"; }

# A machine where the key is already saved, as `linear key` leaves it.
saved_key() {
  mkdir -p "$HOME/.config/entourage"
  printf 'LINEAR_API_KEY=%s\n' "${1:-$KEY}" > "$(env_file)"
  chmod 600 "$(env_file)"
}

# The key the environment file holds, or nothing.
key_in_file() { sed -n 's/^LINEAR_API_KEY=//p' "$(env_file)" 2>/dev/null; }

# The key curl was last handed on stdin, or nothing.
key_given_to_curl() { sed -n 's/^header = "Authorization: \(.*\)"$/\1/p' "$TMP/curl-stdin.log" 2>/dev/null | tail -n 1; }

# A stand-in for `curl`, for tests that ask Linear something. Each call's
# arguments go on one line of curl-calls.log, and what it was given on stdin
# goes in curl-stdin.log. It answers its Nth call with $TMP/linear/N.json, or
# with the last answer there is, and then a line holding the HTTP status
# ($TMP/linear/N.status, else $TMP/linear/status, else 200), as the real one
# does for --write-out '\n%{http_code}'. With $TMP/linear/exit it answers
# nothing and exits with that code, as curl does when it cannot reach the
# server; with $TMP/linear/exit-from, it does that from the call it names on.
stub_linear() {
  mkdir -p "$TMP/linear"
  cat > "$TMP/bin/curl" <<EOF
#!/usr/bin/env bash
d="$TMP/linear"
printf '%s\n' "\$*" >> "$TMP/curl-calls.log"
cat >> "$TMP/curl-stdin.log"
n=\$(( \$(cat "\$d/count" 2>/dev/null || echo 0) + 1 ))
echo "\$n" > "\$d/count"
if [ -f "\$d/exit" ] || { [ -f "\$d/exit-from" ] && [ "\$n" -ge "\$(cat "\$d/exit-from")" ]; }; then
  echo "curl: (6) Could not resolve host: api.linear.app" >&2
  exit "\$(cat "\$d/exit" 2>/dev/null || echo 6)"
fi
status=\$(cat "\$d/\$n.status" 2>/dev/null || cat "\$d/status" 2>/dev/null || echo 200)
while [ ! -f "\$d/\$n.json" ] && [ "\$n" -gt 1 ]; do n=\$((n - 1)); done
[ ! -f "\$d/\$n.json" ] || cat "\$d/\$n.json"
printf '\n%s' "\$status"
EOF
  chmod +x "$TMP/bin/curl"
}

# What Linear answers next: one argument for each call, in order.
linear_answers() {
  local n=0 answer
  for answer in "$@"; do n=$((n + 1)); printf '%s\n' "$answer" > "$TMP/linear/$n.json"; done
}

# The HTTP status of every answer from now on.
linear_status() { echo "$1" > "$TMP/linear/status"; }
# The HTTP status of the Nth answer alone: linear_status_at <N> <status>.
linear_status_at() { echo "$2" > "$TMP/linear/$1.status"; }
# Linear out of reach from the Nth call on, as when the network goes.
linear_gone_from() { echo "$1" > "$TMP/linear/exit-from"; }

# Linear's answer when asked for one card: the card $1, titled $2, with $3 as
# its label in the Type group, or with no labels when $3 is empty. The title
# goes into the JSON as it is, so keep quotes and backslashes out of it.
card_answer() {
  local labels='[]'
  [ -z "${3:-}" ] || labels="[{\"name\":\"$3\",\"parent\":{\"name\":\"Type\"}}]"
  printf '{"data":{"issues":{"nodes":[{"identifier":"%s","title":"%s","labels":{"nodes":%s}}]}}}' "$1" "$2" "$labels"
}
# Linear's answer when it has no such card.
NO_CARD='{"data":{"issues":{"nodes":[]}}}'

# A Linear that has the card $1, titled $2, of the type $3, and a key to ask
# it with. The key is exported, so it is found wherever entourage's home is
# and whatever a case writes in the env file.
linear_has_card() {
  export LINEAR_API_KEY=$KEY
  stub_linear
  linear_answers "$(card_answer "$@")"
}

# A team's statuses as Linear keeps them, each with its kind and its place in
# the team's order, listed out of that order as Linear may send them. Lab's
# and PHY's, with two started statuses:
LAB_STATUSES='[{"id":"s-review","name":"In Review","type":"started","position":4},
  {"id":"s-done","name":"Done","type":"completed","position":5},
  {"id":"s-progress","name":"In Progress","type":"started","position":3},
  {"id":"s-todo","name":"Todo","type":"unstarted","position":2},
  {"id":"s-backlog","name":"Backlog","type":"backlog","position":1},
  {"id":"s-triage","name":"Triage","type":"triage","position":0},
  {"id":"s-canceled","name":"Canceled","type":"canceled","position":6},
  {"id":"s-duplicate","name":"Duplicate","type":"canceled","position":7}]'
# And a team that calls them something else.
OTHER_STATUSES='[{"id":"o-shipped","name":"Shipped","type":"completed","position":40},
  {"id":"o-checking","name":"Checking","type":"started","position":30},
  {"id":"o-doing","name":"Doing","type":"started","position":20},
  {"id":"o-waiting","name":"Waiting","type":"unstarted","position":10}]'
# A team like PHY's, whose cards start in Triage and whose first not-started
# status is Ready for Dev. It has two, listed out of their order.
PHY_STATUSES='[{"id":"p-triage","name":"Triage","type":"triage","position":0},
  {"id":"p-backlog","name":"Backlog","type":"backlog","position":1},
  {"id":"p-next","name":"Up Next","type":"unstarted","position":3},
  {"id":"p-ready","name":"Ready for Dev","type":"unstarted","position":2},
  {"id":"p-progress","name":"In Progress","type":"started","position":4},
  {"id":"p-done","name":"Done","type":"completed","position":5}]'

# A card as a move's answer lists it: the card $1, in its team's status
# named $2, with the team's statuses ($3 as JSON, or Lab's).
move_card() {
  jq -cn --arg card "$1" --arg now "$2" --argjson states "${3:-$LAB_STATUSES}" \
    '{id: ("id-" + $card), identifier: $card,
      state: ($states[] | select(.name == $now)), team: {states: {nodes: $states}}}'
}
# Linear's answer to a move's question: the card $1, in its team's status
# named $2, with the team's statuses ($3 as JSON, or Lab's), and its
# sub-issues ($4, a JSON list of move_card's, or none).
move_answer() {
  jq -cn --argjson card "$(move_card "$1" "$2" "${3:-}")" --argjson subs "${4:-[]}" \
    '{data: {issues: {nodes: [$card + {children: {nodes: $subs}}]}}}'
}
# Linear's answer to the move itself: the card now in the status named $1
# ($2 the team's statuses as JSON, or Lab's).
moved_answer() {
  jq -cn --arg now "$1" --argjson states "${2:-$LAB_STATUSES}" \
    '{data: {issueUpdate: {success: true, issue: {state: ($states[] | select(.name == $now))}}}}'
}
# Linear's answer to a change that a key with Read permission alone may not
# make, at HTTP 400.
NO_WRITE='{"errors":[{"message":"Invalid scope: `write` required","extensions":{"type":"forbidden","code":"FORBIDDEN","statusCode":403,"userError":true,"userPresentableMessage":"You need the write scope to make this change."}}]}'

# The calls that asked Linear to change a card, one line each.
changes_sent() { curl_calls | grep issueUpdate || true; }

# Every call made to curl, one line each, and how many there were.
curl_calls() { cat "$TMP/curl-calls.log" 2>/dev/null; }
curl_count() { curl_calls | grep -c '' || true; }

# A PATH with every command but curl, for a machine that does not have it.
hide_curl() {
  mkdir "$TMP/nocurl"
  ln -s /usr/bin/* /bin/* "$TMP/nocurl/" 2>/dev/null
  rm -f "$TMP/nocurl/curl" "$TMP/bin/curl"
  export PATH=$TMP/bin:$TMP/nocurl
}

# --- GitHub -----------------------------------------------------------------

# A stand-in for `gh`, for tests of the watch on a card's pull requests. It
# answers `gh pr list` in a worktree from the files the case writes for that
# worktree's repo, by its folder's name, one answer per check: the repo's Nth
# call gets $TMP/gh/<repo>/N.json, or the last answer there is, and a repo
# with no answers gets []. A task's worktrees are all on one branch, so the
# folder, not the branch, tells them apart. With $TMP/gh/<repo>/N.exit that
# call fails with that code, as gh does when it cannot reach GitHub. Each call
# goes on a line of gh-calls.log: the repo, then the arguments.
stub_gh() {
  mkdir -p "$TMP/gh"
  cat > "$TMP/bin/gh" <<EOF
#!/usr/bin/env bash
repo=\${PWD##*/}
d="$TMP/gh/\$repo"
printf '%s %s\n' "\$repo" "\$*" >> "$TMP/gh-calls.log"
mkdir -p "\$d"
n=\$(( \$(cat "\$d/count" 2>/dev/null || echo 0) + 1 ))
echo "\$n" > "\$d/count"
if [ -f "\$d/\$n.exit" ]; then
  echo "error connecting to api.github.com" >&2
  exit "\$(cat "\$d/\$n.exit")"
fi
while [ ! -f "\$d/\$n.json" ] && [ "\$n" -gt 1 ]; do n=\$((n - 1)); done
if [ -f "\$d/\$n.json" ]; then cat "\$d/\$n.json"; else echo '[]'; fi
EOF
  chmod +x "$TMP/bin/gh"
}

# What GitHub answers for the repo $1: one argument for each check, in order.
gh_answers() {
  local repo=$1 n=0 answer
  shift
  mkdir -p "$TMP/gh/$repo"
  for answer in "$@"; do n=$((n + 1)); printf '%s\n' "$answer" > "$TMP/gh/$repo/$n.json"; done
}

# The Nth check of the repo $1 fails: gh_fails_at <repo> <N>.
gh_fails_at() { mkdir -p "$TMP/gh/$1"; echo 1 > "$TMP/gh/$1/$2.exit"; }

# Forget every call to gh and to sleep, and every answer given so far, for a
# second watch in the same case.
gh_reset() { rm -rf "$TMP/gh" "$TMP/gh-calls.log" "$TMP/sleep-calls.log"; mkdir -p "$TMP/gh"; }

# `gh pr list`'s answer for one pull request: state $1 (OPEN, MERGED or
# CLOSED), URL $2, opened $3 seconds ago, and whether it can be merged, $4
# (MERGEABLE when left out, CONFLICTING, or UNKNOWN while GitHub works it out).
pr_answer() {
  jq -cn --arg state "$1" --arg url "$2" --argjson ago "$3" --arg mergeable "${4:-MERGEABLE}" \
    '[{url: $url, state: $state, mergeable: $mergeable, createdAt: ((now | floor) - $ago | todate)}]'
}

# Every call made to gh, one line each, and how many there were.
gh_calls() { cat "$TMP/gh-calls.log" 2>/dev/null; }
gh_count() { gh_calls | grep -c '' || true; }

# A stand-in for `sleep` that returns at once, logging the seconds it was
# given, one call to a line.
stub_sleep() {
  printf '#!/usr/bin/env bash\necho "$*" >> "%s"\n' "$TMP/sleep-calls.log" > "$TMP/bin/sleep"
  chmod +x "$TMP/bin/sleep"
}
# The seconds each sleep was given, in order, on one line.
sleeps() { cat "$TMP/sleep-calls.log" 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }
