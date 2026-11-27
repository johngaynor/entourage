# Projects: groups of repos shown in Herdr as spaces. Sourced by cli/entourage.

# A project is a folder in $PROJECTS:
#   PROJECT.md   what the project is and what belongs in each repo
#   repos        one repo path per line (~/ for the home folder, # for comments)
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

project_new() {
  local name=${1:-} dir
  valid_name "$name" || die "a project name is lowercase letters, digits and dashes, like: my-project"
  dir=$PROJECTS/$name
  [ ! -e "$dir" ] || die "project '$name' already exists at $dir"
  [ -f "$TEMPLATE/PROJECT.md" ] || die "the project template is missing from $TEMPLATE"
  mkdir -p "$dir"
  sed "s/__NAME__/$name/" "$TEMPLATE/PROJECT.md" > "$dir/PROJECT.md"
  : > "$dir/repos"
  sync_links "$dir"
  # The real path, which is what Claude Code looks up; $dir may run through a link.
  trust_folder "$(project_dir "$name")"
  say "Made project '$name' at $dir"
  say "Next:"
  say "  entourage project add $name <path to a repo>"
  say "  fill in $dir/PROJECT.md"
  say "  entourage project open $name"
}

project_add() {
  local name=${1:-} path=${2:-} dir abs other stored
  dir=$(project_dir "$name")
  [ -n "$path" ] || die "which repo? Usage: entourage project add $name <path>"
  [ -d "$path" ] || die "$path is not a folder"
  abs=$(cd "$path" && pwd -P)
  is_repo "$abs" || die "$abs is not a git repo (the top folder of a clone is needed)"
  while IFS= read -r other; do
    [ "$other" != "$abs" ] || die "$abs is already in project '$name'"
    [ "${other##*/}" != "${abs##*/}" ] ||
      die "project '$name' already has a repo called ${abs##*/} ($other); two repos in a project cannot share a folder name"
  done < <(project_repos "$dir")
  case $abs in
    "$HOME"/*) stored="~/${abs#"$HOME"/}" ;;
    *) stored=$abs ;;
  esac
  printf '%s\n' "$stored" >> "$dir/repos"
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

project_ls() {
  local d any=0 repo
  for d in "$PROJECTS"/*/; do
    [ -d "$d" ] || continue
    any=1
    d=${d%/}
    say "${d##*/}"
    while IFS= read -r repo; do say "  $repo"; done < <(project_repos "$d")
  done
  [ "$any" = 1 ] || say "No projects yet. Make one with: entourage project new <name>"
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
    ls | list) shift; project_ls ;;
    *) die "usage: entourage project new|add|open|ls (see: entourage help)" ;;
  esac
}
