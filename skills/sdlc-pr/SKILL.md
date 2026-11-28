---
name: sdlc-pr
description: Put a reviewed Linear card up as pull requests, by pushing the task's branch in each repo the work changed, opening a pull request into that repo's default branch that names the card and says how the review step showed each Done when item, moving the card to In Review once they are all open, waiting for the human to merge them while watching them on GitHub, making in the same pull requests any change they ask for in the tab and bringing one that comes to conflict with its default branch up to date, recording the merge once GitHub shows it, without being told, and then finishing the task. Use this once sdlc-review has handed off done with pr next, whenever asked to push, open the pull request for, or put up a reviewed card in its task, even if the request only says "pr ABC-123". It never merges a pull request.
---

# Open the pull request

Pull request is the step after the review step. The build step made the change the Plan describes and committed it on the task's branch, and the review step checked that work against the card's Done when and wrote what it found on the card as its Review. This step pushes the branch, opens a pull request in each repo the work changed, moves the card to In Review once they are all open, watches them on GitHub while the human merges them, makes in the same pull requests any change they ask for in the tab while they wait, brings a pull request up to date when it comes to conflict with its default branch, records the merge once GitHub shows it, without the human having to say so, and then finishes the task, which removes its worktrees and closes its tab.

The human reads the pull request, not this session. So each pull request has to name the card and say, for each Done when item, how the review step showed that it is met and what is left to the human to check.

The human merges. Never run `gh pr merge`, not even with `--auto`, and never turn on auto-merge in the repo's settings on GitHub. Push the task's branch and nothing else, and never forced.

## Before you push anything

1. Get the card. If you weren't given a card ID, ask for one.
2. Read the card with `entourage linear read <card ID>`: the original description, the Specification, the Plan, the Breakdown, the Review and the comments.
3. If the card has no Plan, it was not approved to build. Push nothing, and hand off as `failed`, saying so.
4. If the Breakdown cut the card into several slices, each slice is a sub-issue that is built, reviewed and put up as a pull request on its own. Push nothing, and hand off as `failed`, naming the sub-issue that comes first.
5. Open nothing unless the Review passed the work. The `sdlc-review` skill writes the Review on the card, as a collapsed section after the Breakdown, and marks each Done when item **Met.**, **Not met.** or **For the human.** If the card has no Review, an item in it is **Not met.**, or it says the tests fail, the work has not passed: push nothing, and hand off as `failed`, saying which. An item **For the human.** does not hold the pull request back. It goes in the description, as what is left to the human.
6. Check where you are, as the build step did. The work is in the task's worktrees, which `entourage task start` made under the project's `tasks/` folder, one for each repo, all on the task's branch. Run `git branch --show-current` in each one. The branch has to name this card, as in `feat/abc-122-short-name`. If you are in a repo's own checkout, on its default branch, or on a branch for another card, push nothing and hand off as `failed`, saying where you are.
7. Run `git status` in each worktree. The review step leaves nothing uncommitted, and nothing uncommitted goes into a pull request. If a worktree has changes, push nothing, and hand off as `failed`, naming the worktree and its changed files.

## 1. Find what the work changed

The task started from each repo's default branch, so the work is the commits that branch doesn't have. In each worktree, run `git fetch origin`, then `git log --oneline origin/main..HEAD`, with the repo's own default branch in place of `main`. `git symbolic-ref --short refs/remotes/origin/HEAD` names it, as `origin/<branch>`.

The worktrees with commits ahead of the default branch are the repos the work changed. Each of them gets a pull request, and no other. A worktree with no `origin`, or one whose fetch fails, is held to its local default branch instead (`git log --oneline main..HEAD`): with no commits there it needs no pull request, and with commits the checks in section 2 stop the push.

If no worktree has commits ahead of its default branch, there is nothing to open. Hand off as `failed`, saying so.

## 2. Check that you can push

Check everything that could stop the push or the pull request before you push anything, so that nothing goes up by half. When a check fails, push nothing, not even in a worktree that passed it, and hand off as `failed`, with the reason and what the human can run to put it right.

1. Run `gh auth status`. If `gh` is missing or not signed in to GitHub, the reason is that, and what to run is `gh auth login`.
2. In each worktree with commits, run `git remote get-url origin`. A repo with no `origin` can't be pushed: what to run is `git remote add origin <the repo's URL>`.
3. In each of those worktrees, run `gh repo view --json nameWithOwner,defaultBranchRef`. It has to know the repo, and the default branch it gives is the one the pull request goes into. If it gives another branch than section 1 used, find the commits again against this one. If it fails, give what it said.

## 3. Read how the repo takes a pull request

Read the guidance in each worktree with commits: its `CLAUDE.md`, `AGENTS.md`, `README` and any `CONTRIBUTING` file, and its pull request template, `.github/pull_request_template.md`. GitHub also takes the template at the repo's root, in `docs/`, or as a file in `.github/PULL_REQUEST_TEMPLATE/`. Look for three things:

- **How a pull request is written.** The form of its title, the sections its description must have, and a line or a checklist it must hold.
- **How commits are written.** The review step checked the commits, and its Review says so in its **Commits:** line. If that line names a commit that breaks one of the repo's rules, push nothing and ask the human whether to open the pull request anyway, in a handoff block with `status: needs-human`. Rewriting commits is not for this step.
- **Rules for a change like this one.** A version that only a release changes, or a file that must not be in a commit. Check the commits against a rule the Review does not mention, and ask the human the same way if one breaks it.

## 4. Push the branch and open the pull request

**Back from section 8.** When this step runs again after section 8 brought a pull request up to date and the review step passed the work again, the pull requests are open already: `entourage task log <project> <card ID>` shows the last `pr` hand-off as `done`, with `review` next. Push only a branch that moved. In each worktree with commits, run `git fetch origin`, then `git log --oneline origin/<branch>..HEAD`: when it shows nothing, GitHub has every commit already, so push nothing in that worktree and leave its pull request as it is, open or merged. A branch that moved goes through the list below, but its pull request keeps the title and the description it has, **Changes asked for:** lines and all. Read the description with `gh pr view <url> --json body`, add a line at its end under **Brought up to date:**, putting that heading in the first time, and give it to `gh pr edit` in item 5. The line says what the hand-off of section 8 said in its summary: the merge commit, the files that conflicted and what the fix changed.

For each worktree with commits, and no other:

1. Push the task's branch: `git push -u origin <branch>`. It is never forced: no `--force` and no `--force-with-lease`. If the push is refused, for example because the branch on GitHub has commits this one doesn't, don't force it, pull or rebase. Hand off as `failed`, with what git said, and name any repo already pushed.
2. Write the title by the repo's rules. Where it has none, write it as the build step's commits are written, such as `feat: export orders as CSV`.
3. Write the description, by the repo's template where it has one. It links the card, with its ID and its Linear URL. It lists each Done when item, in the card's words, with how the review step showed it, taken from the Review. An item for the human says what is left to the human: what to run, and what they should see. When the card has pull requests in several repos, each one links the others.
4. Write the description to a file, and give it with `--body-file`. On the command line, the shell would run what is between backticks in it.
5. Run `gh pr list --head <branch> --state open --json number,url`. If the branch already has an open pull request, update it with `gh pr edit <number> --title <title> --body-file <file>` rather than opening another. Otherwise open one into the default branch: `gh pr create --base <default branch> --head <branch> --title <title> --body-file <file>`. If it fails, hand off as `failed`, with what `gh` said and which branches are already pushed.
6. With several repos, open them all first, then edit each description to link the others.
7. Read each pull request back with `gh pr view <url> --json url,title,body,baseRefName,headRefName`, and check that it goes from the task's branch into the default branch and that its description says what you wrote.

Then, once every pull request is open and read back, move the card in Linear to its team's last started status, In Review:

```sh
entourage linear move <card ID> review
```

Run it once, after the last pull request is read back, never in the list above: with pull requests in several repos, the card does not move before the last one is open. The status is picked by its kind and its place in the team's order, so in a team with only one started status the card stays in it. A card that is there already, further on, done or canceled stays where it is, and the command says so. Change nothing else on the card.

If the command exits non-zero, the card was not moved, and what it printed says why, such as Linear out of reach or a key without Write permission. Don't stop for it, don't run it again, and don't move the card with the Linear tools instead: go on to wait for the merge. Say in the summary of the hand-off that waits that the card was not moved, and why, and put the same in `flags` when the step hands off `done`.

## 5. Wait for the merge

With every pull request open, hand off as `needs-human` with their links:

```
entourage task handoff <project> <card ID> <<'EOF'
phase: pr
status: needs-human
summary: <the pull requests opened, one for each repo the work changed, what is left to the human in them, and why the card was not moved to In Review, if it was not>
question: Merge <the link of each pull request>. I watch GitHub and record the merge myself; tell me here if you want a change instead.
options: merged | a change you want made | stop here
EOF
```

Then start `entourage task watch <project> <card ID>` in the background, the way your tools run a long command without waiting for it to end, such as `run_in_background` in Claude Code. You are told when it ends, and can answer the human meanwhile. It asks GitHub about each pull request for the card on a schedule: every minute for the first 10 minutes after the newest was opened, every 5 minutes for the hour after that, then every 30 minutes. Each check prints a line for each pull request, `merged`, `open` or `closed` and its URL, and it ends only once every one has merged or one is closed. It costs nothing while it sleeps. Start it once: an answer from the human, or a change made as section 6 says, leaves it running. A watch that has ended, as it does with 4, is started again when you come back here from section 4 once the pull request is brought up to date. It counts from when the pull request was opened, so it goes on where it was. When it ends:

- **It ends with 0: every pull request for the card has merged.** Its last lines say `merged` for each. The human typed nothing, but the merge is their answer, so record it as one. That way `entourage task log` shows how long the pull requests waited on them, as it does for an answer typed in the tab:

  ```
  entourage task handoff <project> <card ID> <<'EOF'
  phase: pr
  status: answered
  answer: merged on GitHub, seen by the watch
  EOF
  ```

  Then hand off as section 7 says.
- **It ends with 3: a pull request was closed without merging.** Its last lines name it, with `closed`. Record that first, as the answer:

  ```
  entourage task handoff <project> <card ID> <<'EOF'
  phase: pr
  status: answered
  answer: closed on GitHub, <its link>
  EOF
  ```

  Then ask the human whether to stop here, as `needs-human`, naming it. If they want it stopped, hand off as `failed`, with the pull request that was closed in `reason`. Run no `task finish`, whatever they answer. A card whose pull request was closed never reaches section 7, so its task stays as it is, with its work. If they reopen it, start the watch again.
- **It ends with 4: a pull request is in conflict with its default branch.** Its last lines name it, with `conflict`: GitHub cannot merge it as it is. A closed one would have ended it with 3 instead, since the human is asked about that first. Record the conflict first, as the answer:

  ```
  entourage task handoff <project> <card ID> <<'EOF'
  phase: pr
  status: answered
  answer: in conflict on GitHub, <its link>
  EOF
  ```

  Then bring it up to date as section 8, "Bring a pull request up to date", says, without asking the human first.
- **It ends with 1, or keeps saying it could not ask GitHub.** See the table in "If something goes wrong".

When the human answers in the tab, record the answer first, as the handoff block section says. Then:

- **They say it has merged.** Check at once with `entourage task watch <project> <card ID> --once`, which checks once and does not wait: it exits with 0 when every pull request for the card has merged, 2 while one is still open, and 3 when one was closed. With 0, stop the watch in the background, and hand off as section 7 says. With 2, hand off as `needs-human` again, naming the one that has not merged, and leave the watch in the background running. With 3, ask whether to stop, as for a watch that ends with 3. With 4, one is in conflict: stop the watch in the background, and bring it up to date as section 8, "Bring a pull request up to date", says.
- **They ask for a change.** Make it as section 6 says, then wait again. The watch in the background goes on: don't start another.
- **They say to stop.** Stop the watch in the background, and hand off as `failed`, with the pull requests that are still open in `reason`. Leave them open, as they are.

Record the merge once, whichever saw it first: a watch that ends after the merge is recorded needs nothing more. Whatever happens, the human merges. Never run `gh pr merge` yourself, never turn on auto-merge, and never close a pull request.

## 6. Make a change asked for in the tab

The human reads the pull requests, and may want something changed before they merge. They say so in the tab, as their answer to the wait. The change goes into the same pull requests: on the task's branch, in the worktree of the repo it belongs in. Only what the human says in the tab is a change to make here. Comments from a GitHub review, and CI results, are not read in this step.

Ask first, as `needs-human`, before you make a change that would alter what the human approved on the card: one that adds, drops or changes a Done when item, takes another approach than the Plan's, or brings in a new dependency. Ask first too when the change belongs in a repo that has no open pull request for the card, because the pull request there has merged or there never was one; `gh pr view <url> --json state` says which. Say what the change would alter, and make it only once they say yes. A repo that has no open pull request gets one once the change is pushed, opened as section 4 says.

Then, for each change asked for:

1. Make it in the worktree, on the task's branch, as the build step does: by the repo's rules for a change like this one, which section 3 found, and with a test where it changes what the code does, written first and seen to fail.
2. Run the repo's whole test suite. If a test fails, find out why and fix it. Change a test only when the change asked for changes what that test checks. If the tests can't be made to pass, commit and push nothing, leave the change in the worktree as it is, and hand off as `failed`, with the failing tests and what you tried in `reason`. The pull requests stay open as they are.
3. Commit on the task's branch with `git commit`, by the repo's rules for commits. Don't skip its commit hooks. `git status` shows no changes after.
4. Push it with `git push`, never forced. If the push is refused, don't force it, pull or rebase. Hand off as `failed`, with what git said.
5. Add what changed to the pull request's description, so whoever reads it sees what was asked for and which commit made it. Read the description with `gh pr view <url> --json body`, add a line for the change under **Changes asked for:** at its end, putting that heading in the first time, write it to a file, and give it with `gh pr edit <number> --body-file <file>`.
6. Read the pull request back with `gh pr view <url> --json body,commits`, and check that its description says what you wrote and that the new commit is in it.

Then hand off as `needs-human` again, with the links, and wait as section 5 says. The watch in the background is still running, and a pull request just opened for the change is in its next check:

```
entourage task handoff <project> <card ID> <<'EOF'
phase: pr
status: needs-human
summary: <the change made, the commit in each pull request that makes it, and that the tests pass>
question: Merge <the link of each pull request>. I watch GitHub and record the merge myself; tell me here if you want a change instead.
options: merged | a change you want made | stop here
EOF
```

## 7. Hand off

When every pull request for the card has merged, as the watch saw it or `--once` showed it, record the hand-off. The step is not finished until it is recorded:

```
entourage task handoff <project> <card ID> <<'EOF'
phase: pr
status: done
next: merged
summary: <each pull request, and the default branch it merged into>
flags: <each item that was left to the human, a card that was not moved to In Review and why, and anything else they should know>
EOF
```

Put your own words in place of each hint in angle brackets, and leave the `flags` line out when there is nothing to flag. `merged` is where the card ends. No step comes after it, and nothing hands off as it.

Then finish the task. Run this right after the hand-off is recorded. It is the run's last command:

```
entourage task finish <project> <card ID>
```

It removes the task's worktrees, deletes the task's branch in each repo, removes the task's folder and then closes the task's tab. That is the tab this session runs in when `entourage task build` started it. Closing the tab is the last thing it does, and it ends the session. So record the hand-off first, and run nothing after it. The branch on GitHub is left alone: the repo's own settings delete it or keep it.

`task finish` checks every repo before it removes anything. If removing the task would lose work, it removes nothing, and names each thing that would be lost under the repo it is in: changes that are not committed, commits that are not in the default branch, such as a fix pushed after the merge, and ignored files that the repo's setup does not make again, such as a design doc or an `.env`. Then tell the human everything it named, as it said it, and that the task is left as it is. The merge is recorded already, so record no other hand-off. Change nothing more. Don't commit, push or remove anything to get `task finish` through, and don't remove the task by hand. What to keep is the human's call. The same goes for any other stop. It may find no task for the card, or stop partway and name what it removed. Tell the human what it said. When it finishes the task but leaves the tab open, because Herdr is not running or has no such tab, tell the human that too.

## 8. Bring a pull request up to date

The watch ends with 4 when a pull request is in conflict with its default branch: the default branch has moved on since the task started, and GitHub cannot merge the two as they are. Bring it up to date without asking the human, so that it is ready to merge when they come to it. Bring up to date only each pull request the watch named `conflict`: a pull request with no conflict gets no push.

Take the default branch by a merge, never a rebase. A rebase rewrites the branch, and only a forced push would put it on GitHub, which this step never makes.

In the worktree of each repo whose pull request is in conflict, on the task's branch:

1. Run `git fetch origin`, then `git merge origin/<default branch>`, with the default branch section 2 found. git stops with the files in conflict, and `git status` lists them. Note them: the hand-off and the pull request name them. When git merges it with no conflict, as it does when the default branch has moved again since GitHub looked, it commits the merge itself: go on to item 3.
2. Resolve each one, keeping both what the card's work does and what the default branch has done since. `git log HEAD..origin/<default branch> -- <file>` lists the commits that changed it there.
3. Run the repo's whole test suite, as section 6 does. If a test fails, find out why and fix it. Change a test only when the default branch changed what that test checks.
4. Commit the merge with `git commit`, by the repo's rules for commits. Where they say nothing of a merge, keep the message git wrote for it, with `git commit --no-edit`. Don't skip its commit hooks. A fix the tests needed goes in the merge, or in a commit after it. `git status` shows no changes after.
5. Push nothing yet. The review step checks the merge first, and section 4 pushes it once the review step has passed the work again.

Ask the human only when you cannot settle the conflict: when the tests cannot be made to pass, or when a resolution would change what a Done when item says, such as when the default branch now does what an item asks for in another way, or has taken away something the work builds on. Then leave the merge in the worktree as it is, and hand off as `needs-human`, naming the pull request and the files in conflict:

```
entourage task handoff <project> <card ID> <<'EOF'
phase: pr
status: needs-human
summary: <why it cannot be settled: the tests that fail and what you tried, or the Done when item a resolution would change, and how>
question: <the pull request> is in conflict with <the default branch> in <the files in conflict>. <the resolution you recommend>?
options: <your recommendation> | <another resolution> | stop here
EOF
```

Until they answer, commit and push nothing. When they answer, record the answer first, as the handoff block section says, then settle the conflict the way they say, from item 2 above. If they say to stop, hand off as `failed`, with the pull request and the files in conflict in `reason`, and leave the merge in the worktree as it is, for them.

Once the merge is committed and the tests pass, record the hand-off:

```
entourage task handoff <project> <card ID> <<'EOF'
phase: pr
status: done
next: review
summary: <the pull request brought up to date, the merge commit, the files that conflicted and what the fix changed, and that the tests pass>
EOF
```

The step that follows is the `sdlc-review` skill. It checks each Done when item again, now with the merge commit, revises the card's Review, and hands back to this step with `pr` next. This step then runs again from the top. Section 4 finds the pull requests open, pushes only the branch that moved, never forced, and adds the **Brought up to date:** line to its description. Section 5 waits for the merge again, with the watch started again.

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
| The Linear tools aren't available | Hand off as `failed`. Don't open a pull request from memory of the card or from its title |
| `entourage linear read` says no Linear key is saved or that Linear rejected the key, or the command isn't there | Read the card with the Linear tools instead, and say so in `flags` when you hand off |
| `gh` is missing or not signed in | Hand off as `failed`, saying to run `gh auth login`. Push nothing |
| A repo with commits has no `origin`, or `gh repo view` doesn't know it | Hand off as `failed`, naming the repo and what to run. Push nothing, in any repo |
| The push is refused | Hand off as `failed`, with what git said. Never force it, and don't pull or rebase to get it through |
| `gh pr create` or `gh pr edit` fails | Hand off as `failed`, with what `gh` said and which branches are already pushed |
| The branch already has an open pull request | Update it with `gh pr edit`. Don't open a second one |
| `entourage linear move` exits non-zero | The card was not moved. Say so, and why, in the summary of the hand-off that waits, and in `flags` when the step hands off `done`, and go on to wait for the merge. Don't move it with the Linear tools |
| The human says it has merged, and the watch's `--once` says it is open | Name the pull request that has not merged, and ask again. Leave the watch in the background running |
| A pull request was closed without merging | Ask the human whether to stop. Don't reopen it or open another, and run no `task finish`: the task stays |
| A pull request is in conflict, and the tests cannot be made to pass or a resolution would change what a Done when item says | Hand off as `needs-human`, naming the pull request and the files in conflict, as section 8 says. Commit and push nothing until the human answers. Never rebase, and never force a push to get past it |
| The watch ends with 1, or keeps saying it could not ask GitHub | Hand off as `needs-human`, with what it said and what would put it right, such as `gh auth login`. Start the watch again once the human says it is right. Never merge to get past it |
| `task finish` refuses, or stops partway | Tell the human everything it named, and that the task is left as it is. Record no other hand-off, and change nothing to get it through |
| The human asks for a change | Make it as section 6 says, push it and wait again. Ask first if it would alter what they approved on the card |
| The tests fail after a change asked for, and can't be made to pass | Hand off as `failed`, with the failing tests. Commit and push nothing, and leave the pull requests open |

If something fails that isn't on this list, stop and tell the human what happened. Don't work around it, and never merge a pull request to get past it.

## Example

**From the card's Review**

```
>>> ## Review
Round 1, on api 3f2a91c and web 8d04e17. The tests pass in both.

- **Met.** Button shows for a manager: `OrdersPage.test.tsx` renders the page as a manager and as a clerk, and finds the button only for the manager.
- **Met.** Columns, and one row per order: `test_orders_export.py` checks the columns, and that a file of three orders has three rows.
- **For the human.** Opens in a spreadsheet: download the file from the orders page, and open it in a spreadsheet app.

**Commits:** both follow the repo's rules.
>>>
```

**The description of the pull request in api**

```
Builds [ABC-122](https://linear.app/acme/issue/ABC-122/export-orders-as-csv): Export orders as CSV. The web side is in acme/web#88.

**Done when:**

- **Met.** A manager sees a Download CSV button: `OrdersPage.test.tsx` renders the page as a manager and as a clerk, and finds the button only for the manager.
- **Met.** The file has the order's columns, and one row per order: `test_orders_export.py` checks the columns, and that a file of three orders has three rows.
- **Left to you.** The file opens in a spreadsheet: download it from the orders page, and open it in a spreadsheet app.
```

**The hand-offs**

```
entourage task handoff shop ABC-122 <<'EOF'
phase: pr
status: needs-human
summary: Opened acme/api#141 and acme/web#88 into main, each linking the card and the other, and moved ABC-122 to In Review. One item is left to you: open the file in a spreadsheet.
question: Merge https://github.com/acme/api/pull/141 and https://github.com/acme/web/pull/88. I watch GitHub and record the merge myself; tell me here if you want a change instead.
options: merged | a change you want made | stop here
EOF
```

```
entourage task handoff shop ABC-122 <<'EOF'
phase: pr
status: answered
answer: name the file by the day it was made
EOF
```

```
entourage task handoff shop ABC-122 <<'EOF'
phase: pr
status: needs-human
summary: The file is named orders-YYYY-MM-DD.csv now, with its test, in commit 5c1e0d2 on acme/api#141, and its description lists the change. Both test suites pass.
question: Merge https://github.com/acme/api/pull/141 and https://github.com/acme/web/pull/88. I watch GitHub and record the merge myself; tell me here if you want a change instead.
options: merged | a change you want made | stop here
EOF
```

```
entourage task handoff shop ABC-122 <<'EOF'
phase: pr
status: answered
answer: merged on GitHub, seen by the watch
EOF
```

```
entourage task handoff shop ABC-122 <<'EOF'
phase: pr
status: done
next: merged
summary: acme/api#141 and acme/web#88 have both merged into main.
EOF
```

**The last command**

```
entourage task finish shop ABC-122
```
