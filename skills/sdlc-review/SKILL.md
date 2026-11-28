---
name: sdlc-review
description: Review a built Linear card in its task before anything is pushed, by running the tests, checking each Done when item against the Plan's tests, writing what was found on the card as its Review, and sending what is not met back to build. Use this once sdlc-build has handed off done, whenever asked to review, check or verify a built card in its task, even if the request only says "review ABC-123". It changes no code, pushes nothing and opens no pull request.
---

# Review a card

Review is the step after build. Build made the change the Plan describes and committed it on the task's branch. Review checks that work against the card's Done when before anyone else sees it, and sends what falls short back to build.

The human is not watching while it runs. They read the card's Review and the hand-off afterwards, so the Review has to say of each Done when item whether it is met and how that was shown, and the hand-off has to say plainly how the review ended.

Review changes no code. Push nothing and open no pull request. What falls short goes back to build, and pushing and the pull request come after this step.

## Before you check anything

1. Get the card. If you weren't given a card ID, ask for one.
2. Read the card with the Linear tools: the original description, the Specification, the Plan, the Breakdown, the Review if an earlier round wrote one, and the comments.
3. If the card has no Plan, it was not approved to build, so there is nothing to review. Change nothing, and hand off as `failed`, saying so.
4. If the Breakdown cut the card into several slices, each slice is a sub-issue with a Plan and a build of its own. Review the sub-issue, not this card. Change nothing, and hand off as `failed`, naming the sub-issue that comes first.
5. Check where you are. The work is in the task's worktrees, which `entourage task start` made under the project's `tasks/` folder, one for each repo, all on the task's branch. Run `git branch --show-current` in each one. The branch has to name this card, as in `feat/abc-122-short-name`. If you are in a repo's own checkout, on its default branch, or on a branch for another card, change nothing and hand off as `failed`, saying where you are.
6. Run `git status` in each worktree. Build leaves nothing uncommitted. If a worktree has changes, the build did not finish: change nothing, and hand off as `failed`, naming the worktree and its changed files.
7. Find what was built. The task started from each repo's default branch, so the build's commits are the ones the default branch doesn't have: `git log --oneline origin/main..HEAD`, with the repo's own default branch in place of `main`. If no worktree has a commit there, nothing was built. Hand off as `failed`, saying so.

## 1. Read how the repo works

Read the guidance in each worktree with commits: its `CLAUDE.md`, `AGENTS.md`, `README` and any `CONTRIBUTING` file. Look for three things:

- **How it is tested.** The command that runs the tests, and how to run only some of them.
- **How commits are written.** The form of a commit message, and anything a commit must never contain.
- **Rules for a change like this one.** A list that a new file must be added to, docs that change when the behaviour does, a version that only a release changes.

## 2. Run the tests

Run the repo's whole test suite in each worktree with commits. Run it yourself, though build said it passed: the review is what shows it.

If a test fails, note which one and what it said. Don't fix it, because review changes no code. A failing test is work that goes back to build.

If the tests can't run at all, because something they need is missing from the worktree, don't install anything. Ask the human, saying what is missing.

## 3. Check each Done when item

Work through the Done when items in order, one at a time. For each one:

1. Take its test from the Plan's Tests line for that item, and find it in the worktree. Read it, and check that it checks what the item says, not something nearby or something weaker. A test that only checks a page loads doesn't show that the page lists the right rows.
2. Run that test, on its own where the repo can run some tests alone, and see it pass.
3. Where the Plan shows a part of the item by a real run, such as a command used on a real card or a page opened in a browser, do it when it can be done from the worktree and the repo's guidance allows it. A run that reaches outside the task, such as one that pushes, deploys, sends a message or changes a real account, is for the human: say what to run and what they should see.

Each item is one of three:

- **Met.** Its test is there, checks what the item says, and passes, and any real run the Plan names for it was done and showed it.
- **Not met.** Its test is missing, checks less than the item says, or fails, or a real run showed the item isn't true. Say which, in words build can act on.
- **For the human.** Everything you could do shows it, but part of it can only be shown by a run you may not do. An item for the human doesn't send the work back.

## 4. Check the commits

Check each of the build's commits against the repo's rules for commits: the form of its message, and anything a commit must never contain. Check the change against the repo's rules for a change like this one. A commit or a change that breaks one goes in the Review, and in `flags` when you hand off. It doesn't send the work back on its own: a rule that a Done when item needs, such as a new test that must be added to a list before it runs, is already an item not met.

## 5. Write the Review on the card

Write what you found on the card as a collapsed section after the Breakdown. Change nothing else on the card. If an earlier round wrote a Review, revise it in place, so the card has one Review, the latest.

Use this form:

```
>>> ## Review
Round <n>, on <the commit each worktree was at>. The tests <pass, or which fail>.

- **Met.** <Done when item, in a few words>: <how it was shown>
- **Not met.** <Done when item>: <what is missing or fails>
- **For the human.** <Done when item>: <what to run, and what they should see>

**Commits:** <that they follow the repo's rules, or which rule a commit breaks>
>>>
```

The round is 1 the first time, and one more each time build has been sent back before. After writing, read the card back. Check that nothing above the Review changed and that the Review shows as a collapsed section.

## 6. Hand off

When the Review is on the card and you have read it back, record the hand-off. Review is not finished until it is recorded.

When every Done when item is met or for the human, and the tests pass, the work is ready for its pull request:

```
entourage task handoff <project> <card ID> <<'EOF'
phase: review
status: done
next: pr
summary: <how many Done when items are met and how each was shown, in which repos, and that the tests pass>
flags: <each item for the human, with how to check it; any commit that breaks the repo's rules>
EOF
```

Pushing and the pull request are not a skill yet, so the reviewed commits wait on the task's branch for the human.

When a Done when item is not met, or the tests fail, the work goes back to build. First run `entourage task log <project> <card ID>`. If it already shows a review with `next: build` for this card, build has been sent back once already: go to the next block instead. Otherwise send it back:

```
entourage task handoff <project> <card ID> <<'EOF'
phase: review
status: done
next: build
summary: <each Done when item that is not met and why, and each test that fails>
EOF
```

The step that follows is the `sdlc-build` skill, which reads the Review and builds only what it says is not met.

When build has been sent back before, ask the human whether it should go round again, so build and review don't go back and forth with no one watching:

```
entourage task handoff <project> <card ID> <<'EOF'
phase: review
status: needs-human
summary: <each Done when item that is still not met and why, and what the last round changed>
question: <the items still not met, in a few words>. Build again, or stop here?
options: build again | stop here
EOF
```

When they answer, record it, then hand off as `done` with `next: build` if they want it built again. If they want it stopped, hand off as `failed`, with the items still not met in `reason`.

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

`<project>` is the entourage project this session is in. The words in angle brackets are hints: put your own in their place. The command checks the block, records it and prints it back. Which lines you write depends on the status:

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
| The Linear tools aren't available | Hand off as `failed`. Don't review from memory of the card or from its title |
| A repo the Plan changes has no worktree in the task | Ask the human. The task may have been started with targets that left it out |
| The Plan's Tests line names a test that isn't there | The item is not met. Say which test is missing. Don't write it: that is build's work |
| A test fails only now and then | Run it again. If it fails again, the item is not met. If it passes, say in `flags` that it failed once |
| A write to the card fails | Read the card before doing anything else. Retry once, and only if the Review isn't there, so it can't be added twice |
| The collapsed section shows as plain `>>>` text | Leave the content as it is and tell the human. Don't keep reformatting it |

If something fails that isn't on this list, stop and tell the human what happened. Don't work around it.

## Example

**From the card's Plan**

```
**Tests:**
1. Button shows for a manager: component test in `OrdersPage.test.tsx`
2. Columns, and one row per order: API test in `test_orders_export.py`
3. Same filters and range as on screen: API test with a filtered request, and a component test that the filters are passed
```

**The Review it writes**

```
>>> ## Review
Round 1, on api 3f2a91c and web 8d04e17. The tests pass in both.

- **Met.** Button shows for a manager: `OrdersPage.test.tsx` renders the page as a manager and as a clerk, and finds the button only for the manager.
- **Not met.** Columns, and one row per order: `test_orders_export.py` checks the columns, but no test checks that there is one row per order.
- **Met.** Same filters and range as on screen: the API test sends a filtered request, and the component test checks the filters are passed.

**Commits:** both follow the repo's rules.
>>>
```

**The hand-off at the end**

```
entourage task handoff shop ABC-122 <<'EOF'
phase: review
status: done
next: build
summary: Item 2 is not met: test_orders_export.py checks the CSV's columns but not that it has one row per order. Items 1 and 3 are met, and the tests pass in api and web.
EOF
```
