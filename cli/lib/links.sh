# Linking mods and layouts into Herdr. Sourced by cli/entourage.

# Every (source, destination) pair this repo wants linked, one per line,
# tab-separated.
wanted() {
  local m l
  for m in "$REPO"/herdr/mods/*/; do
    [ -d "$m" ] || continue
    m=${m%/}
    printf '%s\t%s\n' "$m" "$APP_HOME/mods/${m##*/}"
  done
  for l in "$REPO"/herdr/layouts/*.json; do
    [ -f "$l" ] || continue
    printf '%s\t%s\n' "$l" "$APP_HOME/layouts/${l##*/}"
  done
}

# linked | missing | elsewhere (a link to somewhere else) | blocked (a real file)
state_of() {
  local src=$1 dst=$2
  if [ -L "$dst" ]; then
    [ "$(readlink "$dst")" = "$src" ] && echo linked || echo elsewhere
  elif [ -e "$dst" ]; then echo blocked
  else echo missing
  fi
}

label() { local dst=$1; say "${dst#"$APP_HOME"/}"; }

# Link what is missing. Never touches a real file or someone else's link.
link_all() {
  local src dst added=0 skipped=0
  mkdir -p "$APP_HOME/mods" "$APP_HOME/layouts"
  while IFS=$'\t' read -r src dst; do
    case $(state_of "$src" "$dst") in
      linked) ;;
      missing) ln -s "$src" "$dst"; say "  linked   $(label "$dst")"; added=$((added + 1)) ;;
      elsewhere) say "  skipped  $(label "$dst") (already a link to $(readlink "$dst"))"; skipped=$((skipped + 1)) ;;
      blocked) say "  skipped  $(label "$dst") (a real file is in the way; move it aside to use ours)"; skipped=$((skipped + 1)) ;;
    esac
  done < <(wanted)
  [ "$added" -gt 0 ] || say "  nothing new to link"
  CHANGED=$((CHANGED + added))
  SKIPPED=$skipped
}

# Remove links that point into this repo at something that no longer exists
# (a mod or layout that was deleted or renamed upstream).
prune() {
  local dst target
  for dst in "$APP_HOME"/mods/* "$APP_HOME"/layouts/*; do
    [ -L "$dst" ] || continue
    target=$(readlink "$dst")
    case $target in "$REPO"/herdr/*) ;; *) continue ;; esac
    if [ ! -e "$target" ]; then
      rm "$dst"; say "  removed  $(label "$dst") (no longer in the repo)"
      CHANGED=$((CHANGED + 1))
    fi
  done
}

# Herdr does not notice edits made through a link. Switching to a shipped
# layout and back makes it re-read our layouts and mods.
refresh_herdr() {
  local current
  current=$(herdr_app status 2>/dev/null | sed -n 's/.*"layout": *"\([^"]*\)".*/\1/p' | head -n 1) || true
  if [ -z "$current" ]; then
    say "  Herdr is not running; it will pick everything up when it starts"
    return 0
  fi
  local other=main
  [ "$current" = main ] && other=terminals
  herdr_app do layout.switch "{\"name\":\"$other\"}" >/dev/null 2>&1 || true
  if herdr_app do layout.switch "{\"name\":\"$current\"}" >/dev/null 2>&1; then
    say "  refreshed Herdr (layout: $current)"
  else
    say "  could not switch Herdr back to '$current'; pick it from the Layout dropdown or press ctrl-shift-l"
  fi
}
