# Glossary

The words entourage's docs, skills, prompts and profiles use, and what each
one means. Use each in this sense only, so that a word names one thing and a
thing has one name. A name stays as it is wherever it appears: a command such
as `task build`, a skill such as `sdlc-review`, a profile such as `build`, a
hand-off value such as `next: review`, a variable such as `ENTOURAGE_HARNESS`,
and a button or a heading.

## Software factory

entourage as a whole: the CLI, the Herdr mods and layouts it links in, the
skills, the prompts and the profiles. It takes a Linear card from a title to a
merged pull request. Not a collection of agent skills: the skills are one part
of it.

## Orchestrator

The `entourage` CLI, the part of the software factory that runs the rest. It
makes the tabs, starts an agent in each, records how each step ended, and
moves the card in Linear.

## Step

One of the eight stages a card goes through, in this order: define, plan,
breakdown, start, build, review, pr and merged. Each step but start and merged
is the skill of its name, such as `sdlc-define`. Start is the
`entourage task start` command, which the human runs. Merged is where a card
ends: it is only ever named as the next step.

A hand-off names its step on its `phase:` line, as in `phase: define`. The
line's name is older than these words, and what it holds is a step.

## Phase

The steps one agent runs. There are two:

- **The write-up phase**: define, plan and breakdown, run by the agent
  `task new` starts. It ends when the human approves the card.
- **The build phase**: build, review and pr, run by the agent `task build`
  starts. It ends when the pull requests have merged.

Start and merged are in no phase.

## Build step and build phase

Build is never a noun on its own. **The build step** is the one the
`sdlc-build` skill runs: it makes the change the Plan describes and commits it.
**The build phase** is the build step, the review step and the pr step
together. A **merge build** is something else: the npm prerelease each push to
`main` publishes under the tag `next`.

## Review step, the Review and a GitHub review

Review is never a noun on its own either:

- **The review step** is the one the `sdlc-review` skill runs: it checks the
  build step's work against the card's Done when.
- **The Review**, with a capital R, is the section the review step writes on
  the card.
- **A GitHub review** is a review of a pull request on GitHub, by a person or
  a bot.

What the `entourage-reviewer` subagent finds is called by its name: what the
reviewer found.

## Phase profile and dev profile

A profile is a Claude Code agent definition: a file that gives a session its
tools. There are two kinds:

- **The phase profiles**, `write-up` and `build`, in `agents/`. `claude` starts
  with `entourage-write-up` for the write-up phase and with `entourage-build`
  for the build phase.
- **The dev profiles**, `reviewer` and `verifier`, in `.claude/profiles/`. They
  are the `entourage-reviewer` and `entourage-verifier` subagents, for work on
  entourage itself.

Each of the four runs on the model and effort `entourage profile set` gives
it.

## Agent

The worker in a tab: a harness that entourage starts there with a first
message, and, when the harness is `claude`, a phase profile. The agent runs
one phase of a card. Not the program it runs in, which is the harness.

## Harness

The program an agent runs in: `claude` unless `ENTOURAGE_HARNESS` names
another command.

## herdr-core

The agent's host: the part of Herdr that runs each tab's terminal, and so the
harness in it.
