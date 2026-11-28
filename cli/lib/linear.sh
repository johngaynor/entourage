# Linear: the one place entourage talks to Linear. Sourced by cli/entourage.

# Cards live in Linear. An agent reaches them through its own Linear tools.
# entourage reaches them here, with a Linear API key the human saves once, so
# that listing cards needs no agent and a Linear step goes the same way on
# every run.
#
# Linear is asked through its GraphQL API with curl, and its answers are read
# with jq. The rest of entourage needs neither, so a command here says which
# one is missing.

LINEAR_URL=https://api.linear.app/graphql
# The key is one of entourage's variables, LINEAR_API_KEY. It comes from the
# environment, or from entourage's env file ($ENV_FILE), which cli/entourage
# has read by now and `linear key` writes.
#
# What a key is made of. Linear's are lin_api_ and then letters and digits. A
# key with a quote, a backslash or a space in it is not one, and could not be
# handed to curl as a line of its config.
KEY_RE='^[A-Za-z0-9_.-]+$'
# How many seconds to wait for Linear before giving up.
LINEAR_WAIT=20
# Where the human makes a key.
KEY_PLACE='Linear, under Settings, Account, Security & access, Personal API keys'

# Stop unless the two programs every Linear command needs are here.
linear_tools() {
  local tool
  for tool in curl jq; do
    command -v "$tool" >/dev/null 2>&1 ||
      die "$tool is not installed, and entourage needs it to ask Linear anything. Install it, then run this again."
  done
}

# Ask Linear one thing and print the data it answers with, as one line of JSON.
#   linear_ask <key> <query> [<the query's variables, as JSON>]
# The key goes to curl on stdin, as a line of its config: other programs on
# the machine can read a command's arguments, and cannot read its stdin. The
# ways this fails are told apart, because what the human does next differs:
# check the network, or replace the key.
linear_ask() {
  local key=$1 query=$2 vars=${3:-} body out code=0 status said
  [ -n "$vars" ] || vars='{}'
  body=$(jq -cn --arg q "$query" --argjson v "$vars" '{query: $q, variables: $v}') ||
    die "could not put a question to Linear together."
  # --disable has to be curl's first argument. It keeps a person's ~/.curlrc
  # from changing how Linear's answers are read, as -init /dev/null does for
  # sqlite3 in handoff.sh: a --fail or --include there would make a rejected
  # key look like the network, or a good answer unreadable. The key's own
  # --config - is still read.
  out=$(printf 'header = "Authorization: %s"\n' "$key" |
    curl --disable --silent --show-error --max-time "$LINEAR_WAIT" --config - \
      --header 'Content-Type: application/json' --data-binary "$body" \
      --write-out '\n%{http_code}' "$LINEAR_URL" 2>&1) || code=$?
  if [ "$code" -ne 0 ]; then
    said=$(printf '%s\n' "$out" | grep -m 1 '^curl: ') || said=
    die "could not reach Linear${said:+ ($said)}. Check the network, then run this again."
  fi
  # curl ends what it prints with the HTTP status, on a line of its own.
  status=${out##*$'\n'}
  out=${out%$'\n'*}
  # A key Linear does not know: a 401, or Linear's own word for it at any
  # status. A 403 counts only when it is Linear's own answer: a page from a
  # proxy or a firewall says nothing about the key, and a new key would not
  # get past it.
  if [ "$status" = 401 ] ||
    { [ "$status" = 403 ] && printf '%s' "$out" | jq -e 'type == "object" and has("errors")' >/dev/null 2>&1; } ||
    [ "$(printf '%s' "$out" | jq -r '[.errors[]?.extensions | ((.type // "") + " " + (.code // "")) | test("authentication"; "i")] | any' 2>/dev/null)" = true ]; then
    die "Linear rejected the key. Make a new one in $KEY_PLACE, then save it with: entourage linear key"
  fi
  said=$(printf '%s' "$out" | jq -r '.errors[0].message // empty' 2>/dev/null) || said=
  [ -z "$said" ] || die "Linear answered with an error: ${said//"$key"/<the key>}"
  # An answer that is not JSON did not come from Linear's API.
  [ "$status" = 200 ] || printf '%s' "$out" | jq -e . >/dev/null 2>&1 ||
    die "something between this machine and Linear answered for it, with HTTP status $status. Check the network, then run this again."
  [ "$status" = 200 ] || die "Linear answered with HTTP status $status and no result. Try again in a minute."
  printf '%s' "$out" | jq -ce '.data // empty' 2>/dev/null ||
    die "Linear's answer was not one entourage can read. Something between this machine and Linear may be answering for it."
}

# Print the key entourage has been given, or stop and say how to save one.
linear_saved_key() {
  local key=${LINEAR_API_KEY:-}
  [ -n "$key" ] ||
    die "no Linear key is saved, so entourage cannot read Linear. Make one in $KEY_PLACE, then save it with: entourage linear key"
  [[ $key =~ $KEY_RE ]] ||
    die "LINEAR_API_KEY does not hold a Linear API key. Check your environment and $ENV_FILE, or save a new key with: entourage linear key"
  printf '%s' "$key"
}

# The kinds of status an open card is in, as Linear names them, in the order
# Linear shows them. A card that is done, cancelled or a duplicate is in one
# of the other kinds, and is never asked for.
OPEN_TYPES='["triage","backlog","unstarted","started"]'
# How many cards to ask for at a time, and how many times to ask before
# deciding that Linear will never say it has no more.
LINEAR_PAGE=100
LINEAR_PAGES=50

# The teams Linear knows of those asked for, their open statuses, and one page
# of their open cards, most recently changed first.
LIST_QUERY='query($teams: [String!], $types: [String!], $first: Int, $after: String) {
  teams(filter: {key: {in: $teams}}) { nodes { key } }
  workflowStates(first: 250, filter: {team: {key: {in: $teams}}, type: {in: $types}}) {
    nodes { name type position team { key } }
  }
  issues(first: $first, after: $after, orderBy: updatedAt,
      filter: {team: {key: {in: $teams}}, state: {type: {in: $types}}}) {
    nodes { identifier title url state { name type position } }
    pageInfo { hasNextPage endCursor }
  }
}'

# Turn the pages Linear answered with (one line of JSON each, on stdin) into
# the list: every open status, in Linear's order, with its cards. Teams often
# share a status name; a status of one name and kind is one group, whichever
# teams have it. $project, $teams and $types are given by the caller.
#   - A card can come on two pages, when it moves while they are fetched. The
#     first copy is kept, in the order Linear gave them.
#   - The statuses are the ones the first page names, and any a card is in
#     that it did not, such as one made while the pages were fetched, so that
#     no card is dropped for want of a group.
#   - A closed status is never listed, should Linear send one.
LIST_SHAPE='
  ($types | to_entries | map({key: .value, value: .key}) | from_entries) as $rank
  | .[0] as $first
  | ([.[].issues.nodes[]] | to_entries | unique_by(.value.identifier) | sort_by(.key) | map(.value)) as $cards
  | {
      missing: ($teams - [$first.teams.nodes[].key]),
      project: $project,
      teams: $teams,
      statuses: [
        ($first.workflowStates.nodes + [$cards[].state])
        | map(select($rank[.type] != null))
        | group_by([.type, .name])
        | map({name: .[0].name, type: .[0].type, position: ((map(.position | numbers) | min) // 1000000)})
        | sort_by([$rank[.type], .position, .name])
        | .[]
        | . as $status
        | {
            name: $status.name,
            type: $status.type,
            cards: [
              $cards[]
              | select(.state.name == $status.name and .state.type == $status.type)
              | {id: .identifier, title: .title, url: .url}
            ]
          }
      ]
    }'

# Print the open cards of some Linear teams as one line of JSON, grouped by
# status:
#   {"project":"demo","teams":["ABC"],"statuses":[
#     {"name":"Backlog","type":"backlog","cards":[{"id":"ABC-1","title":"…","url":"…"}]}]}
# Every open status of the teams is there, with no cards when it has none.
#   linear_open_cards <project> <team key>...
linear_open_cards() {
  local project=$1 key teams vars data pages='' after='' more asked=0 list missing
  shift
  linear_tools
  key=$(linear_saved_key) || exit 1
  teams=$(printf '%s\n' "$@" | jq -Rcn '[inputs]')
  while :; do
    asked=$((asked + 1))
    [ "$asked" -le "$LINEAR_PAGES" ] ||
      die "Linear still had more cards after $LINEAR_PAGES pages of $LINEAR_PAGE, which is more than entourage lists."
    vars=$(jq -cn --argjson teams "$teams" --argjson types "$OPEN_TYPES" --argjson first "$LINEAR_PAGE" \
      --arg after "$after" \
      '{teams: $teams, types: $types, first: $first, after: (if $after == "" then null else $after end)}')
    data=$(linear_ask "$key" "$LIST_QUERY" "$vars") || exit 1
    pages+=$data$'\n'
    more=$(printf '%s' "$data" | jq -r '.issues.pageInfo.hasNextPage == true' 2>/dev/null) ||
      die "Linear's answer was not one entourage can read."
    [ "$more" = true ] || break
    # Listing what came so far would pass a part of the list for the whole.
    after=$(printf '%s' "$data" | jq -r '.issues.pageInfo.endCursor | strings' 2>/dev/null) || after=
    [ -n "$after" ] ||
      die "Linear said it had more cards but not where the next ones start, so the list would be cut short."
  done
  # The pages go to jq on stdin, not as an argument: a long list of cards is
  # more than a command's arguments may hold.
  list=$(printf '%s' "$pages" |
    jq -cs --arg project "$project" --argjson teams "$teams" --argjson types "$OPEN_TYPES" "$LIST_SHAPE" 2>/dev/null) ||
    die "Linear's answer was not one entourage can read."
  missing=$(printf '%s' "$list" | jq -r '.missing | join(", ")')
  [ -z "$missing" ] ||
    die "Linear has no team with the key $missing that the saved key can see. See the project's teams with: entourage project team $project"
  printf '%s' "$list" | jq -c 'del(.missing)'
}

# Find a card by its team's key and its number, as Linear keeps them: ABC-122
# is team ABC, number 122. Its title and labels come with it.
CARD_QUERY='query($team: String!, $number: Float!) {
  issues(first: 1, filter: {team: {key: {eq: $team}}, number: {eq: $number}}) {
    nodes { identifier title labels { nodes { name parent { name } } } }
  }
}'
# The label group a card's type is in. sdlc-define sets the type there.
TYPE_GROUP=Type

# Print one card as one line of JSON, or stop and say why:
#   {"id":"ABC-122","title":"Export orders as CSV","type":"feat"}
# type is null when the card has no label in the Type group.
#   linear_card <card ID, in upper case>
linear_card() {
  local card=$1 key vars data found
  linear_tools
  key=$(linear_saved_key) || exit 1
  vars=$(jq -cn --arg team "${card%-*}" --arg number "${card##*-}" \
    '{team: $team, number: ($number | tonumber)}' 2>/dev/null) ||
    die "'$card' is not a card ID like ABC-122."
  data=$(linear_ask "$key" "$CARD_QUERY" "$vars") || exit 1
  # An answer with no list of cards in it is not Linear saying it has none.
  found=$(printf '%s' "$data" | jq -c --arg group "$TYPE_GROUP" '
    if (.issues.nodes | type) != "array" then error("no list of cards")
    elif (.issues.nodes | length) == 0 then "none"
    else .issues.nodes[0]
      | {id: .identifier, title: (.title // ""),
         type: ([.labels.nodes[]? | select(.parent.name? == $group) | .name] | first)}
    end' 2>/dev/null) || found=
  case $found in
    '') die "Linear's answer was not one entourage can read. Something between this machine and Linear may be answering for it." ;;
    '"none"') die "Linear has no card $card that the saved key can see. Check the ID, then run this again." ;;
  esac
  printf '%s\n' "$found"
}

# Whether Linear has a card, for `task new` to check before it starts one. It
# asks the same question as linear_card, which `task start` uses, but it never
# stops: what it found is in how it returns.
#   linear_card_known <card ID, in upper case>
# It returns how that went, and prints nothing on stdout:
#   0  Linear has the card
#   1  Linear has no such card, that the saved key can see
#   2  no key is saved, so nothing was asked
#   3  Linear could not be asked; why is on stderr
# Only 1 is a no. The rest leave the card to start, so that a missing key,
# the network or a rejected key never keeps an agent from starting.
linear_card_known() {
  local card=$1 key=${LINEAR_API_KEY:-} tool vars data found
  [ -n "$key" ] || return 2
  for tool in curl jq; do
    command -v "$tool" >/dev/null 2>&1 || { printf '%s is not installed\n' "$tool" >&2; return 3; }
  done
  [[ $key =~ $KEY_RE ]] || { printf 'LINEAR_API_KEY does not hold a Linear API key\n' >&2; return 3; }
  vars=$(jq -cn --arg team "${card%-*}" --arg number "${card##*-}" \
    '{team: $team, number: ($number | tonumber)}' 2>/dev/null) ||
    { printf '%s is not a card ID\n' "$card" >&2; return 3; }
  # linear_ask stops with its own message, on stderr, when it cannot ask.
  data=$(linear_ask "$key" "$CARD_QUERY" "$vars") || return 3
  # Judged by what jq prints: some versions exit zero on an empty answer. Only
  # a real list counts: jq gives a missing one a length of 0 too, and that
  # must not read as Linear saying it has no such card.
  found=$(printf '%s' "$data" | jq -r '.issues.nodes | arrays | length' 2>/dev/null) || found=
  case $found in
    0) return 1 ;;
    '' | *[!0-9]*) printf "Linear's answer was not one entourage can read\n" >&2; return 3 ;;
    *) return 0 ;;
  esac
}

# Save the human's Linear API key as LINEAR_API_KEY in entourage's env file,
# once Linear has said whose it is. The key is asked for or read from stdin,
# never taken as an argument, so that it stays out of the shell's history.
linear_key() {
  # Every line the loader in cli/entourage would read as the key.
  local key='' data who tmp tty_was key_line='^[[:space:]]*(export[[:space:]]+)?LINEAR_API_KEY[[:space:]]*='
  [ "$#" -eq 0 ] ||
    die "usage: entourage linear key (it asks for the key, or reads it from stdin; the key is never an argument)"
  # A linked env file is often kept in a dotfiles repo. Replacing the link
  # would cut it loose, and writing through it would put the key in that
  # repo, so it is left alone, as trust.sh leaves a linked Claude Code file.
  # This comes before the key is asked for, so nobody pastes one for nothing.
  [ ! -L "$ENV_FILE" ] ||
    die "$ENV_FILE is a link, so entourage left it alone and saved no key. Add the line LINEAR_API_KEY=<your key> to the file it links to yourself, or put a plain file in its place and run this again."
  linear_tools
  if [ -t 0 ]; then
    printf 'Linear API key (it is not shown as you type or paste it): ' >&2
    # read -s turns the terminal's echo off, and Ctrl-C at the prompt would
    # leave it off. Put the terminal back as it was, then stop as Ctrl-C would
    # have, so that whatever ran this sees it end the same way.
    tty_was=$(stty -g 2>/dev/null) || tty_was=
    trap 'stty "$tty_was" 2>/dev/null || stty echo 2>/dev/null; printf "\n" >&2; trap - INT; kill -INT $$' INT
    IFS= read -rs key || true
    trap - INT
    printf '\n' >&2
  else
    IFS= read -r key || true
  fi
  # A pasted key often brings a space or a line ending with it.
  key=${key%$'\r'}
  key=${key#"${key%%[![:space:]]*}"}
  key=${key%"${key##*[![:space:]]}"}
  [ -n "$key" ] || die "no key was given. Make one in $KEY_PLACE, then run this again."
  [[ $key =~ $KEY_RE ]] ||
    die "that is not a Linear API key. A key is lin_api_ and then letters and digits. Make one in $KEY_PLACE."
  data=$(linear_ask "$key" 'query { viewer { id name } }') || die "the key was not saved."
  # Linear always says who a good key belongs to. An answer that names nobody
  # did not come from Linear, so it checked nothing.
  printf '%s' "$data" | jq -e '.viewer.id | strings' >/dev/null 2>&1 ||
    die "Linear's answer did not say whose key it is, so the key was not saved. Something between this machine and Linear may be answering for it."
  who=$(printf '%s' "$data" | jq -r '.viewer.name // empty' 2>/dev/null) || who=

  # The file is the human's too: every other line of it is kept, and the key
  # gets one line, in place of any it had. It is written beside itself and
  # moved into place whole, so a run cut short leaves the old file or the new
  # one, never half of one. It is made for its owner's eyes only.
  mkdir -p "$ENT_HOME"
  tmp=$ENV_FILE.entourage.$$
  # grep -a: a file with a NUL or another odd byte in it is still text here.
  # Without it grep calls the file binary and prints a note in place of its
  # lines. grep exits 1 when no line is left, which is fine; 2 is an error,
  # and must not leave a file with only the key in it.
  if (umask 077
      {
        if [ -f "$ENV_FILE" ]; then
          grep -a -v -E "$key_line" "$ENV_FILE"
          [ "$?" -le 1 ]
        fi &&
        printf 'LINEAR_API_KEY=%s\n' "$key"
      } > "$tmp") 2>/dev/null && mv -f "$tmp" "$ENV_FILE" 2>/dev/null; then
    chmod 600 "$ENV_FILE" 2>/dev/null || true
  else
    rm -f "$tmp" 2>/dev/null || true
    die "could not write $ENV_FILE, so the key was not saved."
  fi
  say "Saved the Linear key of ${who:-a user with no name} in $ENV_FILE"
  # A key exported in the shell wins over the file, so a different one there
  # would go on being used.
  if [ -n "$KEY_EXPORTED" ] && [ "${LINEAR_API_KEY:-}" != "$key" ]; then
    say "  note      LINEAR_API_KEY is also set in your environment, to another key. That one is used while it is set, not the one just saved."
  fi
}

cmd_linear() {
  case ${1:-} in
    key) shift; linear_key "$@" ;;
    *) die "usage: entourage linear key (see: entourage help)" ;;
  esac
}
