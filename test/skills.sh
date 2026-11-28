# Tests for what the skills and the prompts must say the same way.
# No agent runs here: these only read the text. Sourced by test/run.sh.

# The skills for the steps of a card's lifecycle, each named sdlc-<step>: the
# three that write it up, then the one that builds it and the one that reviews
# the build.
CARD_SKILL_NAMES='sdlc-define sdlc-plan sdlc-breakdown sdlc-build sdlc-review'

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

# task start takes the card, and names the branch from it. The command the
# human is given after approval is the card's, not a branch put together.
task_new_prompt_gives_task_start_the_card() {
  local prompt=$REPO/prompts/task-new.md
  grep -qF 'entourage task start {project} {card}' "$prompt" ||
    fail "the task-new prompt does not give: entourage task start {project} {card}"
  ! grep -q '<type>/' "$prompt" ||
    fail "the task-new prompt still has the agent put a branch together"
}

task_new_prompt_follows_the_block() {
  local prompt=$REPO/prompts/task-new.md want
  for want in '`done`' '`needs-human`' '`failed`' 'next: setup' '{card}' '{project}'; do
    grep -qF -- "$want" "$prompt" || fail "the task-new prompt does not mention $want"
  done
}

# The build's agent starts from prompts/task-build.md, which drives build and
# review as task-new.md drives the write-up, and ends the run where the pull
# request would begin.
task_build_prompt_drives_build_and_review() {
  local prompt=$REPO/prompts/task-build.md want
  for want in 'Start with the sdlc-build skill' '`review` is the sdlc-review skill' \
      '`build` is the sdlc-build skill' 'next: pr' '`done`' '`needs-human`' '`failed`' \
      '{card}' '{project}' 'entourage task handoff {project} {card}' 'record my answer'; do
    grep -qF -- "$want" "$prompt" || fail "the task-build prompt does not mention $want"
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

# A new task's worktree may have nothing installed, so the build installs what
# the tests need, the way the repo's own docs say, before it first runs them.
# It installs only, and starts nothing that would outlive the build.
build_installs_what_the_tests_need_first() {
  local skill=$REPO/skills/sdlc-build/SKILL.md install first_run
  install=$(grep -niF "install what the tests need the way the repo's docs say" "$skill" | head -n1 | cut -d: -f1)
  first_run=$(grep -niF 'run the tests once, before you change anything' "$skill" | head -n1 | cut -d: -f1)
  grep -qF 'Install only: start no app, dev server or database' "$skill" ||
    fail "sdlc-build does not say to install only, starting no app, dev server or database"
  if [ -z "$install" ]; then
    fail "sdlc-build does not say to install what the tests need the way the repo's docs say"
  elif [ -z "$first_run" ]; then
    fail "sdlc-build does not run the tests once before it changes anything"
  elif [ "$install" -ge "$first_run" ]; then
    fail "sdlc-build runs the tests before it installs what they need"
  fi
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

# When the review sends the work back, build takes it as a later round: only
# what the Review names, on top of the commits already there.
build_takes_a_later_round_from_the_review() {
  local skill=$REPO/skills/sdlc-build/SKILL.md
  grep -qF 'later round' "$skill" || fail "sdlc-build does not say how it takes a later round"
  grep -qF 'on top of the commits already there' "$skill" ||
    fail "sdlc-build does not build a later round on top of the commits already there"
  grep -qF 'is the work, not a reason to ask' "$skill" ||
    fail "sdlc-build would ask about a test the Review names as failing"
  ! grep -qF 'Review is not a skill yet' "$skill" ||
    fail "sdlc-build still says review is not a skill"
}

# The review checks the build before anything is pushed. It changes no code:
# what falls short goes back to build, and pushing and the pull request come
# after it.
review_pushes_nothing() {
  local skill=$REPO/skills/sdlc-review/SKILL.md
  grep -qF 'Push nothing and open no pull request' "$skill" ||
    fail "sdlc-review does not say to push nothing and open no pull request"
  grep -qF 'changes no code' "$skill" || fail "sdlc-review does not say it changes no code"
}

# A review that finds every Done when item met hands on to the pull request.
# One that finds an item not met, or the tests failing, sends the work back to
# build.
review_sends_what_is_not_met_back_to_build() {
  local skill=$REPO/skills/sdlc-review/SKILL.md next
  for next in pr build; do
    grep -A3 -F "entourage task handoff <project> <card ID> <<'EOF'" "$skill" | grep -qx "next: $next" ||
      fail "sdlc-review does not show its done hand-off with next: $next"
  done
}

# Build and review must not send the work back and forth with no one watching.
# After one send-back, the review asks the human instead.
review_asks_the_human_after_one_send_back() {
  local skill=$REPO/skills/sdlc-review/SKILL.md
  grep -qF 'already shows a review with `next: build`' "$skill" ||
    fail "sdlc-review does not look in the log for a review that sent the work back"
  grep -qF 'entourage task log <project> <card ID>' "$skill" ||
    fail "sdlc-review does not say how to read the card's log"
  grep -A3 -F "entourage task handoff <project> <card ID> <<'EOF'" "$skill" | grep -qx 'status: needs-human' ||
    fail "sdlc-review does not show the needs-human hand-off it makes after a send-back"
}

# What the review found goes on the card, so the build it sends back to, and
# the pull request after it, can read it from a fresh session.
review_writes_what_it_found_on_the_card() {
  local skill=$REPO/skills/sdlc-review/SKILL.md
  grep -qx '>>> ## Review' "$skill" || fail "sdlc-review does not show its collapsed Review section"
  grep -qF 'after the Breakdown' "$skill" || fail "sdlc-review does not say where the Review goes"
  grep -qF 'revise it in place' "$skill" || fail "sdlc-review does not revise its Review on a later round"
}

CASES="skills_share_one_handoff_block handoff_block_names_every_status
  build_pushes_nothing build_is_done_only_when_the_tests_pass
  build_stops_on_a_card_with_no_plan build_installs_what_the_tests_need_first
  build_takes_a_later_round_from_the_review
  review_pushes_nothing review_sends_what_is_not_met_back_to_build
  review_asks_the_human_after_one_send_back review_writes_what_it_found_on_the_card
  the_answer_is_recorded_first
  handoffs_are_recorded_with_the_command
  each_skill_hands_off_as_itself no_skill_says_then_stop
  no_skill_names_a_person a_routed_change_returns_to_breakdown
  a_done_block_is_written_before_the_next_step
  task_new_prompt_follows_the_block task_new_prompt_gives_task_start_the_card
  task_build_prompt_drives_build_and_review"
