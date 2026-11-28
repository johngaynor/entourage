---
name: sdlc-breakdown
description: Decide whether a planned Linear card is one piece or several, by cutting it into thin end-to-end slices (elephant carpaccio) where it can be cut, then, once the human approves, creating each slice as a sub-issue. Use this after plan on every card, and whenever asked to break down, slice or split a card, or to judge whether a card is too big for one pull request.
---

# Break down a card

Breakdown is the third step of the lifecycle. Define said what is wanted and plan said how. Breakdown decides whether the card is built as one piece or as several, and if several, what each piece is.

The method is elephant carpaccio: cut the work into slices so thin that each one is small, yet each still works end to end. The aim is the earliest usable slice, followed by slices that extend it. Useful comes before done.

Thin slices matter more when an agent is building. Each slice can be checked end to end as soon as it merges, a mistake stays inside one small pull request, and if the third slice never ships, the first two still work.

This skill has two parts. Proposing, and asking the human to approve, happens on every card. Creating sub-issues happens only after they approve a card that was sliced.

## Before you write anything

1. Read the card with the Linear tools: the Specification and the Plan.
2. If either is missing, the earlier step hasn't run. Say so and stop.
3. If the card is itself a sub-issue, don't slice it again. Slices go one level deep. If it looks too big, say so when you ask the human to approve.
4. If the card already has a Breakdown section, don't write a second one. If the human has asked for it to be revised, revise it in place. Otherwise tell the human and ask whether they want it revised, and if they don't, go on to ask them to approve the card.

## Part 1: Propose

### First, is it already small?

Look at the plan's Changes. If the whole card is one agent, one sitting and one quick pull request, it stands as one piece, even if you could cut it further. Every slice costs the human a pull request to read and merge, so don't slice for its own sake.

### If it is too big, try to cut it

Cut along behaviour, using Done when as the map. Use the plan only to judge size and order.

A piece is a slice only if it passes all four checks:

1. **Vertical.** It carries one narrow piece of behaviour through every layer it needs. "The database part" and "the API part" are layers, not slices.
2. **Testable end to end.** Once it merges, there is something to click, read or call, and its own Done when can be checked without the later slices.
3. **Mergeable alone.** It is safe on main if nothing after it ever ships. Feature flags aren't available, so a slice has to be acceptable for users to see as it is.
4. **Small.** One agent, one sitting, one quick pull request.

Ways to make a slice thinner while keeping it end to end:

- One case before many.
- A fixed choice before a configurable one.
- Reading before writing.
- The main path before the rare ones.
- One kind of user before the others.

Permission and safety checks are not something to thin out. They go in the first slice that exposes the thing they protect, because a slice that ships an unprotected endpoint isn't mergeable alone.

Then check the set:

- **The first slice is the thinnest path that works.** Each later slice extends the one before.
- **Nothing is lost.** Every Done when item on the card is covered by a slice, whole or narrowed across more than one.
- **Nothing is added.** Slices divide the Specification. They don't grow it.
- **Each slice has its own Done when**, one to four outcomes written by the same rules as the card's.
- **The slices run in order.** Each builds on the last.

Two to five slices is usual. If you need more than six, the card is probably several cards. Propose what you have and say so when you ask the human to approve.

### If it can't be cut

Some work has no cut that passes the checks. A refactor may have nothing to click halfway through. A migration may have to land together. A first slice may not be acceptable for users to see without the rest.

Then the card stands as one piece, however large it is. Don't force a cut that fails a check. A horizontal slice is worse than a large card, because it merges something nobody can test. Say in one line why it can't be cut, and if it is large, say so when you ask the human to approve.

### Write it to the card

Append a Breakdown section below the Plan. Leave it open, not collapsible, because it is what the human reads to approve the card. Change nothing above it.

Write it with this command, the section's body on stdin. The command adds the `## Breakdown` heading, leaves the section open, and reads the card back before it says it is done.

For one piece:

```
entourage linear section <card ID> Breakdown <<'EOF'
One piece. <one line on why: already small, or why it can't be cut>
EOF
```

For slices:

```
entourage linear section <card ID> Breakdown <<'EOF'
1. **<slice name: a short phrase for the behaviour>**
   - [ ] <its Done when>
   - [ ] …
2. **<slice name>**
   - [ ] …
EOF
```

To change a Breakdown that is already on the card, run the same command with `--replace` after the section name.

Create nothing else in Linear yet. A proposal the human turns down should leave nothing behind to clean up.

### Ask the human to approve

Breakdown is the last step of the write-up phase, so it ends by asking the human to approve the whole card: the Specification, the Plan and the Breakdown together. This happens on every card, sliced or not.

Give them a summary they can answer from without opening Linear:

- The type.
- The Done when list.
- The approach, in a sentence or two.
- Whether it is one piece or several, and why. If several, the slice names in order.

Then ask them to approve or say what to change. Record the ask as a hand-off with this block, then end your message with the summary and, below it, the block the command printed:

```
entourage task handoff <project> <card ID> <<'EOF'
phase: breakdown
status: needs-human
question: Approve <card ID> as specified, planned and broken down?
options: approve | change breakdown | change plan | change specification
EOF
```

Wait for their answer.

| The human says | Then |
|---|---|
| Change the breakdown | Revise the Breakdown section, with `--replace`, and ask again |
| Change the Specification or the Plan | Make the change by that section's own skill, `sdlc-define` or `sdlc-plan`, as a revision the human asked for. That skill ends with its own `done` block, whose `next` does not apply here: come back to this step and re-check every section below the one that changed, because a new Done when item can make the Plan and the Breakdown wrong. Ask again |
| Approve, and the card is one piece | The card is ready to build. Hand off, as described below |
| Approve, and the card is sliced | Go on to part 2 |

## Part 2: Create the sub-issues

Do this only when the human has approved the card in this session, and only when the breakdown has more than one slice.

For each slice, in order:

1. **Create a sub-issue of the card** with the Linear tools. Its title is the slice name. Its description is one or two sentences saying what this slice delivers, and nothing else: its sections come next. Mark it as blocked by the slice before it. The first slice is blocked by nothing.
2. **Set its type**, which is the parent's type. Slices don't get a type of their own. Give the sub-issue's own ID:

   ```
   entourage linear type <sub-issue ID> <type>
   ```
3. **Write its sections** in the same form as any card, each with its own command and the sub-issue's ID, in this order:
   - A Specification, with the parent's Why narrowed to this slice, and the slice's Done when: `entourage linear section <sub-issue ID> Specification <<'EOF'`.
   - A Plan, with the approach in a sentence or two, only the files this slice touches, and the Tests lines for its Done when items: `entourage linear section <sub-issue ID> Plan <<'EOF'`.
   - A Breakdown that reads `One piece. Slice <n> of <total>.`: `entourage linear section <sub-issue ID> Breakdown <<'EOF'`.

A sub-issue has to stand alone. The build step will open it in a fresh session and see only that card, so anything it needs from the parent goes into it.

Then update the parent's Breakdown list so each slice name carries its sub-issue's ID, with `entourage linear section <card ID> Breakdown --replace`. The parent is not built. It stays as the record of the whole.

Read the parent and each sub-issue back, then hand off.

## Hand off

Breakdown is finished when the human has approved the card and, if it was sliced, its sub-issues exist. Then record the hand-off:

```
entourage task handoff <project> <card ID> <<'EOF'
phase: breakdown
status: done
next: start
summary: <that the card is approved, and whether it is one piece or sliced; if sliced, the sub-issues in order with their IDs, and which one is first>
flags: <anything that didn't go to plan, such as a blocking relation that couldn't be set>
EOF
```

Put your own words in place of each hint in angle brackets, and leave the `flags` line out when there is nothing to flag.

Recording this hand-off moves the card in Linear to its team's first not-started status, Todo in Lab or Ready for Dev in PHY, and, when the card was sliced, each of its sub-issues too. A card already further along, done or canceled stays where it is. Below the block, the command says what happened to each card. When it says a card was not moved, tell the human in your message which card was not moved, and why, such as no Linear key saved or a key without Write permission. They can move it in Linear, or run `entourage linear move <card ID> approved` with the parent's ID once what stopped it is fixed. The hand-off is recorded either way, so don't record it again.

Start is not a skill. It is the `entourage task start` command, which the human runs, so there is no skill for you to go on to.

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
| The Linear tools aren't available | Stop and say so. Show the finished section in the session so the work isn't lost. Don't save it somewhere else and report the step as done |
| `entourage linear` says no Linear key is saved, or the command isn't there | Write the Breakdown, set the sub-issues' types and write their sections with the Linear tools instead, in the same form: the Breakdown under the heading `## Breakdown`, and a sub-issue's Specification and Plan each between `>>> ## <name>` and a closing `>>>`. Say so in `flags` |
| `entourage linear` says it could not reach Linear | Run it once more. It checks the card before it writes, so it can't add the section twice. If it then says the card already has a Breakdown, the first try got through |
| `entourage linear section` says the text above the section changed | Put it back from what you read at the start of this run, with the Linear tools, and tell the human |
| `entourage linear type` says the label it needs doesn't exist | Don't create it. Finish the sub-issues, and tell the human which label is missing |
| Creating the sub-issues stops partway | Don't start over. List the sub-issues the card already has and create only the missing ones. Then, on every one, set the type with `entourage linear type`, which does nothing on one that has it, and write any section it lacks: `entourage linear section` refuses one that is there. Then set the blocking order |
| A blocking relation can't be set | Tell the human. The order is still on the parent's Breakdown list, so it isn't lost |
| The human's answer isn't a clear yes | Treat it as a change request. Ask what they want changed, then ask for approval again |

If something fails that isn't on this list, stop and tell the human what happened. Don't work around it.

## Examples

**One piece.** The card "Export orders as CSV" has a plan that touches four files and delivers one behaviour.

```
entourage linear section ABC-122 Breakdown <<'EOF'
One piece. Four files and one behaviour, small enough for a single pull request.
EOF
```

**Sliced.** The card "Order notes" asks that staff can add notes to an order, edit and delete them, and mark some as visible to the customer. The plan touches the database, the API, the staff app and the customer app.

```
entourage linear section ABC-130 Breakdown <<'EOF'
1. **Staff can add a note to an order**
   - [ ] On an order, a staff member can type a note and save it.
   - [ ] Saved notes show on the order, newest first, with the author and time.
   - [ ] Someone who is not staff can neither add nor see notes.
2. **Staff can edit and delete their own notes**
   - [ ] A staff member can edit a note they wrote, and the note shows it was edited.
   - [ ] A staff member can delete a note they wrote, after confirming.
   - [ ] A staff member cannot edit or delete someone else's note.
3. **A note can be shown to the customer**
   - [ ] A staff member can mark a note as visible to the customer.
   - [ ] The customer sees those notes, and only those, on their order page.
EOF
```

**The wrong cut** for the same card:

```
1. Notes table and migration
2. Notes API
3. Notes in the staff app
```

Nothing can be clicked until the third piece merges, so the first two can't be tested by anyone, and a mistake in the first surfaces two pull requests later.
