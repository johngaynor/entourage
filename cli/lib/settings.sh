# The model and effort each agent profile runs on, kept in entourage's
# settings file. Sourced by cli/entourage.

# The file is $SETTINGS, ~/.config/entourage/settings.json, beside the
# spaces. It is JSON, not lines of the env file: the Agent settings mod in
# Herdr reads and changes it through `entourage profile`, and the env file
# holds the Linear key.
#   {"profiles": {"write-up": {"model": "opus", "effort": "xhigh"}, ...}}
# `install` and `update` make it when it is missing, and never change one
# that is there. A profile or a value the file leaves out is the default.
#
# Each profile's values reach claude in their own way:
#   write-up, build     `task new` and `task build` start claude with
#                       --model= and --effort=, which beat the profile's own
#                       model and the human's own Claude Code settings
#   reviewer, verifier  written into the frontmatter of the entourage-reviewer
#                       and entourage-verifier subagents in $AGENTS_HOME, on a
#                       clone: a subagent runs on the model and effort its own
#                       file names (write_review_profiles below)

# The profiles, in the order they are listed.
PROFILES='write-up build reviewer verifier'
DEFAULT_MODEL=opus
DEFAULT_EFFORT=xhigh
# claude's aliases for a model, each the latest of its kind.
MODEL_ALIASES='fable opus sonnet haiku'
# A model's full name: claude-opus-5-5, or claude-opus-5-5[1m] for its long
# context. Every letter is spelled out, as in valid_group.
MODEL_RE='^claude-[abcdefghijklmnopqrstuvwxyz0123456789.-]+(\[1m\])?$'
EFFORTS='low medium high xhigh max'
# What each of them takes, for the messages that refuse a value.
TAKES_PROFILE='write-up, build, reviewer or verifier'
TAKES_MODEL='an alias (fable, opus, sonnet or haiku) or a full model name, like claude-opus-5-5'
TAKES_EFFORT='low, medium, high, xhigh or max'

# Whether a word is one of the words after it.
one_of() {
  local want=$1 w
  shift
  for w in "$@"; do [ "$w" != "$want" ] || return 0; done
  return 1
}
# shellcheck disable=SC2086
is_profile() { one_of "${1-}" $PROFILES; }
# shellcheck disable=SC2086
is_effort() { one_of "${1-}" $EFFORTS; }
# shellcheck disable=SC2086
is_model() { one_of "${1-}" $MODEL_ALIASES || [[ ${1-} =~ $MODEL_RE ]]; }

# A profile's place in PROFILES, from 0.
profile_index() {
  local p i=0
  for p in $PROFILES; do
    [ "$p" != "$1" ] || { printf '%s' "$i"; return 0; }
    i=$((i + 1))
  done
  return 1
}

# What starts on each profile.
profile_for() {
  case $1 in
    write-up) say "task new" ;;
    build) say "task build" ;;
    reviewer) say "the entourage-reviewer subagent" ;;
    verifier) say "the entourage-verifier subagent" ;;
  esac
}

# --- reading the file -------------------------------------------------------

# What settings_load read: each profile's model and effort, in the order of
# PROFILES, the default where the file names none. When the file cannot be
# read, SETTINGS_WHY says why, as a message that stops a command.
SET_MODELS=() SET_EFFORTS=() SETTINGS_WHY='' SETTINGS_LOADED=0

# Every value the file holds, read with jq: one line for each profile it
# names, holding the profile, what its value is, its model and its effort,
# each as JSON and separated by tabs, so that no text in the file can add a
# line or a field. A line starting with ! says what is wrong with the file as
# a whole. -s reads every value in the file, so that an empty file, or one
# with two values, is caught.
SETTINGS_JQ='
  if length == 0 then "!it is empty"
  elif length > 1 then "!it holds more than one JSON value"
  else .[0] |
    if type != "object" then "!it is not a JSON object"
    elif .profiles == null then empty
    elif (.profiles | type) != "object" then "!its \"profiles\" is not an object"
    else .profiles | to_entries[] |
      [(.key | tojson), (.value | type),
       (if (.value | type) == "object" then (.value.model | tojson), (.value.effort | tojson)
        else "null", "null" end)] | join("\t")
    end
  end'

# A JSON string's text, when it is a plain one; anything else as it is, so
# that it is refused and shown as the file has it.
json_plain() {
  case $1 in
    \"*\\*) printf '%s' "$1" ;;
    \"*\") local s=${1#\"}; printf '%s' "${s%\"}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# Read the settings file into SET_MODELS and SET_EFFORTS, or return 1 with
# SETTINGS_WHY saying what is wrong. With no file there is nothing to read,
# and no jq is needed.
settings_load() {
  local out name kind model effort p i why=''
  SET_MODELS=() SET_EFFORTS=() SETTINGS_WHY='' SETTINGS_LOADED=0
  for p in $PROFILES; do SET_MODELS+=("$DEFAULT_MODEL"); SET_EFFORTS+=("$DEFAULT_EFFORT"); done
  if [ ! -e "$SETTINGS" ] && [ ! -L "$SETTINGS" ]; then SETTINGS_LOADED=1; return 0; fi
  if [ ! -f "$SETTINGS" ]; then
    SETTINGS_WHY="$SETTINGS is not a file, and entourage reads each profile's model and effort from a file there. Move it aside, then run: entourage update"
    return 1
  fi
  if [ ! -r "$SETTINGS" ]; then
    SETTINGS_WHY="cannot read $SETTINGS, which holds each profile's model and effort. Check its owner and permissions, then run this again."
    return 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    SETTINGS_WHY="jq is not installed, so $SETTINGS, which holds each profile's model and effort, cannot be read. Install it, then run this again."
    return 1
  fi
  if ! out=$(jq -rs "$SETTINGS_JQ" "$SETTINGS" 2>&1); then
    why="it is not JSON ($(printf '%s' "$out" | head -n 1 | sed 's/^jq: //'))"
  else
    while IFS=$'\t' read -r name kind model effort; do
      [ -n "$name" ] || continue
      case $name in '!'*) why=${name#!}; break ;; esac
      p=$(json_plain "$name")
      if ! is_profile "$p"; then why="it names the profile $name, which is not one of $TAKES_PROFILE"; break; fi
      if [ "$kind" != object ]; then why="its profile $name is a $kind, not an object holding a model and an effort"; break; fi
      i=$(profile_index "$p")
      if [ "$model" != null ]; then
        if ! is_model "$(json_plain "$model")"; then why="the model of $p is $model, which is not $TAKES_MODEL"; break; fi
        SET_MODELS[$i]=$(json_plain "$model")
      fi
      if [ "$effort" != null ]; then
        if ! is_effort "$(json_plain "$effort")"; then why="the effort of $p is $effort, which is not $TAKES_EFFORT"; break; fi
        SET_EFFORTS[$i]=$(json_plain "$effort")
      fi
    done <<< "$out"
  fi
  if [ -n "$why" ]; then
    SETTINGS_WHY="$SETTINGS is not valid settings: $why. Fix that in the file, or move the file aside to go back to the defaults."
    return 1
  fi
  SETTINGS_LOADED=1
}

# Read the settings file, or stop, saying what is wrong with it.
settings_check() { settings_load || die "$SETTINGS_WHY"; }

# A profile's model and effort, the default where the file names none.
profile_model() {
  [ "$SETTINGS_LOADED" = 1 ] || settings_check
  printf '%s\n' "${SET_MODELS[$(profile_index "$1")]}"
}
profile_effort() {
  [ "$SETTINGS_LOADED" = 1 ] || settings_check
  printf '%s\n' "${SET_EFFORTS[$(profile_index "$1")]}"
}

# --- making and changing the file -------------------------------------------

# The file `install` and `update` make: every profile on the default model at
# the default effort.
settings_default() {
  local p sep=''
  printf '{\n  "profiles": {\n'
  for p in $PROFILES; do
    printf '%s    "%s": { "model": "%s", "effort": "%s" }' "$sep" "$p" "$DEFAULT_MODEL" "$DEFAULT_EFFORT"
    sep=$',\n'
  done
  printf '\n  }\n}\n'
}

# Make the settings file when there is none. One that is there is the
# human's, so it is never changed, even when it is not valid settings.
settings_init() {
  local tmp=$SETTINGS.entourage.$$
  [ ! -e "$SETTINGS" ] && [ ! -L "$SETTINGS" ] || return 0
  mkdir -p "${SETTINGS%/*}"
  if settings_default > "$tmp" && mv -f "$tmp" "$SETTINGS"; then
    say "  made     $SETTINGS (every profile on $DEFAULT_MODEL at $DEFAULT_EFFORT effort)"
  else
    rm -f "$tmp"
    say "  note     could not make $SETTINGS, so every profile runs on $DEFAULT_MODEL at $DEFAULT_EFFORT effort"
  fi
}

need_jq() {
  command -v jq >/dev/null 2>&1 ||
    die "jq is not installed, and entourage reads and changes $SETTINGS with it. Install it, then run this again."
}

# entourage profile ls [--json]: each profile's model and effort, and what
# starts on it. --json prints them as one line for programs, with the models
# and efforts there are to choose from; the Agent settings mod reads it.
profile_ls() {
  local json=0 p sep=''
  case ${1:-} in
    --json) json=1 ;;
    '') ;;
    *) die "unknown option for profile ls: $1" ;;
  esac
  [ "$#" -le 1 ] || die "usage: entourage profile ls [--json]"
  need_jq
  settings_check
  if [ "$json" = 0 ]; then
    for p in $PROFILES; do
      printf '%-9s %-8s %-7s %s\n' "$p" "$(profile_model "$p")" "$(profile_effort "$p")" "$(profile_for "$p")"
    done
    [ -e "$SETTINGS" ] || say "(no $SETTINGS, so these are the defaults; entourage update makes the file)"
    return
  fi
  printf '{"file":"%s","profiles":[' "$(json_str "$SETTINGS")"
  for p in $PROFILES; do
    printf '%s{"name":"%s","model":"%s","effort":"%s","for":"%s"}' "$sep" "$p" \
      "$(json_str "$(profile_model "$p")")" "$(profile_effort "$p")" "$(profile_for "$p")"
    sep=,
  done
  printf '],"models":['
  sep=''
  for p in $MODEL_ALIASES; do printf '%s"%s"' "$sep" "$p"; sep=,; done
  printf '],"efforts":['
  sep=''
  for p in $EFFORTS; do printf '%s"%s"' "$sep" "$p"; sep=,; done
  printf ']}\n'
}

# entourage profile set <profile> <model|effort> <value>: change one value in
# the settings file. Everything is checked before the file is touched, and the
# new file is checked before it takes the old one's place, so a refusal or a
# failure leaves the file as it was.
profile_set() {
  local p=${1:-} field=${2:-} value=${3:-} tmp ok=0
  [ "$#" -eq 3 ] ||
    die "usage: entourage profile set <profile> <model|effort> <value>, like: entourage profile set build effort high"
  is_profile "$p" || die "'$p' is not a profile. It takes $TAKES_PROFILE."
  case $field in
    model) is_model "$value" || die "'$value' is not a model. A model is $TAKES_MODEL." ;;
    effort) is_effort "$value" || die "'$value' is not an effort. An effort is $TAKES_EFFORT." ;;
    *) die "'$field' is not something a profile sets. It takes model or effort, like: entourage profile set $p effort high" ;;
  esac
  need_jq
  settings_check
  mkdir -p "${SETTINGS%/*}"
  tmp=$SETTINGS.entourage.$$
  # With no file yet, the new one starts from the defaults, so that it names
  # every profile.
  if { if [ -e "$SETTINGS" ]; then cat "$SETTINGS"; else settings_default; fi; } |
      jq --arg p "$p" --arg f "$field" --arg v "$value" '.profiles[$p][$f] = $v' > "$tmp" 2>/dev/null &&
    [ "$(SETTINGS=$tmp; settings_load && "profile_$field" "$p")" = "$value" ] &&
    mv -f "$tmp" "$SETTINGS"; then
    ok=1
  fi
  rm -f "$tmp"
  [ "$ok" = 1 ] || die "could not change $SETTINGS, so it is as it was."
  settings_check
  say "The $p profile's $field is $value now."
  case $p in
    write-up) say "The next entourage task new starts with it." ;;
    build) say "The next entourage task build starts with it." ;;
    *) if is_clone; then write_review_profiles "$p"
       else say "Only a clone of entourage has the review subagents, so nothing else was changed."
       fi ;;
  esac
}

# --- the review subagents ---------------------------------------------------

# The subagents for work on entourage itself, entourage-reviewer and
# entourage-verifier, are .claude/profiles/<name>.md in the repo. They are
# written into $AGENTS_HOME with the model and effort the settings file names,
# rather than linked as the other profiles are: a subagent runs on the model
# and effort of its own frontmatter, the Agent tool takes no effort, and the
# files in the repo are the same in every checkout and worktree. They are out
# of .claude/agents/, because Claude Code prefers the agent of the repo it
# runs in to a person's of the same name. Only a clone writes them, since only a clone
# works on entourage.
REVIEW_SOURCES=$REPO/.claude/profiles
# The comment that marks a file in $AGENTS_HOME as one entourage wrote,
# followed by the file it was written from. entourage replaces, and removes,
# only a file with this line in its frontmatter.
REVIEW_MARK='# Written by entourage from '

# The settings profile of a source: entourage-reviewer.md is the reviewer's.
review_profile_of() { local n=${1##*/}; n=${n%.md}; printf '%s' "${n#entourage-}"; }

# The text entourage writes for a source: the source, with model:, effort:
# and the mark after its tools: line, or at the end of its frontmatter.
#   $1 the source   $2 the model   $3 the effort
review_text() {
  SRC=$1 MODEL=$2 EFFORT=$3 MARK=$REVIEW_MARK P=$(review_profile_of "$1") awk '
    function extra() {
      print "model: " ENVIRON["MODEL"]
      print "effort: " ENVIRON["EFFORT"]
      print ENVIRON["MARK"] ENVIRON["SRC"]
      print "# Change its model and effort with: entourage profile set " ENVIRON["P"] " model|effort <value>"
      done = 1
    }
    NR == 1 { print; head = ($0 == "---"); next }
    head && $0 == "---" { if (!done) extra(); print; head = 0; next }
    head && /^(model|effort):/ { next }
    { print }
    head && !done && /^tools:/ { extra() }
  ' "$1"
}

# The source a file in $AGENTS_HOME says entourage wrote it from, or nothing
# when entourage did not write it: a link, or a file with no mark in its
# frontmatter, is someone else's.
review_source_of() {
  [ -f "$1" ] && [ ! -L "$1" ] || return 0
  MARK=$REVIEW_MARK awk '
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    index($0, ENVIRON["MARK"]) == 1 { print substr($0, length(ENVIRON["MARK"]) + 1); exit }
  ' "$1" 2>/dev/null || true
}

# written | stale | missing | skipped (someone else's file is there). With
# $3 set, the settings could not be read, so a file of entourage's is taken
# as written without comparing it.
review_state() {
  local src=$1 dst=$2 unread=${3:-} p
  if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then echo missing; return; fi
  [ -n "$(review_source_of "$dst")" ] || { echo skipped; return; }
  [ -z "$unread" ] || { echo written; return; }
  p=$(review_profile_of "$src")
  if [ "$(cat "$dst")" = "$(review_text "$src" "$(profile_model "$p")" "$(profile_effort "$p")")" ]; then
    echo written
  else
    echo stale
  fi
}

# Write each review subagent into $AGENTS_HOME, or only the profile named,
# where it is missing or stale, and remove one entourage wrote whose source
# is no longer in the repo. A file of someone else's is left alone. Nothing is
# written when the settings cannot be read, and none of it stops the command
# it is part of.
write_review_profiles() {
  local only=${1:-} src dst p model effort tmp from
  is_clone || return 0
  [ -d "$REVIEW_SOURCES" ] || [ -d "$AGENTS_HOME" ] || return 0
  if ! settings_load; then
    say "  skipped  the review subagents: $SETTINGS_WHY"
    return 0
  fi
  for src in "$REVIEW_SOURCES"/*.md; do
    [ -f "$src" ] || continue
    p=$(review_profile_of "$src")
    is_profile "$p" || continue
    [ -z "$only" ] || [ "$p" = "$only" ] || continue
    dst=$AGENTS_HOME/${src##*/}
    model=$(profile_model "$p") effort=$(profile_effort "$p")
    case $(review_state "$src" "$dst") in
      written) [ -z "$only" ] || say "  written  $(label "$dst") ($model, $effort effort)" ;;
      missing | stale)
        mkdir -p "$AGENTS_HOME"
        tmp=$dst.entourage.$$
        if review_text "$src" "$model" "$effort" > "$tmp" && mv -f "$tmp" "$dst"; then
          say "  wrote    $(label "$dst") ($model, $effort effort)"
        else
          rm -f "$tmp"
          say "  skipped  $(label "$dst") (it could not be written)"
        fi
        ;;
      skipped) say "  skipped  $(label "$dst") (a file of your own is there; move it aside to use entourage's)" ;;
    esac
  done
  [ -z "$only" ] || return 0
  for dst in "$AGENTS_HOME"/*.md; do
    from=$(review_source_of "$dst")
    case $from in "$REVIEW_SOURCES"/*) ;; *) continue ;; esac
    [ ! -e "$from" ] || continue
    rm -f "$dst"
    say "  removed  $(label "$dst") (no longer in the repo)"
  done
}

cmd_profile() {
  case ${1:-} in
    ls | list) shift; profile_ls "$@" ;;
    set) shift; profile_set "$@" ;;
    *) die "usage: entourage profile ls [--json], or: entourage profile set <profile> <model|effort> <value> (see: entourage help)" ;;
  esac
}
