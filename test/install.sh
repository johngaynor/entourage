# Tests for install, update and status. Sourced by test/run.sh.

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

# --- skills -----------------------------------------------------------------

install_links_skills() {
  "$E" install >/dev/null || fail "install exited non-zero"
  for s in sdlc-define sdlc-plan sdlc-breakdown sdlc-build sdlc-review sdlc-pr; do
    is_link_to "$SK/$s" "$REPO/skills/$s" || fail "$s not linked"
    [ -f "$SK/$s/SKILL.md" ] || fail "$s has no SKILL.md through the link"
  done
}

status_lists_skills() {
  out=$("$E" status) && fail "status exited zero with no skills linked"
  case $out in *"missing    skills/sdlc-define"*) ;; *) fail "status did not report the missing skill: $out" ;; esac
  "$E" install >/dev/null
  out=$("$E" status) || fail "status exited non-zero after install"
  case $out in *"linked     skills/sdlc-define"*) ;; *) fail "status did not list the linked skill: $out" ;; esac
}

update_links_a_new_skill() {
  "$E" install >/dev/null
  # A name no real skill has, so the folder is new to the copy of the repo.
  mkdir "$REPO/skills/made-up-skill" && echo x > "$REPO/skills/made-up-skill/SKILL.md"
  "$E" update --no-pull >/dev/null || fail "update exited non-zero"
  is_link_to "$SK/made-up-skill" "$REPO/skills/made-up-skill" || fail "new skill not linked"
}

update_removes_a_stale_skill_link() {
  "$E" install >/dev/null
  rm -rf "$REPO/skills/sdlc-plan"
  "$E" update --no-pull >/dev/null || fail "update exited non-zero"
  [ ! -L "$SK/sdlc-plan" ] || fail "stale skill link left behind"
  [ -L "$SK/sdlc-define" ] || fail "a live skill link was removed"
}

someone_elses_skills_are_left_alone() {
  mkdir -p "$SK/mine" "$TMP/elsewhere/theirs"
  echo mine > "$SK/mine/SKILL.md"
  ln -s "$TMP/elsewhere/theirs" "$SK/theirs"
  ln -s "$TMP/elsewhere/gone" "$SK/dangling"
  "$E" install >/dev/null
  "$E" update --no-pull >/dev/null
  [ "$(cat "$SK/mine/SKILL.md")" = mine ] || fail "someone's own skill was changed"
  [ -L "$SK/theirs" ] || fail "someone else's skill link was removed"
  [ -L "$SK/dangling" ] || fail "someone else's dangling skill link was removed"
}

a_real_skill_folder_is_never_replaced() {
  mkdir -p "$SK/sdlc-define"; echo mine > "$SK/sdlc-define/SKILL.md"
  out=$("$E" install) || fail "install exited non-zero"
  [ "$(cat "$SK/sdlc-define/SKILL.md")" = mine ] || fail "a real skill folder was replaced"
  case $out in *"skills/sdlc-define (a real file is in the way"*) ;; *) fail "no warning about the real skill folder: $out" ;; esac
}

a_folder_without_a_skill_file_is_not_linked() {
  mkdir "$REPO/skills/notes" && echo x > "$REPO/skills/notes/README.md"
  "$E" install >/dev/null || fail "install exited non-zero"
  [ ! -e "$SK/notes" ] || fail "linked a folder that has no SKILL.md"
}

honors_claude_config_dir() {
  export CLAUDE_CONFIG_DIR=$TMP/claude
  "$E" install >/dev/null || fail "install exited non-zero"
  is_link_to "$CLAUDE_CONFIG_DIR/skills/sdlc-define" "$REPO/skills/sdlc-define" || fail "did not link into CLAUDE_CONFIG_DIR"
  [ ! -e "$SK/sdlc-define" ] || fail "linked into the default folder too"
}

CASES="install_links_everything install_is_repeatable works_through_the_path_link
  update_links_a_new_mod update_removes_stale_links update_leaves_other_links_alone
  real_file_is_never_replaced update_refreshes_herdr status_reports_missing_links
  fails_without_herdr fails_before_herdr_first_run npm_install_skips_path_link
  npm_install_updates_through_npm npm_update_failure_changes_nothing honors_herdr_app_home
  install_links_skills status_lists_skills update_links_a_new_skill
  update_removes_a_stale_skill_link someone_elses_skills_are_left_alone
  a_real_skill_folder_is_never_replaced a_folder_without_a_skill_file_is_not_linked
  honors_claude_config_dir"
