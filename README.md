# entourage

A collection of agent skills for the software development lifecycle (SDLC).

## Status

Early setup. Four skills are in, and they have had only a few runs on real cards:

| Skill | What it does |
|---|---|
| `sdlc-define` | Sets a card's type and writes its Specification |
| `sdlc-plan` | Reads the card and the code, and writes the Plan |
| `sdlc-breakdown` | Decides whether the card is one piece or several slices, then asks you to approve it |
| `sdlc-build` | Builds an approved card in its task: makes the change the Plan describes, runs the tests and commits, pushing nothing |

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
`entourage update` keeps it current. That covers the Herdr setup and the
skills; see [herdr/README.md](herdr/README.md) for the full walkthrough.

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
starts an agent there, which runs the three skills on the card and then asks
you to approve it:

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
newest first, with where each stands, such as waiting on you:

```sh
entourage task log my-project
```

`task start` starts the work. It makes a branch and a git worktree of it in
every repo of the project, and opens a tab for it:

```sh
entourage task start my-project feat/abc-122-insert-task-here
```

Name targets after the branch to take only what the task needs: a repo, or
groups inside a repo (`app:athlete`, or `app:athlete,coach` for several).

```sh
entourage task start my-project feat/abc-122-insert-task-here app:athlete billing
```

The branch is `<type>/<description>`, following
[Conventional Branch](https://conventionalbranch.org), with the card's ID in
the description. The description names the task:

```
~/.config/entourage/projects/my-project/
  tasks/
    abc-122-insert-task-here/   one folder per task
      api/                      a worktree of api on feat/abc-122-insert-task-here
      web/                      a worktree of web on the same branch
```

If a repo has a `justfile` with a `setup` recipe, `just setup` then runs in
the task's tab, so the checkout is ready to work in. See
[what a repo provides](herdr/README.md#what-a-repo-provides).

See [herdr/README.md](herdr/README.md#tasks) for the details.

To build the card, start an agent in the task's tab, such as `claude`, and
ask it to build the card with the `sdlc-build` skill:

```
/sdlc-build ABC-122
```

It reads the card's Plan, makes the change in the task's worktrees, runs the
tests and commits on the task's branch. It pushes nothing and opens no pull
request, so the commits wait for you there. Like the write-up, it records how
it ended, and `task log` shows it: `done` only when the tests pass,
`needs-human` with a question, or `failed` with the reason. A card with no
Plan is not built.

To work on entourage itself, clone the repo and run `cli/entourage install`
from the clone instead. Run the CLI's tests with `npm test`. The cases run
side by side, one per processor; `ENTOURAGE_TEST_JOBS=1 npm test` runs them
one at a time.

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
