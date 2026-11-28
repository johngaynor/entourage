# Spaces: groups of repos, each of which opens in Herdr as one space. Sourced
# by cli/entourage.

# A space is a folder in $SPACES:
#   PROJECT.md   what the space is and what belongs in each repo
#   repos        one repo path per line (~/ for the home folder, # for comments)
#   teams        the keys of the space's Linear teams, like ABC, one per line
#   links/       generated: a link to each repo, named after its folder
#   CLAUDE.md, AGENTS.md   generated: links to PROJECT.md, so agents read it

valid_name() { case ${1:-} in '' | *[!a-z0-9-]*) return 1 ;; esac; }

# Print a space's folder, or stop if there is no such space.
space_dir() {
  local name=${1:-}
  [ -n "$name" ] || die "which space? See: entourage space ls"
  valid_name "$name" && [ -d "$SPACES/$name" ] ||
    die "no space called '$name'. Make it with: entourage space new $name"
  (cd -P "$SPACES/$name" && pwd)
}

# Mark a space's folder as trusted by Claude Code (see trust.sh), when
# entourage made it: a folder of its own in $SPACES. A space name that is
# a link leads to a folder someone else made, perhaps a repo, and entourage
# does not answer for that. Claude Code asks about it itself, once.
trust_space() {
  local name=$1
  [ ! -L "$SPACES/$name" ] || return 0
  # The real path, which is what Claude Code looks up: $SPACES may run
  # through a link.
  trust_folder "$(space_dir "$name")"
}

# Print a space's repo paths, absolute, one per line.
space_repos() {
  local dir=$1 line
  [ -f "$dir/repos" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in
      '' | '#'*) continue ;;
      '~/'*) line=$HOME/${line#'~/'} ;;
    esac
    printf '%s\n' "$line"
  done < "$dir/repos"
}

is_repo() { [ -e "$1/.git" ]; }

# Rebuild what is generated in a space folder. Only links are ever removed
# or replaced; a real file in the way is reported and left alone.
sync_links() {
  local dir=$1 src dst base names=$'\n'
  mkdir -p "$dir/links"
  while IFS= read -r src; do
    base=${src##*/}
    dst=$dir/links/$base
    names+=$base$'\n'
    is_repo "$src" || say "  warning: $src is missing or is not a git repo"
    if [ -L "$dst" ]; then
      [ "$(readlink "$dst")" = "$src" ] || { rm "$dst"; ln -s "$src" "$dst"; }
    elif [ -e "$dst" ]; then
      say "  skipped  links/$base (a real file is in the way)"
    else
      ln -s "$src" "$dst"
    fi
  done < <(space_repos "$dir")
  for dst in "$dir"/links/*; do
    [ -L "$dst" ] || continue
    case $names in *$'\n'"${dst##*/}"$'\n'*) ;; *) rm "$dst" ;; esac
  done
  for base in CLAUDE.md AGENTS.md; do
    [ -e "$dir/$base" ] || [ -L "$dir/$base" ] || ln -s PROJECT.md "$dir/$base"
  done
}

# Print the real folder of the repo a path names, or stop if it is not one.
repo_at() {
  local path=$1 abs
  [ -d "$path" ] || die "$path is not a folder"
  abs=$(cd "$path" && pwd -P)
  is_repo "$abs" || die "$abs is not a git repo (the top folder of a clone is needed)"
  printf '%s\n' "$abs"
}

# Add a line for a repo to a space's repos file, with ~/ for the home folder.
store_repo() {
  local dir=$1 abs=$2
  case $abs in
    "$HOME"/*) abs="~/${abs#"$HOME"/}" ;;
  esac
  printf '%s\n' "$abs" >> "$dir/repos"
}

# With repo paths after the name, the space starts with those repos. The
# projects mod makes a space this way, in one command.
space_new() {
  local name=${1:-} dir path abs other
  local -a repos=()
  valid_name "$name" || die "a space name is lowercase letters, digits and dashes, like: my-space"
  dir=$SPACES/$name
  [ ! -e "$dir" ] || die "space '$name' already exists at $dir"
  [ -f "$TEMPLATE/PROJECT.md" ] || die "the space template is missing from $TEMPLATE"
  shift
  # Every repo is checked before anything is made, so that a bad one does not
  # leave a space behind with only some of them.
  for path in "$@"; do
    abs=$(repo_at "$path")
    for other in ${repos[@]+"${repos[@]}"}; do
      [ "$other" != "$abs" ] || die "$abs is listed twice"
      [ "${other##*/}" != "${abs##*/}" ] ||
        die "$other and $abs are both called ${abs##*/}; two repos in a space cannot share a folder name"
    done
    repos+=("$abs")
  done
  mkdir -p "$dir"
  sed "s/__NAME__/$name/" "$TEMPLATE/PROJECT.md" > "$dir/PROJECT.md"
  : > "$dir/repos"
  for abs in ${repos[@]+"${repos[@]}"}; do store_repo "$dir" "$abs"; done
  sync_links "$dir"
  trust_space "$name"
  say "Made space '$name' at $dir"
  for abs in ${repos[@]+"${repos[@]}"}; do say "  added ${abs##*/}"; done
  say "Next:"
  [ "${#repos[@]}" -gt 0 ] || say "  entourage space add $name <path to a repo>"
  say "  fill in $dir/PROJECT.md"
  say "  entourage space open $name"
}

space_add() {
  local name=${1:-} path=${2:-} dir abs other
  dir=$(space_dir "$name")
  [ -n "$path" ] || die "which repo? Usage: entourage space add $name <path>"
  abs=$(repo_at "$path")
  while IFS= read -r other; do
    [ "$other" != "$abs" ] || die "$abs is already in space '$name'"
    [ "${other##*/}" != "${abs##*/}" ] ||
      die "space '$name' already has a repo called ${abs##*/} ($other); two repos in a space cannot share a folder name"
  done < <(space_repos "$dir")
  store_repo "$dir" "$abs"
  sync_links "$dir"
  say "Added ${abs##*/} to space '$name'"
  say "Describe what it owns in $dir/PROJECT.md"
}

# Show a space in Herdr, making Herdr's space for it if it is not open.
show_space() {
  local name=$1 dir=$2 id
  # Find an open Herdr space whose folder is this space's. `herdr-app ls`
  # prints indented JSON; a Herdr space's own "id" and "folder" are indented
  # six columns. Closed ones are listed after "recent" in the same shape, so
  # stop there.
  id=$(herdr_app ls 2>/dev/null | awk -v want="$dir" '
    /^  "recent"/       { exit }
    /^      "id": /     { id = $2; gsub(/[",]/, "", id) }
    /^      "folder": / { f = $0; sub(/^ *"folder": "/, "", f); sub(/",?$/, "", f)
                          if (f == want) { print id; exit } }') || true
  if [ -n "$id" ]; then
    herdr_app do space.select "{\"id\":\"$id\"}" >/dev/null 2>&1 ||
      die "could not show the space for '$name'. Is Herdr open?"
    say "Showing the space for '$name'"
  else
    herdr_app do space.new "{\"name\":\"$name\",\"folder\":\"$dir\"}" >/dev/null 2>&1 ||
      die "could not make a space for '$name'. Is Herdr open?"
    say "Opened a space for '$name' in $dir"
  fi
}

space_open() {
  local name=${1:-} dir
  dir=$(space_dir "$name")
  require_herdr
  sync_links "$dir"
  show_space "$name" "$dir"
}

# The same list for programs: one line of JSON, each space with its folder
# (as space_dir prints it) and its repos. The projects mod reads this.
space_ls_json() {
  local d repo sep='' rsep
  printf '{"projects":['
  for d in "$SPACES"/*/; do
    [ -d "$d" ] || continue
    d=${d%/}
    printf '%s{"name":"%s","folder":"%s","repos":[' "$sep" \
      "$(json_str "${d##*/}")" "$(json_str "$(cd -P "$d" && pwd)")"
    rsep=''
    while IFS= read -r repo; do
      printf '%s"%s"' "$rsep" "$(json_str "$repo")"
      rsep=,
    done < <(space_repos "$d")
    printf ']}'
    sep=,
  done
  printf ']}\n'
}

space_ls() {
  local d any=0 repo
  case ${1:-} in
    --json) space_ls_json; return ;;
    '') ;;
    *) die "unknown option for space ls: $1" ;;
  esac
  for d in "$SPACES"/*/; do
    [ -d "$d" ] || continue
    any=1
    d=${d%/}
    say "${d##*/}"
    while IFS= read -r repo; do say "  $repo"; done < <(space_repos "$d")
  done
  [ "$any" = 1 ] || say "No spaces yet. Make one with: entourage space new <name>"
}

# A team's key is what its cards' IDs start with: ABC for ABC-122.
TEAM_RE='^[A-Za-z][A-Za-z0-9]*$'

# Print a space's Linear teams, one key per line in upper case, each once,
# or nothing when it has none. The file is the human's to edit, so a # starts
# a comment anywhere on a line, and white space and blank lines are skipped.
# A line that is still not a team key stops it, naming the line, before
# anything is printed: a typo here would otherwise read as a team Linear does
# not have.
space_teams() {
  local dir=$1 line n=0 keys=''
  [ -f "$dir/teams" ] || return 0
  # Not read, it would pass for a space with no team.
  [ -r "$dir/teams" ] || die "cannot read $dir/teams. Check its owner and permissions, then run this again."
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    # The mark some editors put at the start of a file.
    line=${line#$'\357\273\277'}
    line=${line%%#*}
    line=${line#"${line%%[![:space:]]*}"}
    line=${line%"${line##*[![:space:]]}"}
    [ -n "$line" ] || continue
    [[ $line =~ $TEAM_RE ]] ||
      die "line $n of $dir/teams is '$line', which is not a Linear team key. A team's key is what its cards' IDs start with: ABC for ABC-122."
    keys+=$line$'\n'
  done < "$dir/teams"
  [ -n "$keys" ] || return 0
  printf '%s' "$keys" | tr '[:lower:]' '[:upper:]' | awk '!seen[$0]++'
}

# Set the Linear teams whose cards are a space's, or print them when no key
# is given. `task ls` lists those teams' cards. A space can name several
# teams, and several spaces can name the same team. The keys given replace
# the ones there. They are not checked with Linear here, so teams can be set
# with no network and before a Linear key is saved.
space_team() {
  local name=${1:-} dir key keys='' teams
  dir=$(space_dir "$name")
  shift
  if [ "$#" -eq 0 ]; then
    teams=$(space_teams "$dir") || exit 1
    [ -n "$teams" ] ||
      die "space '$name' has no Linear team. Set it with: entourage space team $name <team key>, like: entourage space team $name ABC"
    say "$teams"
    return
  fi
  # Every key is checked before the file is written, so a bad one does not
  # leave the space with only some of its teams.
  for key in "$@"; do
    [[ $key =~ $TEAM_RE ]] ||
      die "'$key' is not a Linear team key. A team's key is what its cards' IDs start with: ABC for ABC-122."
    key=$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')
    case $'\n'$keys in *$'\n'"$key"$'\n'*) continue ;; esac
    keys+=$key$'\n'
  done
  printf '%s' "$keys" > "$dir/teams"
  say "Space '$name' lists the cards of: $(printf '%s' "$keys" | tr '\n' ' ' | sed 's/ $//')"
}

# Print what is wrong with each space; return how many problems there are.
check_spaces() {
  local d repo problems=0 bad
  for d in "$SPACES"/*/; do
    [ -d "$d" ] || continue
    d=${d%/}
    bad=0
    if [ ! -f "$d/PROJECT.md" ]; then
      say "  problem    ${d##*/}: PROJECT.md is missing"; bad=$((bad + 1))
    elif grep -qF -- "$TEMPLATE_MARK" "$d/PROJECT.md"; then
      say "  problem    ${d##*/}: PROJECT.md is still the template; fill it in and delete its first line"; bad=$((bad + 1))
    fi
    while IFS= read -r repo; do
      is_repo "$repo" || { say "  problem    ${d##*/}: $repo is missing or is not a git repo"; bad=$((bad + 1)); }
    done < <(space_repos "$d")
    [ "$bad" -gt 0 ] || say "  ok         ${d##*/}"
    # Notes say what a repo does not provide. They are not problems: a task
    # in the space still starts, only without that step.
    if have_just; then
      while IFS= read -r repo; do
        is_repo "$repo" || continue
        case $(recipe_state "$repo" setup) in
          no-justfile) say "  note       ${d##*/}: ${repo##*/} has no justfile, so tasks start without setup" ;;
          no-recipe) say "  note       ${d##*/}: ${repo##*/}'s justfile has no setup recipe" ;;
          unreadable) say "  note       ${d##*/}: ${repo##*/}'s justfile could not be read by just" ;;
        esac
      done < <(space_repos "$d")
    fi
    problems=$((problems + bad))
  done
  return "$problems"
}

# `entourage project …` is the old name of `entourage space …`, and runs
# the same command. First it says so, in one line that names the space
# command to run instead. The line goes on stderr, so what the command prints
# on stdout, which a program may read, is the space command's.
old_project_name() {
  printf 'entourage: `project` is now `space`: run %s\n' "$(shell_words entourage space "$@")" >&2
}

cmd_space() {
  case ${1:-} in
    new) shift; space_new "$@" ;;
    add) shift; space_add "$@" ;;
    open) shift; space_open "$@" ;;
    ls | list) shift; space_ls "$@" ;;
    team) shift; space_team "$@" ;;
    *) die "usage: entourage space new|add|open|ls|team (see: entourage help)" ;;
  esac
}
