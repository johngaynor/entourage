# Archiving closed cards in Linear, when the human turns it on. Sourced by
# cli/entourage.

# Linear's free plan stops making cards once 250 are not archived, and a card
# that is done stays in its team's lists until Linear's own auto-archive takes
# it, months later. With archiving on, recording a card's merge archives the
# card, once its move to Done has put it in a closed status, and every other
# closed card of the project's teams: done, canceled or a duplicate. An
# archived card is not deleted: it can still be opened by its ID, and
# restored from its team's archive. Archiving is off unless the settings file
# says "archive": true (settings.sh), which `linear archive on` writes.
#
# A card that has a parent card or sub-issues is never archived, whichever it
# is: archiving a card archives its sub-issues with it, and what becomes of a
# sliced card is not decided yet.

# What `linear archive` takes after it.
TAKES_ARCHIVE='on or off, or nothing to say whether archiving is on (--json for programs)'

# --- the setting ------------------------------------------------------------

# entourage linear archive [on|off] [--json]: say whether archiving is on, or
# turn it on or off. --json prints it as one line for programs, with the file
# it is kept in, for a Herdr mod. on and off write "archive" into the
# settings file as profile_set writes a profile: everything is checked before
# the file is touched, and the new file is checked before it takes the old
# one's place, so a refusal or a failure leaves the file as it was.
linear_archive_cmd() {
  local usage="usage: entourage linear archive [on|off|--json]: it takes $TAKES_ARCHIVE"
  case $# in
    0) archive_show plain ;;
    1)
      case $1 in
        --json) archive_show json ;;
        on) archive_set true ;;
        off) archive_set false ;;
        *) die "'$1' is not on or off. entourage linear archive takes $TAKES_ARCHIVE." ;;
      esac
      ;;
    *) die "$usage" ;;
  esac
}

# Say whether archiving is on: plain, for a person, or json, for programs.
archive_show() {
  need_jq
  settings_check
  if [ "$1" = json ]; then
    printf '{"file":"%s","archive":%s}\n' "$(json_str "$SETTINGS")" "$SET_ARCHIVE"
  elif [ "$SET_ARCHIVE" = true ]; then
    say "Archiving is on: recording a card's merge archives it in Linear, and every other closed card of the project's teams. A card with a parent or sub-issues is left as it is."
    say "Turn it off with: entourage linear archive off"
  else
    say "Archiving is off: a merged card stays in Done in Linear."
    say "Turn it on with: entourage linear archive on"
  fi
}

# Write "archive": true or false into the settings file. With no file yet,
# the new one starts from the defaults, so that it names every profile.
archive_set() {
  local want=$1 tmp ok=0
  need_jq
  settings_check
  mkdir -p "${SETTINGS%/*}"
  tmp=$SETTINGS.entourage.$$
  if { if [ -e "$SETTINGS" ]; then cat "$SETTINGS"; else settings_default; fi; } |
      jq --argjson on "$want" '.archive = $on' > "$tmp" 2>/dev/null &&
    [ "$(SETTINGS=$tmp; settings_load && printf '%s' "$SET_ARCHIVE")" = "$want" ] &&
    mv -f "$tmp" "$SETTINGS"; then
    ok=1
  fi
  rm -f "$tmp"
  [ "$ok" = 1 ] || die "could not change $SETTINGS, so it is as it was."
  settings_check
  if [ "$want" = true ]; then
    say "Archiving is on now. The next merge recorded archives its card in Linear, and every other closed card of the project's teams."
  else
    say "Archiving is off now. A merged card stays in Done in Linear."
  fi
}

# --- archiving at the merge -------------------------------------------------

# The merged card's question: its status, its parent and whether it has
# sub-issues.
ARCHIVE_CARD_QUERY='query($team: String!, $number: Float!) {
  issues(first: 1, filter: {team: {key: {eq: $team}}, number: {eq: $number}}) {
    nodes { id identifier state { name type } parent { identifier }
      children(first: 1) { nodes { identifier } } }
  }
}'
# The kinds of status a closed card is in: done, and canceled, which is where
# a duplicate is too.
CLOSED_TYPES='["completed","canceled"]'
# One page of the closed cards of some teams, in the order they were made,
# as linear_open_cards pages through the open ones.
CLOSED_QUERY='query($teams: [String!], $types: [String!], $first: Int, $after: String) {
  issues(first: $first, after: $after, orderBy: createdAt,
      filter: {team: {key: {in: $teams}}, state: {type: {in: $types}}}) {
    nodes { id identifier state { name type } parent { identifier }
      children(first: 1) { nodes { identifier } } }
    pageInfo { hasNextPage endCursor }
  }
}'
# Archive one card. Without trash, so it is archived, not deleted.
ARCHIVE_MUTATION='mutation($id: String!) { issueArchive(id: $id) { success } }'

# Whether a card, in the answer to either question, is to be archived: why
# it is left as it is, or null when it is to be archived. A card whose id,
# ID, status or sub-issues cannot be read did not come from Linear, so the
# whole answer is unreadable and nothing is archived on its say; a card is
# never just left out. A status's name is anyone's text, so a control
# character in it becomes a space, as `task ls` does, and the why stays on
# one line.
ARCHIVE_WHY='
  def plain: explode | map(if . < 32 or (. > 126 and . < 160) then 32 else . end) | implode;
  def why:
    if (.id | type) != "string" or (.id | test("^\\S+$") | not)
      or (.identifier | type) != "string"
      or (.identifier | test("^[A-Za-z][A-Za-z0-9]*-[0-9]+$") | not)
      or (.state | type) != "object" or (.state.type | type) != "string"
      or (.children | type) != "object" or (.children.nodes | type) != "array"
      or (.parent != null and (.parent | type) != "object")
    then error("unreadable")
    elif (.state.type | . != "completed" and . != "canceled")
      then "it is in \((.state.name // .state.type) | tostring | plain), which is not closed"
    elif .parent != null
      then "it is a sub-issue of \((.parent.identifier // "another card") | tostring | plain), and a card with a parent or sub-issues is never archived"
    elif (.children.nodes | length) > 0
      then "it has sub-issues, and a card with a parent or sub-issues is never archived"
    else null end;'

# What to do with the merged card, as one line of JSON, or stop and say why:
#   {"id": <Linear's id for it>, "why": <why it is left as it is, or null>}
#   archive_card_plan <key> <card ID, in upper case>
archive_card_plan() {
  local key=$1 card=$2 vars data plan
  vars=$(jq -cn --arg team "${card%-*}" --arg number "${card##*-}" \
    '{team: $team, number: ($number | tonumber)}' 2>/dev/null) ||
    die "'$card' is not a card ID like ABC-122."
  data=$(linear_ask "$key" "$ARCHIVE_CARD_QUERY" "$vars") || exit 1
  plan=$(printf '%s' "$data" | jq -c "$ARCHIVE_WHY"'
    if (.issues.nodes | type) != "array" then error("no list of cards")
    elif (.issues.nodes | length) == 0 then "none"
    else .issues.nodes[0] | {id, why: why} end' 2>/dev/null) || plan=
  case $plan in
    '{'*) printf '%s\n' "$plan" ;;
    '"none"') die "Linear has no card $card that the saved key can see." ;;
    *) die "Linear's answer was not one entourage can read." ;;
  esac
}

# The closed cards of some teams, but for the merged card, as one line of
# JSON, or stop and say why:
#   {"more": <whether Linear had more than it was asked for>,
#    "cards": [{"card": "ABC-1", "id": <Linear's id>, "why": <or null>}]}
# Every page is fetched before a card is archived, since a card archived
# drops out of the pages after it. Past LINEAR_PAGES pages, the cards listed
# so far are the list, and the next merge lists the rest.
#   archive_closed_cards <key> <the teams, as a JSON list> <card ID>
archive_closed_cards() {
  local key=$1 teams=$2 card=$3 vars data pages='' after='' more asked=0 rest=false list
  while :; do
    asked=$((asked + 1))
    [ "$asked" -le "$LINEAR_PAGES" ] || { rest=true; break; }
    vars=$(jq -cn --argjson teams "$teams" --argjson types "$CLOSED_TYPES" --argjson first "$LINEAR_PAGE" \
      --arg after "$after" \
      '{teams: $teams, types: $types, first: $first, after: (if $after == "" then null else $after end)}')
    data=$(linear_ask "$key" "$CLOSED_QUERY" "$vars") || exit 1
    pages+=$data$'\n'
    more=$(printf '%s' "$data" | jq -r '.issues.pageInfo.hasNextPage == true' 2>/dev/null) ||
      die "Linear's answer was not one entourage can read."
    [ "$more" = true ] || break
    after=$(printf '%s' "$data" | jq -r '.issues.pageInfo.endCursor | strings' 2>/dev/null) || after=
    [ -n "$after" ] ||
      die "Linear said it had more closed cards but not where the next ones start."
  done
  # A card on two pages is listed once, where it came first.
  list=$(printf '%s' "$pages" | jq -cs --arg card "$card" --argjson rest "$rest" "$ARCHIVE_WHY"'
    if any(.[]; (.issues.nodes | type) != "array") then error("no list of cards") else . end
    | [.[].issues.nodes[]]
    | if any(.[]; (.identifier | type) != "string") then error("unreadable") else . end
    | reduce .[] as $c ({seen: {}, cards: []};
        if .seen[$c.identifier] then . else .seen[$c.identifier] = true | .cards += [$c] end)
    | {more: $rest,
       cards: [.cards[] | select((.identifier | ascii_upcase) != $card)
               | {card: (.identifier | ascii_upcase), id, why: why}]}' 2>/dev/null) ||
    die "Linear's answer was not one entourage can read."
  printf '%s\n' "$list"
}

# Archive one card, and read Linear's word that it did, or stop and say why.
#   archive_card <key> <Linear's id for the card>
archive_card() {
  local data
  data=$(linear_ask "$1" "$ARCHIVE_MUTATION" "$(jq -cn --arg id "$2" '{id: $id}')") || exit 1
  [ "$(printf '%s' "$data" | jq -r '.issueArchive.success' 2>/dev/null)" = true ] ||
    die "Linear did not say it archived the card."
}

# Archive the merged card and the other closed cards of the project's teams,
# once the merge is recorded and the card moved to Done, when archiving is
# on; with it off, Linear is asked nothing. The merge is recorded by now, so
# this never stops: each part that can stop runs in a subshell of its own.
# It says one line for each card it archives or leaves as it is, the card's
# ID and then why, in the first sentence of it, and one line with how many
# other closed cards it archived. The first call to Linear that fails ends
# it, naming the card it was on: a key that cannot write, or a Linear out of
# reach, would fail every card after it the same way, and each archive call
# waits for Linear, so going on could keep the hand-off for minutes. The next
# merge tries again. It returns 1 when a card was not archived.
#   linear_archive_note <project> <card ID, in upper case>
linear_archive_note() {
  local project=$1 card=$2 key plan id why out teams shown list each c n=0 stopped='' rc=0 more noun line
  if ! settings_load; then
    say "$card was not archived in Linear: $(first_sentence "$SETTINGS_WHY")"
    return 1
  fi
  [ "$SET_ARCHIVE" = true ] || return 0
  # The merged card itself.
  if ! key=$( { linear_tools && linear_saved_key; } 2>&1); then
    stopped=$key
  elif ! plan=$(archive_card_plan "$key" "$card" 2>&1); then
    stopped=$plan
  else
    id=$(printf '%s' "$plan" | jq -r '.id')
    why=$(printf '%s' "$plan" | jq -r '.why // empty')
    if [ -n "$why" ]; then
      say "$card was not archived in Linear: $why"
      rc=1
    elif out=$(archive_card "$key" "$id" 2>&1); then
      say "$card archived in Linear"
    else
      stopped=$out
    fi
  fi
  if [ -n "$stopped" ]; then
    say "$card was not archived in Linear: $(first_sentence "$stopped")"
    say "The other closed cards were not archived in Linear: archiving stopped at $card, and the next merge tries again"
    return 1
  fi
  # The other closed cards of the project's teams.
  if ! teams=$( { dir=$(project_dir "$project") && project_teams "$dir"; } 2>&1); then
    say "The other closed cards were not archived in Linear: $(first_sentence "$teams")"
    return 1
  fi
  if [ -z "$teams" ]; then
    say "The other closed cards were not archived in Linear: project '$project' has no Linear team"
    return "$rc"
  fi
  teams=$(printf '%s\n' "$teams" | jq -Rcn '[inputs]')
  shown=$(printf '%s' "$teams" | jq -r 'join(", ")')
  if ! list=$(archive_closed_cards "$key" "$teams" "$card" 2>&1); then
    say "The other closed cards of $shown were not archived in Linear: $(first_sentence "$list")"
    return 1
  fi
  more=$(printf '%s' "$list" | jq -r '.more')
  # One line for each card: its ID, Linear's id for it, and why it is left,
  # when it is. The why comes last, so that an empty one is no field at all.
  each=$(printf '%s' "$list" | jq -r '.cards[] | [.card, .id, (.why // "")] | join("\t")')
  while IFS=$'\t' read -r c id why; do
    [ -n "$c" ] || continue
    if [ -n "$why" ]; then
      say "$c was not archived in Linear: $why"
      rc=1
    elif out=$(archive_card "$key" "$id" 2>&1); then
      n=$((n + 1))
    else
      say "$c was not archived in Linear: $(first_sentence "$out")"
      stopped=$c rc=1
      break
    fi
  done <<< "$each"
  noun=cards
  [ "$n" != 1 ] || noun=card
  line="Archived $n other closed $noun of $shown in Linear"
  if [ -n "$stopped" ]; then line="$line, and stopped at $stopped: the next merge tries the rest"
  elif [ "$more" = true ]; then line="$line; Linear has more, which the next merge archives"
  fi
  say "$line"
  return "$rc"
}
