# Shared by every test file. Each case runs against a throwaway copy of the
# repo layout, a throwaway HOME, and a stub herdr-app, so nothing real is
# touched. Sourced by test/run.sh.

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
failures=0
TMP=

fail() { printf 'FAIL: %s: %s\n' "$case_name" "$*"; failures=$((failures + 1)); case_failed=1; }

setup() {
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
  unset CLAUDE_CONFIG_DIR ENTOURAGE_AGENT
  SK=$HOME/.claude/skills
  unset ENTOURAGE_HOME
  P=$HOME/.config/entourage/projects
  mkdir -p "$APP/mods" "$APP/layouts" "$TMP/bin"
  # Stub herdr-app: logs calls, reports the "test" layout as shown.
  cat > "$TMP/bin/herdr-app" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$TMP/herdr-calls.log"
[ "\$1" = status ] && echo '  "layout": "test",'
[ "\$1" = ls ] && [ -f "$TMP/herdr-ls.json" ] && cat "$TMP/herdr-ls.json"
exit 0
EOF
  chmod +x "$TMP/bin/herdr-app"
  export PATH=$TMP/bin:/usr/bin:/bin
  E=$REPO/cli/entourage
}

run_case() {
  case_name=$1 case_failed=0
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
