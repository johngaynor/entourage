# entourage

A collection of agent skills for the software development lifecycle (SDLC).

## Status

Early setup. Three skills are in, and none has been run on a real card yet:

| Skill | What it does |
|---|---|
| `sdlc-define` | Sets a card's type and writes its Specification |
| `sdlc-plan` | Reads the card and the code, and writes the Plan |
| `sdlc-breakdown` | Decides whether the card is one piece or several slices, then asks you to approve it |

They live in [skills/](skills/). `entourage install` links them into
`~/.claude/skills`, so any Claude Code session on the machine can run one by
name, such as `/sdlc-define ABC-122`.

Whenever a skill stops, it ends with a handoff block: which step it was, and
whether it is `done`, `needs-human` or `failed`. A `done` block also names the
step that comes next. Whoever is driving, you or `entourage task new`, reads
that block to know what happens next.

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

Your projects live in `~/.config/entourage/projects`, outside this repo, so
they are never published and survive updates. See
[herdr/README.md](herdr/README.md#projects) for how a project is laid out.

## Tasks

A task is one piece of work in a project, usually a Linear card. It has two
commands, used in this order.

`task new` writes the card up. It opens a tab in the project's Herdr space and
starts an agent there, which runs the three skills on the card and then asks
you to approve it:

```sh
entourage task new my-project ABC-122
```

`task start` starts the work. It makes a branch and a git worktree of it in
every repo of the project, and opens a tab for it:

```sh
entourage task start my-project feat/abc-122-insert-task-here
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

To work on entourage itself, clone the repo and run `cli/entourage install`
from the clone instead. Run the CLI's tests with `npm test`.

## Releasing

Machines get changes from the npm registry, so a merged change is live only
after a release:

```sh
npm version patch        # or minor / major; commits and tags vX.Y.Z
git push --follow-tags
```

Then publish a GitHub release for that tag. The `Publish to npm` workflow runs
the tests and publishes the package. It signs in to npm by
[trusted publishing](https://docs.npmjs.com/trusted-publishers), so there is no
token to keep.
