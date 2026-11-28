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
  is_link_to "$CLAUDE_CONFIG_DIR/agents/entourage-build.md" "$REPO/agents/entourage-build.md" ||
    fail "did not link the profiles into CLAUDE_CONFIG_DIR"
  [ ! -e "$HOME/.claude/agents/entourage-build.md" ] || fail "linked a profile into the default folder too"
}

# --- agent profiles ---------------------------------------------------------

install_links_the_profiles() {
  "$E" install >/dev/null || fail "install exited non-zero"
  for a in entourage-write-up.md entourage-build.md; do
    is_link_to "$AG/$a" "$REPO/agents/$a" || fail "$a not linked into $AG"
    [ -f "$AG/$a" ] || fail "$a cannot be read through the link"
  done
  # The MCP config is handed to the agent by its path in the repo, not linked.
  [ ! -e "$AG/linear-mcp.json" ] && [ ! -L "$AG/linear-mcp.json" ] || fail "linked linear-mcp.json"
}

status_lists_the_profiles() {
  out=$("$E" status) && fail "status exited zero with no profiles linked"
  case $out in *"missing    agents/entourage-write-up.md"*) ;; *) fail "status did not report the missing profile: $out" ;; esac
  case $out in *"Agents: $HOME/.claude/agents"*) ;; *) fail "status did not say where profiles are linked: $out" ;; esac
  "$E" install >/dev/null
  out=$("$E" status) || fail "status exited non-zero after install"
  case $out in *"linked     agents/entourage-build.md"*) ;; *) fail "status did not list the linked profile: $out" ;; esac
  case $out in *linear-mcp*) fail "status lists linear-mcp.json: $out" ;; esac
}

update_links_a_new_profile() {
  "$E" install >/dev/null
  echo x > "$REPO/agents/made-up-profile.md"
  "$E" update --no-pull >/dev/null || fail "update exited non-zero"
  is_link_to "$AG/made-up-profile.md" "$REPO/agents/made-up-profile.md" || fail "new profile not linked"
}

update_removes_a_stale_profile_link() {
  "$E" install >/dev/null
  rm "$REPO/agents/entourage-build.md"
  out=$("$E" update --no-pull) || fail "update exited non-zero"
  [ ! -L "$AG/entourage-build.md" ] || fail "stale profile link left behind"
  [ -L "$AG/entourage-write-up.md" ] || fail "a live profile link was removed"
  case $out in *"removed  agents/entourage-build.md"*) ;; *) fail "did not say the stale link was removed: $out" ;; esac
}

someone_elses_agents_are_left_alone() {
  mkdir -p "$AG" "$TMP/elsewhere"
  echo mine > "$AG/mine.md"
  echo theirs > "$TMP/elsewhere/theirs.md"
  ln -s "$TMP/elsewhere/theirs.md" "$AG/theirs.md"
  ln -s "$TMP/elsewhere/gone.md" "$AG/dangling.md"
  echo mine > "$AG/entourage-build.md"
  out=$("$E" install) || fail "install exited non-zero"
  "$E" update --no-pull >/dev/null
  [ "$(cat "$AG/mine.md")" = mine ] || fail "someone's own agent was changed"
  [ -L "$AG/theirs.md" ] || fail "someone else's agent link was removed"
  [ -L "$AG/dangling.md" ] || fail "someone else's dangling agent link was removed"
  [ "$(cat "$AG/entourage-build.md")" = mine ] || fail "a real agent file was replaced"
  case $out in *"agents/entourage-build.md (a real file is in the way"*) ;; *) fail "no warning about the real agent file: $out" ;; esac
}

# --- the settings file ------------------------------------------------------

# Fail unless the settings file gives every profile Opus at xhigh, and names
# no other profile.
settings_are_the_defaults() {
  local f=$HOME/.config/entourage/settings.json p
  [ -f "$f" ] || { fail "there is no $f"; return; }
  [ "$(jq -r '.profiles | keys | join(" ")' "$f" 2>&1)" = "build reviewer verifier write-up" ] ||
    fail "the file does not name the four profiles: $(cat "$f")"
  for p in write-up build reviewer verifier; do
    [ "$(jq -r --arg p "$p" '.profiles[$p] | "\(.model) \(.effort)"' "$f" 2>&1)" = "opus xhigh" ] ||
      fail "$p is not on opus at xhigh: $(cat "$f")"
  done
}

install_makes_the_settings_file() {
  [ ! -e "$HOME/.config/entourage/settings.json" ] || fail "the case started with a settings file"
  out=$("$E" install) || fail "install exited non-zero: $out"
  settings_are_the_defaults
  case $out in *"made     $HOME/.config/entourage/settings.json"*) ;; *) fail "did not say it made the file: $out" ;; esac
}

update_makes_a_missing_settings_file() {
  "$E" install >/dev/null
  rm "$HOME/.config/entourage/settings.json"
  "$E" update --no-pull >/dev/null || fail "update exited non-zero"
  settings_are_the_defaults
}

# A file that is there is the human's, even one that is not valid settings.
install_and_update_leave_the_settings_file_alone() {
  local f=$HOME/.config/entourage/settings.json before body
  mkdir -p "$HOME/.config/entourage"
  for body in '{ "profiles" : {"build": {"effort":"high"}},
"mine": 1 }' 'not json at all'; do
    printf '%s' "$body" > "$f"
    before=$(cksum < "$f")
    out=$("$E" install 2>&1) || fail "install exited non-zero with the file '$body': $out"
    "$E" update --no-pull >/dev/null 2>&1 || fail "update exited non-zero with the file '$body'"
    [ "$(cksum < "$f")" = "$before" ] || fail "the file '$body' was changed: $(cat "$f")"
    case $out in *"made     "*settings.json*) fail "said it made a file that was there: $out" ;; esac
  done
}

# --- the review subagents ---------------------------------------------------

# The frontmatter of a profile, without its --- lines, and what comes after it.
front() { awk 'NR == 1 { next } $0 == "---" { exit } { print }' "$1"; }
body() { awk 'h >= 2 { print; next } $0 == "---" { h++ }' "$1"; }

# A clone writes the reviewer and the verifier into Claude Code's agents
# folder: the source in the repo, with the model and effort the settings file
# names for it, and a mark naming the source.
install_writes_the_review_profiles() {
  mkdir -p "$HOME/.config/entourage"
  echo '{"profiles":{"reviewer":{"model":"sonnet","effort":"high"}}}' > "$HOME/.config/entourage/settings.json"
  out=$("$E" install) || fail "install exited non-zero: $out"
  local spec p model effort src dst fm
  for spec in reviewer:sonnet:high verifier:opus:xhigh; do
    IFS=: read -r p model effort <<< "$spec"
    src=$REPO/.claude/profiles/entourage-$p.md dst=$AG/entourage-$p.md
    [ -f "$dst" ] && [ ! -L "$dst" ] || { fail "entourage-$p.md was not written into $AG"; continue; }
    [ "$(body "$dst")" = "$(body "$src")" ] || fail "entourage-$p.md does not have its source's instructions"
    [ -n "$(body "$dst")" ] || fail "entourage-$p.md has no instructions"
    fm=$(front "$dst")
    printf '%s\n' "$fm" | grep -qx "model: $model" || fail "entourage-$p.md is not on $model: $fm"
    printf '%s\n' "$fm" | grep -qx "effort: $effort" || fail "entourage-$p.md is not at $effort: $fm"
    printf '%s\n' "$fm" | grep -qxF "# Written by entourage from $src" || fail "entourage-$p.md does not name its source: $fm"
    [ "$(printf '%s\n' "$fm" | grep -v -e '^model: ' -e '^effort: ' -e '^#')" = "$(front "$src")" ] ||
      fail "entourage-$p.md does not keep its source's frontmatter: $fm"
    [ "$(printf '%s\n' "$fm" | grep -A1 '^tools:' | tail -n 1)" = "model: $model" ] || fail "the model does not come after the tools: $fm"
    case $out in *"wrote    agents/entourage-$p.md ($model, $effort effort)"*) ;; *) fail "did not say it wrote entourage-$p.md: $out" ;; esac
  done
  # A person's own reviewer has the plain names; entourage takes neither.
  [ ! -e "$AG/reviewer.md" ] && [ ! -e "$AG/verifier.md" ] || fail "wrote reviewer.md or verifier.md"
  "$E" install >/dev/null || fail "a second install exited non-zero"
  out=$("$E" install) || fail "a third install exited non-zero"
  case $out in *"entourage-reviewer"*) fail "a second install wrote the reviewer again: $out" ;; esac
}

# A review subagent is stale when the settings or its source have changed
# since it was written. update writes it again, and only it.
update_rewrites_a_stale_review_profile() {
  "$E" install >/dev/null
  local f=$HOME/.config/entourage/settings.json
  jq '.profiles.reviewer.effort = "high"' "$f" > "$f.new" && mv "$f.new" "$f"
  out=$("$E" status) && fail "status exited zero with a stale reviewer"
  case $out in *"stale      agents/entourage-reviewer.md"*"written    agents/entourage-verifier.md"*) ;; *) fail "status did not show the reviewer stale: $out" ;; esac
  out=$("$E" update --no-pull) || fail "update exited non-zero: $out"
  grep -qx 'effort: high' "$AG/entourage-reviewer.md" || fail "the reviewer was not written at high: $(cat "$AG/entourage-reviewer.md")"
  case $out in *"wrote    agents/entourage-reviewer.md (opus, high effort)"*) ;; *) fail "did not say it wrote the reviewer: $out" ;; esac
  case $out in *"entourage-verifier"*) fail "wrote the verifier, which was not stale: $out" ;; esac
  "$E" status >/dev/null || fail "status exited non-zero after update"
  echo "One more rule." >> "$REPO/.claude/profiles/entourage-verifier.md"
  "$E" update --no-pull >/dev/null || fail "update exited non-zero"
  [ "$(tail -n 1 "$AG/entourage-verifier.md")" = "One more rule." ] || fail "the verifier was not written again from its changed source"
}

# A file entourage did not write is someone's own, and is never changed:
# one with no mark, or a link.
a_persons_reviewer_file_is_left_alone() {
  mkdir -p "$AG" "$TMP/elsewhere"
  printf -- '---\nname: entourage-reviewer\nmodel: haiku\n---\nmine\n' > "$AG/entourage-reviewer.md"
  echo theirs > "$TMP/elsewhere/verifier.md"
  ln -s "$TMP/elsewhere/verifier.md" "$AG/entourage-verifier.md"
  echo mine > "$AG/reviewer.md"
  local before
  before=$(machine_snapshot | grep '/\.claude/agents/')
  out=$("$E" install) || fail "install exited non-zero: $out"
  "$E" update --no-pull >/dev/null || fail "update exited non-zero"
  "$E" profile set reviewer effort low >/dev/null || fail "profile set exited non-zero"
  [ "$(machine_snapshot | grep '/\.claude/agents/' | grep -v 'entourage-build\|entourage-write-up')" = "$before" ] ||
    fail "a person's file was changed: $(machine_snapshot | grep '/\.claude/agents/')"
  case $out in *"skipped  agents/entourage-reviewer.md (a file of your own is there"*) ;; *) fail "did not say the reviewer was skipped: $out" ;; esac
  case $out in *"skipped  agents/entourage-verifier.md (a file of your own is there"*) ;; *) fail "did not say the verifier was skipped: $out" ;; esac
  out=$("$E" status) && fail "status exited zero with the review subagents skipped"
  case $out in *"skipped    agents/entourage-reviewer.md"*) ;; *) fail "status did not show the reviewer skipped: $out" ;; esac
}

# Only a clone works on entourage, so an npm install writes neither, and
# status does not list them.
npm_install_writes_no_review_profiles() {
  rmdir "$REPO/.git"
  out=$("$E" install) || fail "install exited non-zero: $out"
  [ ! -e "$AG/entourage-reviewer.md" ] && [ ! -e "$AG/entourage-verifier.md" ] || fail "an npm install wrote a review subagent"
  out=$("$E" status) || fail "status exited non-zero: $out"
  case $out in *entourage-reviewer* | *entourage-verifier*) fail "status lists the review subagents: $out" ;; esac
  "$E" profile set reviewer model sonnet >/dev/null || fail "profile set exited non-zero"
  [ ! -e "$AG/entourage-reviewer.md" ] || fail "profile set wrote the reviewer on an npm install"
}

status_lists_the_review_profiles() {
  out=$("$E" status) && fail "status exited zero with nothing written"
  case $out in *"missing    agents/entourage-reviewer.md"*"missing    agents/entourage-verifier.md"*) ;; *) fail "status did not list them as missing: $out" ;; esac
  "$E" install >/dev/null
  out=$("$E" status) || fail "status exited non-zero after install: $out"
  case $out in *"written    agents/entourage-reviewer.md"*"written    agents/entourage-verifier.md"*) ;; *) fail "status did not list them as written: $out" ;; esac
}

# One entourage wrote from a source that has left the repo is removed. One
# written from another clone is that clone's, and is left.
update_removes_a_review_profile_whose_source_is_gone() {
  "$E" install >/dev/null
  printf -- '---\nname: entourage-other\n# Written by entourage from %s\n---\n' "$TMP/other/.claude/profiles/entourage-other.md" > "$AG/entourage-other.md"
  rm "$REPO/.claude/profiles/entourage-verifier.md"
  out=$("$E" update --no-pull) || fail "update exited non-zero: $out"
  [ ! -e "$AG/entourage-verifier.md" ] || fail "the verifier was left behind"
  [ -f "$AG/entourage-reviewer.md" ] || fail "the reviewer was removed"
  [ -f "$AG/entourage-other.md" ] || fail "another clone's file was removed"
  case $out in *"removed  agents/entourage-verifier.md (no longer in the repo)"*) ;; *) fail "did not say the verifier was removed: $out" ;; esac
}

# A file that is not valid settings stops task new and task build, so status
# says so, on an npm install too.
status_says_the_settings_file_is_not_valid() {
  rmdir "$REPO/.git"
  "$E" install >/dev/null
  "$E" status >/dev/null || fail "status exited non-zero with valid settings"
  echo '{"profiles":{"build":{"effort":"extreme"}}}' > "$HOME/.config/entourage/settings.json"
  out=$("$E" status) && fail "status exited zero with a broken settings file: $out"
  case $out in *"problem    $HOME/.config/entourage/settings.json is not valid settings: the effort of build is \"extreme\""*) ;;
    *) fail "status did not say what is wrong with the file: $out" ;; esac
}

CASES="install_links_everything install_is_repeatable works_through_the_path_link
  update_links_a_new_mod update_removes_stale_links update_leaves_other_links_alone
  real_file_is_never_replaced update_refreshes_herdr status_reports_missing_links
  fails_without_herdr fails_before_herdr_first_run npm_install_skips_path_link
  npm_install_updates_through_npm npm_update_failure_changes_nothing honors_herdr_app_home
  install_links_skills status_lists_skills update_links_a_new_skill
  update_removes_a_stale_skill_link someone_elses_skills_are_left_alone
  a_real_skill_folder_is_never_replaced a_folder_without_a_skill_file_is_not_linked
  honors_claude_config_dir install_links_the_profiles status_lists_the_profiles
  update_links_a_new_profile update_removes_a_stale_profile_link someone_elses_agents_are_left_alone
  install_makes_the_settings_file update_makes_a_missing_settings_file
  install_and_update_leave_the_settings_file_alone
  install_writes_the_review_profiles update_rewrites_a_stale_review_profile
  a_persons_reviewer_file_is_left_alone npm_install_writes_no_review_profiles
  status_lists_the_review_profiles update_removes_a_review_profile_whose_source_is_gone
  status_says_the_settings_file_is_not_valid"
