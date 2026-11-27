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

# --- tasks ------------------------------------------------------------------

task_new_refuses_bad_branch() {
  "$E" project new demo >/dev/null
  for b in main master develop abc-122-x Feature/Add-Login feature/new--login \
           feature/-new-login feature/new-login- release/v1.-2.0 "fix/header bug" \
           fix/header_bug unknown/some-task feat/ feat/a/b ""; do
    "$E" task new demo "$b" >/dev/null 2>"$TMP/err" && fail "accepted the branch '$b'"
    grep -q conventionalbranch.org "$TMP/err" || fail "no naming hint for '$b'"
  done
  [ ! -e "$P/demo/tasks" ] || fail "made a tasks folder for a refused branch"
}

task_new_refuses_unknown_project() {
  "$E" task new nope feat/abc-1-x >/dev/null 2>&1 && fail "accepted a project that does not exist"
  [ ! -e "$P/nope" ] || fail "made a project folder"
}

task_usage_on_unknown_subcommand() {
  "$E" task >/dev/null 2>&1 && fail "bare 'task' exited zero"
  "$E" task frob >/dev/null 2>&1 && fail "'task frob' exited zero"
}

# A real repo at $1 with one commit on main, cloned from a bare origin at $1.origin.git.
make_git_repo() {
  mkdir -p "$(dirname "$1")"
  git init -q -b main "$1.seed"
  git -C "$1.seed" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  git clone -q --bare "$1.seed" "$1.origin.git"
  git clone -q "$1.origin.git" "$1"
  rm -rf "$1.seed"
}
branch_of() { git -C "$1" rev-parse --abbrev-ref HEAD; }
head_of() { git -C "$1" rev-parse "${2:-HEAD}"; }
has_branch() { git -C "$1" show-ref --verify --quiet "refs/heads/$2"; }

# The project "demo" with a real repo for each name given.
task_demo() {
  local r
  "$E" project new demo >/dev/null
  for r in "$@"; do
    make_git_repo "$HOME/Dev/$r"
    "$E" project add demo "$HOME/Dev/$r" >/dev/null
  done
  API=$HOME/Dev/api T=$P/demo/tasks
}

task_new_makes_a_worktree() {
  task_demo api
  "$E" task new demo feat/abc-122-insert-task-here >/dev/null || fail "task new exited non-zero"
  local wt=$T/abc-122-insert-task-here/api
  [ -d "$wt" ] || fail "no worktree at tasks/<task>/<repo>"
  [ "$(branch_of "$wt")" = feat/abc-122-insert-task-here ] || fail "worktree is on $(branch_of "$wt")"
  [ "$(head_of "$wt")" = "$(head_of "$API" origin/main)" ] || fail "not cut from origin/main"
}

task_new_accepts_every_spec_name() {
  task_demo api
  local b
  for b in feature/add-login-page feat/add-login-page2 bugfix/fix-header-bug fix/header-bug \
           hotfix/security-patch release/v1.2.0 chore/upgrade-node-v20.11 \
           feature/issue-123-new-login ai/refactor-auth-flow claude/security-patch2 \
           codex/optimize-query copilot/add-login-page3 cursor/fix-header-bug4; do
    "$E" task new demo "$b" >/dev/null 2>&1 || fail "refused the valid branch '$b'"
    [ -d "$T/${b#*/}/api" ] || fail "no worktree for '$b'"
  done
}

task_new_starts_from_the_latest_default_branch() {
  task_demo api
  git clone -q "$API.origin.git" "$TMP/other"
  git -C "$TMP/other" -c user.name=t -c user.email=t@t commit -q --allow-empty -m newer
  git -C "$TMP/other" push -q origin main
  "$E" task new demo feat/x >/dev/null || fail "task new exited non-zero"
  [ "$(head_of "$T/x/api")" = "$(head_of "$TMP/other")" ] || fail "did not start from the fetched commit"
}

task_new_works_offline() {
  task_demo api
  git -C "$API" remote set-url origin "$TMP/gone.git"
  local out
  out=$("$E" task new demo feat/x 2>/dev/null) || fail "task new exited non-zero offline"
  case $out in *warning*) ;; *) fail "no warning about the failed fetch: $out" ;; esac
  [ -d "$T/x/api" ] || fail "no worktree made offline"
}

task_new_without_origin_uses_local_default() {
  task_demo api
  git -C "$API" remote remove origin
  "$E" task new demo feat/x >/dev/null || fail "task new exited non-zero with no origin"
  [ "$(head_of "$T/x/api")" = "$(head_of "$API" main)" ] || fail "not cut from local main"
}

task_new_refuses_no_repos() {
  task_demo
  "$E" task new demo feat/x >/dev/null 2>&1 && fail "accepted a project with no repos"
  [ ! -e "$T" ] || fail "made a tasks folder"
}

task_new_refuses_missing_repo() {
  task_demo api
  echo "$HOME/Dev/gone" >> "$P/demo/repos"
  "$E" task new demo feat/x >/dev/null 2>&1 && fail "accepted a missing repo"
  [ ! -e "$T" ] || fail "made a tasks folder"
  has_branch "$API" feat/x && fail "made a branch in the repo that exists"
}

task_new_refuses_existing_task() {
  task_demo api
  "$E" task new demo feat/x >/dev/null || fail "first task new exited non-zero"
  "$E" task new demo fix/x >/dev/null 2>&1 && fail "made a second task with the same name"
  has_branch "$API" fix/x && fail "made the second task's branch"
}

task_new_refuses_existing_branch() {
  task_demo api
  git -C "$API" branch feat/x
  "$E" task new demo feat/x >/dev/null 2>&1 && fail "reused an existing branch"
  [ ! -e "$T/x" ] || fail "made a task folder"
}

task_new_refuses_branch_on_origin() {
  task_demo api
  git -C "$API.origin.git" branch feat/x
  "$E" task new demo feat/x >/dev/null 2>&1 && fail "reused a branch that is on origin"
  [ ! -e "$T/x" ] || fail "made a task folder"
  has_branch "$API" feat/x && fail "made a local branch"
}

task_new_leaves_the_main_checkout_alone() {
  task_demo api
  git -C "$API" checkout -q -b wip
  echo mine > "$API/untracked.txt"
  local before
  before=$(branch_of "$API"):$(git -C "$API" status --porcelain)
  "$E" task new demo feat/x >/dev/null || fail "task new exited non-zero"
  [ "$(branch_of "$API"):$(git -C "$API" status --porcelain)" = "$before" ] || fail "the main checkout changed"
}

task_new_after_hand_deletion() {
  task_demo api
  "$E" task new demo feat/x >/dev/null || fail "first task new exited non-zero"
  rm -rf "$T/x"
  git -C "$API" branch -q -D feat/x 2>/dev/null || { git -C "$API" worktree prune; git -C "$API" branch -q -D feat/x; }
  "$E" task new demo feat/x >/dev/null 2>&1 || fail "could not remake a task deleted by hand"
  [ -d "$T/x/api" ] || fail "no worktree after remaking"
}

task_new_several_repos() {
  task_demo api web
  "$E" task new demo feat/x >/dev/null || fail "task new exited non-zero"
  [ "$(branch_of "$T/x/api")" = feat/x ] || fail "api worktree not on feat/x"
  [ "$(branch_of "$T/x/web")" = feat/x ] || fail "web worktree not on feat/x"
  is_link_to "$T/x/CLAUDE.md" ../../PROJECT.md || fail "CLAUDE.md not linked to the project doc"
  is_link_to "$T/x/AGENTS.md" ../../PROJECT.md || fail "AGENTS.md not linked to the project doc"
  [ -f "$T/x/CLAUDE.md" ] || fail "the CLAUDE.md link does not resolve"
}

task_new_one_repo_has_no_links() {
  task_demo api
  "$E" task new demo feat/x >/dev/null || fail "task new exited non-zero"
  [ ! -e "$T/x/CLAUDE.md" ] && [ ! -L "$T/x/CLAUDE.md" ] || fail "linked CLAUDE.md beside a single repo"
}

task_new_undoes_a_failed_run() {
  task_demo api web
  # A file where git keeps its worktrees makes `git worktree add` fail in web.
  : > "$HOME/Dev/web/.git/worktrees"
  "$E" task new demo feat/x >/dev/null 2>&1 && fail "exited zero when a worktree could not be made"
  rm -f "$HOME/Dev/web/.git/worktrees"
  [ ! -e "$T/x" ] || fail "left the task folder behind"
  has_branch "$API" feat/x && fail "left the branch behind in api"
  has_branch "$HOME/Dev/web" feat/x && fail "left the branch behind in web"
  [ "$(git -C "$API" worktree list | wc -l | tr -d ' ')" = 1 ] || fail "left the worktree behind in api"
}

last_call() { tail -n 1 "$TMP/herdr-calls.log"; }

task_new_opens_a_tab_one_repo() {
  task_demo api
  "$E" task new demo feat/x >/dev/null || fail "task new exited non-zero"
  [ "$(last_call)" = "do tab.new {\"name\":\"x\",\"folder\":\"$T/x/api\"}" ] || fail "wrong last call: $(last_call)"
  sed '$d' "$TMP/herdr-calls.log" | grep -qF "do space.new {\"name\":\"demo\",\"folder\":\"$P/demo\"}" ||
    fail "did not make the space before the tab: $(cat "$TMP/herdr-calls.log")"
}

task_new_opens_a_tab_several_repos() {
  task_demo api web
  "$E" task new demo feat/x >/dev/null || fail "task new exited non-zero"
  [ "$(last_call)" = "do tab.new {\"name\":\"x\",\"folder\":\"$T/x\"}" ] || fail "wrong last call: $(last_call)"
}

task_new_selects_an_open_space() {
  task_demo api
  cat > "$TMP/herdr-ls.json" <<EOF
{
  "spaces": [
    {
      "id": "spcmine",
      "name": "demo",
      "folder": "$P/demo",
      "tabs": []
    }
  ],
  "recent": []
}
EOF
  "$E" task new demo feat/x >/dev/null || fail "task new exited non-zero"
  grep -qF 'do space.select {"id":"spcmine"}' "$TMP/herdr-calls.log" || fail "did not select the open space"
  grep -q 'space.new' "$TMP/herdr-calls.log" && fail "made a second space"
  case $(last_call) in "do tab.new "*) ;; *) fail "the tab was not opened last: $(last_call)" ;; esac
}

task_new_needs_herdr_running() {
  task_demo api
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/herdr-app"
  "$E" task new demo feat/x >/dev/null 2>"$TMP/err" && fail "exited zero with Herdr not running"
  grep -q 'not running' "$TMP/err" || fail "did not say Herdr is not running: $(cat "$TMP/err")"
  [ ! -e "$T" ] || fail "made a tasks folder"
  has_branch "$API" feat/x && fail "made a branch"
}

task_new_repo_path_with_a_space() {
  "$E" project new demo >/dev/null
  make_git_repo "$HOME/Dev/my api"
  "$E" project add demo "$HOME/Dev/my api" >/dev/null
  "$E" task new demo feat/x >/dev/null || fail "task new exited non-zero"
  [ "$(branch_of "$P/demo/tasks/x/my api")" = feat/x ] || fail "no worktree at a path with a space"
  [ "$(last_call)" = "do tab.new {\"name\":\"x\",\"folder\":\"$P/demo/tasks/x/my api\"}" ] || fail "wrong last call: $(last_call)"
}

# The tab could not be opened: the task is kept, and the message says where it is.
task_new_keeps_the_task_when_the_tab_fails() {
  task_demo api
  cat > "$TMP/bin/herdr-app" <<'EOF'
#!/usr/bin/env bash
[ "$1" = status ] && echo '  "layout": "test",'
[ "$2" = tab.new ] && exit 1
exit 0
EOF
  "$E" task new demo feat/x >/dev/null 2>"$TMP/err" && fail "exited zero when the tab could not be opened"
  [ -d "$T/x/api" ] || fail "removed the task"
  grep -qF "$T/x/api" "$TMP/err" || fail "did not say where the task is: $(cat "$TMP/err")"
}

# --- tasks: what must survive, and what must not be left half-made ----------

task_new_refuses_a_repo_with_no_commits() {
  task_demo api
  git init -q -b main "$HOME/Dev/web"
  "$E" project add demo "$HOME/Dev/web" >/dev/null
  "$E" task new demo feat/x >/dev/null 2>&1 && fail "accepted a repo with no commits"
  [ ! -e "$T" ] || fail "left a tasks folder behind"
  has_branch "$API" feat/x && fail "left the branch behind in api"
}

# web's post-checkout hook interrupts entourage while it is making worktrees.
task_new_undoes_an_interrupted_run() {
  task_demo api web
  mkdir -p "$HOME/Dev/web/.git/hooks"
  printf '#!/bin/sh\nkill -TERM "$(ps -o ppid= -p $PPID | tr -d " ")"\n' > "$HOME/Dev/web/.git/hooks/post-checkout"
  chmod +x "$HOME/Dev/web/.git/hooks/post-checkout"
  "$E" task new demo feat/x >/dev/null 2>&1 && fail "exited zero after being interrupted"
  [ ! -e "$T" ] || fail "left a tasks folder behind: $(ls "$T" "$T"/* 2>/dev/null | tr '\n' ' ')"
  has_branch "$API" feat/x && fail "left the branch behind in api"
  has_branch "$HOME/Dev/web" feat/x && fail "left the branch behind in web"
}

# The space could not be shown: the task is kept, and the message says where it is.
task_new_keeps_the_task_when_the_space_fails() {
  task_demo api
  cat > "$TMP/bin/herdr-app" <<'STUB'
#!/usr/bin/env bash
[ "$1" = status ] && echo '  "layout": "test",'
[ "$2" = space.new ] && exit 1
exit 0
STUB
  "$E" task new demo feat/x >/dev/null 2>"$TMP/err" && fail "exited zero when the space could not be shown"
  [ -d "$T/x/api" ] || fail "removed the task"
  grep -qF "$T/x/api" "$TMP/err" || fail "did not say where the task is: $(cat "$TMP/err")"
}

task_new_branch_has_no_upstream() {
  task_demo api
  "$E" task new demo feat/x >/dev/null || fail "task new exited non-zero"
  git -C "$T/x/api" rev-parse -q --verify '@{u}' >/dev/null 2>&1 && fail "the new branch tracks $(git -C "$T/x/api" rev-parse --abbrev-ref '@{u}')"
}

task_new_refusal_keeps_the_first_task() {
  task_demo api
  "$E" task new demo feat/x >/dev/null || fail "first task new exited non-zero"
  echo work > "$T/x/api/work.txt"
  "$E" task new demo fix/x >/dev/null 2>&1 && fail "made a second task with the same name"
  [ "$(cat "$T/x/api/work.txt" 2>/dev/null)" = work ] || fail "the first task's work is gone"
  [ "$(branch_of "$T/x/api")" = feat/x ] || fail "the first task's worktree is gone"
}

task_new_refusal_keeps_an_existing_branch() {
  task_demo api
  git -C "$API" branch feat/x
  local before
  before=$(head_of "$API" feat/x)
  "$E" task new demo feat/x >/dev/null 2>&1 && fail "reused an existing branch"
  has_branch "$API" feat/x || fail "deleted the branch that was already there"
  [ "$(head_of "$API" feat/x)" = "$before" ] || fail "moved the branch that was already there"
}

# A task folder deleted by hand leaves git thinking its worktree is still there.
task_new_over_a_folder_deleted_by_hand() {
  task_demo api
  "$E" task new demo feat/x >/dev/null || fail "first task new exited non-zero"
  rm -rf "$T/x"
  "$E" task new demo fix/x >/dev/null 2>&1 || fail "could not make a task where one was deleted by hand"
  [ "$(branch_of "$T/x/api")" = fix/x ] || fail "no worktree on fix/x"
}

# A worktree whose folder is away for a while (an unmounted drive) must still work when it is back.
task_new_leaves_other_worktrees_alone() {
  task_demo api
  mkdir -p "$TMP/drive"
  git -C "$API" worktree add -q -b other "$TMP/drive/other" main
  echo staged > "$TMP/drive/other/f.txt"; git -C "$TMP/drive/other" add f.txt
  mv "$TMP/drive" "$TMP/drive.away"
  "$E" task new demo feat/x >/dev/null || fail "task new exited non-zero"
  mv "$TMP/drive.away" "$TMP/drive"
  [ "$(git -C "$TMP/drive/other" status --porcelain 2>/dev/null)" = "A  f.txt" ] || fail "another worktree was broken: $(git -C "$TMP/drive/other" status --porcelain 2>&1)"
}

TASK_CASES="task_new_refuses_a_repo_with_no_commits task_new_undoes_an_interrupted_run
  task_new_keeps_the_task_when_the_space_fails task_new_branch_has_no_upstream
  task_new_refusal_keeps_the_first_task task_new_refusal_keeps_an_existing_branch
  task_new_over_a_folder_deleted_by_hand task_new_leaves_other_worktrees_alone
  task_new_opens_a_tab_one_repo task_new_opens_a_tab_several_repos task_new_selects_an_open_space
  task_new_needs_herdr_running task_new_repo_path_with_a_space task_new_keeps_the_task_when_the_tab_fails
  task_new_several_repos task_new_one_repo_has_no_links task_new_undoes_a_failed_run
  task_new_refuses_bad_branch task_new_refuses_unknown_project task_usage_on_unknown_subcommand
  task_new_makes_a_worktree task_new_accepts_every_spec_name task_new_starts_from_the_latest_default_branch
  task_new_works_offline task_new_without_origin_uses_local_default task_new_refuses_no_repos
  task_new_refuses_missing_repo task_new_refuses_existing_task task_new_refuses_existing_branch
  task_new_refuses_branch_on_origin task_new_leaves_the_main_checkout_alone task_new_after_hand_deletion"

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
  project_open_unknown_project status_reports_project_problems honors_entourage_home \
  $TASK_CASES; do
  run_case "$c"
done

[ "$failures" = 0 ] && echo "all passed" || { echo "$failures failed"; exit 1; }
