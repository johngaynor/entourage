---
name: sdlc-build
description: Build an approved Linear card in the task that `entourage task start` made for it, by reading the card's Plan, making the change in the task's worktree, installing what its tests need and running them, and committing on the task's branch, then recording how the build step ended. Use this once a card is approved and its task started, whenever asked to build, implement or code a card in that task, even if the request only says "build ABC-123". It pushes nothing and opens no pull request.
---

# Build a card

The build step comes after the human has approved the card. Define said what is wanted, plan said how it will be built, and breakdown cut it into pieces the human approved. The build step makes the change that the Plan describes, in the task's worktree, and shows that each Done when item is true.

The human is not watching while it runs. They read the commits and the hand-off afterwards, so the commits have to match the Plan, and the hand-off has to say plainly how the build step ended and what it could not show.

The build step ends with commits on the task's branch. Push nothing and open no pull request. The review step, pushing and the pull request come after this step.

## Before you change anything

1. Get the card. If you weren't given a card ID, ask for one.
2. Read the card with `entourage linear read <card ID>`: the original description, the Specification, the Plan, the Breakdown, the Review if there is one, and the comments.
3. If the card has no Plan, plan hasn't run, and the card was not approved to build. Change nothing, and hand off as `failed`, saying so.
4. If the Breakdown cut the card into several slices, each slice is a sub-issue with a Plan of its own. Build the sub-issue, not this card. Change nothing, and hand off as `failed`, naming the sub-issue that comes first.
5. Check where you are. The work goes in the task's worktrees, which `entourage task start` made under the project's `tasks/` folder, one for each repo, all on the task's branch. Run `git branch --show-current` in each one. The branch has to name this card, as in `feat/abc-122-short-name`. If you are in a repo's own checkout, on its default branch, or on a branch for another card, change nothing and hand off as `failed`, saying where you are.
6. Run `git status` in each worktree. A new task's worktree has no changes. If one has changes that aren't yours, don't touch them: ask the human what to do with them.
7. If the card has a Review with items not met, this is a later round: the `sdlc-review` skill checked an earlier round and sent it back. Build only what those items need, on top of the commits already there, and leave the items it found met as they are. A test that fails for one of those items is the work, not a reason to ask.

## 1. Read how the repo works

Read the guidance in each worktree you will change: its `CLAUDE.md`, `AGENTS.md`, `README` and any `CONTRIBUTING` file. Look for four things:

- **How a fresh checkout is made ready.** What a new clone has to install before its tests can run, such as its dependencies.
- **How it is tested.** The command that runs the tests, and how to run only some of them.
- **How commits are written.** The form of a commit message, and anything a commit must never contain.
- **Rules for a change like this one.** A file that must not be edited by hand, a list that a new file must be added to, a version that only a release changes.

`entourage task start` installs nothing for now, so a new worktree may have none of what its tests need. If it lacks something, install what the tests need the way the repo's docs say. Install only: start no app, dev server or database. Install into the worktree, as its dependencies are: a tool installed on the machine itself, such as with `brew` or a global `npm install`, is for the human, so ask. Read a command before you run it: if the docs' way of making a checkout ready also starts something, run only the part that installs. If the docs don't say how to install what is missing, ask the human rather than guess. If the tests need something you may not start yourself, such as a database or Docker, ask the human, saying what.

Then run the tests once, before you change anything. A test that fails now is not one you broke, and you need to know that before you start. If any fail, ask the human whether to build on top of them.

In a later round, the tests the Review found failing fail now too. They are what you are here to fix, so ask only about a test that fails for some other reason.

## 2. Build what the Plan says

Work through the Done when items in order, one at a time. In a later round, work through only the items the Review found not met, and start each from what the Review says is missing or fails. For each one:

1. Take its test from the Plan's Tests line for that item. Write the test first where the Plan names one, and run it to see it fail for the reason you expect.
2. Make the change the Plan's Changes list gives for it, in the files it names. Reuse the helpers it names.
3. Run the test again and see it pass.

Each path in Changes starts with the repo's name, and that repo's worktree is the folder of the same name in the task. A task with one repo is its worktree.

Stay inside the Plan. The human approved this Plan, not a better one you could write now:

- **The code differs from the Plan in a detail** that changes nothing they approved, such as a helper with another name or a file that moved. Follow the code, and say so in the summary when you hand off.
- **The Plan can't be built as written.** Following it would change what they approved: a Done when item that can't be met, a different approach, a new dependency, or a repo the task has no worktree of. Ask the human before going any further, in a handoff block with `status: needs-human` and your recommendation first in `options`.
- **Something outside the Plan.** You may find a nearby bug, a missing test or a refactor that would help. Leave it alone and put it in `flags` when you hand off.

The build step changes nothing on the card. The hand-off records how it ended.

## 3. Run the tests

When every Done when item has its change, run the repo's whole test suite, in every worktree you changed. The build step is done only when the tests pass.

If a test fails, find out why and fix it. Change a test only when the Plan changes what that test checks. A test made to pass by weakening it is a failure you have hidden from the human.

If the tests can't run at all because something they need is missing, install it as section 1 says, then run them again. If it is something you may not start yourself, ask the human, saying what.

## 4. Commit

Commit on the task's branch, in each worktree you changed, by the repo's own rules for commits. Where the repo has none, write a Conventional Commits message whose type is the card's type, such as `feat: export orders as CSV`.

- Commit only when the tests pass.
- Leave nothing behind: `git status` shows no changes when you are done.
- Don't skip the repo's commit hooks. If a hook refuses the commit, fix what it names and commit again.
- Push nothing and open no pull request.

## 5. Hand off

When the commits are made and the tests pass, record the hand-off. The build step is not finished until it is recorded:

```
entourage task handoff <project> <card ID> <<'EOF'
phase: build
status: done
next: review
summary: <what was built, in which repos, how many commits, and that the tests pass; any detail where you followed the code rather than the Plan>
flags: <any Done when item you could not show to be true, and why; anything you found outside the Plan>
EOF
```

Put your own words in place of each hint in angle brackets, and leave the `flags` line out when there is nothing to flag. Hand off as `done` only when the tests pass. When they can't be made to pass, or something is missing, hand off as `failed`, with what is wrong and what you tried in `reason`, and leave the work as it is for the human.

In a later round, say in `summary` what was done for each item the Review found not met. The step that follows is the review step, which the `sdlc-review` skill runs: it checks the work against the card's Done when, and sends what is not met back here as a later round.

## The handoff block

Every step of the lifecycle ends the same way, so whoever is driving it, a person or a script, can tell how the step ended without reading the whole session.

Record a hand-off every time this step ends or pauses: when the step is finished, when you need an answer, and when something has gone wrong. Record it even when you go straight on to another step, because the record is what shows this one ended. Run `entourage task handoff` with the block on stdin, one value per line:

```
entourage task handoff <project> <card ID> <<'EOF'
phase: <this step>
status: <done, needs-human or failed>
next: <the step that follows>
summary: <one to three sentences on what you did>
flags: <what the human should know but wasn't asked>
question: <one question>
options: <the answers you expect, your recommendation first, separated by " | ">
answer: <what the human said, in a few words>
reason: <what went wrong, and what you already tried>
EOF
```

`<project>` is the entourage project this session is in. The `phase:` line names this step, not a phase. The words in angle brackets are hints: put your own in their place. The command checks the block, records it and prints it back. Which lines you write depends on the status:

| Status | Use it when | Lines |
|---|---|---|
| `done` | This step's work is on the card and you have read it back | `phase`, `status`, `next`, `summary`, and `flags` if there are any |
| `needs-human` | You can't go on without an answer or an approval | `phase`, `status`, `question`, `options`, and `summary` if it helps them answer |
| `answered` | The human has replied to a `needs-human` hand-off | `phase`, `status`, `answer` |
| `failed` | Something is missing or went wrong, and this skill tells you to stop or doesn't cover it | `phase`, `status`, `reason` |

- **If the command refuses the block, fix what it names and run it again.** If it can't record at all, because the command is missing, you are not in an entourage project, or it says the hand-off was not recorded, write the block in your message instead and carry on. Don't make a project or install anything to get it to run.
- **When you stop for the human, end your message with the block the command printed.** Above it goes only what the human needs and can't read on the card: a section you could not write there, or the summary they approve from.
- **Wherever this skill says to ask, tell or stop, use the block.** An ask is `needs-human`. Something to tell goes in `flags`. A stop because something is missing or went wrong is `failed`.
- **`needs-human` is a pause, not an ending.** Wait for the answer. When it comes, record it before anything else, as a hand-off with `status: answered` and what they said in a few words. That is how the time spent waiting on them is told from your own work. Then carry on with this step. The step is over only at `done` or `failed`.
- **Ask one question per block.** If you have two, ask first the one whose answer could change the other. The human can always answer in their own words, so `options` are suggestions.
- **After `done`, this step is over.** Record the hand-off before anything else. If another step sent you here to revise this section, go back to that step and ignore `next`. Otherwise go on to the step in `next` only if you were asked to run more than this one step, and if you weren't, stop there.
- **After `failed`, change nothing more.** Leave the card as it is for the human.

## If something goes wrong

| When this happens | Do this |
|---|---|
| The card ID doesn't resolve | Ask the human for the ID. Don't pick a card because its title looks similar |
| The Linear tools aren't available | Hand off as `failed`. Don't build from memory of the card or from its title |
| `entourage linear read` says no Linear key is saved or that Linear rejected the key, or the command isn't there | Read the card with the Linear tools instead, and say so in `flags` when you hand off |
| A repo the Plan changes has no worktree in the task | Ask the human. The task may have been started with targets that left it out |
| A path in the Plan doesn't exist | Find the real one. If there isn't one, and the file isn't marked as new, ask the human |
| The worktree lacks what the tests need, and the repo's docs don't say how to install it | Ask the human what to install. Don't guess |
| An install fails | Ask the human, with the command and its error. Don't change the repo's files to make it install |
| The tests need an app, server, database or Docker running | Ask the human, saying what. Don't start it yourself |
| A test fails before you have changed anything | Ask the human whether to build on top of it. Don't fix it as part of this card |
| A commit hook refuses the commit | Fix what it names and commit again. Never skip the hook |
| The tests still fail after you have tried what you can | Hand off as `failed`, with the failing tests and what you tried. Leave the work uncommitted in the worktree |

If something fails that isn't on this list, stop and tell the human what happened. Don't work around it.

## Example

**From the card's Plan**

```
**Tests:**
1. Button shows for a manager: component test in `OrdersPage.test.tsx`
2. Columns, and one row per order: API test in `test_orders_export.py`
3. Same filters and range as on screen: API test with a filtered request, and a component test that the filters are passed
```

**The hand-off at the end**

```
entourage task handoff shop ABC-122 <<'EOF'
phase: build
status: done
next: review
summary: Installed each worktree's dependencies as its README says, then built the CSV export in api and the Download CSV button in web, in two commits. Both test suites pass. The CSV helper is csv_rows in shop/api/app/common/export.py, not csv_stream as the Plan said.
flags: The orders page's tests can't set its filters yet, so item 3 is shown by the API test alone. The orders list also ignores the date range on page 2, which is outside this card.
EOF
```
