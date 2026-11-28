# Tests for what entourage asks of Linear. Sourced by test/run.sh. No case
# reaches Linear: a stand-in curl answers from canned files (stub_linear, in
# helpers.sh).

# What Linear answers when asked who a key belongs to.
VIEWER='{"data":{"viewer":{"id":"u-1","name":"Ada Lovelace"}}}'
# What Linear answers to a key it does not know.
REJECTED='{"errors":[{"message":"Authentication required, not authenticated","extensions":{"type":"authentication error","userError":true,"userPresentableMessage":"You need to authenticate to access this operation."}}]}'

# --- saving the key ---------------------------------------------------------

linear_key_saves_the_key() {
  stub_linear; linear_answers "$VIEWER"
  printf '%s\n' "$KEY" | "$E" linear key >/dev/null || fail "linear key exited non-zero"
  [ "$(key_in_file)" = "$KEY" ] || fail "the env file holds: $(cat "$(env_file)" 2>&1)"
}

linear_key_keeps_the_env_file_private() {
  stub_linear; linear_answers "$VIEWER"
  printf '%s\n' "$KEY" | "$E" linear key >/dev/null
  case $(ls -l "$(env_file)" 2>&1) in
    -rw-------*) ;;
    *) fail "others can read the env file: $(ls -l "$(env_file)" 2>&1)" ;;
  esac
}

# A file that was there before, readable by others, is closed to them too.
linear_key_closes_an_env_file_others_could_read() {
  stub_linear; linear_answers "$VIEWER"
  mkdir -p "$HOME/.config/entourage"
  echo 'ENTOURAGE_AGENT=codex' > "$(env_file)"; chmod 644 "$(env_file)"
  printf '%s\n' "$KEY" | "$E" linear key >/dev/null
  case $(ls -l "$(env_file)" 2>&1) in
    -rw-------*) ;;
    *) fail "others can still read the env file: $(ls -l "$(env_file)" 2>&1)" ;;
  esac
}

linear_key_says_whose_key_it_is() {
  stub_linear; linear_answers "$VIEWER"
  out=$(printf '%s\n' "$KEY" | "$E" linear key) || fail "linear key exited non-zero"
  case $out in *"Ada Lovelace"*) ;; *) fail "did not name the key's owner: $out" ;; esac
}

linear_key_never_shows_the_key() {
  stub_linear; linear_answers "$VIEWER"
  out=$(printf '%s\n' "$KEY" | "$E" linear key 2>&1)
  case $out in *"$KEY"*) fail "printed the key: $out" ;; esac
  case $(curl_calls) in *"$KEY"*) fail "passed the key to curl as an argument: $(curl_calls)" ;; esac
}

# The key is checked before it is saved, so curl has to be given it: on
# stdin, where other programs on the machine cannot read it.
linear_key_gives_curl_the_key_on_stdin() {
  stub_linear; linear_answers "$VIEWER"
  printf '%s\n' "$KEY" | "$E" linear key >/dev/null
  [ "$(key_given_to_curl)" = "$KEY" ] ||
    fail "curl was not given the key on stdin: $(cat "$TMP/curl-stdin.log" 2>&1)"
}

# The file is the human's: their other lines stay, and the key has one line.
linear_key_replaces_the_old_key_and_keeps_the_other_lines() {
  stub_linear; linear_answers "$VIEWER"
  mkdir -p "$HOME/.config/entourage"
  printf '%s\n' '# mine' 'LINEAR_API_KEY=lin_api_old' 'ENTOURAGE_AGENT=codex' > "$(env_file)"
  printf '%s\n' "$KEY" | "$E" linear key >/dev/null || fail "linear key exited non-zero"
  want=$(printf '%s\n' '# mine' 'ENTOURAGE_AGENT=codex' "LINEAR_API_KEY=$KEY")
  [ "$(cat "$(env_file)" 2>&1)" = "$want" ] || fail "the env file holds: $(cat "$(env_file)" 2>&1)"
}

# A key exported in the shell is the one entourage uses, so saving another
# would change nothing. Say so, or the human is left wondering.
linear_key_says_when_an_exported_key_is_used_instead() {
  stub_linear; linear_answers "$VIEWER"
  out=$(printf '%s\n' "$KEY" | LINEAR_API_KEY=lin_api_FromTheShell "$E" linear key 2>&1) ||
    fail "linear key exited non-zero"
  case $out in *"LINEAR_API_KEY"*environment*) ;; *) fail "did not say the exported key is the one used: $out" ;; esac
  case $out in *lin_api_FromTheShell*) fail "printed the exported key: $out" ;; esac
}

linear_key_refuses_a_key_linear_rejects() {
  stub_linear; linear_answers "$REJECTED"; linear_status 401
  out=$(printf '%s\n' "$KEY" | "$E" linear key 2>&1) && fail "exited zero for a rejected key"
  case $out in *rejected*) ;; *) fail "did not say Linear rejected the key: $out" ;; esac
  case $out in *"$KEY"*) fail "printed the key: $out" ;; esac
  [ ! -e "$(env_file)" ] || fail "saved a rejected key: $(cat "$(env_file)")"
}

linear_key_keeps_the_old_key_when_the_new_one_is_rejected() {
  stub_linear; linear_answers "$REJECTED"; linear_status 401
  saved_key lin_api_old
  printf '%s\n' "$KEY" | "$E" linear key >/dev/null 2>&1 && fail "exited zero for a rejected key"
  [ "$(key_in_file)" = lin_api_old ] || fail "the env file holds: $(cat "$(env_file)" 2>&1)"
}

linear_key_saves_nothing_when_linear_is_out_of_reach() {
  stub_linear; echo 6 > "$TMP/linear/exit"
  out=$(printf '%s\n' "$KEY" | "$E" linear key 2>&1) && fail "exited zero with Linear out of reach"
  case $out in *"reach"*) ;; *) fail "did not say Linear could not be reached: $out" ;; esac
  [ ! -e "$(env_file)" ] || fail "saved a key it could not check: $(cat "$(env_file)")"
}

linear_key_refuses_what_is_not_a_key() {
  stub_linear; linear_answers "$VIEWER"
  for k in '' 'two words' 'quote"d' 'back\slash'; do
    printf '%s\n' "$k" | "$E" linear key >/dev/null 2>&1 && fail "accepted the key '$k'"
  done
  [ "$(curl_count)" = 0 ] || fail "asked Linear about something that is not a key: $(curl_calls)"
  [ ! -e "$(env_file)" ] || fail "saved something that is not a key: $(cat "$(env_file)")"
}

linear_key_says_when_jq_is_missing() {
  stub_linear; linear_answers "$VIEWER"
  hide_jq
  out=$(printf '%s\n' "$KEY" | "$E" linear key 2>&1) && fail "exited zero without jq"
  case $out in *"jq is not installed"*) ;; *) fail "did not say jq is missing: $out" ;; esac
}

linear_key_says_when_curl_is_missing() {
  hide_curl
  out=$(printf '%s\n' "$KEY" | "$E" linear key 2>&1) && fail "exited zero without curl"
  case $out in *"curl is not installed"*) ;; *) fail "did not say curl is missing: $out" ;; esac
}

# The key is checked by asking Linear whose it is. An answer that names no
# user did not come from Linear, so it checks nothing.
linear_key_refuses_an_answer_that_names_no_user() {
  stub_linear
  for answer in '{"data":{"viewer":null}}' '{"data":{}}' '{"data":"hello"}'; do
    linear_answers "$answer"
    printf '%s\n' "$KEY" | "$E" linear key >/dev/null 2>&1 && fail "saved the key on the answer: $answer"
  done
  [ ! -e "$(env_file)" ] || fail "saved the key: $(cat "$(env_file)")"
}

# A linked env file is often kept in a dotfiles repo. Replacing the link
# would cut it loose, and writing through it would put the key in that repo,
# so it is left alone, as Claude Code's own file is.
linear_key_leaves_a_linked_env_file_alone() {
  stub_linear; linear_answers "$VIEWER"
  mkdir -p "$HOME/.config/entourage" "$TMP/dotfiles"
  echo 'ENTOURAGE_AGENT=codex' > "$TMP/dotfiles/env"
  ln -s "$TMP/dotfiles/env" "$(env_file)"
  out=$(printf '%s\n' "$KEY" | "$E" linear key 2>&1) && fail "exited zero for a linked env file"
  is_link_to "$(env_file)" "$TMP/dotfiles/env" || fail "the link was replaced"
  [ "$(cat "$TMP/dotfiles/env")" = 'ENTOURAGE_AGENT=codex' ] ||
    fail "the file it links to holds: $(cat "$TMP/dotfiles/env")"
  case $out in *link*) ;; *) fail "did not say the env file is a link: $out" ;; esac
  case $out in *"$KEY"*) fail "printed the key: $out" ;; esac
  [ "$(curl_count)" = 0 ] || fail "asked Linear before refusing: $(curl_calls)"
}

# grep calls a file with a NUL byte in it binary, and then prints a note in
# place of its lines. None of the file's other lines may be lost for that.
linear_key_keeps_the_other_lines_of_a_file_grep_calls_binary() {
  stub_linear; linear_answers "$VIEWER"
  mkdir -p "$HOME/.config/entourage"
  printf 'ENTOURAGE_AGENT=codex\n# a\000b\nLINEAR_API_KEY=lin_api_old\nENTOURAGE_SQLITE=sqlite3\n' > "$(env_file)"
  printf '%s\n' "$KEY" | "$E" linear key >/dev/null 2>&1 || fail "linear key exited non-zero"
  grep -a -q -x 'ENTOURAGE_AGENT=codex' "$(env_file)" || fail "lost a line: $(cat -v "$(env_file)")"
  grep -a -q -x 'ENTOURAGE_SQLITE=sqlite3' "$(env_file)" || fail "lost a line: $(cat -v "$(env_file)")"
  ! grep -a -q 'Binary file' "$(env_file)" || fail "wrote grep's note into the file: $(cat -v "$(env_file)")"
  [ "$(key_in_file)" = "$KEY" ] || fail "the env file holds: $(cat -v "$(env_file)")"
}

# A key that cannot be written is not said to be saved, and the old file stays.
linear_key_says_when_the_env_file_cannot_be_written() {
  stub_linear; linear_answers "$VIEWER"
  saved_key lin_api_old
  chmod 500 "$HOME/.config/entourage"
  # As root the folder can still be written, so there is nothing to test.
  if [ -w "$HOME/.config/entourage" ]; then chmod 700 "$HOME/.config/entourage"; return; fi
  out=$(printf '%s\n' "$KEY" | "$E" linear key 2>&1) && fail "exited zero with an env file it could not write"
  chmod 700 "$HOME/.config/entourage"
  case $out in *"could not write"*) ;; *) fail "did not say the file could not be written: $out" ;; esac
  case $out in *Saved*) fail "said the key was saved: $out" ;; esac
  case $out in *"$KEY"*) fail "printed the key: $out" ;; esac
  [ "$(key_in_file)" = lin_api_old ] || fail "the env file holds: $(cat "$(env_file)" 2>&1)"
  for f in "$(env_file)".*; do [ ! -e "$f" ] || fail "left behind: $f"; done
}

# linear key leaves one key line, whichever way the old one was written.
linear_key_replaces_a_key_line_written_with_spaces() {
  stub_linear; linear_answers "$VIEWER"
  mkdir -p "$HOME/.config/entourage"
  printf '%s\n' 'LINEAR_API_KEY = lin_api_old' 'ENTOURAGE_AGENT=codex' > "$(env_file)"
  printf '%s\n' "$KEY" | "$E" linear key >/dev/null 2>&1 || fail "linear key exited non-zero"
  want=$(printf '%s\n' 'ENTOURAGE_AGENT=codex' "LINEAR_API_KEY=$KEY")
  [ "$(cat "$(env_file)" 2>&1)" = "$want" ] || fail "the env file holds: $(cat "$(env_file)" 2>&1)"
}

# A key line that starts with the mark some editors put at the start of a file
# is read as the key, so it is replaced too. macOS grep, in a UTF-8 locale,
# misses that mark in a file with a NUL byte in it, so this file has one.
linear_key_replaces_a_key_line_that_starts_with_a_bom() {
  stub_linear; linear_answers "$VIEWER"
  mkdir -p "$HOME/.config/entourage"
  for locale in C C.UTF-8; do
    printf '\357\273\277LINEAR_API_KEY=lin_api_old\n# a\000b\nENTOURAGE_AGENT=codex\n' > "$(env_file)"
    printf '%s\n' "$KEY" | LC_ALL=$locale "$E" linear key >/dev/null 2>&1 ||
      fail "linear key exited non-zero in the $locale locale"
    ! grep -a -q lin_api_old "$(env_file)" || fail "kept the old key in the $locale locale: $(cat -v "$(env_file)")"
    grep -a -q -x 'ENTOURAGE_AGENT=codex' "$(env_file)" || fail "lost a line in the $locale locale: $(cat -v "$(env_file)")"
    [ "$(key_in_file)" = "$KEY" ] || fail "in the $locale locale the env file holds: $(cat -v "$(env_file)")"
  done
}

# GNU Stow links a whole folder into a dotfiles repo when it can, so the env
# file can be a plain file in a git repo, reached through a linked folder. A
# key written there could be committed and pushed, so none is written.
linear_key_keeps_the_key_out_of_a_git_repo() {
  stub_linear; linear_answers "$VIEWER"
  mkdir -p "$TMP/dotfiles/entourage"
  git init -q -b main "$TMP/dotfiles"
  echo 'ENTOURAGE_AGENT=codex' > "$TMP/dotfiles/entourage/.env"
  ln -s "$TMP/dotfiles/entourage" "$HOME/.config/entourage"
  out=$(printf '%s\n' "$KEY" | "$E" linear key 2>&1) && fail "exited zero for a folder in a git repo"
  [ "$(cat "$TMP/dotfiles/entourage/.env")" = 'ENTOURAGE_AGENT=codex' ] ||
    fail "the file in the repo holds: $(cat "$TMP/dotfiles/entourage/.env")"
  case $out in *"$TMP/dotfiles"*) ;; *) fail "did not name the repo: $out" ;; esac
  case $out in *"LINEAR_API_KEY=<your key>"*) ;; *) fail "did not say how to add the line by hand: $out" ;; esac
  case $out in *"$KEY"*) fail "printed the key: $out" ;; esac
  [ "$(curl_count)" = 0 ] || fail "asked Linear before refusing: $(curl_calls)"
}

# entourage's folder may not be made yet. Made inside a linked folder, it
# would be in the repo that folder is in.
linear_key_keeps_the_key_out_of_a_git_repo_it_would_make_its_folder_in() {
  stub_linear; linear_answers "$VIEWER"
  mkdir -p "$TMP/dotfiles/config"
  git init -q -b main "$TMP/dotfiles"
  ln -s "$TMP/dotfiles/config" "$HOME/dots"
  out=$(printf '%s\n' "$KEY" | ENTOURAGE_HOME=$HOME/dots/entourage "$E" linear key 2>&1) &&
    fail "exited zero for a folder it would make in a git repo"
  [ ! -e "$TMP/dotfiles/config/entourage" ] ||
    fail "made the folder in the repo: $(ls -A "$TMP/dotfiles/config/entourage")"
  case $out in *"$TMP/dotfiles"*) ;; *) fail "did not name the repo: $out" ;; esac
  [ "$(curl_count)" = 0 ] || fail "asked Linear before refusing: $(curl_calls)"
}

# A folder where the env file should be is not the file. The key would be
# moved into it, and said to be saved.
linear_key_writes_nothing_into_a_folder_where_the_env_file_should_be() {
  stub_linear; linear_answers "$VIEWER"
  mkdir -p "$(env_file)"; chmod 755 "$(env_file)"
  out=$(printf '%s\n' "$KEY" | "$E" linear key 2>&1) && fail "exited zero for a folder where the env file should be"
  case $(ls -ld "$(env_file)") in
    drwxr-xr-x*) ;;
    *) fail "changed the folder's permissions: $(ls -ld "$(env_file)")" ;;
  esac
  # So that the folder can be looked in, and cleared away after the case.
  chmod 755 "$(env_file)"
  case $out in *Saved*) fail "said the key was saved: $out" ;; esac
  [ -z "$(ls -A "$(env_file)")" ] || fail "wrote into the folder: $(ls -A "$(env_file)")"
  [ "$(curl_count)" = 0 ] || fail "asked Linear before refusing: $(curl_calls)"
}

# jq 1.6 exits zero for -e when it is given no JSON at all (old_jq, in
# helpers.sh). What jq prints decides, so an answer that names nobody is
# still not Linear's word on the key, an empty one included.
linear_key_refuses_an_answer_that_names_no_user_with_an_old_jq() {
  stub_linear; old_jq
  for answer in '' '{"data":null}' '{"data":{"viewer":null}}' '{"data":{}}' '{"data":"hello"}'; do
    linear_answers "$answer"
    printf '%s\n' "$KEY" | "$E" linear key >/dev/null 2>&1 && fail "saved the key on the answer: '$answer'"
  done
  [ ! -e "$(env_file)" ] || fail "saved the key: $(cat "$(env_file)")"
}

# --- listing a project's open cards -----------------------------------------

# The project "demo" on a machine with a key saved. Its Linear teams are the
# ones named, or ABC.
listed_demo() {
  "$E" project new demo >/dev/null
  "$E" project team demo "${@:-ABC}" >/dev/null
  saved_key
  stub_linear
}

# One team's open statuses, out of order as Linear may give them, and three
# cards, newest change first.
ONE_TEAM='{"data":{
  "teams":{"nodes":[{"key":"ABC"}]},
  "workflowStates":{"nodes":[
    {"name":"In Progress","type":"started","position":2,"team":{"key":"ABC"}},
    {"name":"Backlog","type":"backlog","position":0,"team":{"key":"ABC"}},
    {"name":"In Review","type":"started","position":3,"team":{"key":"ABC"}},
    {"name":"Ready for Dev","type":"unstarted","position":1,"team":{"key":"ABC"}},
    {"name":"Triage","type":"triage","position":0,"team":{"key":"ABC"}}]},
  "issues":{"nodes":[
    {"identifier":"ABC-3","title":"Third card","url":"https://linear.app/x/issue/ABC-3/third-card","updatedAt":"2024-03-01T00:00:00.000Z","state":{"name":"In Review","type":"started"}},
    {"identifier":"ABC-1","title":"First card","url":"https://linear.app/x/issue/ABC-1/first-card","updatedAt":"2024-02-01T00:00:00.000Z","state":{"name":"Backlog","type":"backlog"}},
    {"identifier":"ABC-2","title":"Second \"quoted\" card","url":"https://linear.app/x/issue/ABC-2/second-card","updatedAt":"2024-01-01T00:00:00.000Z","state":{"name":"In Progress","type":"started"}}],
    "pageInfo":{"hasNextPage":false,"endCursor":null}}}}'

task_ls_lists_cards_under_their_status() {
  listed_demo; linear_answers "$ONE_TEAM"
  out=$("$E" task ls demo) || fail "task ls exited non-zero"
  want='Triage (0)
Backlog (1)
  ABC-1  First card
Ready for Dev (0)
In Progress (1)
  ABC-2  Second "quoted" card
In Review (1)
  ABC-3  Third card'
  [ "$out" = "$want" ] || fail "listed: $out"
}

task_ls_json_is_one_line_a_program_can_read() {
  listed_demo; linear_answers "$ONE_TEAM"
  out=$("$E" task ls demo --json) || fail "task ls --json exited non-zero"
  [ "$(printf '%s\n' "$out" | grep -c '')" = 1 ] || fail "the JSON is not one line: $out"
  # The whole document, keys in order: a program reads it, and a key the
  # contract does not have must not slip in.
  want='{"project":"demo","teams":["ABC"],"statuses":[{"name":"Triage","type":"triage","cards":[]},{"name":"Backlog","type":"backlog","cards":[{"id":"ABC-1","title":"First card","url":"https://linear.app/x/issue/ABC-1/first-card"}]},{"name":"Ready for Dev","type":"unstarted","cards":[]},{"name":"In Progress","type":"started","cards":[{"id":"ABC-2","title":"Second \"quoted\" card","url":"https://linear.app/x/issue/ABC-2/second-card"}]},{"name":"In Review","type":"started","cards":[{"id":"ABC-3","title":"Third card","url":"https://linear.app/x/issue/ABC-3/third-card"}]}]}'
  [ "$out" = "$want" ] || fail "the JSON is: $out"
}

# Done, cancelled and duplicate cards are never asked for.
task_ls_asks_only_for_open_cards() {
  listed_demo; linear_answers "$ONE_TEAM"
  "$E" task ls demo >/dev/null || fail "task ls exited non-zero"
  case $(curl_calls) in
    *'"types":["triage","backlog","unstarted","started"]'*) ;;
    *) fail "did not ask for the four open kinds of status: $(curl_calls)" ;;
  esac
}

task_ls_asks_for_every_team_of_the_project() {
  listed_demo ABC XYZ
  linear_answers '{"data":{"teams":{"nodes":[{"key":"XYZ"},{"key":"ABC"}]},"workflowStates":{"nodes":[]},"issues":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}'
  "$E" task ls demo >/dev/null || fail "task ls exited non-zero"
  case $(curl_calls) in
    *'"teams":["ABC","XYZ"]'*) ;;
    *) fail "did not ask for both teams: $(curl_calls)" ;;
  esac
}

# Two teams that both have a Backlog show one Backlog, holding both teams' cards.
task_ls_puts_a_status_two_teams_share_in_one_group() {
  listed_demo ABC XYZ
  linear_answers '{"data":{
    "teams":{"nodes":[{"key":"ABC"},{"key":"XYZ"}]},
    "workflowStates":{"nodes":[
      {"name":"Backlog","type":"backlog","position":0,"team":{"key":"ABC"}},
      {"name":"Todo","type":"unstarted","position":1,"team":{"key":"XYZ"}},
      {"name":"Backlog","type":"backlog","position":0,"team":{"key":"XYZ"}}]},
    "issues":{"nodes":[
      {"identifier":"ABC-1","title":"First card","url":"https://linear.app/x/issue/ABC-1","state":{"name":"Backlog","type":"backlog"}},
      {"identifier":"XYZ-8","title":"Eighth card","url":"https://linear.app/x/issue/XYZ-8","state":{"name":"Todo","type":"unstarted"}},
      {"identifier":"XYZ-7","title":"Seventh card","url":"https://linear.app/x/issue/XYZ-7","state":{"name":"Backlog","type":"backlog"}}],
      "pageInfo":{"hasNextPage":false,"endCursor":null}}}}'
  out=$("$E" task ls demo) || fail "task ls exited non-zero"
  want='Backlog (2)
  ABC-1  First card
  XYZ-7  Seventh card
Todo (1)
  XYZ-8  Eighth card'
  [ "$out" = "$want" ] || fail "listed: $out"
}

# A status is one group across teams only when its name and its type are both
# the same. A Todo that is unstarted in one team and backlog in another is two.
task_ls_keeps_statuses_of_one_name_and_two_types_apart() {
  listed_demo ABC XYZ
  linear_answers '{"data":{
    "teams":{"nodes":[{"key":"ABC"},{"key":"XYZ"}]},
    "workflowStates":{"nodes":[
      {"name":"Todo","type":"unstarted","position":1,"team":{"key":"ABC"}},
      {"name":"Todo","type":"backlog","position":0,"team":{"key":"XYZ"}}]},
    "issues":{"nodes":[
      {"identifier":"ABC-1","title":"First card","url":"u1","state":{"name":"Todo","type":"unstarted"}},
      {"identifier":"XYZ-7","title":"Seventh card","url":"u7","state":{"name":"Todo","type":"backlog"}}],
      "pageInfo":{"hasNextPage":false,"endCursor":null}}}}'
  out=$("$E" task ls demo) || fail "task ls exited non-zero"
  want='Todo (1)
  XYZ-7  Seventh card
Todo (1)
  ABC-1  First card'
  [ "$out" = "$want" ] || fail "listed: $out"
}

# Linear hands cards over a page at a time.
task_ls_fetches_every_page() {
  listed_demo
  states='"teams":{"nodes":[{"key":"ABC"}]},"workflowStates":{"nodes":[{"name":"Backlog","type":"backlog","position":0,"team":{"key":"ABC"}}]}'
  linear_answers \
    "{\"data\":{$states,\"issues\":{\"nodes\":[{\"identifier\":\"ABC-1\",\"title\":\"First card\",\"url\":\"u1\",\"state\":{\"name\":\"Backlog\",\"type\":\"backlog\"}}],\"pageInfo\":{\"hasNextPage\":true,\"endCursor\":\"cursor-1\"}}}}" \
    "{\"data\":{$states,\"issues\":{\"nodes\":[{\"identifier\":\"ABC-2\",\"title\":\"Second card\",\"url\":\"u2\",\"state\":{\"name\":\"Backlog\",\"type\":\"backlog\"}}],\"pageInfo\":{\"hasNextPage\":false,\"endCursor\":null}}}}"
  out=$("$E" task ls demo) || fail "task ls exited non-zero"
  want='Backlog (2)
  ABC-1  First card
  ABC-2  Second card'
  [ "$out" = "$want" ] || fail "listed: $out"
  [ "$(curl_count)" = 2 ] || fail "asked Linear $(curl_count) times, not twice"
  case $(curl_calls | tail -n 1) in
    *'"after":"cursor-1"'*) ;;
    *) fail "the second question did not start where the first page ended: $(curl_calls | tail -n 1)" ;;
  esac
}

task_ls_without_a_key_says_how_to_save_one() {
  listed_demo; rm "$(env_file)"
  out=$("$E" task ls demo 2>&1) && fail "exited zero with no key saved"
  case $out in *"entourage linear key"*) ;; *) fail "did not say how to save a key: $out" ;; esac
  [ "$(curl_count)" = 0 ] || fail "asked Linear with no key: $(curl_calls)"
}

task_ls_with_a_rejected_key_says_so() {
  listed_demo; linear_answers "$REJECTED"; linear_status 401
  out=$("$E" task ls demo 2>&1) && fail "exited zero with a rejected key"
  case $out in *rejected*) ;; *) fail "did not say Linear rejected the key: $out" ;; esac
  case $out in *"$KEY"*) fail "printed the key: $out" ;; esac
  case $(curl_calls) in *"$KEY"*) fail "passed the key to curl as an argument: $(curl_calls)" ;; esac
}

# Linear also answers 400 to a key it does not know, and marks the error.
task_ls_knows_a_rejected_key_by_its_error() {
  listed_demo; linear_answers "$REJECTED"; linear_status 400
  out=$("$E" task ls demo 2>&1) && fail "exited zero with a rejected key"
  case $out in *rejected*) ;; *) fail "did not say Linear rejected the key: $out" ;; esac
}

task_ls_when_linear_is_out_of_reach_says_so() {
  listed_demo; echo 6 > "$TMP/linear/exit"
  out=$("$E" task ls demo 2>&1) && fail "exited zero with Linear out of reach"
  case $out in *reach*) ;; *) fail "did not say Linear could not be reached: $out" ;; esac
  case $out in *"$KEY"*) fail "printed the key: $out" ;; esac
}

task_ls_without_a_team_says_how_to_set_it() {
  listed_demo; rm "$P/demo/teams"
  out=$("$E" task ls demo 2>&1) && fail "exited zero for a project with no team"
  case $out in *"entourage project team demo "*) ;; *) fail "did not say how to set the team: $out" ;; esac
  [ "$(curl_count)" = 0 ] || fail "asked Linear with no team to ask about: $(curl_calls)"
}

task_ls_names_a_team_linear_does_not_have() {
  listed_demo ABC XYZ
  linear_answers '{"data":{"teams":{"nodes":[{"key":"ABC"}]},"workflowStates":{"nodes":[]},"issues":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}'
  out=$("$E" task ls demo 2>&1) && fail "exited zero for a team Linear does not have"
  case $out in *XYZ*) ;; *) fail "did not name the missing team: $out" ;; esac
}

task_ls_says_what_linear_said_was_wrong() {
  listed_demo; linear_answers '{"errors":[{"message":"Query too complex","extensions":{"type":"invalid input"}}]}'
  out=$("$E" task ls demo 2>&1) && fail "exited zero for an error from Linear"
  case $out in *"Query too complex"*) ;; *) fail "did not pass on what Linear said: $out" ;; esac
}

# A program reading --json must get JSON or nothing.
task_ls_json_prints_nothing_when_it_fails() {
  listed_demo; rm "$(env_file)"
  out=$("$E" task ls demo --json 2>/dev/null) && fail "exited zero with no key saved"
  [ -z "$out" ] || fail "printed on stdout: $out"
}

task_ls_says_when_curl_is_missing() {
  listed_demo; hide_curl
  out=$("$E" task ls demo 2>&1) && fail "exited zero without curl"
  case $out in *"curl is not installed"*) ;; *) fail "did not say curl is missing: $out" ;; esac
}

task_ls_unknown_project() {
  stub_linear; saved_key
  "$E" task ls nope >/dev/null 2>&1 && fail "listed a project that does not exist"
  [ "$(curl_count)" = 0 ] || fail "asked Linear about a project that does not exist: $(curl_calls)"
}

task_ls_refuses_an_unknown_option() {
  listed_demo; linear_answers "$ONE_TEAM"
  "$E" task ls demo --yaml >/dev/null 2>&1 && fail "accepted --yaml"
  [ "$(curl_count)" = 0 ] || fail "asked Linear before refusing the option: $(curl_calls)"
}

# What Linear says is passed on, but never the key inside it.
task_ls_never_shows_the_key_in_what_linear_said() {
  listed_demo
  linear_answers "{\"errors\":[{\"message\":\"Bad header: Authorization: $KEY\",\"extensions\":{\"type\":\"invalid input\"}}]}"
  out=$("$E" task ls demo 2>&1) && fail "exited zero for an error from Linear"
  case $out in *"$KEY"*) fail "printed the key: $out" ;; esac
  case $out in *"Bad header: Authorization: <the key>"*) ;; *) fail "did not pass on what Linear said: $out" ;; esac
}

# A 401 is about the key, even when the answer says nothing more.
task_ls_knows_a_rejected_key_by_its_status() {
  listed_demo; linear_answers 'Unauthorized'; linear_status 401
  out=$("$E" task ls demo 2>&1) && fail "exited zero for HTTP 401"
  case $out in *rejected*) ;; *) fail "did not say Linear rejected the key: $out" ;; esac
}

# A 403 that is Linear's own answer is about the key.
task_ls_takes_linears_own_403_as_a_rejected_key() {
  listed_demo; linear_answers "$REJECTED"; linear_status 403
  out=$("$E" task ls demo 2>&1) && fail "exited zero for HTTP 403"
  case $out in *rejected*) ;; *) fail "did not say Linear rejected the key: $out" ;; esac
}

# A 403 page from a proxy or a firewall is not, and a new key would not help.
task_ls_does_not_blame_the_key_for_a_page_from_the_network() {
  listed_demo
  linear_answers '<html><head><title>403 Forbidden</title></head><body>Blocked</body></html>'
  linear_status 403
  out=$("$E" task ls demo 2>&1) && fail "exited zero for a page from the network"
  case $out in *rejected* | *"new one"*) fail "blamed the key: $out" ;; esac
  case $out in *403*) ;; *) fail "did not give the HTTP status: $out" ;; esac
}

# jq 1.6 takes an empty 403 for one of Linear's own answers, which would
# blame the key for what a proxy or a firewall sent.
task_ls_does_not_blame_the_key_for_an_empty_403_with_an_old_jq() {
  listed_demo; old_jq
  linear_answers ''; linear_status 403
  out=$("$E" task ls demo 2>&1) && fail "exited zero for an empty 403"
  case $out in *rejected* | *"new one"*) fail "blamed the key: $out" ;; esac
  case $out in *403*) ;; *) fail "did not give the HTTP status: $out" ;; esac
}

# curl reads ~/.curlrc unless its first argument says not to, and a line there
# such as --fail or --include changes what entourage reads back. The stand-in
# cannot show curl's own behaviour, so this checks the argument it needs.
task_ls_keeps_curl_from_reading_the_humans_curlrc() {
  listed_demo; linear_answers "$ONE_TEAM"
  "$E" task ls demo >/dev/null || fail "task ls exited non-zero"
  case $(curl_calls | head -n 1) in
    '--disable '*) ;;
    *) fail "curl's first argument is not --disable: $(curl_calls | head -n 1)" ;;
  esac
}

# Should Linear send a closed status and its card anyway, neither is listed.
task_ls_never_lists_a_closed_status() {
  listed_demo
  linear_answers '{"data":{"teams":{"nodes":[{"key":"ABC"}]},"workflowStates":{"nodes":[
    {"name":"Done","type":"completed","position":0,"team":{"key":"ABC"}},
    {"name":"Backlog","type":"backlog","position":0,"team":{"key":"ABC"}}]},
    "issues":{"nodes":[
      {"identifier":"ABC-9","title":"Done card","url":"u9","state":{"name":"Done","type":"completed","position":0}},
      {"identifier":"ABC-1","title":"First card","url":"u1","state":{"name":"Backlog","type":"backlog","position":0}}],
    "pageInfo":{"hasNextPage":false,"endCursor":null}}}}'
  out=$("$E" task ls demo) || fail "task ls exited non-zero"
  want='Backlog (1)
  ABC-1  First card'
  [ "$out" = "$want" ] || fail "listed: $out"
}

# One team's Backlog, as the first page of an answer names it.
BACKLOG_ONLY='"teams":{"nodes":[{"key":"ABC"}]},"workflowStates":{"nodes":[{"name":"Backlog","type":"backlog","position":0,"team":{"key":"ABC"}}]}'
# One page of cards: the cards, then whether there are more and where they start.
cards_page() {
  printf '{"data":{%s,"issues":{"nodes":[%s],"pageInfo":{"hasNextPage":%s,"endCursor":%s}}}}' \
    "$BACKLOG_ONLY" "$1" "$2" "$3"
}
backlog_card() {
  printf '{"identifier":"%s","title":"%s","url":"u","state":{"name":"Backlog","type":"backlog","position":0}}' "$1" "$2"
}
# A card in the Backlog that was last changed at $3.
changed_card() {
  printf '{"identifier":"%s","title":"%s","url":"u","updatedAt":"%s","state":{"name":"Backlog","type":"backlog","position":0}}' "$1" "$2" "$3"
}

# Linear pages through cards in the order it is asked for, each page starting
# from a cursor. An edit changes a card's updatedAt, which would move it onto a
# page already fetched and out of the list. When a card was made never changes.
task_ls_asks_for_cards_in_an_order_an_edit_cannot_change() {
  listed_demo; linear_answers "$ONE_TEAM"
  "$E" task ls demo >/dev/null || fail "task ls exited non-zero"
  case $(curl_calls) in
    *'orderBy: createdAt'*) ;;
    *) fail "did not ask for the cards in the order they were made: $(curl_calls)" ;;
  esac
}

# Within a status the card changed last comes first, whichever page it is on.
task_ls_lists_the_most_recently_changed_card_first() {
  listed_demo
  linear_answers \
    "$(cards_page "$(changed_card ABC-3 'Third card' 2024-01-01T00:00:00.000Z),$(changed_card ABC-2 'Second card' 2024-03-01T00:00:00.000Z)" true '"cursor-1"')" \
    "$(cards_page "$(changed_card ABC-1 'First card' 2024-04-01T00:00:00.000Z)" false null)"
  out=$("$E" task ls demo) || fail "task ls exited non-zero"
  want='Backlog (3)
  ABC-1  First card
  ABC-2  Second card
  ABC-3  Third card'
  [ "$out" = "$want" ] || fail "listed: $out"
}

# A card may be in a status the first page did not name, such as one made
# while the list was being fetched. It is listed, under that status.
task_ls_lists_a_card_in_a_status_the_first_page_did_not_name() {
  listed_demo
  linear_answers \
    "$(cards_page "$(backlog_card ABC-1 'First card')" true '"cursor-1"')" \
    "$(cards_page '{"identifier":"ABC-2","title":"Second card","url":"u","state":{"name":"Doing","type":"started","position":1}}' false null)"
  out=$("$E" task ls demo) || fail "task ls exited non-zero"
  want='Backlog (1)
  ABC-1  First card
Doing (1)
  ABC-2  Second card'
  [ "$out" = "$want" ] || fail "listed: $out"
}

# Linear saying there are more cards but not where they start is not the end
# of the list. Listing what came would pass a part for the whole.
task_ls_fails_when_linear_has_more_cards_and_no_cursor() {
  listed_demo
  linear_answers \
    "$(cards_page "$(backlog_card ABC-1 'First card')" true null)" \
    "$(cards_page "$(backlog_card ABC-2 'Second card')" false null)"
  out=$("$E" task ls demo --json 2>/dev/null) && fail "exited zero with the rest of the cards missing"
  [ -z "$out" ] || fail "printed on stdout: $out"
  [ "$(curl_count)" = 1 ] || fail "asked Linear $(curl_count) times, not once"
}

# A card that moves while the pages are fetched can come on two of them.
task_ls_lists_a_card_on_two_pages_once() {
  listed_demo
  linear_answers \
    "$(cards_page "$(backlog_card ABC-1 'First card')" true '"cursor-1"')" \
    "$(cards_page "$(backlog_card ABC-1 'First card'),$(backlog_card ABC-2 'Second card')" false null)"
  out=$("$E" task ls demo) || fail "task ls exited non-zero"
  want='Backlog (2)
  ABC-1  First card
  ABC-2  Second card'
  [ "$out" = "$want" ] || fail "listed: $out"
}

# Card titles are anyone's text. A newline in one must not forge a row, and an
# escape sequence must not reach the terminal. The JSON keeps them as they are.
task_ls_keeps_control_characters_out_of_the_list() {
  listed_demo
  linear_answers "$(cards_page '{"identifier":"ABC-1","title":"Real\n  ABC-9  Forged","url":"u","state":{"name":"Backlog","type":"backlog","position":0}},{"identifier":"ABC-2","title":"Red \u001b[31mtext\u0007 and\u009b","url":"u","state":{"name":"Backlog","type":"backlog","position":0}}' false null)"
  out=$("$E" task ls demo) || fail "task ls exited non-zero"
  want='Backlog (2)
  ABC-1  Real   ABC-9  Forged
  ABC-2  Red  [31mtext  and '
  [ "$out" = "$want" ] || fail "listed: $(printf '%s' "$out" | od -c | head -n 20)"
  title=$("$E" task ls demo --json | jq -r '.statuses[0].cards[0].title')
  [ "$title" = "$(printf 'Real\n  ABC-9  Forged')" ] || fail "the JSON changed the title: $title"
}

# The teams file is the human's to edit, and these are the usual edits.
task_ls_reads_a_hand_edited_teams_file() {
  listed_demo; linear_answers "$ONE_TEAM"
  printf '%s\n' '  # our team' 'abc # ours  ' '' 'ABC' > "$P/demo/teams"
  "$E" task ls demo >/dev/null || fail "task ls exited non-zero"
  case $(curl_calls) in
    *'"teams":["ABC"]'*) ;;
    *) fail "did not ask for the one team: $(curl_calls)" ;;
  esac
}

# A line that is not a team key is named, not sent to Linear.
task_ls_names_the_line_of_a_bad_team_key() {
  listed_demo
  printf '%s\n' ABC 'A B' > "$P/demo/teams"
  out=$("$E" task ls demo --json 2>"$TMP/err") && fail "exited zero for a bad team key"
  [ -z "$out" ] || fail "printed on stdout: $out"
  case $(cat "$TMP/err") in *"line 2 of $P/demo/teams"*) ;; *) fail "did not name the line: $(cat "$TMP/err")" ;; esac
  case $(cat "$TMP/err") in *"no Linear team"*) fail "also said there is no team: $(cat "$TMP/err")" ;; esac
  [ "$(curl_count)" = 0 ] || fail "asked Linear: $(curl_calls)"
}

# --- asking for one card ----------------------------------------------------

# The project "demo" with one repo of one commit, the key saved, and Linear
# answering with $1, for `task start` to ask it about a card.
card_asked() {
  "$E" project new demo >/dev/null
  git init -q -b main "$HOME/Dev/api"
  git -C "$HOME/Dev/api" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  "$E" project add demo "$HOME/Dev/api" >/dev/null
  saved_key; stub_linear; linear_answers "$1"
}
# The repo's branches other than main, one per line.
task_branches() { git -C "$HOME/Dev/api" branch --format='%(refname:short)' | grep -v '^main$' || true; }

# Linear keeps a card as its team's key and a number, so that is how it is
# asked: once, with the key on stdin as for every question. The question
# after it is the card's move, once the task is made.
task_start_asks_linear_for_the_card_by_team_and_number() {
  card_asked "$(card_answer ABC-122 'Export orders' feat)"
  "$E" task start demo abc-122 >/dev/null || fail "task start exited non-zero"
  case $(curl_calls) in *'"team":"ABC"'*) ;; *) fail "did not ask for team ABC: $(curl_calls)" ;; esac
  case $(curl_calls) in *'"number":122'*) ;; *) fail "did not ask for number 122: $(curl_calls)" ;; esac
  [ "$(key_given_to_curl)" = "$KEY" ] || fail "curl was not given the key on stdin"
  case $(curl_calls) in *"$KEY"*) fail "passed the key to curl as an argument" ;; esac
  [ "$(curl_calls | grep -c 'labels')" = 1 ] || fail "asked Linear for the card $(curl_calls | grep -c 'labels') times"
  case $(curl_calls | head -n 1) in *labels*) ;; *) fail "the card was not the first question: $(curl_calls)" ;; esac
}

# The type is the card's label in the Type group. A label in another group,
# or in none, is not a type.
task_start_takes_the_type_from_the_type_group() {
  card_asked '{"data":{"issues":{"nodes":[{"identifier":"ABC-122","title":"Export orders","labels":{"nodes":[
    {"name":"urgent","parent":{"name":"Priority"}},{"name":"feat","parent":null},{"name":"fix","parent":{"name":"Type"}}]}}]}}}'
  "$E" task start demo ABC-122 >/dev/null || fail "task start exited non-zero"
  [ "$(task_branches)" = fix/abc-122-export-orders ] || fail "the task's branch is: $(task_branches)"
}

task_start_finds_no_type_outside_the_type_group() {
  card_asked '{"data":{"issues":{"nodes":[{"identifier":"ABC-122","title":"Export orders","labels":{"nodes":[
    {"name":"feat","parent":{"name":"Kind"}},{"name":"fix"}]}}]}}}'
  "$E" task start demo ABC-122 >/dev/null 2>"$TMP/err" && fail "started a card with no type"
  grep -q 'has no type' "$TMP/err" || fail "did not say the card has no type: $(cat "$TMP/err")"
  [ -z "$(task_branches)" ] || fail "made a branch: $(task_branches)"
}

# An answer with no list of cards in it is not Linear saying it has none.
task_start_says_when_linears_answer_cannot_be_read() {
  card_asked '{"data":{"issues":null}}'
  "$E" task start demo ABC-122 >/dev/null 2>"$TMP/err" && fail "exited zero on an answer it cannot read"
  grep -q 'not one entourage can read' "$TMP/err" || fail "did not say the answer cannot be read: $(cat "$TMP/err")"
  if grep -q 'has no card' "$TMP/err"; then fail "said Linear has no such card: $(cat "$TMP/err")"; fi
}

task_start_says_when_linear_rejects_the_key() {
  card_asked "$REJECTED"; linear_status 401
  "$E" task start demo ABC-122 >/dev/null 2>"$TMP/err" && fail "exited zero with a rejected key"
  grep -q 'Linear rejected the key' "$TMP/err" || fail "did not say the key was rejected: $(cat "$TMP/err")"
  [ ! -e "$P/demo/tasks" ] || fail "made a tasks folder"
}

CARD_LOOKUP_CASES="task_start_asks_linear_for_the_card_by_team_and_number
  task_start_takes_the_type_from_the_type_group task_start_finds_no_type_outside_the_type_group
  task_start_says_when_linears_answer_cannot_be_read task_start_says_when_linear_rejects_the_key"

# --- where the key comes from: entourage's env file, or the environment -----

# A key exported in the shell works with no file at all.
task_ls_takes_the_key_from_the_environment() {
  listed_demo; rm "$(env_file)"; linear_answers "$ONE_TEAM"
  LINEAR_API_KEY=lin_api_FromTheShell "$E" task ls demo >/dev/null || fail "task ls exited non-zero"
  [ "$(key_given_to_curl)" = lin_api_FromTheShell ] || fail "curl was given the key: $(key_given_to_curl)"
}

task_ls_prefers_an_exported_key_to_the_env_file() {
  listed_demo; linear_answers "$ONE_TEAM"
  LINEAR_API_KEY=lin_api_FromTheShell "$E" task ls demo >/dev/null || fail "task ls exited non-zero"
  [ "$(key_given_to_curl)" = lin_api_FromTheShell ] || fail "curl was given the key: $(key_given_to_curl)"
}

# The file is written by hand too, and this is how people write such lines.
env_file_takes_quotes_spaces_and_export() {
  listed_demo; linear_answers "$ONE_TEAM"
  for line in "LINEAR_API_KEY=\"$KEY\"" "LINEAR_API_KEY='$KEY'" "export LINEAR_API_KEY=$KEY" "  LINEAR_API_KEY=$KEY  "; do
    printf '%s\n' '# my key' "$line" > "$(env_file)"
    : > "$TMP/curl-stdin.log"
    "$E" task ls demo >/dev/null 2>&1 || fail "task ls exited non-zero for the line: $line"
    [ "$(key_given_to_curl)" = "$KEY" ] || fail "for the line '$line' curl was given: $(key_given_to_curl)"
  done
}

# The file is read, never run.
env_file_is_never_run() {
  listed_demo; linear_answers "$ONE_TEAM"
  printf '%s\n' "LINEAR_API_KEY=$KEY" "touch $TMP/ran-a-line" "ENTOURAGE_X=\$(touch $TMP/ran-a-value)" > "$(env_file)"
  "$E" task ls demo >/dev/null 2>&1 || fail "task ls exited non-zero"
  [ ! -e "$TMP/ran-a-line" ] || fail "ran a line of the env file"
  [ ! -e "$TMP/ran-a-value" ] || fail "ran a value in the env file"
}

# Only the variables entourage reads are taken from the file: a line for
# anything else is skipped. The Linear key from the file is not passed on to
# the programs entourage starts: it reaches curl on stdin and nowhere else.
# ENTOURAGE_HOME is not taken at all, since it says where the file is.
env_file_keeps_its_lines_from_the_programs_entourage_starts() {
  listed_demo; linear_answers "$ONE_TEAM"
  cat > "$TMP/bin/curl" <<EOF
#!/usr/bin/env bash
cat >> "$TMP/curl-stdin.log"
printf '%s' "\${NOT_ENTOURAGES:-unset} \${ENTOURAGE_HOME:-unset} \${LINEAR_API_KEY:+set}" > "$TMP/seen-by-curl"
cat "$TMP/linear/1.json"
printf '\n200'
EOF
  printf '%s\n' "LINEAR_API_KEY=$KEY" 'NOT_ENTOURAGES=leaked' "ENTOURAGE_HOME=$TMP/elsewhere" > "$(env_file)"
  "$E" task ls demo >/dev/null 2>&1 || fail "task ls exited non-zero"
  [ "$(key_given_to_curl)" = "$KEY" ] || fail "curl was given the key: $(key_given_to_curl)"
  [ "$(cat "$TMP/seen-by-curl" 2>&1)" = "unset unset " ] ||
    fail "curl saw NOT_ENTOURAGES, ENTOURAGE_HOME and LINEAR_API_KEY as: $(cat "$TMP/seen-by-curl" 2>&1)"
}

# ENTOURAGE_HOME says where the file is, so the file cannot move it.
env_file_cannot_move_entourages_folder() {
  mkdir -p "$HOME/.config/entourage"
  echo "ENTOURAGE_HOME=$TMP/elsewhere" > "$(env_file)"
  "$E" project new demo >/dev/null || fail "project new exited non-zero"
  [ -d "$P/demo" ] || fail "the project was not made in the usual folder"
  [ ! -e "$TMP/elsewhere" ] || fail "the env file moved entourage's folder"
}

# A line added at the end of the file, by hand, is the one that counts.
env_file_takes_the_last_line_for_a_name() {
  listed_demo; linear_answers "$ONE_TEAM"
  printf '%s\n' 'LINEAR_API_KEY=lin_api_Older' "LINEAR_API_KEY=$KEY" > "$(env_file)"
  "$E" task ls demo >/dev/null 2>&1 || fail "task ls exited non-zero"
  [ "$(key_given_to_curl)" = "$KEY" ] || fail "curl was given: $(key_given_to_curl)"
}

# However many lines the file has for it, an exported key still wins.
env_file_lines_never_beat_an_exported_key() {
  listed_demo; linear_answers "$ONE_TEAM"
  printf '%s\n' "LINEAR_API_KEY=$KEY" "LINEAR_API_KEY=$KEY" > "$(env_file)"
  LINEAR_API_KEY=lin_api_FromTheShell "$E" task ls demo >/dev/null 2>&1 || fail "task ls exited non-zero"
  [ "$(key_given_to_curl)" = lin_api_FromTheShell ] || fail "curl was given: $(key_given_to_curl)"
}

# An exported key that is empty counts as none, so the file's key is used.
env_file_is_used_when_the_exported_key_is_empty() {
  listed_demo; linear_answers "$ONE_TEAM"
  LINEAR_API_KEY= "$E" task ls demo >/dev/null 2>&1 || fail "task ls exited non-zero"
  [ "$(key_given_to_curl)" = "$KEY" ] || fail "curl was given: $(key_given_to_curl)"
}

# Comments after a value, spaces around =, and the mark some editors start a
# file with.
env_file_takes_comments_spaces_around_equals_and_a_bom() {
  listed_demo; linear_answers "$ONE_TEAM"
  for line in "LINEAR_API_KEY=$KEY # my key" "LINEAR_API_KEY = $KEY" "LINEAR_API_KEY= $KEY" \
      "export LINEAR_API_KEY =\"$KEY\"" "$(printf '\357\273\277')LINEAR_API_KEY=$KEY"; do
    printf '%s\n' "$line" > "$(env_file)"
    : > "$TMP/curl-stdin.log"
    "$E" task ls demo >/dev/null 2>&1 || fail "task ls exited non-zero for the line: $line"
    [ "$(key_given_to_curl)" = "$KEY" ] || fail "for the line '$line' curl was given: $(key_given_to_curl)"
  done
}

# The same for a path: a comment after it must not become part of it.
env_file_drops_a_comment_from_a_path() {
  mkdir -p "$HOME/.config/entourage"
  printf 'HERDR_APP_HOME=%s # where Herdr is\n' "$APP" > "$(env_file)"
  out=$("$E" status 2>&1)
  case $out in *"# where Herdr is"*) fail "took the comment as part of the path: $out" ;; esac
}

# A line with only a comment after the = sets nothing.
env_file_value_that_is_only_a_comment_is_empty() {
  listed_demo; linear_answers "$ONE_TEAM"
  printf '%s\n' 'LINEAR_API_KEY= # none yet' > "$(env_file)"
  out=$("$E" task ls demo 2>&1) && fail "exited zero with no key"
  case $out in *"no Linear key is saved"*) ;; *) fail "did not say no key is saved: $out" ;; esac
}

# An env file entourage cannot read stops it, in a sentence. Going on without
# the file would lose its settings, and linear key would write it anew with
# only the key in it.
env_file_that_cannot_be_read_says_so() {
  saved_key; chmod 000 "$(env_file)"
  # As root the file can still be read, so there is nothing to test.
  if [ -r "$(env_file)" ]; then chmod 600 "$(env_file)"; return; fi
  out=$("$E" help 2>&1) && fail "exited zero with an env file it cannot read"
  chmod 600 "$(env_file)"
  case $out in *"cannot read $(env_file)"*) ;; *) fail "did not say it cannot read the file: $out" ;; esac
  case $out in *"line "[0-9]*) fail "gave bash's own message: $out" ;; esac
}

# --- the card skills' writes: linear type and linear section ----------------

# What a question to Linear held: the JSON body of the Nth call to curl.
sent_body() {
  curl_calls | sed -n "${1}p" | sed 's/.*--data-binary \(.*\) --write-out .*/\1/'
}

# Card ABC-122 with the labels given as JSON objects, and the Type labels
# Linear has for that name: team ABC's, another team's, and one for the whole
# workspace when $2 says so.
type_read() {
  local labels=$1 workspace=${2:-}
  local found='{"id":"abc-feat","name":"feat","team":{"key":"ABC"}},{"id":"xyz-feat","name":"feat","team":{"key":"XYZ"}}'
  [ -z "$workspace" ] || found='{"id":"xyz-feat","name":"feat","team":{"key":"XYZ"}},{"id":"all-feat","name":"feat","team":null}'
  printf '{"data":{"issues":{"nodes":[{"id":"uuid-122","identifier":"ABC-122","labels":{"nodes":[%s]}}]},"issueLabels":{"nodes":[%s]}}}' "$labels" "$found"
}
BUG_LABEL='{"id":"abc-bug","name":"Bug","parent":null}'
FIX_LABEL='{"id":"abc-fix","name":"fix","parent":{"name":"Type"}}'
# Linear's answer to the change: the card's labels as they are now.
type_saved() {
  printf '{"data":{"issueUpdate":{"success":true,"issue":{"labels":{"nodes":[%s]}}}}}' "$1"
}

linear_type_sets_the_type_and_keeps_the_other_labels() {
  saved_key; stub_linear
  linear_answers "$(type_read "$BUG_LABEL,$FIX_LABEL")" \
    "$(type_saved '{"name":"Bug","parent":null},{"name":"feat","parent":{"name":"Type"}}')"
  out=$("$E" linear type abc-122 feat) || fail "linear type exited non-zero: $out"
  case $out in *"ABC-122"*feat*fix*) ;; *) fail "did not say the type and the one it replaced: $out" ;; esac
  [ "$(curl_count)" = 2 ] || fail "asked Linear $(curl_count) times, not twice"
  # Only the type labels are named: the card's other labels are never sent.
  got=$(sent_body 2 | jq -c '.variables | {id, add: .input.addedLabelIds, remove: .input.removedLabelIds, all: .input.labelIds}' 2>&1)
  [ "$got" = '{"id":"uuid-122","add":["abc-feat"],"remove":["abc-fix"],"all":null}' ] ||
    fail "sent: $got (all of it: $(sent_body 2))"
}

# A team with no Type group of its own uses the workspace's.
linear_type_takes_a_workspace_label() {
  saved_key; stub_linear
  linear_answers "$(type_read "$BUG_LABEL" workspace)" \
    "$(type_saved '{"name":"Bug","parent":null},{"name":"feat","parent":{"name":"Type"}}')"
  "$E" linear type ABC-122 feat >/dev/null || fail "linear type exited non-zero"
  got=$(sent_body 2 | jq -c '.variables.input.addedLabelIds' 2>&1)
  [ "$got" = '["all-feat"]' ] || fail "added: $got"
}

linear_type_leaves_a_card_that_has_the_type_already() {
  saved_key; stub_linear
  linear_answers "$(type_read "$BUG_LABEL,"'{"id":"abc-feat","name":"feat","parent":{"name":"Type"}}')"
  out=$("$E" linear type ABC-122 feat) || fail "linear type exited non-zero: $out"
  case $out in *already*) ;; *) fail "did not say the card has the type already: $out" ;; esac
  [ "$(curl_count)" = 1 ] || fail "changed a card that needed no change: $(curl_calls)"
}

# entourage creates nothing in Linear: a missing label is the human's to make.
linear_type_refuses_a_team_without_the_label() {
  saved_key; stub_linear
  linear_answers '{"data":{"issues":{"nodes":[{"id":"uuid-122","identifier":"ABC-122","labels":{"nodes":[]}}]},"issueLabels":{"nodes":[{"id":"xyz-feat","name":"feat","team":{"key":"XYZ"}}]}}}'
  out=$("$E" linear type ABC-122 feat 2>&1) && fail "exited zero with no feat label for team ABC"
  case $out in *ABC*feat*Type* | *ABC*Type*feat*) ;; *) fail "did not name the team, the label and the group: $out" ;; esac
  [ "$(curl_count)" = 1 ] || fail "changed the card anyway: $(curl_calls)"
}

linear_type_refuses_a_type_that_is_not_one() {
  saved_key; stub_linear
  "$E" linear type ABC-122 feature >/dev/null 2>&1 && fail "accepted the type 'feature'"
  "$E" linear type ABC-122 >/dev/null 2>&1 && fail "accepted no type"
  [ "$(curl_count)" = 0 ] || fail "asked Linear about a type that is not one: $(curl_calls)"
}

linear_type_refuses_a_card_linear_does_not_have() {
  saved_key; stub_linear; linear_answers '{"data":{"issues":{"nodes":[]},"issueLabels":{"nodes":[]}}}'
  out=$("$E" linear type ABC-999 feat 2>&1) && fail "exited zero for a card Linear does not have"
  case $out in *"Linear has no card ABC-999"*) ;; *) fail "did not say Linear has no such card: $out" ;; esac
  [ "$(curl_count)" = 1 ] || fail "changed something: $(curl_calls)"
}

# What Linear says it saved is checked: one type, the one asked for.
linear_type_fails_when_linear_keeps_another_type() {
  saved_key; stub_linear
  linear_answers "$(type_read "$FIX_LABEL")" \
    "$(type_saved '{"name":"fix","parent":{"name":"Type"}},{"name":"feat","parent":{"name":"Type"}}')"
  out=$("$E" linear type ABC-122 feat 2>&1) && fail "exited zero when the card was left with two types"
  case $out in *fix*) ;; *) fail "did not say what Linear kept: $out" ;; esac
}

# Card ABC-122 with the description given, as JSON text.
section_read() {
  printf '{"data":{"issues":{"nodes":[{"id":"uuid-122","identifier":"ABC-122","description":%s}]}}}' "$1"
}
# Linear's answer to the change: the description as it now stands.
section_saved() {
  printf '{"data":{"issueUpdate":{"success":true,"issue":{"description":%s}}}}' "$(printf '%s' "$1" | jq -Rs .)"
}
# Linear's answer when card ABC-122 is read whole, for linear read: its type
# and another label, a parent, a description with a folded section and an
# open one, two comments, the newer first and the older made by an app, and
# two sub-issues. $1, a jq filter, changes the card before it is sent.
READ_DESCRIPTION='Managers keep asking for the order list.

+++ ## Specification
**Why:** A manager can download the order list.
+++

## Breakdown
One piece.'
read_answer() {
  jq -cn --arg description "$READ_DESCRIPTION" '
    {identifier: "ABC-122", title: "Export orders as CSV",
     url: "https://linear.app/x/issue/ABC-122/export-orders-as-csv",
     description: $description,
     state: {name: "In Progress", type: "started"},
     labels: {nodes: [{name: "feat", parent: {name: "Type"}}, {name: "urgent", parent: null}],
              pageInfo: {hasNextPage: false}},
     parent: {identifier: "ABC-100", title: "Orders"},
     comments: {nodes: [
       {body: "Approved.", createdAt: "2024-03-02T10:00:00.000Z", user: {name: "Ada Lovelace"}, botActor: null},
       {body: "Opened a pull request.\n\nhttps://github.com/x/y/pull/1", createdAt: "2024-03-01T09:30:00.000Z",
        user: null, botActor: {name: "GitHub"}}],
       pageInfo: {hasNextPage: false}},
     children: {nodes: [
       {identifier: "ABC-123", title: "Slice one", state: {name: "Todo", type: "unstarted"}},
       {identifier: "ABC-124", title: "Slice two", state: {name: "Backlog", type: "backlog"}}],
       pageInfo: {hasNextPage: false}}}
    | '"${1:-.}"'
    | {data: {issues: {nodes: [.]}}}'
}
ORIGINAL='Managers keep asking for the order list.

Let them download it.'
SPEC_BODY='**Why:** A manager can download the order list.

**Done when:**
- [ ] A Download CSV button is on the orders page.'

linear_section_adds_a_collapsed_section_below_the_description() {
  saved_key; stub_linear
  want="$ORIGINAL

+++ ## Specification
$SPEC_BODY
+++"
  linear_answers "$(section_read "$(printf '%s' "$ORIGINAL" | jq -Rs .)")" "$(section_saved "$want")"
  out=$(printf '%s\n' "$SPEC_BODY" | "$E" linear section ABC-122 Specification) || fail "linear section exited non-zero: $out"
  case $out in *Specification*ABC-122*) ;; *) fail "did not say what it added: $out" ;; esac
  got=$(sent_body 2 | jq -r '.variables.input.description')
  [ "$got" = "$want" ] || fail "sent the description: $got"
  [ "$(sent_body 2 | jq -r '.variables.id')" = uuid-122 ] || fail "did not change the card it read: $(sent_body 2)"
}

# The human reads the Breakdown to approve the card, so it is not folded away.
linear_section_writes_the_breakdown_open() {
  saved_key; stub_linear
  want="$ORIGINAL

## Breakdown
One piece. Already small."
  linear_answers "$(section_read "$(printf '%s' "$ORIGINAL" | jq -Rs .)")" "$(section_saved "$want")"
  printf '%s\n' 'One piece. Already small.' | "$E" linear section ABC-122 Breakdown >/dev/null || fail "linear section exited non-zero"
  [ "$(sent_body 2 | jq -r '.variables.input.description')" = "$want" ] ||
    fail "sent the description: $(sent_body 2 | jq -r '.variables.input.description')"
}

linear_section_writes_into_an_empty_description() {
  saved_key; stub_linear
  want="+++ ## Plan
**Approach:** Like the invoice export.
+++"
  linear_answers "$(section_read null)" "$(section_saved "$want")"
  printf '%s\n' '**Approach:** Like the invoice export.' | "$E" linear section ABC-122 Plan >/dev/null ||
    fail "linear section exited non-zero"
  [ "$(sent_body 2 | jq -r '.variables.input.description')" = "$want" ] ||
    fail "sent the description: $(sent_body 2 | jq -r '.variables.input.description')"
}

# Linear keeps a folded section as +++, however it was written; one written
# by hand as >>> counts too.
linear_section_refuses_a_second_section_of_the_same_name() {
  saved_key; stub_linear
  for mark in '+++' '>>>'; do
    : > "$TMP/curl-calls.log"
    linear_answers "$(section_read "$(printf '%s\n\n%s ## Specification\n\nold\n\n%s' "$ORIGINAL" "$mark" "$mark" | jq -Rs .)")"
    out=$(printf '%s\n' "$SPEC_BODY" | "$E" linear section ABC-122 Specification 2>&1) &&
      fail "exited zero with a Specification already there, folded with $mark"
    case $out in *"--replace"*) ;; *) fail "did not say how to replace it: $out" ;; esac
    [ "$(curl_count)" = 1 ] || fail "changed the card anyway: $(curl_calls)"
  done
}

# --replace swaps the section in place and leaves the sections around it.
linear_section_replaces_a_section_in_place() {
  saved_key; stub_linear
  before='Intro.

+++ ## Specification

old

+++

>>> ## Plan

The plan.

>>>'
  want='Intro.

+++ ## Specification
new
+++

>>> ## Plan

The plan.

>>>'
  linear_answers "$(section_read "$(printf '%s' "$before" | jq -Rs .)")" "$(section_saved "$want")"
  printf '%s\n' new | "$E" linear section ABC-122 Specification --replace >/dev/null || fail "linear section exited non-zero"
  got=$(sent_body 2 | jq -r '.variables.input.description')
  [ "$got" = "$want" ] || fail "sent the description: $got"
}

linear_section_replaces_the_open_breakdown() {
  saved_key; stub_linear
  before='Intro.

## Breakdown

1. **The old slice**'
  want='Intro.

## Breakdown
One piece.'
  linear_answers "$(section_read "$(printf '%s' "$before" | jq -Rs .)")" "$(section_saved "$want")"
  printf '%s\n' 'One piece.' | "$E" linear section ABC-122 Breakdown --replace >/dev/null || fail "linear section exited non-zero"
  got=$(sent_body 2 | jq -r '.variables.input.description')
  [ "$got" = "$want" ] || fail "sent the description: $got"
}

# What Linear saved is read back: the text above the section must be as it was.
linear_section_fails_when_the_text_above_changed() {
  saved_key; stub_linear
  linear_answers "$(section_read "$(printf '%s' "$ORIGINAL" | jq -Rs .)")" \
    "$(section_saved "Someone else's words.

+++ ## Specification
$SPEC_BODY
+++")"
  out=$(printf '%s\n' "$SPEC_BODY" | "$E" linear section ABC-122 Specification 2>&1) && fail "exited zero with the text above changed"
  case $out in *above*) ;; *) fail "did not say the text above changed: $out" ;; esac
}

# Linear rewrites a section as it saves it: a blank line after the heading and
# before the end, * for -, and a mention as a link. Only the text above and
# the heading are held to what was sent.
linear_section_accepts_linears_rewriting_of_the_section() {
  saved_key; stub_linear
  linear_answers "$(section_read "$(printf '%s' "$ORIGINAL" | jq -Rs .)")" \
    "$(section_saved "$ORIGINAL

+++ ## Specification

**Why:** A manager can download the order list, as [ABC-1](https://linear.app/x/issue/ABC-1) asked.

**Done when:**

* [ ] A Download CSV button is on the orders page.

+++")"
  printf '%s\n' "$SPEC_BODY" | "$E" linear section ABC-122 Specification >/dev/null || fail "linear section exited non-zero"
}

linear_section_refuses_what_is_not_a_section() {
  saved_key; stub_linear
  printf '%s\n' body | "$E" linear section ABC-122 Notes >/dev/null 2>&1 && fail "accepted the section 'Notes'"
  printf '' | "$E" linear section ABC-122 Plan >/dev/null 2>&1 && fail "accepted an empty section"
  printf '%s\n' 'one' '>>>' 'two' | "$E" linear section ABC-122 Plan >/dev/null 2>&1 &&
    fail "accepted a body with a >>> line, which would end the section early"
  printf '%s\n' 'one' '+++' 'two' | "$E" linear section ABC-122 Plan >/dev/null 2>&1 &&
    fail "accepted a body with a +++ line, which would end the section early"
  printf '%s\n' body | "$E" linear section ABC-122 Plan --force >/dev/null 2>&1 && fail "accepted --force"
  [ "$(curl_count)" = 0 ] || fail "asked Linear before refusing: $(curl_calls)"
}

# --- what the review of LAB-69 found ----------------------------------------

# Start Linear's answers again, for a case that runs a command more than once.
fresh_answers() {
  rm -f "$TMP/linear/count" "$TMP/curl-calls.log" "$TMP/curl-stdin.log" "$TMP/linear/"*.json
  linear_answers "$@"
}

# The command adds the heading itself, and a line that starts a heading or a
# fold would end the section early, or put a second one on the card. A body
# with either is refused before Linear is asked.
linear_section_refuses_a_body_with_its_own_heading() {
  saved_key; stub_linear
  printf '%s\n' '## Breakdown' 'One piece.' | "$E" linear section ABC-122 Breakdown >/dev/null 2>&1 &&
    fail "accepted a Breakdown body that starts with its own heading"
  printf '%s\n' '+++ ## Plan' 'The plan.' | "$E" linear section ABC-122 Plan >/dev/null 2>&1 &&
    fail "accepted a Plan body that starts with its own heading"
  printf '%s\n' 'Why: x' '' '>>> ## Specification' '' 'more' | "$E" linear section ABC-122 Specification >/dev/null 2>&1 &&
    fail "accepted a Specification body that holds its own heading"
  printf '%s\n' '1. **Slice one**' '## Why this cut' 'Because.' | "$E" linear section ABC-122 Breakdown >/dev/null 2>&1 &&
    fail "accepted a Breakdown body with a heading that would end it early"
  printf '%s\n' '1. **Slice one**' '' '+++ Agent notes' '' 'Cut by layer.' '' '+++' |
    "$E" linear section ABC-122 Breakdown >/dev/null 2>&1 &&
    fail "accepted a Breakdown body with a fold that would end it early"
  [ "$(curl_count)" = 0 ] || fail "asked Linear before refusing: $(curl_count) calls"
}

# --replace takes the place of a section the command can read. With none, it
# says so, rather than add a second one beside a section in another form.
linear_section_replace_refuses_a_card_without_the_section() {
  saved_key; stub_linear
  linear_answers "$(section_read "$(printf '%s' 'Intro.

+++ Specification

old

+++' | jq -Rs .)")"
  out=$(printf '%s\n' new | "$E" linear section ABC-122 Specification --replace 2>&1) &&
    fail "exited zero with no Specification to replace: $out"
  [ "$(curl_count)" = 1 ] || fail "changed the card anyway: $(curl_count) calls"
}

# The open Breakdown is refused a second time too: the skills' retry after
# "could not reach Linear" counts on it.
linear_section_refuses_a_second_breakdown() {
  saved_key; stub_linear
  linear_answers "$(section_read "$(printf '%s\n\n## Breakdown\n\nOne piece.' "$ORIGINAL" | jq -Rs .)")"
  out=$(printf '%s\n' 'One piece.' | "$E" linear section ABC-122 Breakdown 2>&1) &&
    fail "exited zero with a Breakdown already there"
  case $out in *"--replace"*) ;; *) fail "did not say how to replace it: $out" ;; esac
  [ "$(curl_count)" = 1 ] || fail "changed the card anyway: $(curl_count) calls"
}

# What Linear saved must have the section once.
linear_section_fails_when_linear_has_the_section_twice() {
  saved_key; stub_linear
  linear_answers "$(section_read "$(printf '%s' "$ORIGINAL" | jq -Rs .)")" \
    "$(section_saved "$ORIGINAL

+++ ## Specification
$SPEC_BODY
+++

+++ ## Specification
$SPEC_BODY
+++")"
  out=$(printf '%s\n' "$SPEC_BODY" | "$E" linear section ABC-122 Specification 2>&1) &&
    fail "exited zero with the section twice in Linear's copy"
  case $out in *once*) ;; *) fail "did not say the section is not there once: $out" ;; esac
}

# A section folded with >>> ends at its own >>> line: the Plan below stays.
linear_section_replaces_a_section_folded_with_the_other_mark() {
  saved_key; stub_linear
  before='Intro.

>>> ## Specification

old

>>>

+++ ## Plan

The plan.

+++'
  want='Intro.

+++ ## Specification
new
+++

+++ ## Plan

The plan.

+++'
  linear_answers "$(section_read "$(printf '%s' "$before" | jq -Rs .)")" "$(section_saved "$want")"
  printf '%s\n' new | "$E" linear section ABC-122 Specification --replace >/dev/null || fail "linear section exited non-zero"
  got=$(sent_body 2 | jq -r '.variables.input.description')
  [ "$got" = "$want" ] || fail "sent the description: $got"
}

# An open Breakdown ends where the next section starts: what is below it stays.
linear_section_replaces_an_open_breakdown_with_a_section_below() {
  saved_key; stub_linear
  before='Intro.

## Breakdown

1. **The old slice**

+++ ## Notes

kept

+++'
  want='Intro.

## Breakdown
One piece.

+++ ## Notes

kept

+++'
  linear_answers "$(section_read "$(printf '%s' "$before" | jq -Rs .)")" "$(section_saved "$want")"
  printf '%s\n' 'One piece.' | "$E" linear section ABC-122 Breakdown --replace >/dev/null || fail "linear section exited non-zero"
  got=$(sent_body 2 | jq -r '.variables.input.description')
  [ "$got" = "$want" ] || fail "sent the description: $got"
}

# A # heading ends the Breakdown too: the human's notes below it stay.
linear_section_replaces_a_breakdown_with_a_top_heading_below() {
  saved_key; stub_linear
  before='Intro.

## Breakdown

One piece.

# Notes

A note the human added.'
  want='Intro.

## Breakdown
Two pieces.

# Notes

A note the human added.'
  linear_answers "$(section_read "$(printf '%s' "$before" | jq -Rs .)")" "$(section_saved "$want")"
  printf '%s\n' 'Two pieces.' | "$E" linear section ABC-122 Breakdown --replace >/dev/null || fail "linear section exited non-zero"
  got=$(sent_body 2 | jq -r '.variables.input.description')
  [ "$got" = "$want" ] || fail "sent the description: $got"
}

# A folded section that is never closed, with another one after it, cannot be
# told apart from the next: replacing it is refused, not the next one deleted.
linear_section_refuses_to_replace_a_fold_that_is_never_closed() {
  saved_key; stub_linear
  linear_answers "$(section_read "$(printf '%s' 'Intro.

+++ ## Specification

old

+++ ## Plan

The plan.

+++' | jq -Rs .)")"
  out=$(printf '%s\n' new | "$E" linear section ABC-122 Specification --replace 2>&1) &&
    fail "replaced a Specification that is never closed: $out"
  [ "$(curl_count)" = 1 ] || fail "changed the card anyway: $(curl_count) calls"
}

# A heading line inside a code block is the card's text, not its section.
linear_section_skips_a_heading_in_a_code_block() {
  saved_key; stub_linear
  before='How a card looks:

```
+++ ## Specification
body
+++
```'
  want="$before

+++ ## Specification
$SPEC_BODY
+++"
  linear_answers "$(section_read "$(printf '%s' "$before" | jq -Rs .)")" "$(section_saved "$want")"
  out=$(printf '%s\n' "$SPEC_BODY" | "$E" linear section ABC-122 Specification 2>&1) ||
    fail "took the example in a code block for the card's Specification: $out"
  [ "$(sent_body 2 | jq -r '.variables.input.description')" = "$want" ] ||
    fail "sent the description: $(sent_body 2 | jq -r '.variables.input.description')"
}

# A description whose lines end with \r is read the same.
linear_section_reads_a_description_with_cr_line_ends() {
  saved_key; stub_linear
  linear_answers "$(section_read "$(printf 'Intro.\r\n\r\n+++ ## Specification\r\n\r\nold\r\n\r\n+++' | jq -Rs .)")"
  out=$(printf '%s\n' new | "$E" linear section ABC-122 Specification 2>&1) &&
    fail "exited zero with a Specification already there"
  case $out in *"--replace"*) ;; *) fail "did not say how to replace it: $out" ;; esac
  [ "$(curl_count)" = 1 ] || fail "changed the card anyway: $(curl_count) calls"
}

# The text above is sent as it was, \r and all, and the check holds whether
# Linear keeps the \r or drops it.
linear_section_takes_a_description_with_crlf_line_ends() {
  saved_key; stub_linear
  want=$(printf 'Line one\r\nLine two\n\n+++ ## Specification\n%s\n+++' "$SPEC_BODY")
  for saved in "$want" "$(printf '%s' "$want" | tr -d '\r')"; do
    fresh_answers "$(section_read '"Line one\r\nLine two\r\n"')" "$(section_saved "$saved")"
    out=$(printf '%s\n' "$SPEC_BODY" | "$E" linear section ABC-122 Specification 2>&1) || fail "exited non-zero: $out"
    [ "$(sent_body 2 | jq -r '.variables.input.description')" = "$want" ] || fail "sent: $(sent_body 2)"
  done
}

linear_section_says_when_jq_is_missing() {
  saved_key; stub_linear; hide_jq
  out=$(printf '%s\n' body | "$E" linear section ABC-122 Plan 2>&1) && fail "exited zero without jq"
  case $out in *"jq is not installed"*) ;; *) fail "did not say jq is missing: $out" ;; esac
  case $out in *"command not found"*) fail "gave bash's own message: $out" ;; esac
}

# The team's label wins over the workspace's, whichever Linear lists first.
linear_type_prefers_the_teams_label_to_the_workspaces() {
  saved_key; stub_linear
  linear_answers '{"data":{"issues":{"nodes":[{"id":"uuid-122","identifier":"ABC-122","labels":{"nodes":[]}}]},"issueLabels":{"nodes":[{"id":"all-feat","name":"feat","team":null},{"id":"abc-feat","name":"feat","team":{"key":"ABC"}}]}}}' \
    "$(type_saved '{"name":"feat","parent":{"name":"Type"}}')"
  "$E" linear type ABC-122 feat >/dev/null || fail "linear type exited non-zero"
  got=$(sent_body 2 | jq -c '.variables.input.addedLabelIds' 2>&1)
  [ "$got" = '["abc-feat"]' ] || fail "added: $got"
}

# Only the card's team's label and the workspace's are asked for, so the
# card's own is never past the first page, however many teams there are.
linear_type_asks_only_for_the_teams_and_the_workspaces_labels() {
  saved_key; stub_linear
  linear_answers "$(type_read "$BUG_LABEL")" "$(type_saved '{"name":"Bug","parent":null},{"name":"feat","parent":{"name":"Type"}}')"
  "$E" linear type ABC-122 feat >/dev/null || fail "linear type exited non-zero"
  case $(sent_body 1 | jq -r '.query') in
    *'or: [{team: {key: {eq: $team}}}, {team: {null: true}}]'*) ;;
    *) fail "did not narrow the labels to the team's and the workspace's: $(sent_body 1)" ;;
  esac
}

# A card with two type labels ends with one: both others come off.
linear_type_takes_off_every_other_type() {
  saved_key; stub_linear
  linear_answers "$(type_read "$FIX_LABEL"',{"id":"abc-chore","name":"chore","parent":{"name":"Type"}}')" \
    "$(type_saved '{"name":"feat","parent":{"name":"Type"}}')"
  "$E" linear type ABC-122 feat >/dev/null || fail "linear type exited non-zero"
  got=$(sent_body 2 | jq -c '.variables.input.removedLabelIds' 2>&1)
  [ "$got" = '["abc-fix","abc-chore"]' ] || fail "removed: $got"
}

# What Linear saved is checked for the card's other labels too.
linear_type_fails_when_linear_drops_another_label() {
  saved_key; stub_linear
  linear_answers "$(type_read "$BUG_LABEL,$FIX_LABEL")" "$(type_saved '{"name":"feat","parent":{"name":"Type"}}')"
  out=$("$E" linear type ABC-122 feat 2>&1) && fail "exited zero with the card's Bug label gone"
  case $out in *Bug*) ;; *) fail "did not name the label Linear dropped: $out" ;; esac
}

# --- reading a card: linear read --------------------------------------------

# The card laid out as it is in Linear: its head, the description as written,
# its comments oldest first, and its sub-issues. Linear is asked once, for
# the card by its team and number, with the key on stdin.
linear_read_prints_the_card_laid_out() {
  saved_key; stub_linear; linear_answers "$(read_answer)"
  out=$("$E" linear read abc-122) || fail "linear read exited non-zero: $out"
  want="ABC-122  Export orders as CSV
Status: In Progress
Labels: feat, urgent
Parent: ABC-100  Orders
URL:    https://linear.app/x/issue/ABC-122/export-orders-as-csv

$READ_DESCRIPTION

Comments (2)
  GitHub, 2024-03-01T09:30:00Z
    Opened a pull request.

    https://github.com/x/y/pull/1
  Ada Lovelace, 2024-03-02T10:00:00Z
    Approved.

Sub-issues (2)
  ABC-123  Todo  Slice one
  ABC-124  Backlog  Slice two"
  [ "$out" = "$want" ] || fail "printed: $out"
  [ "$(curl_count)" = 1 ] || fail "asked Linear $(curl_count) times, not once: $(curl_calls)"
  [ "$(sent_body 1 | jq -c '.variables')" = '{"team":"ABC","number":122}' ] || fail "asked for: $(sent_body 1)"
  [ "$(key_given_to_curl)" = "$KEY" ] || fail "curl was not given the key on stdin"
}

# A card with no labels, parent, description, comments or sub-issues still
# shows each part, so a reader can tell it has none.
linear_read_says_what_a_card_has_none_of() {
  saved_key; stub_linear
  linear_answers "$(read_answer '.labels.nodes = [] | .parent = null | .description = null | .comments.nodes = [] | .children.nodes = []')"
  out=$("$E" linear read ABC-122) || fail "linear read exited non-zero: $out"
  want='ABC-122  Export orders as CSV
Status: In Progress
Labels: none
URL:    https://linear.app/x/issue/ABC-122/export-orders-as-csv

No description.

Comments (0)

Sub-issues (0)'
  [ "$out" = "$want" ] || fail "printed: $out"
}

# The card is anyone's text. A newline in a title must not forge a line, and
# an escape sequence must not reach the terminal, so a control character
# becomes a space, as in task ls. The description's and the comments' own line
# breaks are kept, without the \r Linear may end a line with.
linear_read_keeps_control_characters_out_of_the_text() {
  saved_key; stub_linear
  linear_answers "$(read_answer '.title = "Real\nStatus: Done"
    | .description = "One \u001b[31mred\u0007 line\r\nTwo\r\n"
    | .comments.nodes = [{body: "Bell\u0007rings\nSecond line", createdAt: "2024-03-01T09:30:00.000Z", user: {name: "Ada\nLovelace"}, botActor: null}]
    | .children.nodes = [{identifier: "ABC-123", title: "Slice\u009bone", state: {name: "To\tdo", type: "unstarted"}}]')"
  out=$("$E" linear read ABC-122) || fail "linear read exited non-zero: $out"
  want='ABC-122  Real Status: Done
Status: In Progress
Labels: feat, urgent
Parent: ABC-100  Orders
URL:    https://linear.app/x/issue/ABC-122/export-orders-as-csv

One  [31mred  line
Two

Comments (1)
  Ada Lovelace, 2024-03-01T09:30:00Z
    Bell rings
    Second line

Sub-issues (1)
  ABC-123  To do  Slice one'
  [ "$out" = "$want" ] || fail "printed: $(printf '%s' "$out" | od -c | head -n 30)"
}

# Linear gives so many comments, sub-issues or labels at a time. When it says
# there are more, printing what came would pass part of the card for the
# whole, so nothing is printed, and it says what there was more of.
linear_read_says_when_linear_has_more_than_it_read() {
  local more
  saved_key; stub_linear
  for more in comments children labels; do
    rm -f "$TMP/linear/"*.json
    linear_answers "$(read_answer ".$more.pageInfo.hasNextPage = true")"
    out=$("$E" linear read ABC-122 --json 2>"$TMP/err") && fail "exited zero with more $more in Linear"
    [ -z "$out" ] || fail "printed part of the card with more $more in Linear: $out"
    case $more in children) more=sub-issues ;; esac
    case $(cat "$TMP/err") in *"more than"*"$more"*) ;; *) fail "did not say Linear has more $more: $(cat "$TMP/err")" ;; esac
  done
  case $(sent_body 1 | jq -r '.query') in
    *'comments(first: 100)'*'children(first: 50)'*) ;;
    *) fail "did not ask for 100 comments and 50 sub-issues: $(sent_body 1 | jq -r '.query')" ;;
  esac
}

linear_read_refuses_a_card_linear_does_not_have() {
  saved_key; stub_linear; linear_answers "$NO_CARD"
  out=$("$E" linear read ABC-999 2>&1) && fail "exited zero for a card Linear does not have"
  case $out in *"Linear has no card ABC-999"*) ;; *) fail "did not say Linear has no such card: $out" ;; esac
}

# An answer with no card in a form entourage knows is not one it prints.
linear_read_refuses_an_answer_it_cannot_read() {
  saved_key; stub_linear
  for answer in '{"data":{"issues":null}}' "$(read_answer '.comments.nodes = null')" "$(read_answer '.state = null')"; do
    rm -f "$TMP/linear/"*.json
    linear_answers "$answer"
    out=$("$E" linear read ABC-122 2>"$TMP/err") && fail "exited zero on the answer: $answer"
    [ -z "$out" ] || fail "printed on the answer $answer: $out"
    grep -q 'not one entourage can read' "$TMP/err" || fail "did not say the answer cannot be read: $(cat "$TMP/err")"
  done
}

linear_read_refuses_what_is_not_a_read() {
  saved_key; stub_linear; linear_answers "$(read_answer)"
  "$E" linear read >/dev/null 2>&1 && fail "accepted no card"
  "$E" linear read ABC >/dev/null 2>&1 && fail "accepted 'ABC'"
  "$E" linear read ABC-122 --yaml >/dev/null 2>&1 && fail "accepted --yaml"
  "$E" linear read ABC-122 --json extra >/dev/null 2>&1 && fail "accepted a third word"
  [ "$(curl_count)" = 0 ] || fail "asked Linear before refusing: $(curl_calls)"
}

# --json is one line, for a mod. The whole document is compared, keys in
# order: a program reads it, and a key the contract does not have must not
# slip in. The text comes as Linear gave it.
linear_read_json_is_one_line_a_program_can_read() {
  local card
  saved_key; stub_linear
  linear_answers "$(read_answer '.title = "Export orders\nas CSV"')"
  out=$("$E" linear read ABC-122 --json) || fail "linear read --json exited non-zero: $out"
  [ "$(printf '%s\n' "$out" | grep -c '')" = 1 ] || fail "the JSON is not one line: $out"
  card=$(jq -cn --arg description "$READ_DESCRIPTION" '{
    id: "ABC-122", title: "Export orders\nas CSV",
    url: "https://linear.app/x/issue/ABC-122/export-orders-as-csv",
    status: {name: "In Progress", type: "started"}, type: "feat", labels: ["feat", "urgent"],
    parent: {id: "ABC-100", title: "Orders"}, description: $description,
    comments: [
      {author: "GitHub", createdAt: "2024-03-01T09:30:00.000Z", body: "Opened a pull request.\n\nhttps://github.com/x/y/pull/1"},
      {author: "Ada Lovelace", createdAt: "2024-03-02T10:00:00.000Z", body: "Approved."}],
    subIssues: [
      {id: "ABC-123", title: "Slice one", status: {name: "Todo", type: "unstarted"}},
      {id: "ABC-124", title: "Slice two", status: {name: "Backlog", type: "backlog"}}]}')
  [ "$out" = "$card" ] || fail "the JSON is: $out"
  [ "$(printf '%s' "$out" | jq -r '.description')" = "$READ_DESCRIPTION" ] ||
    fail "the description changed: $(printf '%s' "$out" | jq -r '.description')"
  [ "$(printf '%s' "$out" | jq -r '.title')" = "$(printf 'Export orders\nas CSV')" ] ||
    fail "the title changed: $(printf '%s' "$out" | jq -r '.title')"
}

# A card with no parent and no type gives null for each, and no description
# gives an empty one.
linear_read_json_gives_null_for_what_a_card_has_none_of() {
  saved_key; stub_linear
  linear_answers "$(read_answer '.labels.nodes = [{name: "urgent", parent: null}] | .parent = null | .description = null')"
  out=$("$E" linear read ABC-122 --json) || fail "linear read --json exited non-zero: $out"
  [ "$(printf '%s' "$out" | jq -c '[.type, .parent, .description, .labels]')" = '[null,null,"",["urgent"]]' ] ||
    fail "the JSON is: $out"
}

# The skills fall back to the Linear tools on the words these two say.
linear_read_without_a_key_says_how_to_save_one() {
  stub_linear; linear_answers "$(read_answer)"
  out=$("$E" linear read ABC-122 --json 2>"$TMP/err") && fail "exited zero with no key saved"
  [ -z "$out" ] || fail "printed on stdout: $out"
  case $(cat "$TMP/err") in *"no Linear key is saved"*"entourage linear key"*) ;; *) fail "did not say how to save a key: $(cat "$TMP/err")" ;; esac
  [ "$(curl_count)" = 0 ] || fail "asked Linear with no key: $(curl_calls)"
}

linear_read_with_a_rejected_key_says_so() {
  saved_key; stub_linear; linear_answers "$REJECTED"; linear_status 401
  out=$("$E" linear read ABC-122 2>&1) && fail "exited zero with a rejected key"
  case $out in *"Linear rejected the key"*) ;; *) fail "did not say Linear rejected the key: $out" ;; esac
  case $out in *"$KEY"*) fail "printed the key: $out" ;; esac
}

READ_CASES="linear_read_prints_the_card_laid_out linear_read_says_what_a_card_has_none_of
  linear_read_keeps_control_characters_out_of_the_text linear_read_says_when_linear_has_more_than_it_read
  linear_read_refuses_a_card_linear_does_not_have linear_read_refuses_an_answer_it_cannot_read
  linear_read_refuses_what_is_not_a_read
  linear_read_json_is_one_line_a_program_can_read linear_read_json_gives_null_for_what_a_card_has_none_of
  linear_read_without_a_key_says_how_to_save_one linear_read_with_a_rejected_key_says_so"

# --- moving a card: linear move ---------------------------------------------

# A team with one started status, which is both its first and its last.
ONE_STARTED='[{"id":"w-todo","name":"Todo","type":"unstarted","position":1},
  {"id":"w-doing","name":"Doing","type":"started","position":2},
  {"id":"w-done","name":"Done","type":"completed","position":3}]'

# review is the team's last started status by its place, not the last that
# Linear lists: Lab's statuses list In Review first.
linear_move_moves_a_card_to_review() {
  saved_key; stub_linear
  linear_answers "$(move_answer ABC-122 'In Progress')" "$(moved_answer 'In Review')"
  out=$("$E" linear move abc-122 review) || fail "linear move exited non-zero: $out"
  [ "$(curl_count)" = 2 ] || fail "asked Linear $(curl_count) times, not 2: $(curl_calls)"
  case $(changes_sent) in
    *'"id":"id-ABC-122"'*'"stateId":"s-review"'*) ;;
    *) fail "did not move the card to In Review: $(changes_sent)" ;;
  esac
  [ "$out" = 'ABC-122 moved to In Review in Linear (it was In Progress)' ] || fail "did not say the card moved: $out"
}

# The same in a team of other names, whose last started status is Checking.
linear_move_moves_a_card_to_review_in_a_team_of_other_names() {
  saved_key; stub_linear
  linear_answers "$(move_answer ABC-122 Doing "$OTHER_STATUSES")" "$(moved_answer Checking "$OTHER_STATUSES")"
  out=$("$E" linear move ABC-122 review) || fail "linear move exited non-zero: $out"
  case $(changes_sent) in *'"stateId":"o-checking"'*) ;; *) fail "did not move the card to Checking: $(changes_sent)" ;; esac
  case $out in *"ABC-122 moved to Checking in Linear (it was Doing)"*) ;; *) fail "did not say the card moved: $out" ;; esac
}

# A team with three started statuses, listed out of their order: the last by
# place, Shipping, is neither the first nor the last that Linear lists.
THREE_STARTED='[{"id":"t-doing","name":"Doing","type":"started","position":20},
  {"id":"t-shipping","name":"Shipping","type":"started","position":40},
  {"id":"t-checking","name":"Checking","type":"started","position":30},
  {"id":"t-todo","name":"Todo","type":"unstarted","position":10},
  {"id":"t-done","name":"Done","type":"completed","position":50}]'

# review is picked by place, whatever order Linear lists the statuses in.
linear_move_takes_the_last_started_status_by_place() {
  saved_key; stub_linear
  linear_answers "$(move_answer ABC-122 Doing "$THREE_STARTED")" "$(moved_answer Shipping "$THREE_STARTED")"
  out=$("$E" linear move ABC-122 review) || fail "linear move exited non-zero: $out"
  case $(changes_sent) in
    *'"stateId":"t-shipping"'*) ;;
    *) fail "did not move the card to Shipping, the last started status by place: $(changes_sent)" ;;
  esac
  [ "$out" = 'ABC-122 moved to Shipping in Linear (it was Doing)' ] || fail "did not say the card moved: $out"
}

# In a team with one started status, review is that status, so a card in it
# already stays there, and the command has done all it is asked.
linear_move_leaves_a_card_in_a_teams_only_started_status() {
  saved_key; stub_linear
  linear_answers "$(move_answer ABC-122 Doing "$ONE_STARTED")"
  out=$("$E" linear move ABC-122 review 2>&1) || fail "linear move exited non-zero: $out"
  [ "$(curl_count)" = 1 ] || fail "asked Linear $(curl_count) times, not 1: $(curl_calls)"
  [ -z "$(changes_sent)" ] || fail "asked Linear to change the card: $(changes_sent)"
  [ "$out" = 'ABC-122 is in Doing already' ] || fail "did not say the card is there already: $out"
}

# started and done are the moves task start and the merge make.
linear_move_takes_started_and_done() {
  saved_key; stub_linear
  linear_answers "$(move_answer ABC-122 Todo)" "$(moved_answer 'In Progress')" \
    "$(move_answer ABC-122 'In Review')" "$(moved_answer Done)"
  out=$("$E" linear move ABC-122 started) || fail "linear move started exited non-zero: $out"
  case $out in *"moved to In Progress"*) ;; *) fail "did not move the card to In Progress: $out" ;; esac
  out=$("$E" linear move ABC-122 done) || fail "linear move done exited non-zero: $out"
  case $out in *"moved to Done"*) ;; *) fail "did not move the card to Done: $out" ;; esac
  case $(changes_sent | tr '\n' ' ') in
    *'"stateId":"s-progress"'*'"stateId":"s-done"'*) ;;
    *) fail "did not send In Progress, then Done: $(changes_sent)" ;;
  esac
  # Only the approval moves a card's sub-issues, so these never ask for them.
  ! curl_calls | grep -qF children || fail "asked Linear for the card's sub-issues: $(curl_calls)"
}

# approved is the move the approval makes: the card to its team's first
# not-started status (Todo in Lab), then each of its sub-issues the same way.
linear_move_moves_an_approved_card_and_its_slices() {
  saved_key; stub_linear
  linear_answers "$(move_answer ABC-122 Backlog '' "[$(move_card ABC-123 Backlog),$(move_card ABC-124 'In Progress')]")" \
    "$(moved_answer Todo)"
  out=$("$E" linear move ABC-122 approved) || fail "linear move approved exited non-zero: $out"
  [ "$(curl_count)" = 3 ] || fail "asked Linear $(curl_count) times, not 3: $(curl_calls)"
  case $(changes_sent | tr '\n' ' ') in
    *'"id":"id-ABC-122"'*'"stateId":"s-todo"'*'"id":"id-ABC-123"'*'"stateId":"s-todo"'*) ;;
    *) fail "did not move the card, then its sub-issue in Backlog, to Todo: $(changes_sent)" ;;
  esac
  [ "$out" = 'ABC-122 moved to Todo in Linear (it was Backlog)
ABC-123 moved to Todo in Linear (it was Backlog)
ABC-124 stays in In Progress, which is past Todo: a card only moves forward' ] || fail "did not say what happened to each card: $out"
}

# The same in a team like PHY's: from Triage to Ready for Dev.
linear_move_moves_an_approved_card_to_ready_for_dev() {
  saved_key; stub_linear
  linear_answers "$(move_answer ABC-122 Triage "$PHY_STATUSES")" "$(moved_answer 'Ready for Dev' "$PHY_STATUSES")"
  out=$("$E" linear move ABC-122 approved) || fail "linear move approved exited non-zero: $out"
  case $(changes_sent) in *'"stateId":"p-ready"'*) ;; *) fail "did not move the card to Ready for Dev: $(changes_sent)" ;; esac
  [ "$out" = 'ABC-122 moved to Ready for Dev in Linear (it was Triage)' ] || fail "did not say the card moved: $out"
}

# A sub-issue that cannot be moved fails the command, which still says what
# happened to each card, and still moves the ones it can.
linear_move_fails_when_a_slice_cannot_be_moved() {
  saved_key; stub_linear
  linear_answers "$(move_answer ABC-122 Backlog '' "[$(move_card ABC-123 Backlog)]")" "$(moved_answer Todo)" "$NO_WRITE"
  linear_status_at 3 400
  out=$("$E" linear move ABC-122 approved 2>"$TMP/err") && fail "exited zero when a sub-issue was not moved"
  [ "$out" = 'ABC-122 moved to Todo in Linear (it was Backlog)' ] || fail "did not say the card moved: $out"
  [ "$(cat "$TMP/err")" = 'entourage: ABC-123 was not moved in Linear: Linear answered with an error: Invalid scope: `write` required' ] ||
    fail "did not say the sub-issue was not moved, and why: $(cat "$TMP/err")"
}

# The rules of a move hold for review too: a card that is done or canceled
# is never moved.
linear_move_never_moves_a_closed_card() {
  saved_key; stub_linear
  linear_answers "$(move_answer ABC-122 Done)"
  out=$("$E" linear move ABC-122 review 2>&1) || fail "linear move exited non-zero: $out"
  [ -z "$(changes_sent)" ] || fail "asked Linear to change the card: $(changes_sent)"
  case $out in *"ABC-122 stays in Done, which is closed"*) ;; *) fail "did not say why the card stays: $out" ;; esac
}

# The move is the command's whole work, so a move that fails exits non-zero,
# saying that the card was not moved and why.
linear_move_fails_when_linear_is_out_of_reach() {
  saved_key; stub_linear
  echo 6 > "$TMP/linear/exit"
  out=$("$E" linear move ABC-122 review 2>&1) && fail "exited zero when Linear was out of reach: $out"
  case $out in
    *"ABC-122 was not moved in Linear: could not reach Linear (curl: (6) Could not resolve host: api.linear.app)"*) ;;
    *) fail "did not say the card was not moved, and why: $out" ;;
  esac
}

linear_move_fails_when_linear_refuses_the_change() {
  saved_key; stub_linear
  linear_answers "$(move_answer ABC-122 'In Progress')" "$NO_WRITE"
  linear_status_at 2 400
  out=$("$E" linear move ABC-122 review 2>&1) && fail "exited zero when Linear refused the move: $out"
  case $out in
    *'ABC-122 was not moved in Linear: Linear answered with an error: Invalid scope: `write` required'*) ;;
    *) fail "did not say the card was not moved, and why: $out" ;;
  esac
}

linear_move_refuses_what_is_not_a_move() {
  saved_key; stub_linear
  out=$("$E" linear move ABC-122 todo 2>&1) && fail "accepted the move 'todo'"
  case $out in *approved*started*review*done*) ;; *) fail "did not name the moves there are: $out" ;; esac
  "$E" linear move ABC-122 >/dev/null 2>&1 && fail "accepted no move"
  "$E" linear move >/dev/null 2>&1 && fail "accepted no card"
  out=$("$E" linear move ABC review 2>&1) && fail "accepted the card 'ABC'"
  case $out in *"not a card ID"*) ;; *) fail "did not say ABC is not a card ID: $out" ;; esac
  [ "$(curl_count)" = 0 ] || fail "asked Linear about a move that is not one: $(curl_calls)"
}

MOVE_CASES="linear_move_moves_a_card_to_review linear_move_moves_a_card_to_review_in_a_team_of_other_names
  linear_move_takes_the_last_started_status_by_place
  linear_move_leaves_a_card_in_a_teams_only_started_status linear_move_takes_started_and_done
  linear_move_moves_an_approved_card_and_its_slices linear_move_moves_an_approved_card_to_ready_for_dev
  linear_move_fails_when_a_slice_cannot_be_moved
  linear_move_never_moves_a_closed_card linear_move_fails_when_linear_is_out_of_reach
  linear_move_fails_when_linear_refuses_the_change linear_move_refuses_what_is_not_a_move"

REVIEW_CASES="linear_section_refuses_a_body_with_its_own_heading linear_section_replace_refuses_a_card_without_the_section
  linear_section_refuses_a_second_breakdown linear_section_fails_when_linear_has_the_section_twice
  linear_section_replaces_a_section_folded_with_the_other_mark linear_section_replaces_an_open_breakdown_with_a_section_below
  linear_section_replaces_a_breakdown_with_a_top_heading_below linear_section_refuses_to_replace_a_fold_that_is_never_closed
  linear_section_skips_a_heading_in_a_code_block linear_section_reads_a_description_with_cr_line_ends
  linear_section_takes_a_description_with_crlf_line_ends linear_section_says_when_jq_is_missing
  linear_type_prefers_the_teams_label_to_the_workspaces linear_type_asks_only_for_the_teams_and_the_workspaces_labels
  linear_type_takes_off_every_other_type linear_type_fails_when_linear_drops_another_label"

WRITE_CASES="$REVIEW_CASES linear_type_sets_the_type_and_keeps_the_other_labels linear_type_takes_a_workspace_label
  linear_type_leaves_a_card_that_has_the_type_already linear_type_refuses_a_team_without_the_label
  linear_type_refuses_a_type_that_is_not_one linear_type_refuses_a_card_linear_does_not_have
  linear_type_fails_when_linear_keeps_another_type
  linear_section_adds_a_collapsed_section_below_the_description linear_section_writes_the_breakdown_open
  linear_section_writes_into_an_empty_description linear_section_refuses_a_second_section_of_the_same_name
  linear_section_replaces_a_section_in_place linear_section_replaces_the_open_breakdown
  linear_section_fails_when_the_text_above_changed linear_section_accepts_linears_rewriting_of_the_section
  linear_section_refuses_what_is_not_a_section"

# --- status and the key -----------------------------------------------------

# A machine with everything linked, so that only the key can make status exit
# non-zero, and a stand-in for curl, so that a case that saves a key never
# reaches the real Linear.
status_machine() {
  "$E" install >/dev/null || fail "install exited non-zero"
  stub_linear
}

# status's line about the key: the one after its "Linear key:" heading.
key_line() { printf '%s\n' "$1" | sed -n '/^Linear key: /{n;p;}'; }

status_notes_when_no_key_is_saved() {
  status_machine
  out=$("$E" status 2>&1) || fail "status exited non-zero with no key saved: $out"
  case $(key_line "$out") in
    '  note       no Linear key is saved'*) ;;
    *) fail "did not note that no key is saved: $out" ;;
  esac
  for want in 'task ls' 'the Cards panel' 'task start' 'entourage linear key'; do
    case $(key_line "$out") in *"$want"*) ;; *) fail "the note does not name $want: $(key_line "$out")" ;; esac
  done
  case $out in *"Linear key: $(env_file)"*) ;; *) fail "did not say where the key is saved: $out" ;; esac
  case $out in *"Everything is in order."*) ;; *) fail "did not say everything is in order: $out" ;; esac
  [ "$(curl_count)" = 0 ] || fail "asked Linear with no key: $(curl_calls)"
}

# Linear's answer to a key it does not know, with the key echoed in its
# message, at HTTP 400.
REJECTED_WITH_KEY="{\"errors\":[{\"message\":\"Authentication failed for $KEY\",\"extensions\":{\"type\":\"authentication error\",\"userError\":true}}]}"

# A 401, and Linear's own word for a key it does not know.
status_says_a_rejected_key_is_a_problem() {
  status_machine; saved_key
  linear_answers "$REJECTED"; linear_status 401
  out=$("$E" status 2>&1) && fail "status exited zero for a 401: $out"
  case $(key_line "$out") in
    '  problem    Linear rejected the key. Make a new one in '*', then save it with: entourage linear key') ;;
    *) fail "did not list the rejected key as a problem: $out" ;;
  esac
  case $out in *"$KEY"*) fail "printed the key: $out" ;; esac
  case $out in *"Everything is in order."*) fail "said everything is in order: $out" ;; esac
  rm -f "$TMP/linear/status"
  linear_answers "$REJECTED_WITH_KEY"; linear_status 400
  out=$("$E" status 2>&1) && fail "status exited zero for Linear's authentication error: $out"
  case $(key_line "$out") in
    '  problem    Linear rejected the key.'*'entourage linear key') ;;
    *) fail "did not list the rejected key as a problem: $out" ;;
  esac
  case $out in *"$KEY"*) fail "printed the key Linear's error held: $out" ;; esac
  case $(curl_calls) in *"$KEY"*) fail "passed the key to curl as an argument: $(curl_calls)" ;; esac
}

status_says_a_key_that_is_not_a_key_is_a_problem() {
  status_machine
  out=$(LINEAR_API_KEY='two words' "$E" status 2>&1) && fail "status exited zero for a key that is not one: $out"
  case $(key_line "$out") in
    '  problem    LINEAR_API_KEY does not hold a Linear API key.'*'entourage linear key') ;;
    *) fail "did not list the key as a problem: $out" ;;
  esac
  case $out in *"Linear key: LINEAR_API_KEY, exported in your environment"*) ;; *) fail "did not say the key is exported: $out" ;; esac
  case $out in *'two words'*) fail "printed the key: $out" ;; esac
  [ "$(curl_count)" = 0 ] || fail "asked Linear about something that is not a key: $(curl_calls)"
}

status_says_the_key_works() {
  status_machine; saved_key
  linear_answers "$VIEWER"
  out=$("$E" status 2>&1) || fail "status exited non-zero for a key that works: $out"
  [ "$(key_line "$out")" = '  works      the key of Ada Lovelace' ] || fail "did not say the key works: $out"
  case $out in *"Everything is in order."*) ;; *) fail "did not say everything is in order: $out" ;; esac
  case $out in *"$KEY"*) fail "printed the key: $out" ;; esac
  [ "$(key_given_to_curl)" = "$KEY" ] || fail "curl was not given the key on stdin: $(cat "$TMP/curl-stdin.log" 2>&1)"
  case $(curl_calls) in *viewer*) ;; *) fail "did not ask Linear whose the key is: $(curl_calls)" ;; esac
}

# A key exported in the shell wins over the file, so it is the one checked.
status_checks_the_exported_key_over_the_env_file() {
  status_machine; saved_key lin_api_FromTheFile
  linear_answers "$VIEWER"
  out=$(LINEAR_API_KEY=$KEY "$E" status 2>&1) || fail "status exited non-zero: $out"
  [ "$(key_given_to_curl)" = "$KEY" ] || fail "curl was given another key: $(key_given_to_curl)"
  case $out in *"Linear key: LINEAR_API_KEY, exported in your environment"*) ;; *) fail "did not say the key is exported: $out" ;; esac
  case $out in *"$KEY"* | *lin_api_FromTheFile*) fail "printed a key: $out" ;; esac
}

# A name is anyone's text: an escape sequence in it must not reach the
# terminal, nor a newline forge a line.
status_shows_the_owners_name_as_plain_text() {
  status_machine; saved_key
  linear_answers '{"data":{"viewer":{"id":"u-1","name":"Ada \u001b[31mLovelace\u0007\n  problem    forged"}}}'
  out=$("$E" status 2>&1) || fail "status exited non-zero: $out"
  [ "$(key_line "$out")" = '  works      the key of Ada  [31mLovelace    problem    forged' ] ||
    fail "the name was not made plain: $(key_line "$out" | od -c | head -n 10)"
  case $out in *$'\e'* | *$'\a'*) fail "printed a control character: $(printf '%s' "$out" | od -c | head -n 20)" ;; esac
}

# None of these says anything of the key, so none calls it bad or counts
# against status. $1 is what the note has to say the key was not checked for.
status_key_not_checked() {
  out=$("$E" status 2>&1) || fail "status exited non-zero when the key could not be checked ($1): $out"
  case $(key_line "$out") in
    "  note       the key was not checked: "*"$1"*) ;;
    *) fail "did not note that the key was not checked ($1): $out" ;;
  esac
  case $out in *rejected* | *"new one"*) fail "blamed the key ($1): $out" ;; esac
  case $out in *"$KEY"*) fail "printed the key ($1): $out" ;; esac
  case $out in *"Everything is in order."*) ;; *) fail "did not say everything is in order ($1): $out" ;; esac
}

status_notes_when_the_key_cannot_be_checked() {
  status_machine; saved_key
  # Linear out of reach.
  echo 6 > "$TMP/linear/exit"
  status_key_not_checked 'could not reach Linear (curl: (6) Could not resolve host: api.linear.app)'
  rm "$TMP/linear/exit"
  # A proxy's page in Linear's place.
  linear_answers '<html><body>502 Bad Gateway</body></html>'; linear_status 502
  status_key_not_checked 'something between this machine and Linear answered for it, with HTTP status 502'
  rm "$TMP/linear/status"
  # An answer that names nobody did not come from Linear.
  linear_answers '{"data":{"viewer":null}}'
  status_key_not_checked "Linear's answer did not say whose key it is"
  # No jq. Only the key needs it once the settings file is gone.
  rm "$HOME/.config/entourage/settings.json"
  hide_jq
  status_key_not_checked 'jq is not installed'
  # No curl.
  hide_curl
  status_key_not_checked 'curl is not installed'
}

STATUS_KEY_CASES="status_notes_when_no_key_is_saved status_says_a_rejected_key_is_a_problem
  status_says_a_key_that_is_not_a_key_is_a_problem status_says_the_key_works
  status_checks_the_exported_key_over_the_env_file status_shows_the_owners_name_as_plain_text
  status_notes_when_the_key_cannot_be_checked"

# The same for anything there that is not a file, such as a folder: skipping
# it would hide that the settings are not where entourage reads them.
env_file_that_is_not_a_file_says_so() {
  mkdir -p "$(env_file)"
  out=$("$E" help 2>&1) && fail "exited zero with a folder where the env file should be"
  case $out in *"$(env_file) is not a file"*) ;; *) fail "did not say the env file is not a file: $out" ;; esac
}

CASES="$CARD_LOOKUP_CASES $WRITE_CASES $READ_CASES $MOVE_CASES $STATUS_KEY_CASES
  linear_key_saves_the_key linear_key_keeps_the_env_file_private linear_key_closes_an_env_file_others_could_read
  linear_key_says_whose_key_it_is linear_key_never_shows_the_key linear_key_gives_curl_the_key_on_stdin
  linear_key_replaces_the_old_key_and_keeps_the_other_lines linear_key_says_when_an_exported_key_is_used_instead
  task_ls_takes_the_key_from_the_environment task_ls_prefers_an_exported_key_to_the_env_file
  env_file_takes_quotes_spaces_and_export env_file_is_never_run
  env_file_keeps_its_lines_from_the_programs_entourage_starts env_file_cannot_move_entourages_folder
  env_file_takes_the_last_line_for_a_name env_file_lines_never_beat_an_exported_key
  env_file_is_used_when_the_exported_key_is_empty env_file_takes_comments_spaces_around_equals_and_a_bom
  env_file_drops_a_comment_from_a_path env_file_value_that_is_only_a_comment_is_empty
  env_file_that_cannot_be_read_says_so env_file_that_is_not_a_file_says_so
  linear_key_refuses_an_answer_that_names_no_user linear_key_leaves_a_linked_env_file_alone
  linear_key_keeps_the_other_lines_of_a_file_grep_calls_binary linear_key_says_when_the_env_file_cannot_be_written
  linear_key_replaces_a_key_line_written_with_spaces linear_key_replaces_a_key_line_that_starts_with_a_bom
  linear_key_keeps_the_key_out_of_a_git_repo linear_key_keeps_the_key_out_of_a_git_repo_it_would_make_its_folder_in
  linear_key_writes_nothing_into_a_folder_where_the_env_file_should_be
  linear_key_refuses_an_answer_that_names_no_user_with_an_old_jq
  task_ls_never_shows_the_key_in_what_linear_said task_ls_knows_a_rejected_key_by_its_status
  task_ls_takes_linears_own_403_as_a_rejected_key task_ls_does_not_blame_the_key_for_a_page_from_the_network
  task_ls_does_not_blame_the_key_for_an_empty_403_with_an_old_jq
  task_ls_asks_for_cards_in_an_order_an_edit_cannot_change task_ls_lists_the_most_recently_changed_card_first
  task_ls_keeps_statuses_of_one_name_and_two_types_apart
  task_ls_keeps_curl_from_reading_the_humans_curlrc task_ls_never_lists_a_closed_status
  task_ls_lists_a_card_in_a_status_the_first_page_did_not_name task_ls_fails_when_linear_has_more_cards_and_no_cursor
  task_ls_lists_a_card_on_two_pages_once task_ls_reads_a_hand_edited_teams_file
  task_ls_names_the_line_of_a_bad_team_key task_ls_keeps_control_characters_out_of_the_list
  linear_key_refuses_a_key_linear_rejects linear_key_keeps_the_old_key_when_the_new_one_is_rejected
  linear_key_saves_nothing_when_linear_is_out_of_reach linear_key_refuses_what_is_not_a_key
  linear_key_says_when_jq_is_missing linear_key_says_when_curl_is_missing
  task_ls_lists_cards_under_their_status task_ls_json_is_one_line_a_program_can_read
  task_ls_asks_only_for_open_cards task_ls_asks_for_every_team_of_the_project
  task_ls_puts_a_status_two_teams_share_in_one_group task_ls_fetches_every_page
  task_ls_without_a_key_says_how_to_save_one task_ls_with_a_rejected_key_says_so
  task_ls_knows_a_rejected_key_by_its_error task_ls_when_linear_is_out_of_reach_says_so
  task_ls_without_a_team_says_how_to_set_it task_ls_names_a_team_linear_does_not_have
  task_ls_says_what_linear_said_was_wrong task_ls_json_prints_nothing_when_it_fails
  task_ls_says_when_curl_is_missing task_ls_unknown_project task_ls_refuses_an_unknown_option"
