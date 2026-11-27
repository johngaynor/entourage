# entourage

A collection of agent skills for the software development lifecycle (SDLC).

## Status

Early setup. Skills are being ported in.

## Setting up a machine

```sh
npm install -g @johngaynor/entourage
entourage install
```

`entourage install` links this repo into the tools on a machine, and
`entourage update` keeps it current. Today that covers the Herdr setup; see
[herdr/README.md](herdr/README.md) for the full walkthrough.

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

A task is one piece of work in a project. Starting one makes a branch and a
git worktree of it in every repo of the project, and opens a tab for it in the
project's Herdr space:

```sh
entourage task new my-project feat/abc-122-insert-task-here
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
the tests and publishes the package. It needs a repo secret `NPM_TOKEN`.
