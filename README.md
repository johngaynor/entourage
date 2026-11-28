# entourage

A collection of agent skills for the software development lifecycle (SDLC).

## Status

Early setup. Six skills are in, and they have had only a few runs on real cards:

| Skill | What it does |
|---|---|
| `sdlc-define` | Sets a card's type and writes its Specification |
| `sdlc-plan` | Reads the card and the code, and writes the Plan |
| `sdlc-breakdown` | Decides whether the card is one piece or several slices, then asks you to approve it |
| `sdlc-build` | Builds an approved card in its task: makes the change the Plan describes, runs the tests and commits, pushing nothing |
| `sdlc-review` | Reviews the build against the card's Done when, writes what it found on the card, and sends what is not met back to build |
| `sdlc-pr` | Pushes a reviewed card's branch, opens its pull requests, waits for you to merge them and records the merge. It never merges |

They live in [skills/](skills/). `entourage install` links them into
`~/.claude/skills`, so any Claude Code session on the machine can run one by
name, such as `/sdlc-define ABC-122`.

Whenever a skill ends or pauses, it hands off with a block: which step it was,
and whether it is `done`, `needs-human` or `failed`. A `done` block also names
the step that comes next. The agent records each block with
`entourage task handoff`, and your answer when you reply to a question.
`entourage task log` shows them for a card, with how long each step took, and
the Steps panel in Herdr shows the same for the card whose tab is selected.
With no card, both list the project's cards and where each stands.

## Setting up a machine

```sh
npm install -g @johngaynor/entourage
entourage install
```

`entourage install` links this repo into the tools on a machine, and
`entourage update` keeps it current. That covers the Herdr setup, the skills,
and the two agent profiles in [agents/](agents/), which it links into
`~/.claude/agents`; see [herdr/README.md](herdr/README.md) for the full
walkthrough.

A profile is a Claude Code agent definition: the tools a session has and the
model it runs on. When the agent is `claude`, `task new` starts it with
`entourage-write-up`, and `task build` with `entourage-build`, so each runs on
Opus with only the tools its steps use, whatever your own sessions have. Each also gets Linear's MCP
server alone, from [agents/linear-mcp.json](agents/linear-mcp.json), not the
servers of your own sessions. Claude Code asks once to sign in to Linear as
`linear-server` on a machine where it is not signed in under that name.

## Projects

A project groups the repos that belong together, with a `PROJECT.md` saying
what each repo is for. Each project opens in Herdr as one space. A repo is
cloned once and can be in several projects.

```sh
entourage project new my-project
entourage project add my-project ~/Dev/api
entourage project add my-project ~/Dev/web
entourage project open my-project
```

`project new` also takes the repos after the name, to do the first three
lines in one: `entourage project new my-project ~/Dev/api ~/Dev/web`.

In Herdr, the `+` above the projects list does the same without a terminal:
choose a repo's folder, name the project, and its space opens.

Your projects live in `~/.config/entourage/projects`, outside this repo, so
they are never published and survive updates. See
[herdr/README.md](herdr/README.md#projects) for how a project is laid out.

`project new` also marks the project's folder as trusted in Claude Code's own
file, `~/.claude.json`, so an agent started there is not stopped by the "do
you trust this folder?" question. Only a project folder that entourage made
is marked: never a repo, and not a project folder you linked in from somewhere
else. This needs `jq`; without it Claude Code asks once.

## Tasks

A task is one piece of work in a project, usually a Linear card. You run two
commands, in this order.

To see which cards there are first, `task ls` lists the open cards of the
project's Linear teams, under their statuses:

```sh
entourage linear key                  # once: save your Linear API key
entourage project team my-project ABC # once: the team whose cards are ABC-122
entourage task ls my-project
```

It asks Linear itself, with no agent running. See
[herdr/README.md](herdr/README.md#seeing-a-projects-cards) for the details.

`task new` writes the card up. It opens a tab in the project's Herdr space and
starts an agent there, with the `entourage-write-up` profile, which runs the
three skills on the card and then asks you to approve it:

```sh
entourage task new my-project ABC-122
```

As it goes, the agent records how each step ended. `task log` lists that for
a card, oldest first, with how long each step took and how long a question
waited for your answer:

```sh
entourage task log my-project ABC-122
```

Leave the card out to see every card in the project that has hand-offs,
newest first, with where each stands, such as waiting on you, or merged:

```sh
entourage task log my-project
```

`task start` starts the work, once you have approved the card. It takes the
card too, makes a branch and a git worktree of it in every repo of the
project, opens a tab for it, and starts the agent there that builds the card.
The write-up gives you the command:

```sh
entourage task start my-project ABC-122
```

Name targets after the card to take only what the task needs: a repo, or
groups inside a repo (`app:athlete`, or `app:athlete,coach` for several).

```sh
entourage task start my-project ABC-122 app:athlete billing
```

It asks Linear for the card and names the branch from it:
`<type>/<card-id>-<short-name>`, following
[Conventional Branch](https://conventionalbranch.org). The type is the one
the write-up set on the card, and the short name is the first four words of
its title, leaving out a, an and the. "Insert the task here" gives
`feat/abc-122-insert-task-here`. Everything after the type names the task:

```
~/.config/entourage/projects/my-project/
  tasks/
    abc-122-insert-task-here/   one folder per task
      api/                      a worktree of api on feat/abc-122-insert-task-here
      web/                      a worktree of web on the same branch
```

It needs your Linear key, as `task ls` does. A card Linear doesn't have, a
card with no type yet, or Linear out of reach stops it before anything is
made.

Setup is off for now, while the local environment each task gets is worked
out. With `ENTOURAGE_SETUP=1`, a repo that has a `justfile` with a `setup`
recipe gets `just setup` run in the task's tab, so the checkout is ready to
work in. See [what a repo provides](herdr/README.md#what-a-repo-provides).

Then `task start` types this into the task's tab, after `just setup` when
setup runs, so the agent starts once the checkout is ready and you type
nothing there:

```sh
entourage task build my-project ABC-122
```

`task build` starts the agent, `claude` unless `ENTOURAGE_AGENT` names
another, with the `entourage-build` profile and a first message that has it
build the card with the
`sdlc-build` skill, review the build with the `sdlc-review` skill, and then
put it up as a pull request with the `sdlc-pr` skill. If the agent stops, run
the same command again in the tab. It runs only in the
card's own task folder. When a profile is not linked, `task new` and
`task build` stop before they start anything, and say to run
`entourage update`. Another agent, named by `ENTOURAGE_AGENT`, starts as it
always has, with no profile. When the task has one repo and Claude Code has not
trusted that repo yet, `task start` says so: Claude Code asks once in the tab,
and not again for that repo. `task log` shows when the work was started.

See [herdr/README.md](herdr/README.md#tasks) for the details.

The build reads the card's Plan, makes the change in the task's worktrees,
runs the tests and commits on the task's branch. Since setup is off, it first
installs into each worktree what the tests need, the way that repo's own docs
say. It installs only: it starts no app, server or database, and asks you when
the tests need one running. It pushes nothing and opens no pull request: that
comes after the review. Like the write-up, it records how it ended,
and `task log` shows it: `done` only when the tests pass, `needs-human` with a
question, or `failed` with the reason. A card with no Plan is not built.

Then the review runs the tests itself, checks each Done when item against the
test the Plan names for it, and writes what it found on the card as a Review.
It changes no code, pushes nothing and opens no pull request. When every item
is met, it hands off `done` with `pr` next, and the pull request comes next.
When an item is not met or a test fails, it hands
off with `build` next, and `sdlc-build` builds only what the Review names.
After one send-back, it asks you whether to build again or stop.

Then the pull request. `sdlc-pr` reads the Review on the card and opens
nothing unless every item in it is met or left to you. Before it pushes
anything, it checks that `gh` is signed in and that each repo the work changed
has an `origin` GitHub knows; when one is not, it hands off `failed` with the
reason and what to run, and pushes nothing. Then, in each repo whose branch
has commits ahead of its default branch, and no other, it pushes the task's
branch, never forced, and opens a pull request into the default branch, by the
repo's own rules and pull request template. Each one links the card and says,
for each Done when item, how the review showed it and what is left to you.

Then it asks you to merge them, as `needs-human` with their links. Merge each
one on GitHub yourself, then tell the agent in the tab that they have merged.
It checks each with `gh pr view`, and once every one has merged it hands off
`done` with `merged` next, which ends the card: `task log` shows the card as
merged. If one has not merged yet, it names it and asks again. No agent merges
a pull request.

To have something changed instead of merging, say what in the tab. The agent
makes the change on the task's branch, with its test, runs the whole test
suite, then commits and pushes it, never forced, so the pull request shows
it, and adds it to the pull request's description. Then it asks you again,
and `task log` shows another `pr` `needs-human` after your answer. A change
that would alter what you approved on the card, such as a Done when item or a
new dependency, it asks you about before it makes it. It takes changes only
from what you say in the tab, not from review comments or CI on GitHub.

Each skill also runs on its own in any agent, as `/sdlc-build ABC-122`,
`/sdlc-review ABC-122` or `/sdlc-pr ABC-122`.

To work on entourage itself, clone the repo and run `cli/entourage install`
from the clone instead. A session in the clone, or in any worktree of it, can
start the `reviewer` and `verifier` subagents in
[.claude/agents/](.claude/agents/) by name, to review a change or check what a
review found; see [CLAUDE.md](CLAUDE.md#reviewing-a-change). Run the CLI's tests with `npm test`. The cases run
side by side, one per processor; `ENTOURAGE_TEST_JOBS=1 npm test` runs them
one at a time. Once a pull request merges, `scripts/after-merge <name>`, run
from the clone, removes the Claude Code worktree under `.claude/worktrees/`
that the work was done in, deletes its branch and updates the clone; see
[CLAUDE.md](CLAUDE.md#after-a-pull-request-merges).

A git worktree of the repo, such as the one `task start` makes for one of
entourage's own cards, holds a copy of the CLI that is a change being built.
Its `./cli/entourage` runs only the commands that read: `help`, `status`,
`project ls`, `project team <name>`, `task ls` and `task log`. Any other
command stops before it does anything, says that it is a worktree's copy, and
gives the command that runs it for real: `ENTOURAGE_LIVE=1 ./cli/entourage …`,
for that one run. The installed `entourage` is never stopped, whatever folder
it is run from, so an agent in the worktree records its hand-offs with it.

## Releasing

A machine installed through npm gets changes only from a release:

```sh
npm version patch        # or minor / major; commits and tags vX.Y.Z
git push --follow-tags
```

Then publish a GitHub release for that tag. The `Publish to npm` workflow runs
the tests and publishes the package. It signs in to npm by
[trusted publishing](https://docs.npmjs.com/trusted-publishers), so there is no
token to keep.

Every push to `main` is published too, as a merge build under the npm tag
`next` (`0.4.1-next.3`, for example). `entourage update` does not install
those. To try one on a machine installed through npm:

```sh
ENTOURAGE_NPM_SPEC=@johngaynor/entourage@next entourage update
```

A plain `entourage update` goes back to the latest release.
