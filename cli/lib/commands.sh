# The top-level commands: install, update, status. Sourced by cli/entourage.

cmd_install() {
  require_herdr
  CHANGED=0 SKIPPED=0
  say "Linking mods and layouts into $APP_HOME, and skills into $SKILLS_HOME"
  link_all

  # npm already put the command on PATH; a clone has to do it itself.
  if is_clone; then
    say "Putting entourage on your PATH"
    mkdir -p "$BIN_DIR"
    local me=$REPO/cli/entourage dst=$BIN_DIR/entourage
    case $(state_of "$me" "$dst") in
      linked) say "  already at $dst" ;;
      missing) ln -s "$me" "$dst"; say "  linked   $dst" ;;
      *) say "  skipped  $dst (something else is already there)" ;;
    esac
    case ":$PATH:" in
      *":$BIN_DIR:"*) ;;
      *) say "  note: $BIN_DIR is not on your PATH; add it to run 'entourage' from anywhere" ;;
    esac
  fi

  say "Refreshing Herdr"
  refresh_herdr
  say "Done. Pick a layout from the Layout dropdown, or press ctrl-shift-l."
}

cmd_update() {
  local pull=1
  case ${1:-} in
    --no-pull) pull=0 ;;
    '') ;;
    *) die "unknown option for update: $1" ;;
  esac
  require_herdr
  CHANGED=0 SKIPPED=0
  local before=none after=none
  if [ "$pull" = 1 ] && ! is_clone; then
    # Installed by npm: reinstall, then hand over to the new copy to relink.
    command -v npm >/dev/null 2>&1 || die "npm is needed to update this install, and it is not on your PATH."
    say "Updating entourage with npm ($NPM_SPEC)"
    npm install -g "$NPM_SPEC" || die "npm install failed; nothing was changed in Herdr."
    exec entourage update --no-pull
  fi
  if is_clone; then before=$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo none); fi
  if [ "$pull" = 1 ]; then
    say "Pulling $REPO"
    git -C "$REPO" pull --ff-only || die "git pull failed; fix that in $REPO and run update again."
  fi
  if is_clone; then after=$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo none); fi

  say "Linking mods and layouts into $APP_HOME, and skills into $SKILLS_HOME"
  link_all
  prune

  say "Refreshing Herdr"
  if [ "$before" != "$after" ] || [ "$CHANGED" -gt 0 ] || [ "$pull" = 0 ]; then
    refresh_herdr
  else
    say "  nothing changed"
  fi
}

cmd_status() {
  say "Repo:  $REPO"
  say "Herdr: $APP_HOME"
  say "Skills: $SKILLS_HOME"
  have_herdr || say "  Herdr is not installed ($HERDR_INSTALL)"
  local src dst s problems=0
  while IFS=$'\t' read -r src dst; do
    s=$(state_of "$src" "$dst")
    [ "$s" = linked ] || problems=$((problems + 1))
    printf '  %-10s %s\n' "$s" "$(label "$dst")"
  done < <(wanted)
  [ "$problems" = 0 ] || say "$problems not linked. Run: entourage update"
  say "Projects: $PROJECTS"
  local project_problems=0
  check_projects || project_problems=$?
  # Only worth saying on a machine that has projects to start tasks in.
  if ! have_just && [ -n "$(ls -d "$PROJECTS"/*/ 2>/dev/null)" ]; then
    say "  note       just is not installed, so tasks start without setup. Install it: https://just.systems"
  fi
  if ! have_sqlite && [ -n "$(ls -d "$PROJECTS"/*/ 2>/dev/null)" ]; then
    say "  note       $SQLITE is not installed, so hand-offs are not recorded."
  fi
  if [ "$problems" -gt 0 ] || [ "$project_problems" -gt 0 ]; then
    [ "$project_problems" = 0 ] || say "$project_problems project problem(s)."
    return 1
  fi
  say "Everything is in order."
}
