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
  # A key exported in the shell that runs the tests must not reach a case.
  unset CLAUDE_CONFIG_DIR ENTOURAGE_AGENT ENTOURAGE_SQLITE LINEAR_API_KEY
  SK=$HOME/.claude/skills
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
# justfile it cannot parse. Every call is logged.
stub_just() {
  cat > "$TMP/bin/just" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$TMP/just-calls.log"
[ "\$1" = --justfile ] && [ "\$3" = --summary ] || exit 2
grep -qx BROKEN "\$2" && { echo "error: could not parse" >&2; exit 1; }
sed -n 's/^\([a-zA-Z0-9_-][a-zA-Z0-9_-]*\):.*/\1/p' "\$2" | tr '\n' ' ' | sed 's/ \$//'
echo
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
# ($TMP/linear/status, or 200), as the real one does for
# --write-out '\n%{http_code}'. With $TMP/linear/exit it answers nothing and
# exits with that code, as curl does when it cannot reach the server.
stub_linear() {
  mkdir -p "$TMP/linear"
  cat > "$TMP/bin/curl" <<EOF
#!/usr/bin/env bash
d="$TMP/linear"
printf '%s\n' "\$*" >> "$TMP/curl-calls.log"
cat >> "$TMP/curl-stdin.log"
if [ -f "\$d/exit" ]; then
  echo "curl: (6) Could not resolve host: api.linear.app" >&2
  exit "\$(cat "\$d/exit")"
fi
n=\$(( \$(cat "\$d/count" 2>/dev/null || echo 0) + 1 ))
echo "\$n" > "\$d/count"
while [ ! -f "\$d/\$n.json" ] && [ "\$n" -gt 1 ]; do n=\$((n - 1)); done
[ ! -f "\$d/\$n.json" ] || cat "\$d/\$n.json"
printf '\n%s' "\$(cat "\$d/status" 2>/dev/null || echo 200)"
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
