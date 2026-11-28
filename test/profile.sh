# Tests for each agent profile's model and effort: the settings file and the
# `entourage profile` command (cli/lib/settings.sh), and the Agent settings
# button that shows and changes them in Herdr. Sourced by test/run.sh.

settings() { printf '%s' "$HOME/.config/entourage/settings.json"; }

# Every value in the settings file, one profile to a line: its name, model
# and effort.
all_values() {
  jq -r '.profiles | to_entries[] | "\(.key) \(.value.model) \(.value.effort)"' "$(settings)" 2>&1 | LC_ALL=C sort
}

# A settings file holding the JSON given.
settings_file() {
  mkdir -p "$HOME/.config/entourage"
  printf '%s\n' "$1" > "$(settings)"
}

# Run `profile set` with the arguments given, which it must refuse with a
# message holding $1, leaving the settings file byte for byte as it was.
refuses_set() {
  local want=$1 before out
  shift
  before=$(cksum < "$(settings)")
  if out=$("$E" profile set "$@" 2>&1); then fail "profile set $* exited zero: $out"; fi
  case $out in *"$want"*) ;; *) fail "profile set $* did not say it takes $want: $out" ;; esac
  [ "$(cksum < "$(settings)")" = "$before" ] || fail "profile set $* changed the file: $(cat "$(settings)")"
}

# --- showing them -----------------------------------------------------------

profile_ls_shows_each_profile() {
  "$E" install >/dev/null
  out=$("$E" profile ls) || fail "profile ls exited non-zero: $out"
  printf '%s\n' "$out" | grep -Eq '^write-up +opus +xhigh +task new$' || fail "no line for the write-up: $out"
  printf '%s\n' "$out" | grep -Eq '^build +opus +xhigh +task build$' || fail "no line for the build: $out"
  printf '%s\n' "$out" | grep -Eq '^reviewer +opus +xhigh +the entourage-reviewer subagent$' || fail "no line for the reviewer: $out"
  printf '%s\n' "$out" | grep -Eq '^verifier +opus +xhigh +the entourage-verifier subagent$' || fail "no line for the verifier: $out"
  [ "$(printf '%s\n' "$out" | grep -c '')" = 4 ] || fail "expected four lines: $out"
}

profile_ls_json_lists_profiles_models_and_efforts() {
  "$E" install >/dev/null
  out=$("$E" profile ls --json) || fail "profile ls --json exited non-zero: $out"
  [ "$(printf '%s\n' "$out" | grep -c '')" = 1 ] || fail "not one line: $out"
  printf '%s' "$out" | jq -e --arg f "$(settings)" '
    .file == $f
    and ([.profiles[] | .name] == ["write-up", "build", "reviewer", "verifier"])
    and ([.profiles[] | .model + " " + .effort] | unique == ["opus xhigh"])
    and ([.profiles[] | .for] == ["task new", "task build", "the entourage-reviewer subagent", "the entourage-verifier subagent"])
    and .models == ["fable", "opus", "sonnet", "haiku"]
    and .efforts == ["low", "medium", "high", "xhigh", "max"]' >/dev/null ||
    fail "the JSON does not list the profiles, models and efforts: $out"
}

# With no file, every profile is on the default, and the list says so.
profile_ls_defaults_with_no_file() {
  out=$("$E" profile ls) || fail "profile ls exited non-zero: $out"
  [ "$(printf '%s\n' "$out" | grep -Ec '^[a-z-]+ +opus +xhigh ')" = 4 ] || fail "not every profile is on opus at xhigh: $out"
  case $out in *"no $(settings)"*"entourage update"*) ;; *) fail "did not say there is no file: $out" ;; esac
  out=$("$E" profile ls --json) || fail "profile ls --json exited non-zero: $out"
  printf '%s' "$out" | jq -e '[.profiles[] | .model + " " + .effort] == ["opus xhigh", "opus xhigh", "opus xhigh", "opus xhigh"]' >/dev/null ||
    fail "the JSON does not give the defaults: $out"
  [ ! -e "$(settings)" ] || fail "profile ls made the file"
}

# A profile, or a value, the file leaves out is the default.
profile_ls_defaults_a_missing_field() {
  settings_file '{"profiles":{"build":{"effort":"high"},"reviewer":{"model":"sonnet"}}}'
  out=$("$E" profile ls) || fail "profile ls exited non-zero: $out"
  printf '%s\n' "$out" | grep -Eq '^build +opus +high ' || fail "the build is not on opus at high: $out"
  printf '%s\n' "$out" | grep -Eq '^reviewer +sonnet +xhigh ' || fail "the reviewer is not on sonnet at xhigh: $out"
  printf '%s\n' "$out" | grep -Eq '^write-up +opus +xhigh ' || fail "the write-up is not on the defaults: $out"
  printf '%s\n' "$out" | grep -Eq '^verifier +opus +xhigh ' || fail "the verifier is not on the defaults: $out"
  settings_file '{}'
  out=$("$E" profile ls) || fail "profile ls exited non-zero with {}: $out"
  [ "$(printf '%s\n' "$out" | grep -Ec '^[a-z-]+ +opus +xhigh ')" = 4 ] || fail "{} is not every profile on the defaults: $out"
}

# A file that is not valid settings stops it, saying what is wrong.
profile_ls_says_what_is_wrong_with_the_file() {
  local body want
  while IFS='|' read -r body want; do
    settings_file "$body"
    if out=$("$E" profile ls 2>&1); then fail "profile ls exited zero with the file '$body': $out"; continue; fi
    case $out in *"$(settings) is not valid settings: $want"*) ;; *) fail "the file '$body' did not give '$want': $out" ;; esac
  done <<'EOF'
not json|it is not JSON
[1, 2]|it is not a JSON object
{"profiles":[]}|its "profiles" is not an object
{"profiles":{"planner":{"model":"opus"}}}|it names the profile "planner", which is not one of write-up, build, reviewer or verifier
{"profiles":{"build":"opus"}}|its profile "build" is a string, not an object
{"profiles":{"build":{"model":"gpt-5"}}}|the model of build is "gpt-5", which is not an alias (fable, opus, sonnet or haiku) or a full model name
{"profiles":{"build":{"model":7}}}|the model of build is 7
{"profiles":{"build":{"effort":"extreme"}}}|the effort of build is "extreme", which is not low, medium, high, xhigh or max
{} {}|it holds more than one JSON value
EOF
  : > "$(settings)"
  out=$("$E" profile ls 2>&1) && fail "profile ls exited zero with an empty file"
  case $out in *"is not valid settings: it is empty"*) ;; *) fail "an empty file did not say so: $out" ;; esac
}

# --- changing them ----------------------------------------------------------

profile_set_changes_one_value() {
  "$E" install >/dev/null
  before=$(all_values)
  out=$("$E" profile set build effort high) || fail "profile set exited non-zero: $out"
  case $out in *"build"*"effort is high"*"task build"*) ;; *) fail "did not say what changed and what it reaches: $out" ;; esac
  want=$(printf '%s\n' "$before" | sed 's/^build opus xhigh$/build opus high/')
  [ "$(all_values)" = "$want" ] || fail "the file is not the build at high with the rest as it was: $(cat "$(settings)")"
  out=$("$E" profile ls)
  printf '%s\n' "$out" | grep -Eq '^build +opus +high +task build$' || fail "profile ls does not show the change: $out"
  "$E" profile set write-up model sonnet >/dev/null || fail "profile set of the write-up's model exited non-zero"
  out=$("$E" profile ls)
  printf '%s\n' "$out" | grep -Eq '^write-up +sonnet +xhigh ' || fail "profile ls does not show the write-up on sonnet: $out"
  printf '%s\n' "$out" | grep -Eq '^build +opus +high ' || fail "the second change undid the first: $out"
}

# With no file yet, the change makes one that names every profile.
profile_set_makes_a_missing_file() {
  "$E" profile set verifier effort low >/dev/null || fail "profile set exited non-zero with no file"
  [ "$(all_values)" = "$(printf '%s\n' 'build opus xhigh' 'reviewer opus xhigh' 'verifier opus low' 'write-up opus xhigh')" ] ||
    fail "the file made is not the defaults with the verifier at low: $(cat "$(settings)" 2>&1)"
}

profile_set_takes_a_full_model_name() {
  "$E" install >/dev/null
  local m
  for m in claude-opus-5-5 'claude-sonnet-5-5[1m]' claude-haiku-4.5-20251001 fable haiku; do
    "$E" profile set build model "$m" >/dev/null || fail "profile set refused the model $m"
    [ "$(jq -r '.profiles.build.model' "$(settings)")" = "$m" ] || fail "the file does not hold $m: $(cat "$(settings)")"
  done
  out=$("$E" profile ls --json)
  printf '%s' "$out" | jq -e '.profiles[1].model == "haiku"' >/dev/null || fail "profile ls --json does not show it: $out"
}

profile_set_refuses_an_unknown_effort() {
  "$E" install >/dev/null
  local e
  for e in extreme HIGH '' 'high ' 'low medium'; do refuses_set 'low, medium, high, xhigh or max' build effort "$e"; done
}

profile_set_refuses_an_unknown_model() {
  "$E" install >/dev/null
  local m
  for m in gpt-5 Opus claude- claude-Opus-5 'claude-opus-5-5[2m]' 'opus;rm' '' 'opus sonnet' ../opus; do
    refuses_set 'an alias (fable, opus, sonnet or haiku) or a full model name' build model "$m"
  done
}

profile_set_refuses_an_unknown_profile() {
  "$E" install >/dev/null
  local p
  for p in planner Build '' 'write-up build' entourage-build; do
    refuses_set 'write-up, build, reviewer or verifier' "$p" effort high
  done
  refuses_set 'model or effort' build temperature high
  refuses_set 'usage: entourage profile set' build effort
  refuses_set 'usage: entourage profile set' build effort high extra
}

# A broken file is not mended by a change on top of it.
profile_set_refuses_a_broken_file() {
  settings_file '{"profiles":{"planner":{}}}'
  refuses_set 'it names the profile "planner"' build effort high
}

# On a clone, a change to the reviewer's or the verifier's writes its file
# again, and leaves the other one as it was.
profile_set_rewrites_the_reviewer() {
  "$E" install >/dev/null
  local ag=$HOME/.claude/agents verifier
  verifier=$(cat "$ag/entourage-verifier.md")
  out=$("$E" profile set reviewer model sonnet) || fail "profile set exited non-zero: $out"
  grep -qx 'model: sonnet' "$ag/entourage-reviewer.md" || fail "the reviewer is not on sonnet: $(cat "$ag/entourage-reviewer.md")"
  grep -qx 'effort: xhigh' "$ag/entourage-reviewer.md" || fail "the reviewer's effort changed: $(cat "$ag/entourage-reviewer.md")"
  [ "$(cat "$ag/entourage-verifier.md")" = "$verifier" ] || fail "the verifier was changed"
  case $out in *"wrote    agents/entourage-reviewer.md (sonnet, xhigh effort)"*) ;; *) fail "did not say it wrote the reviewer: $out" ;; esac
  "$E" profile set verifier effort max >/dev/null || fail "profile set of the verifier exited non-zero"
  grep -qx 'effort: max' "$ag/entourage-verifier.md" || fail "the verifier is not at max: $(cat "$ag/entourage-verifier.md")"
  "$E" status >/dev/null || fail "status exited non-zero after the changes"
}

profile_needs_jq() {
  "$E" install >/dev/null
  hide_jq
  out=$("$E" profile ls 2>&1) && fail "profile ls exited zero without jq: $out"
  case $out in *"jq is not installed"*) ;; *) fail "did not say jq is missing: $out" ;; esac
  refuses_set 'jq is not installed' build effort high
}

# --- in Herdr ---------------------------------------------------------------

# Both layouts put the Agent settings button at the right end of the tab bar:
# the tab bar's block becomes a row of the tabs, which take the room and drag
# the window as before, and the button.
layouts_place_agent_settings() {
  local l f
  for l in default test; do
    f=$ROOT/herdr/layouts/$l.json
    jq -e '
      def nodes: ., (.children[]? | nodes);
      [nodes | select(.type == "row" and ([.children[]? | .content.mod] == ["tabs", "agent-settings"]))] as $rows
      | ($rows | length) == 1
        and $rows[0].size.px == 42
        and $rows[0].resizable == false
        and ($rows[0].children[0] | .id == "tabs" and .size.weight == 1 and .window_drag == true)
        and ($rows[0].children[1] | .id == "agent-settings" and .type == "block" and (.size.px > 0))
        and ([nodes | select(.content.mod? == "tabs" or .content.mod? == "agent-settings")] | length) == 2' \
      "$f" >/dev/null || fail "$l.json does not put agent-settings beside tabs in a 42px row"
  done
  jq -e '.place == "none" and .title == "Agent settings"' "$ROOT/herdr/mods/agent-settings/mod.json" >/dev/null 2>&1 ||
    fail "herdr/mods/agent-settings/mod.json is not placed by the layouts alone: $(cat "$ROOT/herdr/mods/agent-settings/mod.json" 2>&1)"
  [ -f "$ROOT/herdr/mods/agent-settings/main.js" ] || fail "there is no herdr/mods/agent-settings/main.js"
}

# The mod holds no rules: it reads what entourage lists, choices included,
# and changes a value with entourage.
agent_settings_mod_asks_entourage() {
  local f=$ROOT/herdr/mods/agent-settings/main.js want
  [ -f "$f" ] || { fail "there is no herdr/mods/agent-settings/main.js"; return; }
  for want in '"profile", "ls", "--json"' '"profile", "set"' '.models' '.efforts'; do
    grep -qF -- "$want" "$f" || fail "main.js does not use $want"
  done
  # Its code, without comments or the sample `herdr-app check` draws.
  local code
  code=$(awk '/^const SAMPLE = /{ skip = 1 } !skip && !/^ *\/\//{ print } skip && /^};/{ skip = 0 }' "$f")
  for want in '"xhigh"' '"opus"' '"write-up"' 'claude-'; do
    case $code in *"$want"*) fail "main.js names $want outside its sample: that is entourage's to say" ;; esac
  done
}

CASES="profile_ls_shows_each_profile profile_ls_json_lists_profiles_models_and_efforts
  profile_ls_defaults_with_no_file profile_ls_defaults_a_missing_field
  profile_ls_says_what_is_wrong_with_the_file
  profile_set_changes_one_value profile_set_makes_a_missing_file profile_set_takes_a_full_model_name
  profile_set_refuses_an_unknown_effort profile_set_refuses_an_unknown_model
  profile_set_refuses_an_unknown_profile profile_set_refuses_a_broken_file profile_needs_jq
  profile_set_rewrites_the_reviewer layouts_place_agent_settings agent_settings_mod_asks_entourage"
