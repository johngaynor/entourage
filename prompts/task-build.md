Build Linear card {card}, which is approved and has its task started. This session is in the task's folder in the entourage project `{project}`.

Start with the sdlc-build skill. Each skill ends by recording a hand-off with `entourage task handoff {project} {card}`, as the skill describes. Record each one before you start the next skill, even though you carry straight on: the hand-offs are how I see how each step ended. You are driving this run, so act on the `status` you recorded:

- `done`: go straight on to the step in `next`, without waiting for me. `review` is the sdlc-review skill, and `build` is the sdlc-build skill again, which builds what the review found not met.
- `needs-human`: wait for my answer. When it comes, record my answer as the skill describes, then carry on with the same skill.
- `failed`: stop there. Don't start the next skill.

When the review hands off with `next: pr`, the run is over. Pushing and the pull request are not a skill yet, so tell me that the reviewed commits are waiting on the task's branch. Don't push them or open a pull request yourself.

Do every step yourself, in this session. Don't hand a step to a subagent.
