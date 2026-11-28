Build Linear card {card}, which is approved and has its task started. This session is in the task's folder in the entourage project `{project}`.

Start with the sdlc-build skill. Each skill ends by recording a hand-off with `entourage task handoff {project} {card}`, as the skill describes. Record each one before you start the next skill, even though you carry straight on: the hand-offs are how I see how each step ended. You are driving this run, so act on the `status` you recorded:

- `done`: go straight on to the step in `next`, without waiting for me. `review` is the sdlc-review skill, `build` is the sdlc-build skill again, which builds what the review found not met, and `pr` is the sdlc-pr skill, which pushes the reviewed commits and opens the pull request.
- `needs-human`: wait for my answer. When it comes, record my answer as the skill describes, then carry on with the same skill.
- `failed`: stop there. Don't start the next skill.

When the pull request hands off with `next: merged`, the run is over: every pull request for the card has merged, so tell me that. I merge the pull requests myself. Never merge one, and never turn on auto-merge.

Do every step yourself, in this session. Don't hand a step to a subagent.
