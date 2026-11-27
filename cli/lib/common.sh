# Helpers every part of the CLI uses. Sourced by cli/entourage.

# A git clone updates with `git pull`; an npm install updates through npm.
is_clone() { [ -e "$REPO/.git" ]; }

say() { printf '%s\n' "$*"; }
die() { printf 'entourage: %s\n' "$*" >&2; exit 1; }

herdr_app() {
  if command -v herdr-app >/dev/null 2>&1; then herdr-app "$@"
  elif [ -x "$BIN_DIR/herdr-app" ]; then "$BIN_DIR/herdr-app" "$@"
  else return 127
  fi
}

have_herdr() { command -v herdr-app >/dev/null 2>&1 || [ -x "$BIN_DIR/herdr-app" ]; }

# hc is the command for Herdr's terminals; it is installed beside herdr-app.
hc_cmd() {
  if command -v hc >/dev/null 2>&1; then hc "$@"
  elif [ -x "$BIN_DIR/hc" ]; then "$BIN_DIR/hc" "$@"
  else return 127
  fi
}

have_hc() { command -v hc >/dev/null 2>&1 || [ -x "$BIN_DIR/hc" ]; }

# Print a string quoted for a shell to read back as one word: it's -> 'it'\''s'.
# LC_ALL=C: sed must not give up on a name that is not valid text in this locale.
sh_quote() { printf "'%s'" "$(printf '%s' "$1" | LC_ALL=C sed "s/'/'\\\\''/g")"; }

# Herdr answers `status` with the layout it shows only while its window is open.
herdr_running() { herdr_app status 2>/dev/null | grep -q '"layout"'; }

require_herdr() {
  have_herdr || die "Herdr is not installed. Install it, open it once, then run this again:
  $HERDR_INSTALL"
  [ -d "$APP_HOME" ] || die "$APP_HOME does not exist yet. Open Herdr once so it creates its folder, then run this again."
}

# Print a string as the inside of a JSON string. sed and awk do the work so
# that the result does not depend on the bash version's quoting rules.
json_str() {
  printf '%s' "$1" | tr '\t\r' '  ' |
    sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' |
    awk 'BEGIN { ORS = "" } NR > 1 { print "\\n" } { print }'
}
