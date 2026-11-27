# Tests for what the skills and the task-new prompt must say the same way.
# No agent runs here: these only read the text. Sourced by test/run.sh.

# The skills for the steps of a card's lifecycle, each named sdlc-<step>: the
# three that write it up, then the one that builds it.
CARD_SKILL_NAMES='sdlc-define sdlc-plan sdlc-breakdown sdlc-build'

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
  for status in done needs-human answered failed; do
    case $section in
      *"\`$status\`"*) ;;
      *) fail "the handoff block section does not name the $status status" ;;
    esac
  done
}

each_skill_hands_off_as_itself() {
  local s
  for s in $CARD_SKILL_NAMES; do
    grep -A1 -F "entourage task handoff <project> <card ID> <<'EOF'" "$REPO/skills/$s/SKILL.md" |
      grep -qx "phase: ${s#sdlc-}" ||
      fail "$s does not show the command for handing off with phase: ${s#sdlc-}"
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

# Two real runs showed that an agent chaining skills writes no block between
# them, whatever the wording. So the hand-off is a command it runs.
handoffs_are_recorded_with_the_command() {
  local s
  case $(handoff_section sdlc-define) in
    *"entourage task handoff <project> <card ID> <<'EOF'"*) ;;
    *) fail "the handoff block section does not show the command to run" ;;
  esac
  # The quotes in <<'EOF' are what stop the shell running backticks and $()
  # in a value. Every place a skill shows the command has to keep them.
  for s in $CARD_SKILL_NAMES; do
    ! grep -F 'entourage task handoff <' "$REPO/skills/$s/SKILL.md" | grep -qv "<<'EOF'\$" ||
      fail "$s shows the command without the quoted <<'EOF'"
  done
  grep -qF 'entourage task handoff {project} {card}' "$REPO/prompts/task-new.md" ||
    fail "the task-new prompt does not name the command, with the project and card filled in"
}

# Waiting on the human can only be told from work if the agent says when the
# answer came.
the_answer_is_recorded_first() {
  case $(handoff_section sdlc-define) in
    *'record it before anything else'*'status: answered'*) ;;
    *) fail "the handoff block section does not say to record the answer first" ;;
  esac
  grep -qF 'record my answer' "$REPO/prompts/task-new.md" ||
    fail "the task-new prompt does not say to record the answer"
}

# The build commits on the task's branch and stops there. Review, pushing and
# the pull request come after it, so the human sees the work before anyone
# else does.
build_pushes_nothing() {
  local skill=$REPO/skills/sdlc-build/SKILL.md
  grep -qF 'Push nothing and open no pull request' "$skill" ||
    fail "sdlc-build does not say to push nothing and open no pull request"
}

# A build is done only when the tests pass, and review comes after it.
build_is_done_only_when_the_tests_pass() {
  local skill=$REPO/skills/sdlc-build/SKILL.md
  grep -A3 -F "entourage task handoff <project> <card ID> <<'EOF'" "$skill" | grep -qx 'next: review' ||
    fail "sdlc-build does not show its done hand-off with next: review"
  grep -qF 'only when the tests pass' "$skill" ||
    fail "sdlc-build does not say it is done only when the tests pass"
}

# A card with no Plan is not built. The skill says so in its first section,
# before any step that changes a file.
build_stops_on_a_card_with_no_plan() {
  local first
  first=$(awk '/^## / { if (on) exit; on = 1 } on' "$REPO/skills/sdlc-build/SKILL.md")
  case $first in
    '## Before you change anything'*) ;;
    *) fail "sdlc-build's first section is not 'Before you change anything'" ;;
  esac
  case $first in
    *'no Plan'*'`failed`'*) ;;
    *) fail "sdlc-build's first section does not hand a card with no Plan off as failed" ;;
  esac
}

CASES="skills_share_one_handoff_block handoff_block_names_every_status
  build_pushes_nothing build_is_done_only_when_the_tests_pass
  build_stops_on_a_card_with_no_plan
  the_answer_is_recorded_first
  handoffs_are_recorded_with_the_command
  each_skill_hands_off_as_itself no_skill_says_then_stop
  no_skill_names_a_person a_routed_change_returns_to_breakdown
  a_done_block_is_written_before_the_next_step
  task_new_prompt_follows_the_block"
