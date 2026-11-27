---
name: sdlc-plan
description: Write the technical plan for a Linear card that already has a Specification by reading the card and the code, then appending a Plan (Approach, Changes, Tests) to the card. Use this after define and before breakdown, and whenever asked to plan a card, scope it technically or work out how to build it, even if the request only says "plan ABC-123" or "how would we build this one".
---

# Plan a card

Plan is the second step of the lifecycle. Define said what is wanted. Plan reads the code and says how it will be built: the approach, the files that change, and how each Done when item will be shown to be true.

Two readers depend on it. John reads it to approve the card, so it has to be short and honest. The build step starts later in a fresh session with only the card, so the plan has to be exact enough to build from cold. A plan that says "update the orders module" helps neither of them.

Plan only reads. It writes no code and makes no branch or worktree. Whether the card is one piece or several is breakdown's job, which comes next.

## Before you write anything

1. Read the card with the Linear tools: the original description and the Specification.
2. If there is no Specification, define hasn't run. Say so and stop.
3. If the card already has a Plan section, don't write a second one. Tell John and ask whether he wants it revised.

## 1. Read the code

Start from the project's `PROJECT.md`. Its sections on what each repo owns tell you where this work belongs.

Then read until you could explain the change to someone who knows the codebase:

- **The guidance above the code you expect to touch.** Read the `CLAUDE.md`, `AGENTS.md` or `.ai/` files on the path down to those files. They hold conventions you can't infer from one file.
- **Where similar work already lives.** Find the closest existing feature and read it end to end. The best plan is usually "built like that one".
- **What you can reuse.** Look for shared helpers, components and test utilities before planning a new one.
- **How it is tested.** Find the tests for the closest feature, and note the level they work at and how they are set up.

The repo clones linked into the project are shared reference copies. Don't switch branches or edit anything in them. Fetch first, and if a clone isn't on an up-to-date base branch, read from the remote base branch with git instead of from the working files.

## 2. Write the Plan

It has three parts.

### Approach

A few sentences on how it will be built. Name the existing pattern it follows and where that pattern lives.

- If you chose between two real options, add one line on the one you rejected and why. It saves John asking.
- If the work needs a new dependency, say so here. That is a decision John should see.
- If the work needs more than one repo, say which and why.

### Changes

The files you expect to touch, grouped by app or package. Give each one a few words on what changes.

- Write each path from the repo root, starting with the repo's name, so the repo never needs stating separately.
- Mark new files as new.
- Include the unglamorous ones: migrations, config, seed data, docs.
- Name the helpers you will reuse.
- Check that every existing path you write is real. A path you guessed reads exactly like one you checked, and the build step will trust it.

This is a list of where and what, not code. Don't write the implementation.

### Tests

One line for each Done when item, in the same order, saying how it will be shown to be true.

- Prefer a test, and say what level it works at and which file it goes in.
- Where a test can't prove the item, say what will: a screenshot, or the output of a command.
- Every Done when item gets a line. An item with no line is an item nobody will check.
- For a fix, the first test reproduces the bug and fails before the change.
- For a change that shouldn't alter behaviour, name the existing tests that cover it. No new ones are needed.

## 3. Stay inside the Specification

Plan never edits the Specification or the original description. They are what John asked for, and the plan answers to them.

- **A Done when item can't be met as written.** The code may show that an item is impossible, contradicts how the product works, or costs far more than the card suggests. Ask John before going any further, in a handoff block with `status: needs-human`. He may change the Specification. You may not.
- **A technical question.** Settle it from the code where you can. Ask John only what the code can't answer, such as an upcoming change that affects the approach, or a choice between two workable options with different costs. Ask one question at a time, in a handoff block with `status: needs-human` and your recommendation first in `options`.
- **Something outside the Specification.** While reading you may find a nearby bug, a missing test or a refactor that would help. Leave it out of the plan and put it in `flags` when you hand off. Folding it in makes the card bigger than what he approved.

## 4. Write it to the card

- Append the Plan below the Specification as a collapsible section.
- Change nothing above it.
- Add nothing else: no repo line, no risk, no open questions.

Use this form:

```
>>> ## Plan
**Approach:** …

**Changes:**
- `repo/path/to/file`: what changes
- `repo/path/to/new-file` (new): what it holds

**Tests:**
1. <Done when item, in a few words>: how it is shown
2. …
>>>
```

After writing, read the card back. Check that the description and Specification are unchanged and that the Plan shows as a collapsed section.

## 5. Hand off

When the Plan is on the card and you have read it back, end with a handoff block:

- `phase: plan`, `status: done` and `next: breakdown`.
- `summary`: the approach in one sentence, roughly how much it touches (how many files, in which apps or repos), and whether it looks like one pull request's worth or more. Breakdown decides, but your read is useful.
- `flags`: anything you found that sits outside the Specification.

## The handoff block

Every step of the lifecycle ends the same way, so whoever is driving it, a person or a script, can tell how the step ended without reading the whole session.

End your message with one handoff block every time you stop: when the step is finished, when you need an answer, and when something has gone wrong. Put it last, in a code block, one value per line:

```
phase: <this step>
status: <done, needs-human or failed>
next: <the step that follows>
summary: <one to three sentences on what you did>
flags: <what the human should know but wasn't asked>
question: <one question>
options: <the answers you expect, your recommendation first, separated by " | ">
reason: <what went wrong, and what you already tried>
```

Which lines you write depends on the status:

| Status | Use it when | Lines |
|---|---|---|
| `done` | This step's work is on the card and you have read it back | `phase`, `status`, `next`, `summary`, and `flags` if there are any |
| `needs-human` | You can't go on without an answer or an approval | `phase`, `status`, `question`, `options`, and `summary` if it helps them answer |
| `failed` | Something is missing or went wrong, and this skill tells you to stop or doesn't cover it | `phase`, `status`, `reason` |

- **Wherever this skill says to ask, tell or stop, use the block.** An ask is `needs-human`. Something to tell goes in `flags`. A stop because something is missing or went wrong is `failed`.
- **`needs-human` is a pause, not an ending.** Wait for the answer, then carry on with this step. The step is over only at `done` or `failed`.
- **Ask one question per block.** If you have two, ask first the one whose answer could change the other. The human can always answer in their own words, so `options` are suggestions.
- **Keep the block short.** Anything long, such as a section you could not write to the card, goes above the block.
- **After `done`, this step is over.** Go on to the step in `next` only if you were asked to run more than this one step. Otherwise stop there.
- **After `failed`, change nothing more.** Leave the card as it is for the human.

## If something goes wrong

| When this happens | Do this |
|---|---|
| The card ID doesn't resolve | Ask John for the ID. Don't pick a card because its title looks similar |
| The Linear tools aren't available | Stop and say so. Show the finished section in the session so the work isn't lost. Don't save it somewhere else and report the step as done |
| A write to the card fails | Read the card before doing anything else. Retry once, and only if the section isn't there, so it can't be added twice |
| The read-back shows that text above your section changed | Put it back from what you read at the start of this run, append your section again, and tell John |
| The collapsed section shows as plain `>>>` text | Leave the content as it is and tell John. Don't keep reformatting it |
| A repo named in `PROJECT.md` is missing, or the fetch fails | Tell John, and ask whether to plan from what is on disk |
| You can't tell which repo the work belongs in | Ask John. Don't guess paths |
| A path you were about to write doesn't exist | Find the real one, or mark the file as new. Never leave a path you haven't checked |

If something fails that isn't on this list, stop and tell John what happened. Don't work around it.

## Example

**The card's Specification**

```
**Why:** A manager can download the order list as a CSV, so they can analyse it in their own spreadsheet.

**Done when:**
- [ ] On the orders page, a manager sees a Download CSV button.
- [ ] The file has one row per order, with the order number, date, customer, status and total.
- [ ] The file covers the same filters and date range that are showing on screen.
- [ ] With no orders in range, the file has the header row and no others.
- [ ] Someone who is not a manager does not see the button and cannot fetch the file.
```

**Appended to the card**

```
>>> ## Plan
**Approach:** Add a CSV response to the existing orders list endpoint, and a button on the orders page that calls it with the filters currently applied. This follows the invoice export, which already streams a CSV the same way. A separate export endpoint was rejected because it would duplicate the list endpoint's filtering.

**Changes:**
- `shop/api/app/orders/routes.py`: accept `format=csv` on the list route, managers only
- `shop/api/app/orders/export.py` (new): turn the filtered query into CSV rows, reusing `csv_stream` from `shop/api/app/common/export.py`
- `shop/web/src/pages/orders/OrdersPage.tsx`: Download CSV button, shown to managers, passing the current filters
- `shop/web/src/api/orders.ts`: `downloadOrdersCsv(filters)`

**Tests:**
1. Button shows for a manager: component test in `OrdersPage.test.tsx`
2. Columns, and one row per order: API test in `test_orders_export.py`
3. Same filters and range as on screen: API test with a filtered request, and a component test that the filters are passed
4. Empty range gives the header only: API test in `test_orders_export.py`
5. A non-manager can't see or fetch it: component test for the button, API test for a 403
>>>
```
