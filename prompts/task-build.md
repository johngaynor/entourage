Build Linear card {card}, which is approved and has its task started. This session is in the task's folder in the entourage space `{space}`.

Start with the sdlc-build skill. Each skill ends by recording a hand-off with `entourage task handoff {space} {card}`, as the skill describes. Record each one before you start the next skill, even though you carry straight on: the hand-offs are how I see how each step ended. You are driving this run, so act on the `status` you recorded:

- `done`: go straight on to the step in `next`, without waiting for me. `review` is the sdlc-review skill, which may come next from sdlc-pr too, once it has merged the default branch in to bring a pull request up to date, `build` is the sdlc-build skill again, which builds what the review step found not met, and `pr` is the sdlc-pr skill, which pushes the reviewed commits and opens the pull request.
- `needs-human`: wait for my answer. When it comes, record my answer as the skill describes, then carry on with the same skill.
- `failed`: stop there. Don't start the next skill.

When sdlc-pr hands off with `next: merged`, every pull request for the card has merged. Then finish the task with `entourage task finish {space} {card}`, as the sdlc-pr skill says. It is the run's last command. It removes the task and closes this tab, which ends the run. When it removes nothing because that would lose work, or stops for another reason, tell me everything it named and leave the task as it is. I merge the pull requests myself. Never merge one, and never turn on auto-merge.

Do every step yourself, in this session. Don't hand a step to a subagent.
