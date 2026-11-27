---
name: sdlc-define
description: Fill out a Linear card from its title and short description by setting its type label and writing its Specification (Why, Done when, Out of scope). Use this as the first step on any card that has no Specification yet, and whenever asked to define, spec, scope or write up a card, even if the request only says "start on ABC-123" and the card is still just a title and a sentence or two.
---

# Define a card

Define is the first step of the lifecycle. It takes a card that holds a title and a sentence or two, and leaves it with a type and a Specification that says what is wanted and how anyone can tell it is done.

Everything after this step is checked against the Specification. Plan maps its tests to Done when, breakdown cuts along it, build is finished when it is true, and John reads it to approve the card. A vague Specification doesn't slow an agent down. It gets built as whatever the agent guessed.

Define says what and why. How it will be built belongs to plan, and whether it is one piece or several belongs to breakdown. Leave both alone here.

## Before you write anything

1. Get the card. If you weren't given a card ID, ask for one.
2. Read the card with the Linear tools: title, description, labels and comments.
3. If the card already has a Specification section, don't write a second one. Tell John and ask whether he wants it revised.
4. Read the project's `PROJECT.md`, and look at only enough of the product, docs and code to use the right names and to know what exists today. Stop there. Working out the approach is plan's job, and doing it now tends to leak files and design into the Specification.

## 1. Set the type

Every card gets exactly one type. The types come from Conventional Branch, because the type becomes the branch prefix.

| Type | Use it when the change… |
|---|---|
| `feat` | adds behaviour a user, admin or agent can use |
| `fix` | corrects behaviour that was broken |
| `chore` | is neither: a refactor, docs, tests, tooling, infrastructure or a dependency update |

- If two could fit, take the first that does, in this order: `fix`, `feat`, `chore`.
- Work the type out from the title and description even when the card already carries a type label. Labels get added by habit and are often wrong. Replace the label if yours differs.
- Set the type as the card's label in the `Type` label group, which allows one per card. The name is lowercase and exact, because setup uses it as the branch prefix: `<type>/<card-id>-<short-name>`, for example `feat/abc-122-export-orders`.
- If the work is really two types, such as a fix plus an unrelated clean-up, this card keeps its main change. Tell John about the other part and ask whether he wants a second card for it. Don't create that card yourself.

The type is a label only. Don't write it into the card's text.

## 2. Write the Specification

It has three parts.

### Why

One or two lines on the reason. How it reads depends on the type.

| Type | Why reads as |
|---|---|
| `feat` | A story: who can now do what, so that why |
| `fix` | What is broken and who it affects, with how to reproduce it, what was expected and what happens |
| `chore` | What is awkward, missing or out of date, and why now. For a refactor, also what must stay the same |

### Done when

A checklist of three to seven items. A small chore can have fewer. Each item is something a reviewer can check without asking you what you meant.

- **Describe an outcome, not work.** "A manager can download this month's orders as a CSV" is an outcome. "Add an export endpoint" is work, and it can be finished while the outcome is still false.
- **Make it pass or fail.** "The page loads quickly" can't fail. "The orders page shows within two seconds on the seed data" can.
- **Make each item checkable alone.** If two things have to be checked together, they are one item.
- **Cover the unhappy path that matters.** Think about the empty state, bad input and someone without permission, and include the ones a user would actually hit.
- **Turn needs like speed or access into items.** Agents build what the list says. A need that isn't on the list won't be met on purpose.
- **A fix always includes** "A test fails before the fix and passes after." That is what shows the bug was real and is gone.
- **A change that shouldn't alter behaviour, such as a refactor, always includes** "Existing tests pass without being changed." That is what shows behaviour didn't move.
- **Don't split by layer.** An API change and the screen that depends on it belong on the same card. A card that stops at the API can't be checked by anyone using the product.

If you end up with more than seven items, the card is probably more than one thing. Write the items anyway and say so when you finish. Breakdown deals with it after plan.

### Out of scope

Include this only when a reader would reasonably expect something that this card will not do. Otherwise leave it out.

## 3. When to ask John

Ask in the session and wait for the answer when:

- The title and description aren't enough to say who this is for or what done looks like.
- An item depends on a product decision or a fact only he has, such as a limit, a wording, or which users.
- There are two readings that would give different Done when lists.

Ask one question at a time, and offer your best guess so he can answer with a yes. Don't fill a gap with a guess or a placeholder. A made-up criterion reads exactly like a real one, and it will be built.

## 4. Write it to the card

- Leave the original description exactly as it is, at the top. It is the original ask, and later steps read it.
- Append the Specification below it as a collapsible section, so the card stays short when John opens it.
- Add nothing else. No type line, repo, risk or flags, and no approach or file names.

Use this form:

```
>>> ## Specification
**Why:** …

**Done when:**
- [ ] …
- [ ] …

**Out of scope:** …
>>>
```

After writing, read the card back. Check that the original description is unchanged and that the Specification shows as a collapsed section.

## 5. Finish

Tell John in two or three lines:

- The type you set, and whether you replaced a label that was already there.
- How many Done when items there are.
- Anything you weren't sure about, and whether the card looks like more than one thing.

Then stop. Plan is the next step, and John may want to read the Specification first.

## If something goes wrong

| When this happens | Do this |
|---|---|
| The card ID doesn't resolve | Ask John for the ID. Don't pick a card because its title looks similar |
| The Linear tools aren't available | Stop and say so. Show the finished section in the session so the work isn't lost. Don't save it somewhere else and report the step as done |
| A write to the card fails | Read the card before doing anything else. Retry once, and only if the section isn't there, so it can't be added twice |
| The read-back shows that text above your section changed | Put it back from what you read at the start of this run, append your section again, and tell John |
| The collapsed section shows as plain `>>>` text | Leave the content as it is and tell John. Don't keep reformatting it |
| The `Type` label group, or the label you need, doesn't exist | Don't create it. Finish the Specification, and tell John which label is missing |
| The card carries more than one type label | Leave only the one you worked out |

If something fails that isn't on this list, stop and tell John what happened. Don't work around it.

## Example

**The card arrives as**

> **Export orders as CSV**
> Managers keep asking for the raw order list so they can work on it in a spreadsheet. Let them download it.

**Type:** `feat`, set as the label.

**Appended to the card**

```
>>> ## Specification
**Why:** A manager can download the order list as a CSV, so they can analyse it in their own spreadsheet.

**Done when:**
- [ ] On the orders page, a manager sees a Download CSV button.
- [ ] The file has one row per order, with the order number, date, customer, status and total.
- [ ] The file covers the same filters and date range that are showing on screen.
- [ ] With no orders in range, the file has the header row and no others.
- [ ] Someone who is not a manager does not see the button and cannot fetch the file.

**Out of scope:** Scheduled or emailed exports.
>>>
```

Notice what isn't there: no endpoint, no file names, no library. Those are plan's.
