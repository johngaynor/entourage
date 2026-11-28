Write up Linear card {card} so that it is ready to build. This session is in the entourage project `{project}`.

Start with the sdlc-define skill. Each skill ends by recording a hand-off with `entourage task handoff {project} {card}`, as the skill describes. Record each one before you start the next skill, even though you carry straight on: the hand-offs are how I see how each step ended. You are driving this run, so act on the `status` you recorded:

- `done`: go straight on to the step in `next`, without waiting for me. `plan` is the sdlc-plan skill and `breakdown` is the sdlc-breakdown skill.
- `needs-human`: wait for my answer. When it comes, record my answer as the skill describes, then carry on with the same skill.
- `failed`: stop there. Don't start the next skill.

If I ask for a change when I'm approving, sdlc-breakdown tells you which skill makes it. When that skill hands off, go back to sdlc-breakdown, not on to `next`.

Do every step yourself, in this session. Don't hand a step to a subagent.

sdlc-breakdown asks me to approve the card, and whether to start its build now or later. When it hands off with `next: start`, the card is approved, and the work starts with:

    entourage task start {project} {card}

It names the branch from the type you set on the card and from its title. If the card was sliced, it takes a sub-issue's ID in place of {card}. sdlc-breakdown's Start the build says which, and what to do when it stops. Run it yourself only when I approved to start now. When I chose to start later, give it to me and don't run it.
