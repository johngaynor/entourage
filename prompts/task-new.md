Write up Linear card {card} so that it is ready to build. This session is in the entourage project `{project}`.

Start with the sdlc-define skill. Each skill ends its messages with a handoff block. You are driving this run, so act on the block's `status`:

- `done`: go straight on to the step in `next`, without waiting for me. `plan` is the sdlc-plan skill and `breakdown` is the sdlc-breakdown skill.
- `needs-human`: wait for my answer, then carry on with the same skill.
- `failed`: stop there. Don't start the next skill.

If I ask for a change when I'm approving, sdlc-breakdown tells you which skill makes it. When that skill hands off, go back to sdlc-breakdown, not on to `next`.

Do every step yourself, in this session. Don't hand a step to a subagent.

sdlc-breakdown asks me to approve the card. When it hands off with `next: setup`, the card is approved. Give me the command that starts the work, and don't run it yourself:

    entourage task start {project} <type>/<card-id>-<short-name>

Use the type you set on the card, the card's ID in lowercase, and two to four words from its title, in lowercase with hyphens. If the card was sliced, give the command for the first sub-issue.
