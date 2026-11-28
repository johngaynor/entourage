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

# What the projects mod runs: the project and its repos in one command.
project_new_takes_repos() {
  make_repo "$HOME/code/api"; make_repo "$HOME/my code/web app"; make_repo "$TMP/elsewhere/tools"
  out=$(cd "$HOME/code" && "$E" project new demo api "$HOME/my code/web app" "$TMP/elsewhere/tools") ||
    fail "new with repos exited non-zero"
  want=$(printf '%s\n' '~/code/api' '~/my code/web app' "$TMP/elsewhere/tools")
  [ "$(cat "$P/demo/repos")" = "$want" ] || fail "repos file is: $(cat "$P/demo/repos")"
  is_link_to "$P/demo/links/api" "$HOME/code/api" || fail "relative path not linked"
  is_link_to "$P/demo/links/web app" "$HOME/my code/web app" || fail "path with spaces not linked"
  is_link_to "$P/demo/links/tools" "$TMP/elsewhere/tools" || fail "repo outside the home folder not linked"
  grep -q '^# demo$' "$P/demo/PROJECT.md" || fail "doc not made from the template"
  case $out in *"entourage project add"*) fail "told to add a repo when it has some: $out" ;; esac
  case $out in *"entourage project open demo"*) ;; *) fail "no hint to open it: $out" ;; esac
}

# A dialog that failed must leave nothing to clean up before the next try.
project_new_makes_nothing_when_a_repo_is_bad() {
  make_repo "$HOME/code/api"; make_repo "$HOME/other/api"; mkdir -p "$HOME/code/plain"
  out=$("$E" project new demo "$HOME/code/api" "$HOME/code/plain" 2>&1) && fail "took a folder that is not a repo"
  case $out in *"code/plain is not a git repo"*) ;; *) fail "did not say which folder: $out" ;; esac
  "$E" project new demo "$HOME/code/api" "$HOME/code/nowhere" >/dev/null 2>&1 && fail "took a folder that does not exist"
  out=$("$E" project new demo "$HOME/code/api" "$HOME/code/api" 2>&1) && fail "took the same repo twice"
  case $out in *"twice"*) ;; *) fail "did not say it was given twice: $out" ;; esac
  out=$("$E" project new demo "$HOME/code/api" "$HOME/other/api" 2>&1) && fail "took two repos with the same folder name"
  case $out in *"cannot share a folder name"*) ;; *) fail "did not explain the clash: $out" ;; esac
  [ ! -e "$P/demo" ] || fail "left a project behind"
  "$E" project new demo "$HOME/code/api" >/dev/null || fail "could not make it after the failures"
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
  # "may ask": without jq there is no telling whether the folder is trusted already.
  case $out in
    *"Claude Code may ask to trust $P/demo: jq is not installed"*) ;;
    *) fail "did not say jq is missing: $out" ;;
  esac
  no_trust_litter
}

# An rm that cannot remove the temp file, as when the state file is immutable
# and so is every copy of it.
project_new_survives_a_temp_file_it_cannot_remove() {
  claude_state
  cat > "$TMP/bin/rm" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  case $a in *.claude.json.entourage.*) echo "rm: $a: Operation not permitted" >&2; exit 1 ;; esac
done
exec /bin/rm "$@"
EOF
  chmod +x "$TMP/bin/rm"
  local out
  out=$("$E" project new demo 2>&1) || fail "new exited non-zero: $out"
  case $out in *"Made project 'demo'"*) ;; *) fail "the project was not reported made: $out" ;; esac
  case $out in *"Operation not permitted"*) fail "showed a raw error: $out" ;; esac
  is_trusted "$P/demo" || fail "the folder is not trusted"
  [ ! -e "$HOME/.claude.json.lock" ] || fail "left the lock behind"
}

# A sleep that fails, as one that does not take a fraction of a second would.
project_new_survives_a_sleep_that_fails() {
  claude_state
  mkdir "$HOME/.claude.json.lock"
  stub sleep 1
  local out
  out=$("$E" project new demo 2>&1) || fail "new exited non-zero: $out"
  case $out in *"is in use"*"Made project 'demo'"*) ;; *) fail "did not carry on past the wait: $out" ;; esac
}

# Reading through a link is harmless, so a linked file that already trusts the
# folder is nothing to speak of.
project_new_is_quiet_when_a_linked_claude_state_trusts_it() {
  printf '{"projects":{"%s":{"hasTrustDialogAccepted":true}}}\n' "$P/demo" > "$TMP/real.json"
  ln -s "$TMP/real.json" "$HOME/.claude.json"
  local out
  out=$("$E" project new demo) || fail "new exited non-zero"
  case $out in
    # The words of the two trust lines, not any note: another part of the CLI
    # may have a note of its own to print.
    *"Claude Code may ask to trust"* | *"Claude Code will not ask to trust"*)
      fail "spoke of trust for a folder that is trusted already: $out" ;;
  esac
  [ -L "$HOME/.claude.json" ] || fail "the link was replaced"
}

# Not JSON, empty (jq prints nothing for it and exits zero), JSON that is not
# the object Claude Code keeps, and two values where there should be one.
project_new_leaves_broken_claude_state() {
  local name text out
  for name in a b c d e; do
    case $name in
      a) text='{broken' ;; b) text='' ;; c) text='[]' ;; d) text='null' ;;
      e) text='{"a":1} {"b":2}' ;;
    esac
    printf '%s' "$text" > "$HOME/.claude.json"
    cp "$HOME/.claude.json" "$TMP/before"
    out=$("$E" project new "$name") || fail "new exited non-zero with the state file '$text'"
    [ -f "$P/$name/PROJECT.md" ] || fail "the project was not made with the state file '$text'"
    cmp -s "$HOME/.claude.json" "$TMP/before" || fail "the state file '$text' changed: $(cat "$HOME/.claude.json")"
    case $out in *"could not be updated"*) ;; *) fail "did not say the state file '$text' was left alone: $out" ;; esac
    no_trust_litter
  done
}

# jq 1.6, which Debian 12 and Ubuntu 22.04 ship, exits zero for an empty file
# even when it is asked to judge its answer. The stand-in (old_jq, in
# helpers.sh) does the same.
project_new_is_not_fooled_by_an_old_jq() {
  local out
  old_jq
  : > "$HOME/.claude.json"
  out=$("$E" project new demo) || fail "new exited non-zero"
  [ ! -s "$HOME/.claude.json" ] || fail "the empty state file changed: $(cat "$HOME/.claude.json")"
  case $out in
    *"could not be updated"*) ;;
    *) fail "took an empty state file for one that trusts the folder: $out" ;;
  esac
  no_trust_litter
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

# What the projects mod reads: one line of JSON, each project with its folder.
project_ls_json_lists() {
  out=$("$E" project ls --json) || fail "ls --json exited non-zero with no projects"
  [ "$out" = '{"projects":[]}' ] || fail "empty listing is: $out"
  make_repo "$HOME/code/api"; make_repo "$HOME/code/we\"b"; make_repo "$HOME/code/back\\slash"
  "$E" project new demo >/dev/null
  "$E" project add demo "$HOME/code/api" >/dev/null
  "$E" project add demo "$HOME/code/we\"b" >/dev/null
  "$E" project add demo "$HOME/code/back\\slash" >/dev/null
  "$E" project new alpha >/dev/null
  rm "$P/alpha/repos"
  out=$("$E" project ls --json) || fail "ls --json exited non-zero"
  want=$(printf '{"projects":[{"name":"alpha","folder":"%s/alpha","repos":[]},{"name":"demo","folder":"%s/demo","repos":["%s/code/api","%s/code/we\\"b","%s/code/back\\\\slash"]}]}' "$P" "$P" "$HOME" "$HOME" "$HOME")
  [ "$out" = "$want" ] || fail "listing is: $out"
  "$E" project ls --bogus >/dev/null 2>&1 && fail "accepted an unknown option"
}

# The projects mod asks for this list every 15 seconds, so names and paths
# that need no escaping must not each start helper programs.
project_ls_json_starts_no_helpers_for_plain_paths() {
  make_repo "$HOME/code/api"
  "$E" project new demo >/dev/null; "$E" project add demo "$HOME/code/api" >/dev/null
  printf '#!/bin/sh\necho x >> "%s"\nexec /usr/bin/awk "$@"\n' "$TMP/awk-calls.log" > "$TMP/bin/awk"
  chmod +x "$TMP/bin/awk"
  out=$("$E" project ls --json) || fail "ls --json exited non-zero"
  [ "$out" = "{\"projects\":[{\"name\":\"demo\",\"folder\":\"$P/demo\",\"repos\":[\"$HOME/code/api\"]}]}" ] || fail "listing is: $out"
  [ ! -e "$TMP/awk-calls.log" ] ||
    fail "started a helper $(grep -c x "$TMP/awk-calls.log") times for strings that need no escaping"
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

# --- a project's Linear team ------------------------------------------------

project_team_sets_the_team() {
  "$E" project new demo >/dev/null
  "$E" project team demo PHY >/dev/null || fail "team exited non-zero"
  [ "$(cat "$P/demo/teams" 2>&1)" = PHY ] || fail "the team file holds: $(cat "$P/demo/teams" 2>&1)"
}

# Linear writes a team's key in upper case, however it is typed here.
project_team_stores_the_key_in_upper_case() {
  "$E" project new demo >/dev/null
  "$E" project team demo phy >/dev/null || fail "team exited non-zero"
  [ "$(cat "$P/demo/teams" 2>&1)" = PHY ] || fail "the team file holds: $(cat "$P/demo/teams" 2>&1)"
}

project_team_replaces_the_team() {
  "$E" project new demo >/dev/null
  "$E" project team demo PHY >/dev/null
  "$E" project team demo LAB >/dev/null || fail "the second team exited non-zero"
  [ "$(cat "$P/demo/teams" 2>&1)" = LAB ] || fail "the team file holds: $(cat "$P/demo/teams" 2>&1)"
}

project_team_prints_the_team() {
  "$E" project new demo >/dev/null
  "$E" project team demo PHY >/dev/null
  out=$("$E" project team demo) || fail "printing the team exited non-zero"
  [ "$out" = PHY ] || fail "printed: $out"
}

# A project's cards can be spread over several Linear teams, and a team can be
# named by several projects.
project_team_takes_several_teams() {
  "$E" project new demo >/dev/null
  "$E" project team demo PHY lab >/dev/null || fail "team exited non-zero"
  [ "$(cat "$P/demo/teams" 2>&1)" = "$(printf 'PHY\nLAB')" ] ||
    fail "the teams file holds: $(cat "$P/demo/teams" 2>&1)"
}

project_team_prints_every_team() {
  "$E" project new demo >/dev/null
  "$E" project team demo PHY LAB >/dev/null
  out=$("$E" project team demo) || fail "printing the teams exited non-zero"
  [ "$out" = "$(printf 'PHY\nLAB')" ] || fail "printed: $out"
}

project_team_lists_a_team_once() {
  "$E" project new demo >/dev/null
  "$E" project team demo PHY phy >/dev/null || fail "team exited non-zero"
  [ "$(cat "$P/demo/teams" 2>&1)" = PHY ] || fail "the teams file holds: $(cat "$P/demo/teams" 2>&1)"
}

# One bad key must not leave the project with only some of its teams.
project_team_keeps_the_old_teams_when_a_key_is_bad() {
  "$E" project new demo >/dev/null
  "$E" project team demo PHY >/dev/null
  "$E" project team demo LAB "A B" >/dev/null 2>&1 && fail "accepted a bad key among good ones"
  [ "$(cat "$P/demo/teams" 2>&1)" = PHY ] || fail "the teams file holds: $(cat "$P/demo/teams" 2>&1)"
}

# The file is the human's to edit: lower case, spaces, blank lines and
# comments are all read as they mean.
project_team_reads_a_hand_edited_file() {
  "$E" project new demo >/dev/null
  printf '%s\n' '  # our teams' 'abc # ours  ' '' 'ABC' 'lab' > "$P/demo/teams"
  out=$("$E" project team demo) || fail "printing the teams exited non-zero"
  [ "$out" = "$(printf 'ABC\nLAB')" ] || fail "printed: $out"
}

# The mark some editors put at the start of a file is not part of the first
# key, in a UTF-8 locale or not.
project_team_reads_a_teams_file_that_starts_with_a_bom() {
  "$E" project new demo >/dev/null
  printf '\357\273\277ABC\nlab\n' > "$P/demo/teams"
  for locale in C C.UTF-8; do
    out=$(LC_ALL=$locale "$E" project team demo 2>"$TMP/err") ||
      fail "printing the teams exited non-zero in the $locale locale: $(cat "$TMP/err")"
    [ "$out" = "$(printf 'ABC\nLAB')" ] || fail "in the $locale locale printed: $out"
  done
}

# A teams file entourage cannot read stops it in a sentence. It is not taken
# for a project with no team.
project_team_says_when_the_teams_file_cannot_be_read() {
  "$E" project new demo >/dev/null
  "$E" project team demo PHY >/dev/null
  chmod 000 "$P/demo/teams"
  # As root the file can still be read, so there is nothing to test.
  if [ -r "$P/demo/teams" ]; then chmod 600 "$P/demo/teams"; return; fi
  out=$("$E" project team demo 2>&1) && fail "exited zero with a teams file it cannot read"
  chmod 600 "$P/demo/teams"
  case $out in *"cannot read $P/demo/teams"*) ;; *) fail "did not say it cannot read the file: $out" ;; esac
  case $out in *"no Linear team"*) fail "said the project has no team: $out" ;; esac
  case $out in *"line "[0-9]*) fail "gave bash's own message: $out" ;; esac
}

project_team_without_one_says_how_to_set_it() {
  "$E" project new demo >/dev/null
  out=$("$E" project team demo 2>&1) && fail "exited zero for a project with no team"
  case $out in *"entourage project team demo "*) ;; *) fail "did not say how to set it: $out" ;; esac
}

project_team_refuses_what_is_not_a_team_key() {
  "$E" project new demo >/dev/null
  for k in "A B" 12 AB-1 'A"B' 'A/B'; do
    "$E" project team demo "$k" >/dev/null 2>&1 && fail "accepted the team key '$k'"
  done
  [ ! -e "$P/demo/teams" ] || fail "wrote a team file: $(cat "$P/demo/teams")"
}

project_team_unknown_project() {
  "$E" project team nope PHY >/dev/null 2>&1 && fail "set a team on a project that does not exist"
  [ ! -e "$P/nope" ] || fail "made the project"
}

CASES="status_is_quiet_about_just_without_projects status_notes_a_repo_without_a_justfile status_notes_a_justfile_without_setup
  status_is_quiet_when_setup_exists status_ignores_a_parent_justfile
  status_notes_an_unreadable_justfile status_says_once_when_just_is_missing
  project_new_creates_from_template project_new_refuses_existing project_new_refuses_bad_name
  project_new_takes_repos project_new_makes_nothing_when_a_repo_is_bad
  project_new_trusts_its_folder project_new_without_claude_state_writes_none
  project_new_without_jq_leaves_claude_state project_new_leaves_broken_claude_state
  project_new_survives_a_temp_file_it_cannot_remove project_new_survives_a_sleep_that_fails
  project_new_is_quiet_when_a_linked_claude_state_trusts_it project_new_is_not_fooled_by_an_old_jq
  project_new_leaves_linked_claude_state project_new_leaves_claude_state_in_use
  project_new_trust_honors_claude_config_dir project_new_trusts_a_path_with_quotes
  project_new_trusts_the_real_path
  project_ls_lists project_ls_json_lists project_ls_json_starts_no_helpers_for_plain_paths
  project_add_links_repo project_add_takes_a_relative_path
  project_add_refuses_non_repo project_add_refuses_duplicates project_add_handles_spaces
  project_add_unknown_project a_repo_can_be_in_two_projects stale_link_removed_real_file_kept
  project_open_makes_space project_open_selects_existing project_open_ignores_closed_spaces project_open_warns_missing_repo
  project_open_unknown_project status_reports_project_problems honors_entourage_home
  project_team_sets_the_team project_team_stores_the_key_in_upper_case project_team_replaces_the_team
  project_team_prints_the_team project_team_without_one_says_how_to_set_it
  project_team_takes_several_teams project_team_prints_every_team project_team_lists_a_team_once
  project_team_keeps_the_old_teams_when_a_key_is_bad project_team_reads_a_hand_edited_file
  project_team_reads_a_teams_file_that_starts_with_a_bom project_team_says_when_the_teams_file_cannot_be_read
  project_team_refuses_what_is_not_a_team_key project_team_unknown_project"
