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
    {"identifier":"ABC-3","title":"Third card","url":"https://linear.app/x/issue/ABC-3/third-card","state":{"name":"In Review","type":"started"}},
    {"identifier":"ABC-1","title":"First card","url":"https://linear.app/x/issue/ABC-1/first-card","state":{"name":"Backlog","type":"backlog"}},
    {"identifier":"ABC-2","title":"Second \"quoted\" card","url":"https://linear.app/x/issue/ABC-2/second-card","state":{"name":"In Progress","type":"started"}}],
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
# asked: once, with the key on stdin as for every question.
task_start_asks_linear_for_the_card_by_team_and_number() {
  card_asked "$(card_answer ABC-122 'Export orders' feat)"
  "$E" task start demo abc-122 >/dev/null || fail "task start exited non-zero"
  case $(curl_calls) in *'"team":"ABC"'*) ;; *) fail "did not ask for team ABC: $(curl_calls)" ;; esac
  case $(curl_calls) in *'"number":122'*) ;; *) fail "did not ask for number 122: $(curl_calls)" ;; esac
  [ "$(key_given_to_curl)" = "$KEY" ] || fail "curl was not given the key on stdin"
  case $(curl_calls) in *"$KEY"*) fail "passed the key to curl as an argument" ;; esac
  [ "$(curl_count)" = 1 ] || fail "asked Linear $(curl_count) times"
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

CASES="$CARD_LOOKUP_CASES
  linear_key_saves_the_key linear_key_keeps_the_env_file_private linear_key_closes_an_env_file_others_could_read
  linear_key_says_whose_key_it_is linear_key_never_shows_the_key linear_key_gives_curl_the_key_on_stdin
  linear_key_replaces_the_old_key_and_keeps_the_other_lines linear_key_says_when_an_exported_key_is_used_instead
  task_ls_takes_the_key_from_the_environment task_ls_prefers_an_exported_key_to_the_env_file
  env_file_takes_quotes_spaces_and_export env_file_is_never_run
  env_file_keeps_its_lines_from_the_programs_entourage_starts env_file_cannot_move_entourages_folder
  env_file_takes_the_last_line_for_a_name env_file_lines_never_beat_an_exported_key
  env_file_is_used_when_the_exported_key_is_empty env_file_takes_comments_spaces_around_equals_and_a_bom
  env_file_drops_a_comment_from_a_path env_file_value_that_is_only_a_comment_is_empty
  env_file_that_cannot_be_read_says_so
  linear_key_refuses_an_answer_that_names_no_user linear_key_leaves_a_linked_env_file_alone
  linear_key_keeps_the_other_lines_of_a_file_grep_calls_binary linear_key_says_when_the_env_file_cannot_be_written
  linear_key_replaces_a_key_line_written_with_spaces
  task_ls_never_shows_the_key_in_what_linear_said task_ls_knows_a_rejected_key_by_its_status
  task_ls_takes_linears_own_403_as_a_rejected_key task_ls_does_not_blame_the_key_for_a_page_from_the_network
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
