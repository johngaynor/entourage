---
name: sdlc-breakdown
description: Decide whether a planned Linear card is one piece or several, by cutting it into thin end-to-end slices (elephant carpaccio) where it can be cut, then, once John approves, creating each slice as a sub-issue. Use this after plan on every card, and whenever asked to break down, slice or split a card, or to judge whether a card is too big for one pull request.
---

# Break down a card

Breakdown is the third step of the lifecycle. Define said what is wanted and plan said how. Breakdown decides whether the card is built as one piece or as several, and if several, what each piece is.

The method is elephant carpaccio: cut the work into slices so thin that each one is small, yet each still works end to end. The aim is the earliest usable slice, followed by slices that extend it. Useful comes before done.

Thin slices matter more when an agent is building. Each slice can be checked end to end as soon as it merges, a mistake stays inside one small pull request, and if the third slice never ships, the first two still work.

This skill has two parts. Proposing, and asking John to approve, happens on every card. Creating sub-issues happens only after he approves a card that was sliced.

## Before you write anything

1. Read the card with the Linear tools: the Specification and the Plan.
2. If either is missing, the earlier step hasn't run. Say so and stop.
3. If the card is itself a sub-issue, don't slice it again. Slices go one level deep. If it looks too big, tell John.
4. If the card already has a Breakdown section, don't write a second one. Tell John and ask whether he wants it revised.

## Part 1: Propose

### First, is it already small?

Look at the plan's Changes. If the whole card is one agent, one sitting and one quick pull request, it stands as one piece, even if you could cut it further. Every slice costs John a review and a merge, so don't slice for its own sake.

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

Two to five slices is usual. If you need more than six, the card is probably several cards. Propose what you have and say so when you finish.

### If it can't be cut

Some work has no cut that passes the checks. A refactor may have nothing to click halfway through. A migration may have to land together. A first slice may not be acceptable for users to see without the rest.

Then the card stands as one piece, however large it is. Don't force a cut that fails a check. A horizontal slice is worse than a large card, because it merges something nobody can test. Say in one line why it can't be cut, and if it is large, tell John when you finish.

### Write it to the card

Append a Breakdown section below the Plan. Leave it open, not collapsible, because it is what John reads to approve the card. Change nothing above it.

For one piece:

```
## Breakdown
One piece. <one line on why: already small, or why it can't be cut>
```

For slices:

```
## Breakdown
1. **<slice name: a short phrase for the behaviour>**
   - [ ] <its Done when>
   - [ ] …
2. **<slice name>**
   - [ ] …
```

Create nothing else in Linear yet. A proposal John turns down should leave nothing behind to clean up.

### Ask John to approve

Breakdown is the last step before building, so it ends by asking John to approve the whole card: the Specification, the Plan and the Breakdown together. This happens on every card, sliced or not.

Give him a summary he can answer from without opening Linear:

- The type.
- The Done when list.
- The approach, in a sentence or two.
- Whether it is one piece or several, and why. If several, the slice names in order.

Then ask him to approve or say what to change, and wait.

| John says | Then |
|---|---|
| Change the breakdown | Revise the Breakdown section and ask again |
| Change the Specification or the Plan | Make the change by that section's own skill, `sdlc-define` or `sdlc-plan`. Then re-check every section below the one that changed, because a new Done when item can make the Plan and the Breakdown wrong. Ask again |
| Yes, and the card is one piece | Tell him the card is approved and ready to build. Setup and build aren't built yet, so stop there |
| Yes, and the card is sliced | Go on to part 2 |

## Part 2: Create the sub-issues

Do this only when John has approved the card in this session, and only when the breakdown has more than one slice.

For each slice, in order, create a sub-issue of the card:

- **Title.** The slice name.
- **Type.** The parent's type, set as the label. Slices don't get a type of their own.
- **Description.** One or two sentences saying what this slice delivers, then its own sections in the same form as any card:
  - A collapsed Specification, with the parent's Why narrowed to this slice, and the slice's Done when.
  - A collapsed Plan, with the approach in a sentence or two, only the files this slice touches, and the Tests lines for its Done when items.
  - A Breakdown section that reads `One piece. Slice <n> of <total>.`
- **Order.** Mark it as blocked by the slice before it. The first slice is blocked by nothing.

A sub-issue has to stand alone. The build step will open it in a fresh session and see only that card, so anything it needs from the parent goes into it.

Then update the parent's Breakdown list so each slice name carries its sub-issue's ID. The parent is not built. It stays as the record of the whole.

Read the parent and each sub-issue back. Tell John what was created, in order, and which slice is first. Setup and build aren't built yet, so stop there.

## If something goes wrong

| When this happens | Do this |
|---|---|
| The card ID doesn't resolve | Ask John for the ID. Don't pick a card because its title looks similar |
| The Linear tools aren't available | Stop and say so. Show the finished section in the session so the work isn't lost. Don't save it somewhere else and report the step as done |
| A write to the card fails | Read the card before doing anything else. Retry once, and only if the section isn't there, so it can't be added twice |
| The read-back shows that text above your section changed | Put it back from what you read at the start of this run, append your section again, and tell John |
| Creating the sub-issues stops partway | Don't start over. List the sub-issues the card already has, create only the missing ones, then set the blocking order |
| A blocking relation can't be set | Tell John. The order is still on the parent's Breakdown list, so it isn't lost |
| John's answer isn't a clear yes | Treat it as a change request. Ask what he wants changed, then ask for approval again |

If something fails that isn't on this list, stop and tell John what happened. Don't work around it.

## Examples

**One piece.** The card "Export orders as CSV" has a plan that touches four files and delivers one behaviour.

```
## Breakdown
One piece. Four files and one behaviour, small enough for a single pull request.
```

**Sliced.** The card "Order notes" asks that staff can add notes to an order, edit and delete them, and mark some as visible to the customer. The plan touches the database, the API, the staff app and the customer app.

```
## Breakdown
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
```

**The wrong cut** for the same card:

```
1. Notes table and migration
2. Notes API
3. Notes in the staff app
```

Nothing can be clicked until the third piece merges, so the first two can't be tested by anyone, and a mistake in the first surfaces two pull requests later.
