# Tests for projects. Sourced by test/run.sh.

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

# --- project new: the folder is trusted by Claude Code ----------------------

project_new_trusts_its_folder() {
  claude_state '{"numStartups":3,"cost":0.1234,"at":1764259200123,"name":"café","projects":{"/other":{"allowedTools":["x"],"hasTrustDialogAccepted":false}}}'
  local out
  out=$("$E" project new demo) || fail "new exited non-zero"
  is_trusted "$P/demo" || fail "the project's folder is not trusted: $(cat "$HOME/.claude.json")"
  jq -e '.numStartups == 3 and .cost == 0.1234 and .at == 1764259200123 and .name == "café"
    and .projects["/other"].allowedTools == ["x"] and .projects["/other"].hasTrustDialogAccepted == false' \
    "$HOME/.claude.json" >/dev/null || fail "the rest of the file changed: $(cat "$HOME/.claude.json")"
  case $(ls -l "$HOME/.claude.json") in -rw-------*) ;; *) fail "permissions changed: $(ls -l "$HOME/.claude.json")" ;; esac
  case $'\n'$out in *$'\n'"  trusted   $P/demo "*) ;; *) fail "did not say the folder is trusted: $out" ;; esac
  no_trust_litter
}

project_new_without_claude_state_writes_none() {
  local out
  out=$("$E" project new demo) || fail "new exited non-zero"
  [ -f "$P/demo/PROJECT.md" ] || fail "the project was not made"
  [ ! -e "$HOME/.claude.json" ] || fail "made a state file for Claude Code"
  case $out in *"  note      "*"there is no $HOME/.claude.json yet"*) ;; *) fail "did not say why the folder is not trusted: $out" ;; esac
  no_trust_litter
}

project_new_without_jq_leaves_claude_state() {
  claude_state
  cp "$HOME/.claude.json" "$TMP/before"
  hide_jq
  local out
  out=$("$E" project new demo) || fail "new exited non-zero"
  [ -f "$P/demo/PROJECT.md" ] || fail "the project was not made"
  cmp -s "$HOME/.claude.json" "$TMP/before" || fail "the state file changed"
  case $out in *"jq is not installed"*) ;; *) fail "did not say jq is missing: $out" ;; esac
  no_trust_litter
}

# Not JSON, empty (jq prints nothing for it and exits zero), and JSON that is
# not the object Claude Code keeps.
project_new_leaves_broken_claude_state() {
  local name text out
  for name in a b c d; do
    case $name in a) text='{broken' ;; b) text='' ;; c) text='[]' ;; d) text='null' ;; esac
    printf '%s' "$text" > "$HOME/.claude.json"
    cp "$HOME/.claude.json" "$TMP/before"
    out=$("$E" project new "$name") || fail "new exited non-zero with the state file '$text'"
    [ -f "$P/$name/PROJECT.md" ] || fail "the project was not made with the state file '$text'"
    cmp -s "$HOME/.claude.json" "$TMP/before" || fail "the state file '$text' changed: $(cat "$HOME/.claude.json")"
    case $out in *"could not be updated"*) ;; *) fail "did not say the state file '$text' was left alone: $out" ;; esac
    no_trust_litter
  done
}

project_new_leaves_linked_claude_state() {
  echo '{}' > "$TMP/real.json"
  ln -s "$TMP/real.json" "$HOME/.claude.json"
  local out
  out=$("$E" project new demo) || fail "new exited non-zero"
  [ -L "$HOME/.claude.json" ] || fail "the link was replaced"
  [ "$(cat "$TMP/real.json")" = '{}' ] || fail "the linked file changed"
  case $out in *"is a link"*) ;; *) fail "did not say the state file is a link: $out" ;; esac
  no_trust_litter
}

# Claude Code holds a lock, a folder beside the file, while it writes.
project_new_leaves_claude_state_in_use() {
  claude_state
  cp "$HOME/.claude.json" "$TMP/before"
  mkdir "$HOME/.claude.json.lock"
  local out
  out=$("$E" project new demo) || fail "new exited non-zero"
  [ -f "$P/demo/PROJECT.md" ] || fail "the project was not made"
  cmp -s "$HOME/.claude.json" "$TMP/before" || fail "the state file changed while another program held it"
  [ -d "$HOME/.claude.json.lock" ] || fail "removed a lock it did not make"
  case $out in *"is in use"*) ;; *) fail "did not say the state file is in use: $out" ;; esac
  set -- "$HOME"/.claude.json.entourage.*
  [ ! -e "$1" ] || fail "left a temp file behind: $1"
}

project_new_trust_honors_claude_config_dir() {
  export CLAUDE_CONFIG_DIR=$TMP/cc
  mkdir "$CLAUDE_CONFIG_DIR"
  echo '{}' > "$CLAUDE_CONFIG_DIR/.claude.json"
  echo '{}' > "$HOME/.claude.json"
  "$E" project new demo >/dev/null || fail "new exited non-zero"
  is_trusted "$P/demo" "$CLAUDE_CONFIG_DIR/.claude.json" || fail "did not use CLAUDE_CONFIG_DIR"
  [ "$(cat "$HOME/.claude.json")" = '{}' ] || fail "wrote to the file in HOME too"
  no_trust_litter "$CLAUDE_CONFIG_DIR"
}

project_new_trusts_a_path_with_quotes() {
  claude_state
  export ENTOURAGE_HOME="$TMP/it's a \"home\""
  "$E" project new demo >/dev/null || fail "new exited non-zero"
  is_trusted "$ENTOURAGE_HOME/projects/demo" || fail "wrong key for a path with quotes: $(cat "$HOME/.claude.json")"
  no_trust_litter
}

# Claude Code looks a folder up by its real path, and /tmp on macOS is a link.
project_new_trusts_the_real_path() {
  claude_state
  mkdir "$TMP/real"
  ln -s "$TMP/real" "$TMP/link"
  export ENTOURAGE_HOME=$TMP/link
  "$E" project new demo >/dev/null || fail "new exited non-zero"
  is_trusted "$TMP/real/projects/demo" || fail "the real path is not trusted: $(cat "$HOME/.claude.json")"
  is_trusted "$TMP/link/projects/demo" && fail "the path through the link was written as a key"
  no_trust_litter
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

# --- status: what a repo provides -------------------------------------------

# The project "demo" with a filled-in doc and a repo folder for each name given.
status_demo() {
  local r
  "$E" install >/dev/null
  "$E" project new demo >/dev/null
  echo "# demo" > "$P/demo/PROJECT.md"
  for r in "$@"; do
    make_repo "$HOME/Dev/$r"
    "$E" project add demo "$HOME/Dev/$r" >/dev/null
  done
}

status_notes_a_repo_without_a_justfile() {
  stub_just; status_demo api
  out=$("$E" status) || fail "status exited non-zero for a note"
  case $out in *"note       demo: api has no justfile, so tasks start without setup"*) ;; *) fail "no note: $out" ;; esac
  case $out in *"ok         demo"*) ;; *) fail "the project is no longer ok: $out" ;; esac
}

status_notes_a_justfile_without_setup() {
  stub_just; status_demo api
  printf 'setup-db:\n\techo\npresetup:\n\techo\n' > "$HOME/Dev/api/justfile"
  out=$("$E" status) || fail "status exited non-zero for a note"
  case $out in *"note       demo: api's justfile has no setup recipe"*) ;; *) fail "no note: $out" ;; esac
}

status_is_quiet_when_setup_exists() {
  stub_just; status_demo api web
  printf 'setup:\n\techo\n' > "$HOME/Dev/api/justfile"
  printf 'build:\n\techo\nsetup: build\n\techo\n' > "$HOME/Dev/web/Justfile"
  out=$("$E" status) || fail "status exited non-zero"
  case $out in *note*) fail "a note for repos that have setup: $out" ;; esac
}

status_ignores_a_parent_justfile() {
  stub_just; status_demo api
  printf 'setup:\n\techo\n' > "$HOME/Dev/justfile"
  out=$("$E" status) || fail "status exited non-zero"
  case $out in *"api has no justfile"*) ;; *) fail "used a justfile from the folder above: $out" ;; esac
}

status_notes_an_unreadable_justfile() {
  stub_just; status_demo api
  printf 'BROKEN\nsetup:\n\techo\n' > "$HOME/Dev/api/justfile"
  out=$("$E" status) || fail "status exited non-zero for a note"
  case $out in *"note       demo: api's justfile could not be read by just"*) ;; *) fail "no note: $out" ;; esac
}

status_says_once_when_just_is_missing() {
  status_demo api web
  out=$("$E" status) || fail "status exited non-zero without just"
  [ "$(printf '%s\n' "$out" | grep -c 'just is not installed')" = 1 ] || fail "did not say once that just is missing: $out"
  case $out in *"has no justfile"*) fail "checked recipes without just: $out" ;; esac
}

# A stray file in the projects folder is not a project.
status_is_quiet_about_just_without_projects() {
  "$E" install >/dev/null
  mkdir -p "$P"; : > "$P/.DS_Store"
  out=$("$E" status) || fail "status exited non-zero"
  case $out in *"just is not installed"*) fail "mentioned just on a machine with no projects: $out" ;; esac
}

CASES="status_is_quiet_about_just_without_projects status_notes_a_repo_without_a_justfile status_notes_a_justfile_without_setup
  status_is_quiet_when_setup_exists status_ignores_a_parent_justfile
  status_notes_an_unreadable_justfile status_says_once_when_just_is_missing
  project_new_creates_from_template project_new_refuses_existing project_new_refuses_bad_name
  project_new_trusts_its_folder project_new_without_claude_state_writes_none
  project_new_without_jq_leaves_claude_state project_new_leaves_broken_claude_state
  project_new_leaves_linked_claude_state project_new_leaves_claude_state_in_use
  project_new_trust_honors_claude_config_dir project_new_trusts_a_path_with_quotes
  project_new_trusts_the_real_path
  project_ls_lists project_add_links_repo project_add_takes_a_relative_path
  project_add_refuses_non_repo project_add_refuses_duplicates project_add_handles_spaces
  project_add_unknown_project a_repo_can_be_in_two_projects stale_link_removed_real_file_kept
  project_open_makes_space project_open_selects_existing project_open_ignores_closed_spaces project_open_warns_missing_repo
  project_open_unknown_project status_reports_project_problems honors_entourage_home"
