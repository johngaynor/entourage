#!/usr/bin/env bash
# Tests for cli/entourage. Each case runs against a throwaway copy of the repo
# layout, a throwaway HOME, and a stub herdr-app, so nothing real is touched.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
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
  cp "$HERE/entourage" "$REPO/cli/entourage"
  echo x > "$REPO/herdr/mods/cpu/main.js"
  echo x > "$REPO/herdr/mods/layout-switch/main.js"
  echo '{}' > "$REPO/herdr/layouts/default.json"
  echo '{}' > "$REPO/herdr/layouts/test.json"
  mkdir -p "$APP/mods" "$APP/layouts" "$TMP/bin"
  # Stub herdr-app: logs calls, reports the "test" layout as shown.
  cat > "$TMP/bin/herdr-app" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$TMP/herdr-calls.log"
[ "\$1" = status ] && echo '  "layout": "test",'
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

install_links_everything() {
  "$E" install >/dev/null || fail "install exited non-zero"
  is_link_to "$APP/mods/cpu" "$REPO/herdr/mods/cpu" || fail "cpu mod not linked"
  is_link_to "$APP/mods/layout-switch" "$REPO/herdr/mods/layout-switch" || fail "layout-switch not linked"
  is_link_to "$APP/layouts/default.json" "$REPO/herdr/layouts/default.json" || fail "default layout not linked"
  is_link_to "$APP/layouts/test.json" "$REPO/herdr/layouts/test.json" || fail "test layout not linked"
  is_link_to "$HOME/.local/bin/entourage" "$REPO/cli/entourage" || fail "entourage not linked onto PATH"
}

install_is_repeatable() {
  "$E" install >/dev/null
  out=$("$E" install) || fail "second install exited non-zero"
  case $out in *"nothing new to link"*) ;; *) fail "second install linked something: $out" ;; esac
}

works_through_the_path_link() {
  "$E" install >/dev/null
  "$HOME/.local/bin/entourage" status >/dev/null || fail "status through the PATH link failed"
}

update_links_a_new_mod() {
  "$E" install >/dev/null
  mkdir "$REPO/herdr/mods/memory" && echo x > "$REPO/herdr/mods/memory/main.js"
  "$E" update --no-pull >/dev/null || fail "update exited non-zero"
  is_link_to "$APP/mods/memory" "$REPO/herdr/mods/memory" || fail "new mod not linked"
}

update_removes_stale_links() {
  "$E" install >/dev/null
  rm -rf "$REPO/herdr/mods/cpu"
  rm "$REPO/herdr/layouts/test.json"
  "$E" update --no-pull >/dev/null || fail "update exited non-zero"
  [ ! -L "$APP/mods/cpu" ] || fail "stale mod link left behind"
  [ ! -L "$APP/layouts/test.json" ] || fail "stale layout link left behind"
  [ -L "$APP/mods/layout-switch" ] || fail "a live link was removed"
}

update_leaves_other_links_alone() {
  mkdir -p "$TMP/elsewhere/mine"
  ln -s "$TMP/elsewhere/mine" "$APP/mods/mine"
  ln -s "$TMP/elsewhere/gone" "$APP/mods/dangling"
  "$E" update --no-pull >/dev/null
  [ -L "$APP/mods/mine" ] || fail "someone else's link was removed"
  [ -L "$APP/mods/dangling" ] || fail "someone else's dangling link was removed"
}

real_file_is_never_replaced() {
  rm -rf "$APP/mods/cpu"; mkdir "$APP/mods/cpu"; echo mine > "$APP/mods/cpu/main.js"
  echo mine > "$APP/layouts/default.json"
  out=$("$E" install) || fail "install exited non-zero"
  [ "$(cat "$APP/mods/cpu/main.js")" = mine ] || fail "real mod folder was replaced"
  [ "$(cat "$APP/layouts/default.json")" = mine ] || fail "real layout file was replaced"
  case $out in *"a real file is in the way"*) ;; *) fail "no warning about the real file" ;; esac
}

update_refreshes_herdr() {
  "$E" install >/dev/null
  : > "$TMP/herdr-calls.log"
  "$E" update --no-pull >/dev/null
  grep -q 'layout.switch {"name":"main"}' "$TMP/herdr-calls.log" || fail "did not switch away"
  grep -q 'layout.switch {"name":"test"}' "$TMP/herdr-calls.log" || fail "did not switch back to the shown layout"
}

status_reports_missing_links() {
  out=$("$E" status) && fail "status exited zero with nothing linked"
  case $out in *"missing"*) ;; *) fail "status did not report missing links" ;; esac
  "$E" install >/dev/null
  "$E" status >/dev/null || fail "status exited non-zero after install"
}

fails_without_herdr() {
  rm "$TMP/bin/herdr-app"
  out=$("$E" install 2>&1) && fail "install exited zero without Herdr"
  case $out in *"releases.herdr.dev/app/install.sh"*) ;; *) fail "no install hint" ;; esac
  [ ! -e "$APP/mods/cpu" ] || fail "linked something without Herdr"
}

fails_before_herdr_first_run() {
  rm -rf "$APP"
  out=$("$E" install 2>&1) && fail "install exited zero without Herdr's folder"
  case $out in *"Open Herdr once"*) ;; *) fail "no hint to open Herdr" ;; esac
  [ ! -d "$APP" ] || fail "created Herdr's folder itself"
}

# An npm install has no .git: it must not link itself onto PATH (npm did that).
npm_install_skips_path_link() {
  rmdir "$REPO/.git"
  "$E" install >/dev/null || fail "install exited non-zero"
  is_link_to "$APP/mods/cpu" "$REPO/herdr/mods/cpu" || fail "cpu mod not linked"
  [ ! -e "$HOME/.local/bin/entourage" ] || fail "linked itself onto PATH in an npm install"
}

# A stub command that logs its arguments and exits with the given code.
stub() {
  printf '#!/usr/bin/env bash\necho "$*" >> "%s"\nexit %s\n' "$TMP/$1-calls.log" "${2:-0}" > "$TMP/bin/$1"
  chmod +x "$TMP/bin/$1"
}

# An npm install updates through npm, then hands over to the new copy.
npm_install_updates_through_npm() {
  rmdir "$REPO/.git"
  stub npm; stub entourage
  "$E" update >/dev/null || fail "update exited non-zero"
  grep -q 'install -g github:johngaynor/entourage' "$TMP/npm-calls.log" 2>/dev/null || fail "did not reinstall through npm"
  grep -q 'update --no-pull' "$TMP/entourage-calls.log" 2>/dev/null || fail "did not hand over to the new copy"
}

npm_update_failure_changes_nothing() {
  rmdir "$REPO/.git"
  stub npm 1
  out=$("$E" update 2>&1) && fail "update exited zero when npm failed"
  [ ! -e "$APP/mods/cpu" ] || fail "linked after a failed npm install"
}

honors_herdr_app_home() {
  export HERDR_APP_HOME=$TMP/custom
  mkdir -p "$HERDR_APP_HOME"
  "$E" install >/dev/null || fail "install exited non-zero"
  is_link_to "$HERDR_APP_HOME/mods/cpu" "$REPO/herdr/mods/cpu" || fail "did not link into HERDR_APP_HOME"
  [ ! -e "$APP/mods/cpu" ] || fail "linked into the default folder too"
}

for c in install_links_everything install_is_repeatable works_through_the_path_link \
  update_links_a_new_mod update_removes_stale_links update_leaves_other_links_alone \
  real_file_is_never_replaced update_refreshes_herdr status_reports_missing_links \
  fails_without_herdr fails_before_herdr_first_run npm_install_skips_path_link \
  npm_install_updates_through_npm npm_update_failure_changes_nothing honors_herdr_app_home; do
  run_case "$c"
done

[ "$failures" = 0 ] && echo "all passed" || { echo "$failures failed"; exit 1; }
