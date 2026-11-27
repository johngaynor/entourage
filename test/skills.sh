# Tests for what the skills and the task-new prompt must say the same way.
# No agent runs here: these only read the text. Sourced by test/run.sh.

# The skills that write a card up, each named sdlc-<step>.
CARD_SKILL_NAMES='sdlc-define sdlc-plan sdlc-breakdown'

# Print a skill's "The handoff block" section: its heading and everything up
# to the next second-level heading.
handoff_section() {
  awk '/^## The handoff block$/ { on = 1; print; next } on && /^## / { exit } on' \
    "$REPO/skills/$1/SKILL.md"
}

skills_share_one_handoff_block() {
  local first s
  first=$(handoff_section sdlc-define)
  [ -n "$first" ] || fail "sdlc-define has no 'The handoff block' section"
  for s in $CARD_SKILL_NAMES; do
    [ "$(handoff_section "$s")" = "$first" ] ||
      fail "the handoff block section in $s differs from the one in sdlc-define"
  done
}

handoff_block_names_every_status() {
  local section status
  section=$(handoff_section sdlc-define)
  for status in done needs-human failed; do
    case $section in
      *"\`$status\`"*) ;;
      *) fail "the handoff block section does not name the $status status" ;;
    esac
  done
}

each_skill_hands_off_as_itself() {
  local s
  for s in $CARD_SKILL_NAMES; do
    grep -q "^- \`phase: ${s#sdlc-}\`" "$REPO/skills/$s/SKILL.md" ||
      fail "$s does not say to hand off with phase: ${s#sdlc-}"
  done
}

# "Then stop" is how a skill used to end. It contradicts the block's own rule
# about going on to the next step, so the prompt had to tell agents to ignore it.
no_skill_says_then_stop() {
  local s
  for s in $CARD_SKILL_NAMES; do
    ! grep -q 'Then stop' "$REPO/skills/$s/SKILL.md" ||
      fail "$s still says 'Then stop'"
  done
}

task_new_prompt_follows_the_block() {
  local prompt=$REPO/prompts/task-new.md want
  for want in '`done`' '`needs-human`' '`failed`' 'next: setup' '{card}' '{project}'; do
    grep -qF -- "$want" "$prompt" || fail "the task-new prompt does not mention $want"
  done
}

# The skills ship to everyone who installs entourage, so they name no one.
# They say "the human".
no_skill_names_a_person() {
  local s
  for s in $CARD_SKILL_NAMES; do
    ! grep -qw 'John' "$REPO/skills/$s/SKILL.md" ||
      fail "$s names John; say 'the human'"
  done
}

# When the human asks for a change at approval, breakdown sends the agent to
# sdlc-define or sdlc-plan. That skill's `done` block names its own next step,
# which is wrong there: the agent has to come back to breakdown.
a_routed_change_returns_to_breakdown() {
  case $(handoff_section sdlc-define) in
    *"go back to that step"*) ;;
    *) fail "the handoff block section does not send a revising skill back to the step that called it" ;;
  esac
  grep -qF 'does not apply here' "$REPO/skills/sdlc-breakdown/SKILL.md" ||
    fail "sdlc-breakdown does not say the routed skill's next does not apply"
  grep -qF 'go back to sdlc-breakdown' "$REPO/prompts/task-new.md" ||
    fail "the task-new prompt does not send a routed change back to sdlc-breakdown"
}

# On the first real card the agent ran define and plan with no block between
# them: the skills asked for one "every time you stop", and under task new it
# does not stop between skills. The block marks the step ending, stop or not.
a_done_block_is_written_before_the_next_step() {
  case $(handoff_section sdlc-define) in
    *"even when you go straight on to another step"*) ;;
    *) fail "the handoff block section does not ask for a block when the agent carries straight on" ;;
  esac
  grep -qF 'before you start the next skill' "$REPO/prompts/task-new.md" ||
    fail "the task-new prompt does not ask for each block before the next skill starts"
}

CASES="skills_share_one_handoff_block handoff_block_names_every_status
  each_skill_hands_off_as_itself no_skill_says_then_stop
  no_skill_names_a_person a_routed_change_returns_to_breakdown
  a_done_block_is_written_before_the_next_step
  task_new_prompt_follows_the_block"
