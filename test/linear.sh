# Tests for what entourage asks of Linear. Sourced by test/run.sh. No case
# reaches Linear: a stand-in curl answers from canned files (stub_linear, in
# helpers.sh).

# What Linear answers when asked who a key belongs to.
VIEWER='{"data":{"viewer":{"name":"Ada Lovelace"}}}'
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
  got=$(printf '%s' "$out" | jq -c '{project, teams, names: [.statuses[].name], types: [.statuses[].type], backlog: .statuses[1].cards}' 2>&1)
  want='{"project":"demo","teams":["ABC"],"names":["Triage","Backlog","Ready for Dev","In Progress","In Review"],"types":["triage","backlog","unstarted","started","started"],"backlog":[{"id":"ABC-1","title":"First card","url":"https://linear.app/x/issue/ABC-1/first-card"}]}'
  [ "$got" = "$want" ] || fail "the JSON holds: $got (all of it: $out)"
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

# Only entourage's own variables are taken from the file, so it cannot change
# how the programs entourage starts behave.
env_file_sets_only_entourages_variables() {
  listed_demo; linear_answers "$ONE_TEAM"
  cat > "$TMP/bin/curl" <<EOF
#!/usr/bin/env bash
cat > /dev/null
printf '%s' "\${NOT_ENTOURAGES:-unset}" > "$TMP/seen-by-curl"
cat "$TMP/linear/1.json"
printf '\n200'
EOF
  printf '%s\n' "LINEAR_API_KEY=$KEY" 'NOT_ENTOURAGES=leaked' > "$(env_file)"
  "$E" task ls demo >/dev/null 2>&1 || fail "task ls exited non-zero"
  [ "$(cat "$TMP/seen-by-curl" 2>&1)" = unset ] || fail "curl saw NOT_ENTOURAGES as: $(cat "$TMP/seen-by-curl" 2>&1)"
}

# ENTOURAGE_HOME says where the file is, so the file cannot move it.
env_file_cannot_move_entourages_folder() {
  mkdir -p "$HOME/.config/entourage"
  echo "ENTOURAGE_HOME=$TMP/elsewhere" > "$(env_file)"
  "$E" project new demo >/dev/null || fail "project new exited non-zero"
  [ -d "$P/demo" ] || fail "the project was not made in the usual folder"
  [ ! -e "$TMP/elsewhere" ] || fail "the env file moved entourage's folder"
}

CASES="linear_key_saves_the_key linear_key_keeps_the_env_file_private linear_key_closes_an_env_file_others_could_read
  linear_key_says_whose_key_it_is linear_key_never_shows_the_key linear_key_gives_curl_the_key_on_stdin
  linear_key_replaces_the_old_key_and_keeps_the_other_lines linear_key_says_when_an_exported_key_is_used_instead
  task_ls_takes_the_key_from_the_environment task_ls_prefers_an_exported_key_to_the_env_file
  env_file_takes_quotes_spaces_and_export env_file_is_never_run env_file_sets_only_entourages_variables
  env_file_cannot_move_entourages_folder
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
