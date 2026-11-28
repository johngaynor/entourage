# Tests for what the skills and the prompts must say the same way.
# No agent runs here: these only read the text. Sourced by test/run.sh.

# The skills for the steps of a card's lifecycle, each named sdlc-<step>: the
# three that write it up, then the one that builds it, the one that reviews
# the build and the one that opens its pull request and waits for the merge.
CARD_SKILL_NAMES='sdlc-define sdlc-plan sdlc-breakdown sdlc-build sdlc-review sdlc-pr'

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

# task start takes the card, and names the branch from it. The command that
# starts the work after approval is the card's, not a branch put together.
task_new_prompt_gives_task_start_the_card() {
  local prompt=$REPO/prompts/task-new.md
  grep -qF 'entourage task start {project} {card}' "$prompt" ||
    fail "the task-new prompt does not give: entourage task start {project} {card}"
  ! grep -q '<type>/' "$prompt" ||
    fail "the task-new prompt still has the agent put a branch together"
}

task_new_prompt_follows_the_block() {
  local prompt=$REPO/prompts/task-new.md want
  for want in '`done`' '`needs-human`' '`failed`' 'next: start' '{card}' '{project}'; do
    grep -qF -- "$want" "$prompt" || fail "the task-new prompt does not mention $want"
  done
}

# The step after breakdown is `entourage task start`, and it has one name:
# start, the word its own row in the log uses. Breakdown hands on to it, and
# nothing the agents read still calls it setup.
breakdown_hands_on_to_start() {
  local skill=$REPO/skills/sdlc-breakdown/SKILL.md found
  grep -A3 -F "entourage task handoff <project> <card ID> <<'EOF'" "$skill" | grep -qx 'next: start' ||
    fail "sdlc-breakdown does not show its done hand-off with next: start"
  found=$(grep -rnF 'next: setup' "$REPO/skills" "$REPO/prompts") &&
    fail "the step after breakdown is still called setup: $found"
  return 0
}

# Approving the card starts its build phase, unless the human holds it for later:
# breakdown asks which, and the task-new prompt has the agent run task start
# itself only for an approval to start now.
approval_starts_the_build_unless_held() {
  local skill=$REPO/skills/sdlc-breakdown/SKILL.md prompt=$REPO/prompts/task-new.md section want
  grep -qxF 'question: Approve <card ID> as specified, planned and broken down, and start its build phase now?' "$skill" ||
    fail "the approval's question does not ask whether to start the build phase now"
  grep -qxF 'options: approve and start | approve, start later | change breakdown | change plan | change specification' "$skill" ||
    fail "sdlc-breakdown does not offer to start now or later"
  grep -qF 'Go by what they mean, not by the exact words.' "$skill" ||
    fail "sdlc-breakdown does not tell a start now from a start later by what the human means"
  section=$(sed -n '/^### Start the build phase/,/^## /p' "$skill")
  [ -n "$section" ] || { fail "sdlc-breakdown has no Start the build phase section"; return; }
  for want in 'the first sub-issue in order that is not already started, done or canceled' \
      'start later:** give them the command, `entourage task start <project> <ID>`, and run nothing' \
      'start now:** run that command yourself, once, after the hand-off above is recorded' \
      'every `agent` and `note` line' "If it stops, don't run it again." \
      'it says `made the task at <folder>`' 'run `entourage task build <project> <ID>` there'; do
    case $section in *"$want"*) ;; *) fail "sdlc-breakdown's Start the build phase does not say: $want" ;; esac
  done
  ! grep -qF 'which the human runs' "$skill" || fail "sdlc-breakdown still says the human always runs task start"
  ! grep -qF "don't run it yourself" "$prompt" || fail "the task-new prompt still has the agent never run task start"
  grep -qF 'Run it yourself only when I approved to start now. When I chose to start later, give it to me and' "$prompt" ||
    fail "the task-new prompt does not say when the agent runs task start and when it holds it"
}

# Recording the approval moves the card, and its slices, to the team's
# not-started status. The hand-off is recorded either way, so when the command
# notes that a card was not moved, sdlc-breakdown tells the human which, and
# why, in its message, rather than recording the hand-off again.
breakdown_tells_the_human_when_the_approval_did_not_move_a_card() {
  local skill=$REPO/skills/sdlc-breakdown/SKILL.md section
  section=$(awk '/^## / { if (on) exit } /^## Hand off$/ { on = 1 } on' "$skill")
  [ -n "$section" ] || { fail "sdlc-breakdown has no Hand off section"; return; }
  case $section in
    *'moves the card'*'first not-started status'*'sub-issues'*) ;;
    *) fail "sdlc-breakdown's Hand off does not say that recording the approval moves the card and its sub-issues to the team's first not-started status" ;;
  esac
  case $section in
    *'not moved'*'tell the human'*'which card'*'why'*) ;;
    *) fail "sdlc-breakdown's Hand off does not say to tell the human which card was not moved, and why" ;;
  esac
  case $section in
    *"don't record it again"*) ;;
    *) fail "sdlc-breakdown's Hand off does not say the hand-off is recorded even when a card was not moved" ;;
  esac
}

# The build's agent starts from prompts/task-build.md, which drives build,
# review and the pull request as task-new.md drives the write-up, and ends the
# run when the pull request has merged.
task_build_prompt_drives_build_and_review() {
  local prompt=$REPO/prompts/task-build.md want
  for want in 'Start with the sdlc-build skill' '`review` is the sdlc-review skill' \
      '`build` is the sdlc-build skill' '`pr` is the sdlc-pr skill' 'next: merged' \
      '`done`' '`needs-human`' '`failed`' \
      '{card}' '{project}' 'entourage task handoff {project} {card}' 'record my answer'; do
    grep -qF -- "$want" "$prompt" || fail "the task-build prompt does not mention $want"
  done
  # The run used to end at the review, before the pull request was a skill.
  ! grep -qF 'not a skill yet' "$prompt" ||
    fail "the task-build prompt still says the pull request is not a skill"
  ! grep -qF 'not a skill yet' "$REPO/skills/sdlc-review/SKILL.md" ||
    fail "sdlc-review still says the pull request is not a skill"
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

# The card skills write to Linear through entourage: each shows the command
# for its own section, and define and breakdown the one for the type.
each_skill_writes_its_section_with_the_command() {
  local s section
  for s in sdlc-define sdlc-plan sdlc-breakdown; do
    case $s in
      sdlc-define) section=Specification ;;
      sdlc-plan) section=Plan ;;
      sdlc-breakdown) section=Breakdown ;;
    esac
    grep -qF "entourage linear section <card ID> $section <<'EOF'" "$REPO/skills/$s/SKILL.md" ||
      fail "$s does not show the command that writes its $section"
  done
  grep -qF 'entourage linear type <card ID> <type>' "$REPO/skills/sdlc-define/SKILL.md" ||
    fail "sdlc-define does not show the command that sets the card's type"
  # A slice's type and sections go on the slice, by its own ID.
  grep -qF 'entourage linear type <sub-issue ID> <type>' "$REPO/skills/sdlc-breakdown/SKILL.md" ||
    fail "sdlc-breakdown does not show the command that sets a sub-issue's type"
  grep -qF 'entourage linear section <sub-issue ID>' "$REPO/skills/sdlc-breakdown/SKILL.md" ||
    fail "sdlc-breakdown does not show the command that writes a sub-issue's sections"
}

# The command adds a section's heading and folding. A skill that shows a
# section written with its heading, in any form, would have it written twice.
no_skill_writes_a_section_itself() {
  local s
  for s in $CARD_SKILL_NAMES; do
    ! grep -qE '^((>>>|\+\+\+) )?## (Specification|Plan|Breakdown)$' "$REPO/skills/$s/SKILL.md" ||
      fail "$s still shows a section written with its heading: $(grep -nE '^((>>>|\+\+\+) )?## (Specification|Plan|Breakdown)$' "$REPO/skills/$s/SKILL.md")"
  done
}

# Each skill revises its section in place, never by writing a second one.
each_skill_revises_its_section_with_replace() {
  local s section
  for s in sdlc-define sdlc-plan sdlc-breakdown; do
    case $s in
      sdlc-define) section=Specification ;;
      sdlc-plan) section=Plan ;;
      sdlc-breakdown) section=Breakdown ;;
    esac
    grep -q -- '--replace' "$REPO/skills/$s/SKILL.md" || fail "$s never says how to revise its $section"
  done
  grep -F '| Change the breakdown |' "$REPO/skills/sdlc-breakdown/SKILL.md" | grep -q -- '--replace' ||
    fail "sdlc-breakdown's change of the breakdown does not use --replace"
  grep -qF 'entourage linear section <card ID> Breakdown --replace' "$REPO/skills/sdlc-breakdown/SKILL.md" ||
    fail "sdlc-breakdown does not replace the parent's Breakdown to add the sub-issue IDs"
}

# With no key saved, each skill still writes, through the agent's Linear tools.
each_skill_falls_back_without_a_key() {
  local s
  for s in sdlc-define sdlc-plan sdlc-breakdown; do
    grep -qF '`entourage linear` says no Linear key is saved' "$REPO/skills/$s/SKILL.md" ||
      fail "$s does not say what to do when no Linear key is saved"
  done
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

# The build step and the review step must not send the work back and forth
# with no one watching. After one send-back, the review step asks the human
# instead.
review_asks_the_human_after_one_send_back() {
  local skill=$REPO/skills/sdlc-review/SKILL.md
  grep -qF 'already shows a hand-off from the review step with `next: build`' "$skill" ||
    fail "sdlc-review does not look in the log for a hand-off from the review step that sent the work back"
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

# The pull request goes up only for work the review passed, from the Review
# the review wrote on the card. The skill says so in its first section,
# before any step that pushes.
pr_opens_nothing_unless_the_review_met_every_item() {
  local first
  first=$(awk '/^## / { if (on) exit; on = 1 } on' "$REPO/skills/sdlc-pr/SKILL.md")
  case $first in
    '## Before you push anything'*) ;;
    *) fail "sdlc-pr's first section is not 'Before you push anything'" ;;
  esac
  case $first in
    *'Open nothing unless the Review'*) ;;
    *) fail "sdlc-pr's first section does not say to open nothing unless the Review passed the work" ;;
  esac
  case $first in
    *'**Not met.**'*'`failed`'*) ;;
    *) fail "sdlc-pr's first section does not hand a Review with an item not met off as failed" ;;
  esac
}

# Only the repos the work changed get a pull request: the worktrees whose
# branch has commits the default branch does not.
pr_pushes_only_the_worktrees_with_commits() {
  local skill=$REPO/skills/sdlc-pr/SKILL.md
  grep -qF 'commits ahead of the default branch' "$skill" ||
    fail "sdlc-pr does not find the worktrees with commits ahead of the default branch"
  grep -qF 'and no other' "$skill" || fail "sdlc-pr does not say to push those worktrees and no other"
  grep -qF 'git log --oneline origin/' "$skill" || fail "sdlc-pr does not say how to find the commits"
}

# A pull request follows the repo's own rules, and says, for each Done when
# item, how the review step showed it.
pr_follows_the_repos_rules_for_pull_requests() {
  local skill=$REPO/skills/sdlc-pr/SKILL.md want
  for want in 'CLAUDE.md' 'CONTRIBUTING' '.github/pull_request_template.md' \
      'links the card' 'each Done when item' 'how the review step showed it' 'left to the human'; do
    grep -qF -- "$want" "$skill" || fail "sdlc-pr does not mention $want"
  done
  # A description written on the command line would have its backticks run
  # by the shell, so it goes in a file.
  grep -qF -- '--body-file' "$skill" || fail "sdlc-pr does not give the description as a file"
}

# With the pull request open, the agent waits for the human to merge it, and
# hands on to merged only once GitHub says every one has.
pr_waits_for_the_human_to_merge() {
  local skill=$REPO/skills/sdlc-pr/SKILL.md
  grep -A3 -F "entourage task handoff <project> <card ID> <<'EOF'" "$skill" | grep -qx 'status: needs-human' ||
    fail "sdlc-pr does not show its needs-human hand-off with the links"
  grep -A3 -F "entourage task handoff <project> <card ID> <<'EOF'" "$skill" | grep -qx 'next: merged' ||
    fail "sdlc-pr does not show its done hand-off with next: merged"
  grep -qF 'gh pr view' "$skill" && grep -qF -- '--json state' "$skill" ||
    fail "sdlc-pr does not check each pull request with gh pr view --json state"
  grep -qF 'every pull request for the card has merged' "$skill" ||
    fail "sdlc-pr does not wait for every pull request to merge"
}

# sdlc-pr's section that waits for the merge, from its heading to the next.
pr_wait_section() {
  awk '/^## / { if (on) exit } /^## [0-9]+\. Wait for the merge/ { on = 1 } on' "$REPO/skills/sdlc-pr/SKILL.md"
}

# While the pull requests wait, the agent watches them on GitHub in the
# background, started after its needs-human, so that it learns of the merge
# without being told. Told "merged", it checks at once, with --once.
pr_watches_the_pull_requests() {
  local wait asked watched
  wait=$(pr_wait_section)
  [ -n "$wait" ] || { fail "sdlc-pr has no section that waits for the merge"; return; }
  asked=$(printf '%s\n' "$wait" | grep -nx 'status: needs-human' | head -n1 | cut -d: -f1)
  watched=$(printf '%s\n' "$wait" | grep -nF 'entourage task watch <project> <card ID>`' | head -n1 | cut -d: -f1)
  if [ -z "$asked" ] || [ -z "$watched" ]; then
    fail "sdlc-pr's wait does not hand off needs-human and start entourage task watch"
  elif [ "$asked" -ge "$watched" ]; then
    fail "sdlc-pr starts the watch before it hands off needs-human"
  fi
  case $wait in *'in the background'*) ;; *) fail "sdlc-pr does not run the watch in the background" ;; esac
  case $wait in
    *'They say it has merged.'*'entourage task watch <project> <card ID> --once'*) ;;
    *) fail "sdlc-pr does not check at once with --once when told it has merged" ;;
  esac
  case $wait in *'gh pr view'*) fail "sdlc-pr's wait still checks with gh pr view" ;; esac
}

# When the watch ends with every pull request merged, the agent records it as
# the human's answer, so the log shows the wait, then hands off done with
# merged next, with no one typing in the tab.
pr_records_a_merge_the_watch_sees() {
  local wait ended
  wait=$(pr_wait_section)
  ended=$(printf '%s\n' "$wait" | awk '/^- \*\*It ends with 0/ { on = 1 } on && /^- \*\*It ends with [^0]/ { exit } on')
  [ -n "$ended" ] || { fail "sdlc-pr does not say what to do when the watch ends with 0"; return; }
  case $ended in
    *'status: answered'*'answer: merged on GitHub'*) ;;
    *) fail "sdlc-pr does not record answered, merged on GitHub, when the watch ends with 0" ;;
  esac
  case $ended in *'section 7'*) ;; *) fail "sdlc-pr does not hand off as section 7 says once the watch sees the merge" ;; esac
  grep -A4 -F "entourage task handoff <project> <card ID> <<'EOF'" "$REPO/skills/sdlc-pr/SKILL.md" |
    grep -A2 -x 'status: done' | grep -qx 'next: merged' || fail "sdlc-pr's section 7 does not hand off done with merged next"
}

# When the watch ends with a pull request closed, the agent records that and
# asks the human whether to stop.
pr_asks_when_a_pull_request_is_closed() {
  local wait ended
  wait=$(pr_wait_section)
  ended=$(printf '%s\n' "$wait" | awk '/^- \*\*It ends with 3/ { on = 1 } on && /^- \*\*It ends with [^3]/ { exit } on')
  [ -n "$ended" ] || { fail "sdlc-pr does not say what to do when the watch ends with 3"; return; }
  case $ended in
    *'status: answered'*'answer: closed on GitHub'*) ;;
    *) fail "sdlc-pr does not record answered, closed on GitHub, when the watch ends with 3" ;;
  esac
  case $ended in
    *'whether to stop'*'`needs-human`'* | *'`needs-human`'*'whether to stop'*) ;;
    *) fail "sdlc-pr does not ask the human whether to stop when a pull request was closed" ;;
  esac
}

# The human merges. No agent does, by hand or by auto-merge.
no_agent_merges_a_pull_request() {
  local skill=$REPO/skills/sdlc-pr/SKILL.md line
  grep -qF 'Never run `gh pr merge`' "$skill" || fail "sdlc-pr does not say never to run gh pr merge"
  grep -qF 'auto-merge' "$skill" || fail "sdlc-pr does not say never to turn on auto-merge"
  # Any other line that names the command says never to run it.
  while IFS= read -r line; do
    case $line in *[Nn]ever*) ;; *) fail "sdlc-pr names gh pr merge without saying never: $line" ;; esac
  done < <(grep -F 'gh pr merge' "$skill")
}

# While the pull requests wait to be merged, the human can ask in the tab for a
# change instead. It goes into the same pull request: made on the task's
# branch with its test, committed, pushed, never forced, added to the
# description, and then the agent waits again.
pr_makes_a_change_asked_for_in_the_tab() {
  local skill=$REPO/skills/sdlc-pr/SKILL.md section want
  ! grep -qF 'not part of this step yet' "$skill" ||
    fail "sdlc-pr still says a change asked for in the tab is not made"
  # The wait names a change as one of its answers.
  grep -A5 -F "entourage task handoff <project> <card ID> <<'EOF'" "$skill" |
    grep -E '^options: merged \|' | grep -q 'change' ||
    fail "sdlc-pr's wait for the merge does not name a change as an answer"
  # The section that makes a change, from its heading to the next one.
  section=$(awk '/^## / { if (on) exit } /^## [0-9]+\. Make a change/ { on = 1 } on' "$skill")
  [ -n "$section" ] || fail "sdlc-pr has no section that makes a change asked for in the tab"
  for want in "task's branch" 'whole test suite' 'git commit' 'git push' 'never forced' \
      'gh pr edit' '--body-file' 'Ask first' 'Done when item' 'new dependency'; do
    case $section in
      *"$want"*) ;;
      *) fail "sdlc-pr's section that makes a change does not mention $want" ;;
    esac
  done
  # Once the change is pushed, the agent waits for the merge again.
  case $section in
    *'`needs-human` again'*) ;;
    *) fail "sdlc-pr does not hand off needs-human again once the change is pushed" ;;
  esac
  case $section in *'--force'*) fail "sdlc-pr's section that makes a change shows a forced push" ;; esac
}

# Print one of sdlc-pr's numbered sections: its heading, such as "## 7.", and
# everything up to the next second-level heading.
pr_section() {
  awk -v want="## $1. " '/^## / { if (on) exit } index($0, want) == 1 { on = 1 } on' \
    "$REPO/skills/sdlc-pr/SKILL.md"
}

# Once the merge is recorded, the agent finishes the task with `task finish`,
# which removes its worktrees, branches and folder and closes its tab. It
# runs after the done hand-off, since closing the tab ends the session.
pr_finishes_the_task_after_the_merge() {
  local section done_at finish_at prompt=$REPO/prompts/task-build.md
  section=$(pr_section 7)
  [ -n "$section" ] || fail "sdlc-pr has no section 7"
  done_at=$(printf '%s\n' "$section" | grep -nx 'next: merged' | head -n1 | cut -d: -f1)
  finish_at=$(printf '%s\n' "$section" | grep -nF 'entourage task finish <project> <card ID>' | head -n1 | cut -d: -f1)
  if [ -z "$done_at" ]; then
    fail "sdlc-pr's section 7 does not show its done hand-off with next: merged"
  elif [ -z "$finish_at" ]; then
    fail "sdlc-pr's section 7 does not run entourage task finish <project> <card ID>"
  elif [ "$finish_at" -le "$done_at" ]; then
    fail "sdlc-pr's section 7 runs task finish before it records the merge"
  fi
  case $section in
    *'last command'*) ;;
    *) fail "sdlc-pr's section 7 does not say task finish is the run's last command" ;;
  esac
  # The task used to be left as it was after the merge.
  ! grep -qF 'tab stay as they are' "$REPO/skills/sdlc-pr/SKILL.md" ||
    fail "sdlc-pr still says the task's worktrees and its tab stay as they are"
  grep -qF 'entourage task finish {project} {card}' "$prompt" ||
    fail "the task-build prompt does not say the task is finished at next: merged"
  ! grep -qF 'tab stay' "$prompt" || fail "the task-build prompt says the task's tab stays"
}

# When finishing the task would lose work, `task finish` removes nothing and
# names it. The agent tells the human all of it and changes nothing more.
pr_says_what_finish_would_lose() {
  local section want
  section=$(pr_section 7)
  for want in 'removes nothing' 'everything it named'; do
    case $section in
      *"$want"*) ;;
      *) fail "sdlc-pr's section 7 does not say, for a task finish that refuses: $want" ;;
    esac
  done
  case $section in
    *[Cc]'hange nothing more'*) ;;
    *) fail "sdlc-pr's section 7 does not say to change nothing more when task finish refuses" ;;
  esac
  # It records no hand-off for it: the merge is recorded already.
  case $section in
    *'no other hand-off'*) ;;
    *) fail "sdlc-pr's section 7 does not say to record no other hand-off when task finish refuses" ;;
  esac
  grep -E '^\| `task finish` ' "$REPO/skills/sdlc-pr/SKILL.md" | grep -qF 'everything it named' ||
    fail "sdlc-pr's 'If something goes wrong' has no row for a task finish that refuses"
}

# A pull request closed without merging never reaches section 7, so the task
# stays: the agent asks whether to stop, and runs no `task finish`.
pr_finishes_nothing_for_a_closed_pull_request() {
  local line
  # The watch's ending for it, from its bullet to the next one.
  line=$(pr_section 5 | awk '/^- \*\*It ends with 3: a pull request was closed without merging/ { on = 1; print; next }
    on && /^- \*\*/ { exit } on')
  [ -n "$line" ] || fail "sdlc-pr's section 5 has no answer for a pull request closed without merging"
  case $line in
    *'whether to stop'*) ;;
    *) fail "sdlc-pr does not ask whether to stop when a pull request is closed" ;;
  esac
  case $line in
    *'no `task finish`'*) ;;
    *) fail "sdlc-pr does not say it runs no task finish for a pull request closed without merging" ;;
  esac
  grep -E '^\| A pull request was closed without merging' "$REPO/skills/sdlc-pr/SKILL.md" |
    grep -qF 'no `task finish`' ||
    fail "sdlc-pr's 'If something goes wrong' row for a closed pull request does not say it runs no task finish"
}

# sdlc-pr's section that brings a pull request in conflict up to date, from
# its heading to the next.
pr_up_to_date_section() {
  awk '/^## / { if (on) exit } /^## [0-9]+\. Bring a pull request up to date/ { on = 1 } on' \
    "$REPO/skills/sdlc-pr/SKILL.md"
}

# When the watch ends with 4, a pull request conflicts with its default
# branch. The agent records that as the answer and brings it up to date
# without asking: it merges the default branch in, never by a rebase, which
# would need a forced push, runs the whole test suite and commits the merge,
# pushing nothing, then hands off done with review next. The review checks the
# merge again and says so on its round line. Back in pr, the pull request is
# open already: it pushes only a branch that moved, keeps the description's
# added lines, adds one under Brought up to date:, and starts the watch again.
pr_brings_a_conflicting_branch_up_to_date() {
  local skill=$REPO/skills/sdlc-pr/SKILL.md wait ended section open want
  wait=$(pr_wait_section)
  ended=$(printf '%s\n' "$wait" | awk '/^- \*\*It ends with 4/ { on = 1 } on && /^- \*\*It ends with [^4]/ { exit } on')
  [ -n "$ended" ] || fail "sdlc-pr does not say what to do when the watch ends with 4"
  case $ended in
    *'status: answered'*'answer: in conflict on GitHub'*'Bring a pull request up to date'*) ;;
    *) fail "sdlc-pr does not record a conflict the watch sees as the answer, then bring the pull request up to date" ;;
  esac
  case $wait in
    *'--once'*'With 4,'*'Bring a pull request up to date'*) ;;
    *) fail "sdlc-pr does not bring a pull request up to date when --once ends with 4" ;;
  esac
  case $wait in *'started again'*) ;; *) fail "sdlc-pr does not start the watch again once a watch has ended" ;; esac

  section=$(pr_up_to_date_section)
  [ -n "$section" ] || { fail "sdlc-pr has no section that brings a pull request up to date"; return; }
  for want in 'without asking the human' 'no conflict gets no push' 'git fetch origin' \
      'git merge origin/<default branch>' 'never a rebase' 'whole test suite' 'git commit' 'Push nothing'; do
    case $section in
      *"$want"*) ;;
      *) fail "sdlc-pr's section that brings a pull request up to date does not mention $want" ;;
    esac
  done
  case $section in *'git rebase'* | *'--force'* | *'git push'*) fail "sdlc-pr's section that brings a pull request up to date rebases, forces or pushes" ;; esac
  printf '%s\n' "$section" | grep -A3 -F "entourage task handoff <project> <card ID> <<'EOF'" |
    grep -A1 -x 'status: done' | grep -qx 'next: review' ||
    fail "sdlc-pr's section that brings a pull request up to date does not hand off done with review next"
  printf '%s\n' "$section" | grep -A4 -F "entourage task handoff <project> <card ID> <<'EOF'" |
    grep -E '^summary: ' | grep 'files that conflicted' | grep -q 'what the fix changed' ||
    fail "sdlc-pr's done hand-off for a merge does not name the files that conflicted and what the fix changed"

  # The review it hands on to checks the merge, and says so.
  grep -qF 'default branch was merged in' "$REPO/skills/sdlc-review/SKILL.md" ||
    fail "sdlc-review does not say on its round line that the default branch was merged in"
  grep -F '`review` is the sdlc-review skill' "$REPO/prompts/task-build.md" | grep -qF 'from sdlc-pr' ||
    fail "the task-build prompt does not say review may come next from sdlc-pr"

  # Back in pr, with the pull request open already.
  open=$(pr_section 4)
  for want in 'already has an open pull request' 'origin/<branch>..HEAD' 'push nothing in that worktree' \
      '**Changes asked for:**' '**Brought up to date:**' 'files that conflicted' 'what the fix changed'; do
    case $open in
      *"$want"*) ;;
      *) fail "sdlc-pr's section 4 does not mention, for a pull request already open: $want" ;;
    esac
  done
  case $open in *'never forced'*) ;; *) fail "sdlc-pr's section 4 does not say the push is never forced" ;; esac
  ! printf '%s\n' "$open" | grep -qE -- 'git push[^`]*--force' || fail "sdlc-pr's section 4 shows a forced push"
}

# The agent asks the human about a conflict only when it cannot settle it:
# the tests cannot be made to pass, or a resolution would change what a Done
# when item says. It names the pull request and the files in conflict, and
# commits and pushes nothing until they answer.
pr_asks_only_when_a_conflict_cannot_be_settled() {
  local skill=$REPO/skills/sdlc-pr/SKILL.md section want row
  section=$(pr_up_to_date_section)
  [ -n "$section" ] || { fail "sdlc-pr has no section that brings a pull request up to date"; return; }
  case $section in
    *'Ask the human only when'*'cannot be made to pass'*'what a Done when item says'*) ;;
    *) fail "sdlc-pr does not name the two times it asks the human about a conflict" ;;
  esac
  printf '%s\n' "$section" | grep -A3 -F "entourage task handoff <project> <card ID> <<'EOF'" |
    grep -qx 'status: needs-human' ||
    fail "sdlc-pr's section that brings a pull request up to date does not show its needs-human hand-off"
  printf '%s\n' "$section" | grep -A4 -F "entourage task handoff <project> <card ID> <<'EOF'" |
    grep -E '^question: ' | grep '<the pull request>' | grep -q '<the files in conflict>' ||
    fail "sdlc-pr's question about a conflict does not name the pull request and the files in conflict"
  for want in 'Until they answer, commit and push nothing' 'record the answer first' '`failed`'; do
    case $section in
      *"$want"*) ;;
      *) fail "sdlc-pr's question about a conflict does not say: $want" ;;
    esac
  done
  row=$(grep -E '^\| A pull request is in conflict' "$skill")
  [ -n "$row" ] || { fail "sdlc-pr's 'If something goes wrong' has no row for a conflict it cannot settle"; return; }
  case $row in
    *'`needs-human`'*'files in conflict'*'push nothing'*) ;;
    *) fail "sdlc-pr's row for a conflict does not ask as needs-human, with the files, pushing nothing: $row" ;;
  esac
}

# What can stop the push is checked before anything is pushed, and a check
# that fails is a failed hand-off with the reason, not a push that half works.
pr_checks_it_can_push_before_pushing() {
  local skill=$REPO/skills/sdlc-pr/SKILL.md auth remote push
  auth=$(grep -nF 'gh auth status' "$skill" | head -n1 | cut -d: -f1)
  remote=$(grep -nF 'gh repo view' "$skill" | head -n1 | cut -d: -f1)
  push=$(grep -nF 'git push' "$skill" | head -n1 | cut -d: -f1)
  if [ -z "$auth" ] || [ -z "$remote" ]; then
    fail "sdlc-pr does not check gh auth status and the remote with gh repo view"
  elif [ -z "$push" ]; then
    fail "sdlc-pr does not say how to push the branch"
  elif [ "$auth" -ge "$push" ] || [ "$remote" -ge "$push" ]; then
    fail "sdlc-pr pushes before it checks that it can"
  fi
  # The section that checks says to hand off as failed, and pushes nothing.
  local checks
  checks=$(awk '/^## / { if (s ~ /gh auth status/) exit; s = "" } { s = s $0 "\n" } END { printf "%s", s }' "$skill")
  case $checks in
    *'gh auth status'*'`failed`'* | *'`failed`'*'gh auth status'*) ;;
    *) fail "sdlc-pr's checks before the push do not hand off as failed when one fails" ;;
  esac
  case $checks in *'git push'*) fail "sdlc-pr pushes in the section that checks it can" ;; esac
  grep -qF 'never forced' "$skill" || fail "sdlc-pr does not say the push is never forced"
  ! grep -qE -- 'git push[^`]*--force' "$skill" || fail "sdlc-pr shows a forced push"
}

# Once every pull request for the card is open and read back, sdlc-pr moves
# the card to In Review with one run of linear move: after the read-back, and
# after the steps it takes for each repo, so a card with pull requests in
# several repos does not move before the last one is open.
pr_moves_the_card_to_review_once_every_pull_request_is_open() {
  local skill=$REPO/skills/sdlc-pr/SKILL.md section readback last_step move
  section=$(awk '/^## / { if (on) exit } /^## [0-9]+\. Push the branch/ { on = 1 } on' "$skill")
  [ -n "$section" ] || { fail "sdlc-pr has no section that pushes the branch and opens the pull requests"; return; }
  readback=$(printf '%s\n' "$section" | grep -nF 'gh pr view <url> --json url,title,body,baseRefName,headRefName' | head -n1 | cut -d: -f1)
  last_step=$(printf '%s\n' "$section" | grep -nE '^[0-9]+\. ' | tail -n1 | cut -d: -f1)
  move=$(printf '%s\n' "$section" | grep -nF 'entourage linear move <card ID> review' | head -n1 | cut -d: -f1)
  if [ -z "$move" ]; then
    fail "sdlc-pr's section that opens the pull requests does not run entourage linear move <card ID> review"
    return
  elif [ -z "$readback" ] || [ "$move" -le "$readback" ]; then
    fail "sdlc-pr moves the card before it reads every pull request back"
  elif [ "$move" -le "$last_step" ]; then
    fail "sdlc-pr moves the card in the steps it takes for each repo"
  fi
  # The move comes before the wait for the merge.
  [ "$(grep -nF 'entourage linear move' "$skill" | head -n1 | cut -d: -f1)" -lt \
    "$(grep -nE '^## [0-9]+\. Wait for the merge' "$skill" | cut -d: -f1)" ] ||
    fail "sdlc-pr moves the card after it waits for the merge"
}

# A move that fails does not stop the step: sdlc-pr says that the card was not
# moved, and why, in flags, and goes on to wait for the merge.
pr_goes_on_when_the_card_cannot_be_moved() {
  local skill=$REPO/skills/sdlc-pr/SKILL.md section row
  section=$(awk '/^## / { if (on) exit } /^## [0-9]+\. Push the branch/ { on = 1 } on' "$skill")
  case $section in
    *'exits non-zero'*'not moved'*'wait for the merge'*'`flags`'*) ;;
    *) fail "sdlc-pr does not say to go on to wait for the merge, with the move in flags, when the card is not moved" ;;
  esac
  row=$(grep -F '| `entourage linear move` exits non-zero |' "$skill")
  [ -n "$row" ] || fail "sdlc-pr's table of what goes wrong has no row for a move that fails"
  case $row in
    *'`flags`'*'wait for the merge'*) ;;
    *) fail "sdlc-pr's row for a move that fails does not say to flag it and wait for the merge: $row" ;;
  esac
  # The hand-off that ends the step has room for it.
  grep -A5 -F "entourage task handoff <project> <card ID> <<'EOF'" "$skill" | grep -E '^flags: ' | grep -q 'not moved' ||
    fail "sdlc-pr's done hand-off does not say a card that was not moved goes in flags"
}

# entourage moves the card now, so the skill no longer leaves it to the human.
pr_no_longer_leaves_the_status_to_the_human() {
  ! grep -qF "is the human's to move" "$REPO/skills/sdlc-pr/SKILL.md" ||
    fail "sdlc-pr still says the card's status is the human's to move"
}

# --- agent profiles ---------------------------------------------------------

# A profile is a Claude Code agent definition: frontmatter between two ---
# lines, then the agent's instructions. The reviewer and the verifier are for
# work on entourage itself, in the repo's own .claude/profiles/, which a clone
# writes into Claude Code's agents folder with their model and effort. The
# write-up and the build ship in agents/.
REVIEW_PROFILES="$ROOT/.claude/profiles/entourage-reviewer.md $ROOT/.claude/profiles/entourage-verifier.md"
factory_profiles() { printf '%s\n' "$REPO/agents/entourage-write-up.md" "$REPO/agents/entourage-build.md"; }

# Print the value of one key in a profile's frontmatter, or nothing.
profile_field() {
  awk -v k="$2" '
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    { i = index($0, ":"); if (i && substr($0, 1, i - 1) == k) { v = substr($0, i + 1); sub(/^[ \t]+/, "", v); print v } }
  ' "$1"
}

# Fail unless a profile's tools are exactly the list given.
profile_tools_are() {
  local tools
  tools=$(profile_field "$1" tools)
  [ "$tools" = "$2" ] || fail "${1##*/} has the tools '$tools', not '$2'"
}

# A reviewer and a verifier can be started by name, as entourage-reviewer and
# entourage-verifier, each with only the tools it uses. Those include writing
# files: reviewers write throwaway copies and repro scripts. The entourage-
# names keep them from standing in for a person's own reviewer.
review_profiles_are_named_with_only_their_tools() {
  local f name
  for f in $REVIEW_PROFILES; do
    [ -f "$f" ] || { fail "there is no ${f#"$ROOT"/}"; continue; }
    name=${f##*/}; name=${name%.md}
    case $name in entourage-*) ;; *) fail "${f##*/} is not named entourage-<something>" ;; esac
    [ "$(profile_field "$f" name)" = "$name" ] || fail "${f##*/} is not named $name: '$(profile_field "$f" name)'"
    [ -n "$(profile_field "$f" description)" ] || fail "${f##*/} has no description, so the Agent tool cannot list it"
    profile_tools_are "$f" 'Read, Bash, Edit, Write'
  done
}

# Without the Skill and ToolSearch tools a session starts without the skill
# listing and the deferred tool list, and without Agent it starts no
# subagents of its own.
review_profiles_leave_out_the_listing_tools() {
  local f tool
  for f in $REVIEW_PROFILES; do
    for tool in Skill ToolSearch Agent; do
      case ", $(profile_field "$f" tools), " in
        *", $tool, "*) fail "${f##*/} has the $tool tool" ;;
      esac
    done
  done
}

# The rules that every review prompt used to repeat are in the profiles, so a
# prompt can leave them out.
review_profiles_carry_the_review_rules() {
  local f want
  for f in $REVIEW_PROFILES; do
    for want in '~/.config/entourage/.env' LINEAR_API_KEY api.linear.app herdr-app 'mktemp -d' \
        ENTOURAGE_HOME '~/Dev/entourage' 'bash 3.2' subagents CLAUDE.md README.md herdr/README.md; do
      grep -qF -- "$want" "$f" || fail "${f##*/} does not mention $want"
    done
  done
  for want in Critical Important Minor verdict; do
    grep -qF -- "$want" "$ROOT/.claude/profiles/entourage-reviewer.md" || fail "entourage-reviewer.md does not mention $want"
  done
  for want in fix-now fix-later skip refute; do
    grep -qF -- "$want" "$ROOT/.claude/profiles/entourage-verifier.md" || fail "entourage-verifier.md does not mention $want"
  done
}

# The write-up profile has only the tools a write-up uses, and the Linear
# server its session is given is the only one it has.
write_up_profile_has_only_its_tools() {
  local f=$REPO/agents/entourage-write-up.md mcp=$REPO/agents/linear-mcp.json
  [ -f "$f" ] || { fail "there is no agents/entourage-write-up.md"; return; }
  [ "$(profile_field "$f" name)" = entourage-write-up ] || fail "the write-up profile is not named entourage-write-up"
  profile_tools_are "$f" 'Bash, Read, Skill, mcp__linear-server__get_issue, mcp__linear-server__list_comments, mcp__linear-server__list_issues, mcp__linear-server__save_issue'
  jq -e '.mcpServers | keys == ["linear-server"]' "$mcp" >/dev/null 2>&1 ||
    fail "agents/linear-mcp.json does not parse, or names other servers than linear-server: $(cat "$mcp" 2>&1)"
  jq -e '.mcpServers["linear-server"] | .type == "http" and .url == "https://mcp.linear.app/mcp"' "$mcp" >/dev/null 2>&1 ||
    fail "agents/linear-mcp.json does not give Linear's own server: $(cat "$mcp" 2>&1)"
}

# The build profile has only the tools a build and a review use.
build_profile_has_only_its_tools() {
  local f=$REPO/agents/entourage-build.md
  [ -f "$f" ] || { fail "there is no agents/entourage-build.md"; return; }
  [ "$(profile_field "$f" name)" = entourage-build ] || fail "the build profile is not named entourage-build"
  profile_tools_are "$f" 'Bash, Read, Edit, Write, Skill, mcp__linear-server__get_issue, mcp__linear-server__list_comments, mcp__linear-server__save_issue'
}

# The write-up and the build say Opus, though --model= beats it: the settings
# file picks each profile's model and effort (settings.sh). No source sets an
# effort, and the reviewer's and verifier's set no model either, since
# entourage writes both into the file it makes of each.
every_profile_runs_on_opus() {
  local f
  for f in $(factory_profiles); do
    [ -f "$f" ] || { fail "there is no $f"; continue; }
    [ "$(profile_field "$f" model)" = opus ] || fail "${f##*/} does not say model: opus"
  done
  for f in $REVIEW_PROFILES; do
    [ -f "$f" ] || { fail "there is no $f"; continue; }
    [ -z "$(profile_field "$f" model)" ] || fail "${f##*/} sets a model, which entourage writes"
  done
  for f in $REVIEW_PROFILES $(factory_profiles); do
    [ -z "$(profile_field "$f" effort)" ] || fail "${f##*/} sets an effort"
  done
}

# The factory's profiles ship to everyone who installs entourage, so they
# name no one.
no_profile_names_a_person() {
  local f
  for f in $(factory_profiles); do
    ! grep -qw 'John' "$f" || fail "${f##*/} names John; say 'the human'"
  done
}

CASES="skills_share_one_handoff_block handoff_block_names_every_status
  each_skill_writes_its_section_with_the_command no_skill_writes_a_section_itself
  each_skill_revises_its_section_with_replace each_skill_falls_back_without_a_key
  build_pushes_nothing build_is_done_only_when_the_tests_pass
  build_stops_on_a_card_with_no_plan build_installs_what_the_tests_need_first
  build_takes_a_later_round_from_the_review
  review_pushes_nothing review_sends_what_is_not_met_back_to_build
  review_asks_the_human_after_one_send_back review_writes_what_it_found_on_the_card
  pr_opens_nothing_unless_the_review_met_every_item pr_pushes_only_the_worktrees_with_commits
  pr_follows_the_repos_rules_for_pull_requests pr_waits_for_the_human_to_merge
  no_agent_merges_a_pull_request pr_checks_it_can_push_before_pushing
  pr_makes_a_change_asked_for_in_the_tab
  pr_watches_the_pull_requests pr_records_a_merge_the_watch_sees pr_asks_when_a_pull_request_is_closed
  pr_moves_the_card_to_review_once_every_pull_request_is_open pr_goes_on_when_the_card_cannot_be_moved
  pr_no_longer_leaves_the_status_to_the_human
  pr_finishes_the_task_after_the_merge pr_says_what_finish_would_lose
  pr_finishes_nothing_for_a_closed_pull_request
  pr_brings_a_conflicting_branch_up_to_date pr_asks_only_when_a_conflict_cannot_be_settled
  the_answer_is_recorded_first
  handoffs_are_recorded_with_the_command
  each_skill_hands_off_as_itself no_skill_says_then_stop
  review_profiles_are_named_with_only_their_tools review_profiles_leave_out_the_listing_tools
  review_profiles_carry_the_review_rules write_up_profile_has_only_its_tools
  build_profile_has_only_its_tools every_profile_runs_on_opus no_profile_names_a_person
  no_skill_names_a_person a_routed_change_returns_to_breakdown
  approval_starts_the_build_unless_held
  a_done_block_is_written_before_the_next_step
  task_new_prompt_follows_the_block task_new_prompt_gives_task_start_the_card
  task_build_prompt_drives_build_and_review breakdown_hands_on_to_start
  breakdown_tells_the_human_when_the_approval_did_not_move_a_card"
