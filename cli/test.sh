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
  mkdir -p "$REPO/herdr/projects/template"
  cp "$HERE/../herdr/projects/template/PROJECT.md" "$REPO/herdr/projects/template/PROJECT.md"
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
  grep -q 'install -g @johngaynor/entourage' "$TMP/npm-calls.log" 2>/dev/null || fail "did not reinstall through npm"
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

# --- projects ---------------------------------------------------------------

# A folder that looks like a clone, under the throwaway HOME.
make_repo() { mkdir -p "$1/.git"; }

project_new_creates_from_template() {
  "$E" project new demo >/dev/null || fail "new exited non-zero"
  grep -q '^# demo$' "$P/demo/PROJECT.md" || fail "name not put in the doc title"
  grep -qF '<!-- entourage:template -->' "$P/demo/PROJECT.md" || fail "template marker missing"
  [ -f "$P/demo/repos" ] && [ ! -s "$P/demo/repos" ] || fail "repos file not created empty"
  is_link_to "$P/demo/CLAUDE.md" PROJECT.md || fail "CLAUDE.md not linked to the doc"
  is_link_to "$P/demo/AGENTS.md" PROJECT.md || fail "AGENTS.md not linked to the doc"
}

project_new_refuses_existing() {
  "$E" project new demo >/dev/null
  echo mine > "$P/demo/PROJECT.md"
  "$E" project new demo >/dev/null 2>&1 && fail "second new exited zero"
  [ "$(cat "$P/demo/PROJECT.md")" = mine ] || fail "existing project was overwritten"
}

project_new_refuses_bad_name() {
  for n in Bad_Name ../up "two words" ""; do
    "$E" project new "$n" >/dev/null 2>&1 && fail "accepted the name '$n'"
  done
  [ ! -e "$HOME/.config/entourage/up" ] || fail "wrote outside the projects folder"
}

project_ls_lists() {
  out=$("$E" project ls) || fail "ls exited non-zero with no projects"
  case $out in *"No projects yet"*) ;; *) fail "no hint when empty: $out" ;; esac
  make_repo "$HOME/code/api"
  "$E" project new demo >/dev/null; "$E" project add demo "$HOME/code/api" >/dev/null
  out=$("$E" project ls)
  case $out in *demo*"$HOME/code/api"*) ;; *) fail "ls did not list the project and repo: $out" ;; esac
}

project_add_links_repo() {
  make_repo "$HOME/code/api"
  "$E" project new demo >/dev/null
  "$E" project add demo "$HOME/code/api" >/dev/null || fail "add exited non-zero"
  [ "$(cat "$P/demo/repos")" = '~/code/api' ] || fail "repos file is: $(cat "$P/demo/repos")"
  is_link_to "$P/demo/links/api" "$HOME/code/api" || fail "repo not linked"
}

project_add_takes_a_relative_path() {
  make_repo "$HOME/code/api"
  "$E" project new demo >/dev/null
  (cd "$HOME/code" && "$E" project add demo api >/dev/null) || fail "add exited non-zero"
  is_link_to "$P/demo/links/api" "$HOME/code/api" || fail "relative path not resolved"
}

project_add_refuses_non_repo() {
  mkdir -p "$HOME/code/plain"
  "$E" project new demo >/dev/null
  "$E" project add demo "$HOME/code/plain" >/dev/null 2>&1 && fail "added a folder that is not a repo"
  "$E" project add demo "$HOME/code/nowhere" >/dev/null 2>&1 && fail "added a folder that does not exist"
  [ ! -s "$P/demo/repos" ] || fail "repos file was written"
}

project_add_refuses_duplicates() {
  make_repo "$HOME/code/api"; make_repo "$HOME/other/api"
  "$E" project new demo >/dev/null
  "$E" project add demo "$HOME/code/api" >/dev/null
  "$E" project add demo "$HOME/code/api" >/dev/null 2>&1 && fail "added the same repo twice"
  "$E" project add demo "$HOME/other/api" >/dev/null 2>&1 && fail "added a second repo with the same folder name"
  [ "$(wc -l < "$P/demo/repos" | tr -d ' ')" = 1 ] || fail "repos file has extra lines"
}

project_add_handles_spaces() {
  make_repo "$HOME/my code/web app"
  "$E" project new demo >/dev/null
  "$E" project add demo "$HOME/my code/web app" >/dev/null || fail "add exited non-zero"
  is_link_to "$P/demo/links/web app" "$HOME/my code/web app" || fail "path with spaces not linked"
}

project_add_unknown_project() {
  make_repo "$HOME/code/api"
  out=$("$E" project add nope "$HOME/code/api" 2>&1) && fail "add to an unknown project exited zero"
  case $out in *"entourage project new nope"*) ;; *) fail "no hint to make it: $out" ;; esac
  [ ! -e "$P/nope" ] || fail "created the project"
}

a_repo_can_be_in_two_projects() {
  make_repo "$HOME/code/api"
  "$E" project new one >/dev/null; "$E" project new two >/dev/null
  "$E" project add one "$HOME/code/api" >/dev/null || fail "first add failed"
  "$E" project add two "$HOME/code/api" >/dev/null || fail "second add failed"
  is_link_to "$P/one/links/api" "$HOME/code/api" && is_link_to "$P/two/links/api" "$HOME/code/api" || fail "not linked in both"
}

stale_link_removed_real_file_kept() {
  make_repo "$HOME/code/api"; make_repo "$HOME/code/web"
  "$E" project new demo >/dev/null
  "$E" project add demo "$HOME/code/api" >/dev/null
  "$E" project add demo "$HOME/code/web" >/dev/null
  echo '~/code/web' > "$P/demo/repos"
  echo mine > "$P/demo/links/notes.txt"
  rm "$P/demo/links/web"; mkdir "$P/demo/links/web"
  out=$("$E" project open demo) || fail "open exited non-zero"
  [ ! -L "$P/demo/links/api" ] || fail "stale link left behind"
  [ -d "$HOME/code/api/.git" ] || fail "the repo itself was touched"
  [ "$(cat "$P/demo/links/notes.txt")" = mine ] || fail "a real file in links/ was removed"
  [ -d "$P/demo/links/web" ] && [ ! -L "$P/demo/links/web" ] || fail "a real folder was replaced"
  case $out in *"a real file is in the way"*) ;; *) fail "no warning about the real folder" ;; esac
}

project_open_makes_space() {
  make_repo "$HOME/code/api"
  "$E" project new demo >/dev/null; "$E" project add demo "$HOME/code/api" >/dev/null
  "$E" project open demo >/dev/null || fail "open exited non-zero"
  grep -qF "do space.new {\"name\":\"demo\",\"folder\":\"$P/demo\"}" "$TMP/herdr-calls.log" || fail "did not make the space: $(cat "$TMP/herdr-calls.log")"
}

project_open_selects_existing() {
  "$E" project new demo >/dev/null
  cat > "$TMP/herdr-ls.json" <<EOF
{
  "spaces": [
    {
      "id": "spcother",
      "name": "demo",
      "folder": "$HOME/somewhere/else",
      "tabs": [
        {
          "id": "tb1",
          "name": "1"
        }
      ]
    },
    {
      "id": "spcmine",
      "name": "renamed",
      "folder": "$P/demo",
      "tabs": [
        {
          "id": "tb2",
          "name": "1"
        }
      ]
    }
  ],
  "recent": []
}
EOF
  "$E" project open demo >/dev/null || fail "open exited non-zero"
  grep -qF 'do space.select {"id":"spcmine"}' "$TMP/herdr-calls.log" || fail "did not select the open space: $(cat "$TMP/herdr-calls.log")"
  grep -q 'space.new' "$TMP/herdr-calls.log" && fail "made a second space"
}

# A closed space is still listed under "recent"; it must not be mistaken for an open one.
project_open_ignores_closed_spaces() {
  "$E" project new demo >/dev/null
  cat > "$TMP/herdr-ls.json" <<EOF
{
  "spaces": [
    {
      "id": "spcother",
      "name": "other",
      "folder": "$HOME/somewhere/else",
      "tabs": []
    }
  ],
  "recent": [
    {
      "name": "demo",
      "folder": "$P/demo"
    }
  ]
}
EOF
  "$E" project open demo >/dev/null || fail "open exited non-zero"
  grep -q 'space.select' "$TMP/herdr-calls.log" && fail "selected another space for a closed project"
  grep -q 'space.new' "$TMP/herdr-calls.log" || fail "did not make a new space"
}

project_open_warns_missing_repo() {
  make_repo "$HOME/code/api"
  "$E" project new demo >/dev/null; "$E" project add demo "$HOME/code/api" >/dev/null
  rm -rf "$HOME/code/api"
  out=$("$E" project open demo) || fail "open exited non-zero with a missing repo"
  case $out in *"missing or is not a git repo"*) ;; *) fail "no warning: $out" ;; esac
}

project_open_unknown_project() {
  "$E" project open nope >/dev/null 2>&1 && fail "open of an unknown project exited zero"
  [ ! -e "$TMP/herdr-calls.log" ] || fail "called Herdr for an unknown project"
}

status_reports_project_problems() {
  "$E" install >/dev/null
  make_repo "$HOME/code/api"
  "$E" project new demo >/dev/null; "$E" project add demo "$HOME/code/api" >/dev/null
  out=$("$E" status) && fail "status exited zero with an unfinished doc"
  case $out in *"still the template"*) ;; *) fail "did not report the template doc: $out" ;; esac
  echo "# demo" > "$P/demo/PROJECT.md"
  "$E" status >/dev/null || fail "status exited non-zero for a good project"
  rm -rf "$HOME/code/api"
  out=$("$E" status) && fail "status exited zero with a missing repo"
  case $out in *"code/api is missing"*) ;; *) fail "did not report the missing repo: $out" ;; esac
}

honors_entourage_home() {
  export ENTOURAGE_HOME=$TMP/custom-ent
  "$E" project new demo >/dev/null || fail "new exited non-zero"
  [ -f "$ENTOURAGE_HOME/projects/demo/PROJECT.md" ] || fail "did not use ENTOURAGE_HOME"
  [ ! -e "$P/demo" ] || fail "wrote to the default folder too"
}

for c in install_links_everything install_is_repeatable works_through_the_path_link \
  update_links_a_new_mod update_removes_stale_links update_leaves_other_links_alone \
  real_file_is_never_replaced update_refreshes_herdr status_reports_missing_links \
  fails_without_herdr fails_before_herdr_first_run npm_install_skips_path_link \
  npm_install_updates_through_npm npm_update_failure_changes_nothing honors_herdr_app_home \
  project_new_creates_from_template project_new_refuses_existing project_new_refuses_bad_name \
  project_ls_lists project_add_links_repo project_add_takes_a_relative_path \
  project_add_refuses_non_repo project_add_refuses_duplicates project_add_handles_spaces \
  project_add_unknown_project a_repo_can_be_in_two_projects stale_link_removed_real_file_kept \
  project_open_makes_space project_open_selects_existing project_open_ignores_closed_spaces project_open_warns_missing_repo \
  project_open_unknown_project status_reports_project_problems honors_entourage_home; do
  run_case "$c"
done

[ "$failures" = 0 ] && echo "all passed" || { echo "$failures failed"; exit 1; }
