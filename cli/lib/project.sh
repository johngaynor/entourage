# Projects: groups of repos shown in Herdr as spaces. Sourced by cli/entourage.

# A project is a folder in $PROJECTS:
#   PROJECT.md   what the project is and what belongs in each repo
#   repos        one repo path per line (~/ for the home folder, # for comments)
#   teams        the keys of the project's Linear teams, like ABC, one per line
#   links/       generated: a link to each repo, named after its folder
#   CLAUDE.md, AGENTS.md   generated: links to PROJECT.md, so agents read it

valid_name() { case ${1:-} in '' | *[!a-z0-9-]*) return 1 ;; esac; }

# Print a project's folder, or stop if there is no such project.
project_dir() {
  local name=${1:-}
  [ -n "$name" ] || die "which project? See: entourage project ls"
  valid_name "$name" && [ -d "$PROJECTS/$name" ] ||
    die "no project called '$name'. Make it with: entourage project new $name"
  (cd -P "$PROJECTS/$name" && pwd)
}

# Mark a project's folder as trusted by Claude Code (see trust.sh), when
# entourage made it: a folder of its own in $PROJECTS. A project name that is
# a link leads to a folder someone else made, perhaps a repo, and entourage
# does not answer for that. Claude Code asks about it itself, once.
trust_project() {
  local name=$1
  [ ! -L "$PROJECTS/$name" ] || return 0
  # The real path, which is what Claude Code looks up: $PROJECTS may run
  # through a link.
  trust_folder "$(project_dir "$name")"
}

# Print a project's repo paths, absolute, one per line.
project_repos() {
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

# Rebuild what is generated in a project folder. Only links are ever removed
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
  done < <(project_repos "$dir")
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

# Add a line for a repo to a project's repos file, with ~/ for the home folder.
store_repo() {
  local dir=$1 abs=$2
  case $abs in
    "$HOME"/*) abs="~/${abs#"$HOME"/}" ;;
  esac
  printf '%s\n' "$abs" >> "$dir/repos"
}

# With repo paths after the name, the project starts with those repos. The
# projects mod makes a project this way, in one command.
project_new() {
  local name=${1:-} dir path abs other
  local -a repos=()
  valid_name "$name" || die "a project name is lowercase letters, digits and dashes, like: my-project"
  dir=$PROJECTS/$name
  [ ! -e "$dir" ] || die "project '$name' already exists at $dir"
  [ -f "$TEMPLATE/PROJECT.md" ] || die "the project template is missing from $TEMPLATE"
  shift
  # Every repo is checked before anything is made, so that a bad one does not
  # leave a project behind with only some of them.
  for path in "$@"; do
    abs=$(repo_at "$path")
    for other in ${repos[@]+"${repos[@]}"}; do
      [ "$other" != "$abs" ] || die "$abs is listed twice"
      [ "${other##*/}" != "${abs##*/}" ] ||
        die "$other and $abs are both called ${abs##*/}; two repos in a project cannot share a folder name"
    done
    repos+=("$abs")
  done
  mkdir -p "$dir"
  sed "s/__NAME__/$name/" "$TEMPLATE/PROJECT.md" > "$dir/PROJECT.md"
  : > "$dir/repos"
  for abs in ${repos[@]+"${repos[@]}"}; do store_repo "$dir" "$abs"; done
  sync_links "$dir"
  trust_project "$name"
  say "Made project '$name' at $dir"
  for abs in ${repos[@]+"${repos[@]}"}; do say "  added ${abs##*/}"; done
  say "Next:"
  [ "${#repos[@]}" -gt 0 ] || say "  entourage project add $name <path to a repo>"
  say "  fill in $dir/PROJECT.md"
  say "  entourage project open $name"
}

project_add() {
  local name=${1:-} path=${2:-} dir abs other
  dir=$(project_dir "$name")
  [ -n "$path" ] || die "which repo? Usage: entourage project add $name <path>"
  abs=$(repo_at "$path")
  while IFS= read -r other; do
    [ "$other" != "$abs" ] || die "$abs is already in project '$name'"
    [ "${other##*/}" != "${abs##*/}" ] ||
      die "project '$name' already has a repo called ${abs##*/} ($other); two repos in a project cannot share a folder name"
  done < <(project_repos "$dir")
  store_repo "$dir" "$abs"
  sync_links "$dir"
  say "Added ${abs##*/} to project '$name'"
  say "Describe what it owns in $dir/PROJECT.md"
}

# Show the Herdr space for a project, making it if it is not open.
show_space() {
  local name=$1 dir=$2 id
  # Find an open space whose folder is this project's. `herdr-app ls` prints
  # indented JSON; a space's own "id" and "folder" sit at six spaces. Closed
  # spaces are listed after "recent" in the same shape, so stop there.
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

project_open() {
  local name=${1:-} dir
  dir=$(project_dir "$name")
  require_herdr
  sync_links "$dir"
  show_space "$name" "$dir"
}

# The same list for programs: one line of JSON, each project with its folder
# (as project_dir prints it) and its repos. The projects mod reads this.
project_ls_json() {
  local d repo sep='' rsep
  printf '{"projects":['
  for d in "$PROJECTS"/*/; do
    [ -d "$d" ] || continue
    d=${d%/}
    printf '%s{"name":"%s","folder":"%s","repos":[' "$sep" \
      "$(json_str "${d##*/}")" "$(json_str "$(cd -P "$d" && pwd)")"
    rsep=''
    while IFS= read -r repo; do
      printf '%s"%s"' "$rsep" "$(json_str "$repo")"
      rsep=,
    done < <(project_repos "$d")
    printf ']}'
    sep=,
  done
  printf ']}\n'
}

project_ls() {
  local d any=0 repo
  case ${1:-} in
    --json) project_ls_json; return ;;
    '') ;;
    *) die "unknown option for project ls: $1" ;;
  esac
  for d in "$PROJECTS"/*/; do
    [ -d "$d" ] || continue
    any=1
    d=${d%/}
    say "${d##*/}"
    while IFS= read -r repo; do say "  $repo"; done < <(project_repos "$d")
  done
  [ "$any" = 1 ] || say "No projects yet. Make one with: entourage project new <name>"
}

# A team's key is what its cards' IDs start with: ABC for ABC-122.
TEAM_RE='^[A-Za-z][A-Za-z0-9]*$'

# Print a project's Linear teams, one key per line in upper case, each once,
# or nothing when it has none. The file is the human's to edit, so a # starts
# a comment anywhere on a line, and spaces and blank lines are skipped. A line
# that is still not a team key stops it, naming the line, before anything is
# printed: a typo here would otherwise read as a team Linear does not have.
project_teams() {
  local dir=$1 line n=0 keys=''
  [ -f "$dir/teams" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
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

# Set the Linear teams whose cards are a project's, or print them when no key
# is given. `task ls` lists those teams' cards. A project can name several
# teams, and several projects can name the same team. The keys given replace
# the ones there. They are not checked with Linear here, so teams can be set
# with no network and before a Linear key is saved.
project_team() {
  local name=${1:-} dir key keys='' teams
  dir=$(project_dir "$name")
  shift
  if [ "$#" -eq 0 ]; then
    teams=$(project_teams "$dir") || exit 1
    [ -n "$teams" ] ||
      die "project '$name' has no Linear team. Set it with: entourage project team $name <team key>, like: entourage project team $name ABC"
    say "$teams"
    return
  fi
  # Every key is checked before the file is written, so a bad one does not
  # leave the project with only some of its teams.
  for key in "$@"; do
    [[ $key =~ $TEAM_RE ]] ||
      die "'$key' is not a Linear team key. A team's key is what its cards' IDs start with: ABC for ABC-122."
    key=$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')
    case $'\n'$keys in *$'\n'"$key"$'\n'*) continue ;; esac
    keys+=$key$'\n'
  done
  printf '%s' "$keys" > "$dir/teams"
  say "Project '$name' lists the cards of: $(printf '%s' "$keys" | tr '\n' ' ' | sed 's/ $//')"
}

# Print what is wrong with each project; return how many problems there are.
check_projects() {
  local d repo problems=0 bad
  for d in "$PROJECTS"/*/; do
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
    done < <(project_repos "$d")
    [ "$bad" -gt 0 ] || say "  ok         ${d##*/}"
    # Notes say what a repo does not provide. They are not problems: a task
    # in the project still starts, only without that step.
    if have_just; then
      while IFS= read -r repo; do
        is_repo "$repo" || continue
        case $(recipe_state "$repo" setup) in
          no-justfile) say "  note       ${d##*/}: ${repo##*/} has no justfile, so tasks start without setup" ;;
          no-recipe) say "  note       ${d##*/}: ${repo##*/}'s justfile has no setup recipe" ;;
          unreadable) say "  note       ${d##*/}: ${repo##*/}'s justfile could not be read by just" ;;
        esac
      done < <(project_repos "$d")
    fi
    problems=$((problems + bad))
  done
  return "$problems"
}

cmd_project() {
  case ${1:-} in
    new) shift; project_new "$@" ;;
    add) shift; project_add "$@" ;;
    open) shift; project_open "$@" ;;
    ls | list) shift; project_ls "$@" ;;
    team) shift; project_team "$@" ;;
    *) die "usage: entourage project new|add|open|ls|team (see: entourage help)" ;;
  esac
}
