# What a repo provides: recipes in a justfile at its root (https://just.systems).
# entourage knows recipes by name only, never what they do. This file is the
# only place that runs `just`.

have_just() { command -v just >/dev/null 2>&1; }

# Print the justfile at a folder's own root, or return 1 when it has none.
# `just` would also look in the folders above; a recipe from another project's
# justfile must never be run in a repo, so only the root counts.
root_justfile() {
  local dir=$1 name
  for name in justfile Justfile .justfile; do
    if [ -f "$dir/$name" ]; then printf '%s\n' "$dir/$name"; return 0; fi
  done
  return 1
}

# Print whether a folder provides a recipe, as one word:
#   ok           its justfile has the recipe
#   no-justfile  it has no justfile at its root
#   no-recipe    its justfile has no recipe of that name
#   unreadable   just could not read its justfile
recipe_state() {
  local dir=$1 recipe=$2 file names
  file=$(root_justfile "$dir") || { echo no-justfile; return 0; }
  # --summary prints the recipe names on one line, separated by spaces.
  names=$(just --justfile "$file" --summary 2>/dev/null) || { echo unreadable; return 0; }
  case " $(printf '%s' "$names" | tr '\n\t' '  ') " in
    *" $recipe "*) echo ok ;;
    *) echo no-recipe ;;
  esac
}
