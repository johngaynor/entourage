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
  local key=$1 query=$2 vars=${3:-} body out code=0 status said rejected
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
  # A key Linear does not know: a 401, whatever comes with it.
  rejected="Linear rejected the key. Make a new one in $KEY_PLACE, then save it with: entourage linear key"
  [ "$status" != 401 ] || die "$rejected"
  # Linear's API always answers with JSON, so an empty answer did not come
  # from it. It is stopped here, before jq judges it: jq 1.6 exits zero for
  # -e when it is given no JSON at all, so the tests below would pass on it.
  case $out in
    *[![:space:]]*) ;;
    *) die "Linear's answer was empty, with HTTP status $status. Something between this machine and Linear may be answering for it: check the network, then run this again." ;;
  esac
  # Linear's own word for a key it does not know, at any status. A 403 counts
  # only when it is Linear's own answer: a page from a proxy or a firewall
  # says nothing about the key, and a new key would not get past it.
  if { [ "$status" = 403 ] && printf '%s' "$out" | jq -e 'type == "object" and has("errors")' >/dev/null 2>&1; } ||
    [ "$(printf '%s' "$out" | jq -r '[.errors[]?.extensions | ((.type // "") + " " + (.code // "")) | test("authentication"; "i")] | any' 2>/dev/null)" = true ]; then
    die "$rejected"
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
# of their open cards, with when each was last changed. Linear pages through
# the cards in the order it is asked for, each page starting where the last
# ended. That order is when each card was made, which nothing changes: in the
# order they were last changed, a card edited while the pages are fetched
# would move onto a page already fetched, and never be listed.
LIST_QUERY='query($teams: [String!], $types: [String!], $first: Int, $after: String) {
  teams(filter: {key: {in: $teams}}) { nodes { key } }
  workflowStates(first: 250, filter: {team: {key: {in: $teams}}, type: {in: $types}}) {
    nodes { name type position team { key } }
  }
  issues(first: $first, after: $after, orderBy: createdAt,
      filter: {team: {key: {in: $teams}}, state: {type: {in: $types}}}) {
    nodes { identifier title url updatedAt state { name type position } }
    pageInfo { hasNextPage endCursor }
  }
}'

# Turn the pages Linear answered with (one line of JSON each, on stdin) into
# the list: every open status, in Linear's order, with its cards. Teams often
# share a status name; a status of one name and kind is one group, whichever
# teams have it. $project, $teams and $types are given by the caller.
#   - Under each status the card changed last comes first. Cards changed at
#     the same moment keep the order Linear gave them in.
#   - Should a card come on two pages, the first copy is kept.
#   - The statuses are the ones the first page names, and any a card is in
#     that it did not, such as one made while the pages were fetched, so that
#     no card is dropped for want of a group.
#   - A closed status is never listed, should Linear send one.
LIST_SHAPE='
  ($types | to_entries | map({key: .value, value: .key}) | from_entries) as $rank
  | .[0] as $first
  | ([.[].issues.nodes[]] | to_entries | unique_by(.value.identifier)
      | sort_by([.value.updatedAt, -.key]) | reverse | map(.value)) as $cards
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
# Turn Linear's answer to CARD_QUERY into the card, {id, title, type}, or
# "none" when Linear has no such card. type is null when the card has no
# label in the Type group ($group). An answer with no list of cards in it is
# not Linear saying it has none, so it is an error.
CARD_SHAPE='
  if (.issues.nodes | type) != "array" then error("no list of cards")
  elif (.issues.nodes | length) == 0 then "none"
  else .issues.nodes[0]
    | {id: .identifier, title: (.title // ""),
       type: ([.labels.nodes[]? | select(.parent.name? == $group) | .name] | first)}
  end'

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
  found=$(printf '%s' "$data" | jq -c --arg group "$TYPE_GROUP" "$CARD_SHAPE" 2>/dev/null) || found=
  case $found in
    '') die "Linear's answer was not one entourage can read. Something between this machine and Linear may be answering for it." ;;
    '"none"') die "Linear has no card $card that the saved key can see. Check the ID, then run this again." ;;
  esac
  printf '%s\n' "$found"
}

# Whether Linear has a card, for `task new` to check before it starts one, and
# for `task start` when it is given the card's type and title. It asks the
# same question as linear_card, but it never stops: what it found is in how
# it returns.
#   linear_card_known <card ID, in upper case>
# It returns how that went:
#   0  Linear has the card, which it prints on stdout as linear_card does
#   1  Linear has no such card, that the saved key can see
#   2  no key is saved, so nothing was asked
#   3  Linear could not be asked; why is on stderr
# Only 1 is a no. The rest leave the card to start, so that a missing key,
# the network or a rejected key never keeps an agent from starting. Only 0
# prints anything on stdout.
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
  # a real list counts (CARD_SHAPE), and a missing one must not read as
  # Linear saying it has no such card.
  found=$(printf '%s' "$data" | jq -c --arg group "$TYPE_GROUP" "$CARD_SHAPE" 2>/dev/null) || found=
  case $found in
    '"none"') return 1 ;;
    '{'*) printf '%s\n' "$found" ;;
    *) printf "Linear's answer was not one entourage can read\n" >&2; return 3 ;;
  esac
}

# Print the top folder of the git repo a folder is in, through any links on
# the way, or fail when it is in none. A folder not made yet is looked for
# from the nearest folder above it that is, where mkdir -p would make it.
#   git_repo_around <folder>
git_repo_around() {
  local dir=$1
  while [ ! -d "$dir" ]; do dir=$(dirname "$dir"); done
  dir=$(cd -P "$dir" 2>/dev/null && pwd) || return 1
  while [ ! -e "$dir/.git" ]; do
    [ "$dir" != / ] || return 1
    dir=$(dirname "$dir")
  done
  printf '%s\n' "$dir"
}

# Save the human's Linear API key as LINEAR_API_KEY in entourage's env file,
# once Linear has said whose it is. The key is asked for or read from stdin,
# never taken as an argument, so that it stays out of the shell's history.
linear_key() {
  # Every line the loader in cli/entourage would read as the key, one that
  # starts with the mark some editors put at the start of a file included.
  local key='' data who tmp tty_was repo
  local key_line=$'^(\357\273\277)?[[:space:]]*(export[[:space:]]+)?LINEAR_API_KEY[[:space:]]*='
  [ "$#" -eq 0 ] ||
    die "usage: entourage linear key (it asks for the key, or reads it from stdin; the key is never an argument)"
  # A linked env file is often kept in a dotfiles repo. Replacing the link
  # would cut it loose, and writing through it would put the key in that
  # repo, so it is left alone, as trust.sh leaves a linked Claude Code file.
  # This comes before the key is asked for, so nobody pastes one for nothing.
  # (Anything else there that is not a file has stopped cli/entourage already.)
  [ ! -L "$ENV_FILE" ] ||
    die "$ENV_FILE is a link, so entourage left it alone and saved no key. Add the line LINEAR_API_KEY=<your key> to the file it links to yourself, or put a plain file in its place and run this again."
  # The same goes for a plain file in a git repo, where the key could be
  # committed and pushed. GNU Stow, for one, links a whole folder into a
  # dotfiles repo when it can, so entourage's folder may lead into one.
  if repo=$(git_repo_around "$ENT_HOME"); then
    die "$ENT_HOME is in the git repo at $repo, where a saved key could be committed and pushed, so entourage saved no key. Add the line LINEAR_API_KEY=<your key> to $ENV_FILE yourself if that repo ignores the file, or move $ENT_HOME out of the repo and run this again."
  fi
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
  # did not come from Linear, so it checked nothing. What jq prints decides,
  # not how it exits: jq 1.6 exits zero for -e when it is given no JSON.
  [ -n "$(printf '%s' "$data" | jq -r '.viewer.id | strings' 2>/dev/null)" ] ||
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
  # lines. LC_ALL=C: macOS grep in a UTF-8 locale does not match that mark
  # in such a file, so its key line would be kept. grep exits 1 when no line
  # is left, which is fine; 2 is an error, and must not leave a file with
  # only the key in it.
  if (umask 077
      {
        if [ -f "$ENV_FILE" ]; then
          LC_ALL=C grep -a -v -E "$key_line" "$ENV_FILE"
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

# --- reading a card ---------------------------------------------------------
#
# The card skills read a card here, so that the read goes the same way on
# every run, with the card's sections, comments and sub-issues. A mod reads
# it too, with --json.

# Linear's text as a line of a list or of a card: every control character
# becomes a space, so that a newline cannot start what looks like another line
# and an escape sequence cannot reach the terminal. No regex, so any jq does
# it. `task ls` uses it too.
PLAIN_DEF='def plain: explode | map(if . < 32 or (. > 126 and . < 160) then 32 else . end) | implode;'

# How many labels, comments and sub-issues a read asks Linear for. A card
# with more than that is not printed, since what was read would pass for the
# whole of it.
READ_LABELS=100
READ_COMMENTS=100
READ_SUBS=50

# The question for linear read: the card whole.
READ_QUERY='query($team: String!, $number: Float!) {
  issues(first: 1, filter: {team: {key: {eq: $team}}, number: {eq: $number}}) {
    nodes {
      identifier title url description
      state { name type }
      labels(first: '$READ_LABELS') { nodes { name parent { name } } pageInfo { hasNextPage } }
      parent { identifier title }
      comments(first: '$READ_COMMENTS') { nodes { body createdAt user { name } botActor { name } } pageInfo { hasNextPage } }
      children(first: '$READ_SUBS') { nodes { identifier title state { name type } } pageInfo { hasNextPage } }
    }
  }
}'

# From the answer to READ_QUERY, on stdin, print "none" when Linear has no
# such card, {"more": <what>} when it has more comments, sub-issues or labels
# than were asked for, or {"card": <the card>}, the card as linear read --json
# prints it. A comment's author is the app Linear credits with it, or else
# the user who wrote it. Comments come oldest first. An answer with a card in
# it that is not in this form did not come from Linear. $group is TYPE_GROUP.
READ_SHAPE='
  def text: if type == "string" then . else error("unreadable") end;
  def list: if (.nodes | type) == "array" then .nodes[] else error("unreadable") end;
  def status: if type == "object" then {name: (.name | text), type: (.type | text)} else error("unreadable") end;
  if (.issues.nodes | type) != "array" then error("no list of cards")
  elif (.issues.nodes | length) == 0 then "none"
  else .issues.nodes[0]
    | if .comments.pageInfo.hasNextPage? == true then {more: "comments"}
      elif .children.pageInfo.hasNextPage? == true then {more: "sub-issues"}
      elif .labels.pageInfo.hasNextPage? == true then {more: "labels"}
      else {card: {
        id: (.identifier | text),
        title: (.title | text),
        url: (.url // "" | text),
        status: (.state | status),
        type: ([.labels | list | select(.parent.name? == $group) | .name] | first),
        labels: [.labels | list | .name | text],
        parent: (if .parent == null then null else {id: (.parent.identifier | text), title: (.parent.title | text)} end),
        description: (.description // "" | text),
        comments: ([.comments | list
          | {author: (.botActor.name? // .user.name? // "unknown" | text),
             createdAt: (.createdAt | text), body: (.body // "" | text)}] | sort_by(.createdAt)),
        subIssues: [.children | list | {id: (.identifier | text), title: (.title | text), status: (.state | status)}]
      }}
      end
  end'

# The card from READ_SHAPE, on stdin, laid out like the card: its head, the
# description as written, the comments, each with its body indented under who
# wrote it and when, and the sub-issues. Every field is made plain, but the
# description and the comments keep their line breaks, without the \r Linear
# may end a line with, and lose only the blank lines at either end.
READ_TEXT=$PLAIN_DEF'
  def blank: explode | all(. == 32);
  def trim_blank: if length > 0 and (.[0] | blank) then .[1:] | trim_blank
    elif length > 0 and (.[-1] | blank) then .[:-1] | trim_blank else . end;
  def lines: split("\n") | map(rtrimstr("\r") | plain) | trim_blank;
  "\(.id | plain)  \(.title | plain)",
  "Status: \(.status.name | plain)",
  "Labels: \(if .labels == [] then "none" else .labels | map(plain) | join(", ") end)",
  (.parent // empty | "Parent: \(.id | plain)  \(.title | plain)"),
  "URL:    \(.url | plain)",
  "",
  ((.description | lines) as $lines | if $lines == [] then "No description." else $lines[] end),
  "",
  "Comments (\(.comments | length))",
  (.comments[]
    | "  \(.author | plain), \(.createdAt | sub("\\.[0-9]+Z$"; "Z") | plain)",
      (.body | lines[] | if blank then "" else "    " + . end)),
  "",
  "Sub-issues (\(.subIssues | length))",
  (.subIssues[] | "  \(.id | plain)  \(.status.name | plain)  \(.title | plain)")'

# Print a card whole, laid out like the card, or with --json as one line of
# JSON, for a mod:
#   {"id":"ABC-122","title":"…","url":"…","status":{"name":"In Progress","type":"started"},
#    "type":"feat","labels":["feat"],"parent":{"id":"ABC-100","title":"…"},"description":"…",
#    "comments":[{"author":"…","createdAt":"…","body":"…"}],
#    "subIssues":[{"id":"ABC-123","title":"…","status":{"name":"Todo","type":"unstarted"}}]}
# type is the card's label in the Type group, or null; parent is null for a
# card with none. When it fails it prints nothing on stdout.
#   entourage linear read <card> [--json]
linear_read() {
  local card=${1:-} json=0 key vars data shape more=''
  [ "$#" -ge 1 ] && [ "$#" -le 2 ] ||
    die "usage: entourage linear read <card> [--json], like: entourage linear read ABC-122"
  case ${2:-} in
    --json) json=1 ;;
    '') ;;
    *) die "unknown option for linear read: $2" ;;
  esac
  [[ $card =~ $CARD_RE ]] || die "'$card' is not a card ID like ABC-122."
  card=$(printf '%s' "$card" | tr '[:lower:]' '[:upper:]')
  linear_tools
  key=$(linear_saved_key) || exit 1
  vars=$(jq -cn --arg team "${card%-*}" --arg number "${card##*-}" '{team: $team, number: ($number | tonumber)}') ||
    die "'$card' is not a card ID like ABC-122."
  data=$(linear_ask "$key" "$READ_QUERY" "$vars") || exit 1
  # Judged by what jq prints: some versions exit zero on an empty answer.
  shape=$(printf '%s' "$data" | jq -c --arg group "$TYPE_GROUP" "$READ_SHAPE" 2>/dev/null) || shape=
  case $shape in
    '{"card":'*) ;;
    '"none"') die "Linear has no card $card that the saved key can see. Check the ID, then run this again." ;;
    '{"more":"comments"}') more="$READ_COMMENTS comments" ;;
    '{"more":"sub-issues"}') more="$READ_SUBS sub-issues" ;;
    '{"more":"labels"}') more="$READ_LABELS labels" ;;
    *) die "Linear's answer was not one entourage can read. Something between this machine and Linear may be answering for it." ;;
  esac
  [ -z "$more" ] ||
    die "$card has more than $more, more than entourage reads, so it printed none of the card: what it read would pass for the whole. Read the card in Linear, or with an agent's Linear tools."
  if [ "$json" = 1 ]; then
    printf '%s' "$shape" | jq -c '.card'
  else
    printf '%s' "$shape" | jq -r '.card | '"$READ_TEXT"
  fi
}

# --- the card skills' writes ------------------------------------------------
#
# The card skills write two things to a card: its type label, and a section
# of its description. Each is one command here, so that it goes the same way
# on every run, and each reads back what Linear saved before it says it is
# done. Nothing else in Linear is changed, and nothing is created.

# The types a card can have. Each is the start of the card's branch name.
CARD_TYPES='feat fix chore'

# Change a card: its fields as Linear's IssueUpdateInput names them, in $2 as
# JSON. Linear's answer gives back what is asked for in $3.
#   linear_update <key> <the card's id> <input, as JSON> <fields to read back>
linear_update() {
  local key=$1 id=$2 input=$3 fields=$4 vars
  vars=$(jq -cn --arg id "$id" --argjson input "$input" '{id: $id, input: $input}') ||
    die "could not put the change to Linear together."
  linear_ask "$key" "mutation(\$id: String!, \$input: IssueUpdateInput!) {
  issueUpdate(id: \$id, input: \$input) { success issue { $fields } }
}" "$vars"
}

# The card's own question for linear type: the card, its labels, and the
# labels of the name asked for in a group of the name asked for, the card's
# team's and the workspace's only, so that other teams' never crowd them out.
TYPE_QUERY='query($team: String!, $number: Float!, $type: String!, $group: String!) {
  issues(first: 1, filter: {team: {key: {eq: $team}}, number: {eq: $number}}) {
    nodes { id identifier labels(first: 100) { nodes { id name parent { name } } } }
  }
  issueLabels(first: 50, filter: {name: {eq: $type}, parent: {name: {eq: $group}},
      or: [{team: {key: {eq: $team}}}, {team: {null: true}}]}) {
    nodes { id name team { key } }
  }
}'

# Set a card's type: its one label in the Type group. The label is the card's
# team's, or the workspace's when the team has none. Any other label of the
# group comes off; the card's other labels are never sent, so they stay.
#   entourage linear type <card> <feat|fix|chore>
linear_type() {
  local card=${1:-} type=${2:-} key vars data plan add remove was saved lost
  [ "$#" -eq 2 ] || die "usage: entourage linear type <card> <feat|fix|chore>, like: entourage linear type ABC-122 feat"
  [[ $card =~ $CARD_RE ]] || die "'$card' is not a card ID like ABC-122."
  card=$(printf '%s' "$card" | tr '[:lower:]' '[:upper:]')
  in_list "$type" "$CARD_TYPES" ||
    die "'$type' is not a card type. A card's type is one of: $CARD_TYPES (see https://conventionalbranch.org)."
  linear_tools
  key=$(linear_saved_key) || exit 1
  vars=$(jq -cn --arg team "${card%-*}" --arg number "${card##*-}" --arg type "$type" --arg group "$TYPE_GROUP" \
    '{team: $team, number: ($number | tonumber), type: $type, group: $group}') ||
    die "'$card' is not a card ID like ABC-122."
  data=$(linear_ask "$key" "$TYPE_QUERY" "$vars") || exit 1
  # What to add and take off, or why there is nothing to do.
  plan=$(printf '%s' "$data" | jq -c --arg team "${card%-*}" --arg type "$type" --arg group "$TYPE_GROUP" '
    if (.issues.nodes | type) != "array" then error("no list of cards")
    elif (.issues.nodes | length) == 0 then {state: "none"}
    else .issues.nodes[0] as $card
      | ([.issueLabels.nodes[]? | select(.name == $type)]) as $named
      | (([$named[] | select(.team.key? == $team)] + [$named[] | select(.team == null)]) | .[0]) as $label
      | if $label == null then {state: "nolabel"}
        else ([$card.labels.nodes[]? | select(.parent.name? == $group)]) as $types
          | {state: "ok", id: $card.id,
             add: (if any($types[]; .id == $label.id) then [] else [$label.id] end),
             remove: [$types[] | select(.id != $label.id) | .id],
             was: [$types[] | select(.id != $label.id) | .name],
             keep: [$card.labels.nodes[]? | select(.parent.name? != $group) | .name]}
        end
    end' 2>/dev/null) || plan=
  case $(printf '%s' "$plan" | jq -r '.state' 2>/dev/null) in
    ok) ;;
    none) die "Linear has no card $card that the saved key can see. Check the ID, then run this again." ;;
    nolabel) die "team ${card%-*} has no label '$type' in a label group called $TYPE_GROUP, and nor does the workspace, so the type was not set. entourage makes no labels: make the $TYPE_GROUP group and its labels ($CARD_TYPES) in Linear, then run this again." ;;
    *) die "Linear's answer was not one entourage can read. Something between this machine and Linear may be answering for it." ;;
  esac
  add=$(printf '%s' "$plan" | jq -c '.add')
  remove=$(printf '%s' "$plan" | jq -c '.remove')
  was=$(printf '%s' "$plan" | jq -r '.was | join(", ")')
  if [ "$add" = '[]' ] && [ "$remove" = '[]' ]; then
    say "$card's type is already $type"
    return
  fi
  data=$(linear_update "$key" "$(printf '%s' "$plan" | jq -r '.id')" \
    "$(jq -cn --argjson add "$add" --argjson remove "$remove" \
      '{} + (if $add == [] then {} else {addedLabelIds: $add} end) + (if $remove == [] then {} else {removedLabelIds: $remove} end)')" \
    'labels(first: 100) { nodes { name parent { name } } }') || exit 1
  # What Linear says the card now has: one type, the one asked for.
  saved=$(printf '%s' "$data" | jq -r --arg group "$TYPE_GROUP" \
    '[.issueUpdate.issue.labels.nodes[]? | select(.parent.name? == $group) | .name] | join(", ")' 2>/dev/null) || saved=
  [ "$saved" = "$type" ] ||
    die "Linear did not save $card's type as $type alone: its $TYPE_GROUP labels are now '${saved:-none}'. Look at the card in Linear."
  # And the card's other labels are all still there.
  lost=$(printf '%s' "$data" | jq -r --argjson keep "$(printf '%s' "$plan" | jq -c '.keep')" \
    '$keep - [.issueUpdate.issue.labels.nodes[]?.name] | join(", ")' 2>/dev/null) || lost='its other labels'
  [ -z "$lost" ] ||
    die "Linear set $card's type to $type, but its answer shows the card without $lost. Look at the card in Linear."
  say "Set $card's type to $type${was:+ (it was $was)}"
}

# The sections the card skills write, in the order they come on a card.
# Specification and Plan are folded away; the human reads the Breakdown to
# approve the card, so it is left open.
CARD_SECTIONS='Specification Plan Breakdown'

# The question for linear section: the card and its description.
SECTION_QUERY='query($team: String!, $number: Float!) {
  issues(first: 1, filter: {team: {key: {eq: $team}}, number: {eq: $number}}) {
    nodes { id identifier description }
  }
}'

# Place a section in a description, on stdin, and print
#   {"before": <the text above it>, "new": <the description with it>}
# A folded section is "+++ ## <name>", its body, then a line "+++": the form
# Linear's API keeps it in, whatever it was written with. One written as
# ">>>", the form Linear's own tools show, is read the same. An open section
# is "## <name>" and its body, up to the next section or the end. $open,
# $replace: "true" or "false". Linear's own copy of a description can end its
# lines with \r and its sections with blank lines, so both are allowed for.
#   - A line inside a fenced code block is the card's text, never a section:
#     a card about entourage itself may show these forms as examples.
#   - An open section ends at the next heading of level 1 or 2, or the next
#     fold. A folded one ends at its closing line, and only there: a folded
#     section that meets another fold before it is closed cannot be told
#     apart from the next one, so it is not replaced.
SECTION_FORMS='
  def trim_end: sub("\\s+\\z"; "");
  def trim_start: sub("\\A\\s+"; "");
  def is_heading: if $open == "true" then . == "## " + $name
    else . == "+++ ## " + $name or . == ">>> ## " + $name end;
  def is_close: . == "+++" or . == ">>>";
  def is_fold: test("^(\\+\\+\\+|>>>)( |$)");
  def ends_open: is_fold or test("^##? ");
  def is_fence: test("^ {0,3}(```|~~~)");
  def in_code: . as $l
    | [foreach range(0; $l | length) as $i ({in: false, out: false};
        if ($l[$i] | is_fence) then {in: (.in | not), out: true} else {in: .in, out: .in} end;
        .out)];'
SECTION_PLACE=$SECTION_FORMS'
  def section: if $open == "true" then "## " + $name + "\n" + $body
    else "+++ ## " + $name + "\n" + $body + "\n+++" end;
  def join_parts: map(select(. != "")) | join("\n\n");
  (. // "") as $d
  | ($d | split("\n")) as $raw
  | ($raw | map(rtrimstr("\r"))) as $lines
  | ($lines | in_code) as $code
  | [range(0; $lines | length) | select(($code[.] | not) and ($lines[.] | is_heading))] as $at
  | if ($at | length) > 1 then error("twice")
    elif ($at | length) == 1 and $replace != "true" then error("there")
    elif ($at | length) == 0 and $replace == "true" then error("missing")
    elif ($at | length) == 0 then
      ($d | trim_end) as $before
      | {before: $before, new: ([$before, section] | join_parts)}
    else $at[0] as $start
      | [range($start + 1; $lines | length) | select($code[.] | not)] as $later
      | (if $open == "true"
           then {at: ([$later[] | select($lines[.] | ends_open)] | .[0] // ($lines | length)), skip: 0}
           else ([$later[] | select($lines[.] | is_fold)] | .[0]) as $fold
             | {at: (if $fold != null and ($lines[$fold] | is_close) then $fold else null end), skip: 1}
         end) as $end
      | if $end.at == null then error("open") else . end
      | ($raw[0:$start] | join("\n") | trim_end) as $before
      | ($raw[($end.at + $end.skip):] | join("\n") | trim_start | trim_end) as $after
      | {before: $before, new: ([$before, section, $after] | join_parts)}
    end'

# Check a description Linear saved, on stdin: it has the section once, and
# the text above it is $before. Prints ok, or what is wrong. Line ends are
# compared without their \r, which Linear may keep or drop.
SECTION_CHECK=$SECTION_FORMS'
  ((.issueUpdate.issue.description // "") | split("\n") | map(rtrimstr("\r"))) as $lines
  | ($lines | in_code) as $code
  | [range(0; $lines | length) | select(($code[.] | not) and ($lines[.] | is_heading))] as $at
  | if ($at | length) != 1 then "count"
    elif ($lines[0:$at[0]] | join("\n") | trim_end)
      != ($before | split("\n") | map(rtrimstr("\r")) | join("\n") | trim_end) then "above"
    else "ok" end'

# Whether a section body, on stdin, has a line that would end the section
# early or start a second one: a fold line in a folded section, and a heading
# of level 1 or 2 or a fold line in an open one. Prints true or false.
SECTION_BODY_CHECK=$SECTION_FORMS'
  split("\n") | map(rtrimstr("\r")) | . as $l | ($l | in_code) as $code
  | any(range(0; $l | length);
      ($code[.] | not) and ($l[.] | if $open == "true" then ends_open else is_fold end))'

# Add a section to a card's description, below what is there, or with
# --replace put it in place of the one of that name. The body is on stdin;
# the heading and the folding are added here. The whole description is sent
# back, then what Linear saved is read: the text above the section must be as
# it was, and the section there once.
#   entourage linear section <card> <Specification|Plan|Breakdown> [--replace]
linear_section() {
  local card=${1:-} name=${2:-} replace=false open=false body key vars data id placed new before check
  [ "$#" -ge 2 ] && [ "$#" -le 3 ] ||
    die "usage: entourage linear section <card> <$(printf '%s' "$CARD_SECTIONS" | tr ' ' '|')> [--replace], with the section's body on stdin"
  case ${3:-} in
    --replace) replace=true ;;
    '') ;;
    *) die "unknown option for linear section: $3" ;;
  esac
  [[ $card =~ $CARD_RE ]] || die "'$card' is not a card ID like ABC-122."
  card=$(printf '%s' "$card" | tr '[:lower:]' '[:upper:]')
  in_list "$name" "$CARD_SECTIONS" ||
    die "'$name' is not a section entourage writes. The sections are: $CARD_SECTIONS."
  [ "$name" != Breakdown ] || open=true
  [ ! -t 0 ] || die "give the section's body on stdin, like: entourage linear section $card $name <<'EOF'"
  # jq reads the body, so it is checked for before the body is.
  linear_tools
  body=$(cat)
  # Blank lines at either end are dropped: the heading and the folding come
  # with their own.
  body=$(printf '%s' "$body" | jq -Rs 'sub("\\A\\s+"; "") | sub("\\s+\\z"; "")') ||
    die "could not read the section's body."
  [ "$body" != '""' ] || die "the $name has no body. Give it on stdin."
  # Judged by what jq prints: some versions exit zero on an empty answer.
  case $(printf '%s' "$body" | jq -r --arg open "$open" --arg name "$name" "$SECTION_BODY_CHECK" 2>/dev/null) in
    false) ;;
    true)
      if [ "$open" = true ]; then
        die "the $name's body has a line that starts a heading (# or ##) or a folded section (+++ or >>>), which would end the $name early. Make it a ### heading, or take it out. The command adds the $name's own heading."
      else
        die "the $name's body has a line that starts or ends a folded section (+++ or >>>), which would end the $name early. Take that line out. The command adds the $name's own heading and closing line."
      fi ;;
    *) die "could not read the section's body." ;;
  esac
  key=$(linear_saved_key) || exit 1
  vars=$(jq -cn --arg team "${card%-*}" --arg number "${card##*-}" '{team: $team, number: ($number | tonumber)}') ||
    die "'$card' is not a card ID like ABC-122."
  data=$(linear_ask "$key" "$SECTION_QUERY" "$vars") || exit 1
  case $(printf '%s' "$data" | jq -r 'if (.issues.nodes | type) != "array" then "unreadable" elif (.issues.nodes | length) == 0 then "none" else "ok" end' 2>/dev/null) in
    ok) ;;
    none) die "Linear has no card $card that the saved key can see. Check the ID, then run this again." ;;
    *) die "Linear's answer was not one entourage can read. Something between this machine and Linear may be answering for it." ;;
  esac
  id=$(printf '%s' "$data" | jq -r '.issues.nodes[0].id')
  placed=$(printf '%s' "$data" | jq -c --arg name "$name" --arg open "$open" --arg replace "$replace" \
    --argjson body "$body" '.issues.nodes[0].description | '"$SECTION_PLACE" 2>&1) || {
    case $placed in
      *there*) die "$card already has a $name. To put this one in its place, run it again with --replace." ;;
      *twice*) die "$card has two sections called $name, so entourage cannot tell which to change. Make it one in Linear, then run this again." ;;
      *missing*) die "$card has no $name that entourage can read, so there is none to replace. Look at the card in Linear: a $name written in another form needs putting right by hand." ;;
      *open*) die "$card's $name is not closed before the next folded section, so entourage cannot tell where it ends. Close it in Linear, then run this again." ;;
      *) die "could not place the $name in $card's description." ;;
    esac
  }
  new=$(printf '%s' "$placed" | jq -c '.new')
  before=$(printf '%s' "$placed" | jq -r '.before')
  data=$(linear_update "$key" "$id" "$(jq -cn --argjson d "$new" '{description: $d}')" 'description') || exit 1
  check=$(printf '%s' "$data" | jq -r --arg name "$name" --arg open "$open" --arg before "$before" "$SECTION_CHECK" 2>/dev/null) || check=
  case $check in
    ok) ;;
    above) die "the $name was written to $card, but the text above it changed on the way: Linear's copy is not what was there before. Look at the card in Linear." ;;
    count) die "the $name was written to $card, but Linear's copy does not have it once. Look at the card in Linear." ;;
    *) die "the $name was written to $card, but Linear's answer could not be read to check it. Look at the card in Linear." ;;
  esac
  if [ "$replace" = true ]; then say "Wrote the $name on $card"
  else say "Added the $name to $card"
  fi
}

# --- moving a card ----------------------------------------------------------
#
# entourage moves a card at four points: the hand-off that records the
# human's approval moves it, and each of its sub-issues, to its team's first
# not-started status; `task start` moves it to its team's first started
# status; `sdlc-pr` runs `linear move <card> review` once every pull request
# for it is open, which moves it to the last started status; and the hand-off
# that records its merge moves it to the first completed one. The status is
# picked by its kind and its place in the team's order, never by its name,
# which each team chooses. A card only moves forward, so a person who has
# moved it further on by hand is never undone, and a card that is done,
# canceled or a duplicate is never moved at all.

# The kinds of status a card moves through, in order. A card in a completed
# status, or one of any other kind, is closed.
MOVE_ORDER='{"triage":0,"backlog":1,"unstarted":2,"started":3,"completed":4}'

# A card in a move's question: its ids and its status.
MOVE_FIELDS='id identifier state { id name type position }'
# The question for a move: the card, its status, and its team's statuses.
MOVE_QUERY='query($team: String!, $number: Float!) {
  issues(first: 1, filter: {team: {key: {eq: $team}}, number: {eq: $number}}) {
    nodes { '$MOVE_FIELDS'
      team { states(first: 250) { nodes { id name type position } } } }
  }
}'
# The question for the approval's move, which moves the card's sub-issues
# too: the same, and each sub-issue with its status and its own team's
# statuses. Linear caps what one question may cost, and each sub-issue's
# statuses count again, so fewer are asked for than for the card itself.
APPROVED_QUERY='query($team: String!, $number: Float!) {
  issues(first: 1, filter: {team: {key: {eq: $team}}, number: {eq: $number}}) {
    nodes { '$MOVE_FIELDS'
      team { states(first: 250) { nodes { id name type position } } }
      children(first: 50) { nodes { '$MOVE_FIELDS'
        team { states(first: 50) { nodes { id name type position } } } } } }
  }
}'

# From the answer to MOVE_QUERY or APPROVED_QUERY, on stdin, what to do with
# each card: a list of {card, plan}, the card first and then, for approved,
# each of its sub-issues; or "none" when Linear has no such card. $card is the
# card's ID, $to is where to move to, approved, started, review or completed,
# and $order is MOVE_ORDER. The target is the status of that kind that comes
# first in the card's team's order (approved is the first unstarted one); for
# review it is the started status that comes last, which in a team with one
# started status is that one. A card moves only when the target is further
# along: a later kind, or a later place within the same kind. An answer with a
# card in it that cannot be read did not come from Linear, so none is moved.
MOVE_PLAN='
  def place: (.position | numbers) // 1000000;
  (if $to == "review" then "started" elif $to == "approved" then "unstarted" else $to end) as $kind
  | def plan:
      .state as $now
      | if (.id | type) != "string" or ($now.id? | type) != "string"
          or ($now.type? | type) != "string" or (.team.states.nodes? | type) != "array"
        then error("unreadable") else . end
      | ([.team.states.nodes[] | select(.type == $kind and (.id | type) == "string")]
         | sort_by(place) | if $to == "review" then last else first end) as $target
      | if $target == null then {state: "notarget"}
        elif $now.id == $target.id then {state: "there", now: $now.name}
        elif $order[$now.type] == null or $now.type == "completed" then {state: "closed", now: $now.name}
        elif $order[$target.type] > $order[$now.type]
          or ($target.type == $now.type and ($target | place) > ($now | place))
          then {state: "move", id: .id, to: $target.id, name: $target.name, was: $now.name}
        else {state: "past", now: $now.name, name: $target.name}
        end;
  if (.issues.nodes | type) != "array" then error("no list of cards")
  elif (.issues.nodes | length) == 0 then "none"
  else .issues.nodes[0]
    | [{card: $card, plan: plan}]
      + if $to != "approved" then []
        elif (.children.nodes | type) != "array" then error("no list of sub-issues")
        else [.children.nodes[]
          | if (.identifier | type) != "string" or (.identifier | test("^[A-Za-z][A-Za-z0-9]*-[0-9]+$") | not)
            then error("unreadable") else . end
          | {card: (.identifier | ascii_upcase), plan: plan}]
        end
  end'

# Ask Linear what to do with a card and, for approved, its sub-issues, and
# print the list MOVE_PLAN makes, as one line of JSON; or stop and say why.
#   move_plans <card ID, in upper case> <approved|started|review|completed>
move_plans() {
  local card=$1 to=$2 query=$MOVE_QUERY key vars data plans
  [ "$to" != approved ] || query=$APPROVED_QUERY
  linear_tools
  key=$(linear_saved_key) || exit 1
  vars=$(jq -cn --arg team "${card%-*}" --arg number "${card##*-}" \
    '{team: $team, number: ($number | tonumber)}' 2>/dev/null) ||
    die "'$card' is not a card ID like ABC-122."
  data=$(linear_ask "$key" "$query" "$vars") || exit 1
  plans=$(printf '%s' "$data" |
    jq -c --arg card "$card" --arg to "$to" --argjson order "$MOVE_ORDER" "$MOVE_PLAN" 2>/dev/null) || plans=
  case $plans in
    '['*) printf '%s\n' "$plans" ;;
    '"none"') die "Linear has no card $card that the saved key can see." ;;
    *) die "Linear's answer was not one entourage can read. Something between this machine and Linear may be answering for it." ;;
  esac
}

# Move one card by its plan from MOVE_PLAN, and read the change back: the
# card has to be in the status asked for. It says where the card is now, or
# stops and says why it was not moved.
#   move_by_plan <card ID> <its plan, as JSON> <approved|started|review|completed>
move_by_plan() {
  local card=$1 plan=$2 kind key data saved
  case $3 in
    approved) kind=unstarted ;;
    review) kind=started ;;
    *) kind=$3 ;;
  esac
  case $(printf '%s' "$plan" | jq -r '.state' 2>/dev/null) in
    move) ;;
    there) say "$card is in $(printf '%s' "$plan" | jq -r '.now') already"; return ;;
    past) say "$card stays in $(printf '%s' "$plan" | jq -r '.now'), which is past $(printf '%s' "$plan" | jq -r '.name'): a card only moves forward"; return ;;
    closed) say "$card stays in $(printf '%s' "$plan" | jq -r '.now'), which is closed: a card that is done or canceled is never moved"; return ;;
    notarget) die "team ${card%-*} has no $kind status in Linear." ;;
    *) die "Linear's answer was not one entourage can read. Something between this machine and Linear may be answering for it." ;;
  esac
  key=$(linear_saved_key) || exit 1
  data=$(linear_update "$key" "$(printf '%s' "$plan" | jq -r '.id')" \
    "$(printf '%s' "$plan" | jq -c '{stateId: .to}')" 'state { id name }') || exit 1
  # What Linear says the card is in now: the status asked for.
  saved=$(printf '%s' "$data" | jq -r '.issueUpdate.issue.state.id // empty' 2>/dev/null) || saved=
  [ "$saved" = "$(printf '%s' "$plan" | jq -r '.to')" ] ||
    die "Linear did not save $card in $(printf '%s' "$plan" | jq -r '.name'): its answer shows it in $(printf '%s' "$data" | jq -r '.issueUpdate.issue.state.name // "no status"' 2>/dev/null || printf 'no status'). Look at the card in Linear."
  say "$card moved to $(printf '%s' "$plan" | jq -r '.name') in Linear (it was $(printf '%s' "$plan" | jq -r '.was'))"
}

# What linear_move says of a card it could not move: the card's ID, then this,
# then why. A line it says of a card that moved, or stays, never matches.
NOT_MOVED_RE='^([A-Z][A-Z0-9]*-[0-9]+) was not moved in Linear(: (.*))?$'

# Move a card forward to its team's first status of a kind, or for review its
# last started one, or leave it where it is and say why. For approved, each of
# the card's sub-issues is moved after it the same way, by its own team's
# statuses: each card on its own, so one that stays or cannot be moved never
# keeps another from moving. It says one line for each card: where it is now,
# or "<card> was not moved in Linear: <why>". It returns 1 when a card was not
# moved; when Linear cannot be asked, that is the card itself.
#   linear_move <card ID, in upper case> <approved|started|review|completed>
linear_move() {
  local card=$1 to=$2 plans each out id plan failed=0
  if ! plans=$(move_plans "$card" "$to" 2>&1); then
    out=${plans#entourage: }
    say "$card was not moved in Linear${out:+: ${out//$'\n'/ }}"
    return 1
  fi
  # One line for each card: its ID, then its plan.
  each=$(printf '%s' "$plans" | jq -r '.[] | .card + " " + (.plan | tojson)' 2>/dev/null) || each=
  if [ -z "$each" ]; then
    say "$card was not moved in Linear: Linear's answer was not one entourage can read"
    return 1
  fi
  while read -r id plan; do
    [ -n "$id" ] || continue
    if out=$(move_by_plan "$id" "$plan" "$to" 2>&1); then
      say "$out"
    else
      out=${out#entourage: }
      say "$id was not moved in Linear${out:+: ${out//$'\n'/ }}"
      failed=1
    fi
  done <<< "$each"
  return "$failed"
}

# The first sentence of a message from die, on one line, with no "entourage: "
# before it. The rest of such a message is often advice for a command that
# stops, such as to run it again, which is wrong for a step that goes on.
first_sentence() {
  local why=$1
  why=${why#entourage: }; why=${why%%$'\n'*}; why=${why%%. *}; why=${why%.}
  printf '%s' "$why"
}

# Move a card as linear_move does, for a command whose own work is done by
# then and must not be undone by Linear: it never stops. It prints what
# linear_move said, one line for each card, with only the first sentence of
# why a card was not moved, and returns 1 when a card was not moved.
#   linear_move_note <card ID, in upper case> <approved|started|completed>
linear_move_note() {
  local out line rc=0
  out=$(linear_move "$1" "$2" 2>&1) || rc=1
  while IFS= read -r line; do
    if [[ $line =~ $NOT_MOVED_RE ]] && [ -n "${BASH_REMATCH[3]}" ]; then
      say "${BASH_REMATCH[1]} was not moved in Linear: $(first_sentence "${BASH_REMATCH[3]}")"
    else
      say "$line"
    fi
  done <<< "$out"
  return "$rc"
}

# The places `linear move` takes a card to, in the order a card goes through
# them. done is the first completed status, which linear_move calls
# completed.
MOVE_WORDS='approved started review done'

# Move a card forward in Linear, by the rules of linear_move: approved is its
# team's first not-started status (Todo in Lab, Ready for Dev in PHY), and
# each of its sub-issues' too; started is its team's first started status,
# review its last started one (In Review in Lab and PHY), and done its first
# completed one. Moving the card is the whole of this command, unlike in
# `task start` and `task handoff`, so a move that cannot be made stops it,
# saying which card was not moved, and why. A card that is there already,
# further on or closed stays where it is, and that is not a failure.
#   entourage linear move <card> <approved|started|review|done>
linear_move_cmd() {
  local card=${1:-} word=${2:-} to out line
  [ "$#" -eq 2 ] ||
    die "usage: entourage linear move <card> <$(printf '%s' "$MOVE_WORDS" | tr ' ' '|')>, like: entourage linear move ABC-122 review"
  [[ $card =~ $CARD_RE ]] || die "'$card' is not a card ID like ABC-122."
  card=$(printf '%s' "$card" | tr '[:lower:]' '[:upper:]')
  in_list "$word" "$MOVE_WORDS" ||
    die "'$word' is not a place a card moves to. A card moves to one of: $MOVE_WORDS."
  to=$word
  [ "$word" != done ] || to=completed
  if out=$(linear_move "$card" "$to" 2>&1); then
    say "$out"
    return
  fi
  # What happened to each card is said, a card that was not moved as an
  # error, and then the command stops.
  while IFS= read -r line; do
    if [[ $line =~ $NOT_MOVED_RE ]]; then printf 'entourage: %s\n' "$line" >&2
    else say "$line"
    fi
  done <<< "$out"
  exit 1
}

cmd_linear() {
  case ${1:-} in
    key) shift; linear_key "$@" ;;
    type) shift; linear_type "$@" ;;
    section) shift; linear_section "$@" ;;
    move) shift; linear_move_cmd "$@" ;;
    read) shift; linear_read "$@" ;;
    *) die "usage: entourage linear key, or: entourage linear read <card> [--json], or: entourage linear type <card> <feat|fix|chore>, or: entourage linear section <card> <Specification|Plan|Breakdown> [--replace], or: entourage linear move <card> <approved|started|review|done> (see: entourage help)" ;;
  esac
}
