# The top-level commands: install, update, status. Sourced by cli/entourage.

cmd_install() {
  require_herdr
  CHANGED=0 SKIPPED=0
  say "Linking mods and layouts into $APP_HOME, skills into $SKILLS_HOME, and agent profiles into $AGENTS_HOME"
  link_all
  settings_init
  write_review_profiles

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

  say "Linking mods and layouts into $APP_HOME, skills into $SKILLS_HOME, and agent profiles into $AGENTS_HOME"
  link_all
  prune
  settings_init
  write_review_profiles

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
  say "Agents: $AGENTS_HOME"
  have_herdr || say "  Herdr is not installed ($HERDR_INSTALL)"
  local src dst s problems=0 settings_problems=0 unread=''
  while IFS=$'\t' read -r src dst; do
    s=$(state_of "$src" "$dst")
    [ "$s" = linked ] || problems=$((problems + 1))
    printf '  %-10s %s\n' "$s" "$(label "$dst")"
  done < <(wanted)
  # The settings file, which stops task new and task build when it is not
  # valid settings. Without it read, a review subagent entourage wrote cannot
  # be compared with what it would write now.
  if ! settings_load; then
    say "  problem    $SETTINGS_WHY"
    settings_problems=1 unread=1
  fi
  # The review subagents a clone writes, rather than links (settings.sh).
  if is_clone; then
    for src in "$REVIEW_SOURCES"/*.md; do
      [ -f "$src" ] || continue
      is_profile "$(review_profile_of "$src")" || continue
      dst=$AGENTS_HOME/${src##*/}
      s=$(review_state "$src" "$dst" "$unread")
      [ "$s" = written ] || problems=$((problems + 1))
      printf '  %-10s %s\n' "$s" "$(label "$dst")"
    done
  fi
  [ "$problems" = 0 ] || say "$problems not linked or not up to date. Run: entourage update"
  say "Spaces: $SPACES"
  local space_problems=0
  check_spaces || space_problems=$?
  # Only worth saying on a machine that has spaces to start tasks in.
  if ! have_just && [ -n "$(ls -d "$SPACES"/*/ 2>/dev/null)" ]; then
    say "  note       just is not installed, so tasks start without setup. Install it: https://just.systems"
  fi
  if ! have_sqlite && [ -n "$(ls -d "$SPACES"/*/ 2>/dev/null)" ]; then
    say "  note       $SQLITE is not installed, so hand-offs are not recorded."
  fi
  # The Linear key, asked of Linear itself. Only a key Linear rejects, or one
  # that is no key at all, is a problem. With none saved the rest of entourage
  # still works, and a key that could not be checked may work too.
  local key_problems=0 key_rc=0 key_out
  if [ -n "$KEY_EXPORTED" ]; then say "Linear key: LINEAR_API_KEY, exported in your environment"
  else say "Linear key: $ENV_FILE"
  fi
  key_out=$(linear_key_state 2>&1) || key_rc=$?
  case $key_rc in
    0) printf '  %-10s %s\n' works "the key of ${key_out:-a user with no name}" ;;
    1) key_out=${key_out#entourage: }
       printf '  %-10s %s\n' problem "${key_out%%$'\n'*}"
       key_problems=1 ;;
    2) printf '  %-10s %s\n' note "no Linear key is saved, and task ls and the Cards panel need one, as does task start unless it is given the card's type and title. Make one in $KEY_PLACE, then save it with: entourage linear key" ;;
    # Only the first sentence of why, as task new gives it: the rest of
    # linear_ask's message is advice for a command that stops.
    *) key_out=$(first_sentence "$key_out")
       printf '  %-10s %s\n' note "the key was not checked${key_out:+: $key_out}" ;;
  esac
  if [ "$problems" -gt 0 ] || [ "$space_problems" -gt 0 ] || [ "$settings_problems" -gt 0 ] ||
    [ "$key_problems" -gt 0 ]; then
    [ "$space_problems" = 0 ] || say "$space_problems space problem(s)."
    return 1
  fi
  say "Everything is in order."
}
