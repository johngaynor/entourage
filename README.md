# entourage

A software factory: agent skills, and the Herdr setup to run them, that take a
Linear card from its title to a merged pull request. The `entourage` CLI is
the orchestrator in it: it opens a tab for each agent, starts it, records how
each step ended and moves the card in Linear. The words these docs use, such
as step, phase and harness, are in [GLOSSARY.md](GLOSSARY.md).

## Status

Early setup. Six skills are in, and they have had only a few runs on real cards:

| Skill | What it does |
|---|---|
| `sdlc-define` | The define step: sets a card's type and writes its Specification |
| `sdlc-plan` | The plan step: reads the card and the code, and writes the Plan |
| `sdlc-breakdown` | The breakdown step: decides whether the card is one piece or several slices, then asks you to approve it |
| `sdlc-build` | The build step: builds an approved card in its task, making the change the Plan describes, running the tests and committing, pushing nothing |
| `sdlc-review` | The review step: checks the build step's work against the card's Done when, writes what it found on the card as its Review, and sends what is not met back to the build step |
| `sdlc-pr` | The pr step: pushes a reviewed card's branch, opens its pull requests, moves the card to In Review, watches GitHub while you merge them and records the merge once it sees it. It never merges |

They live in [skills/](skills/). `entourage install` links them into
`~/.claude/skills`, so any Claude Code session on the machine can run one by
name, such as `/sdlc-define ABC-122`.

Whenever a skill ends or pauses, it hands off with a block: which step it was,
on the block's `phase:` line, and whether it is `done`, `needs-human` or
`failed`. A `done` block also names
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
and the two phase profiles in [agents/](agents/), which it links into
`~/.claude/agents`; see [herdr/README.md](herdr/README.md) for the full
walkthrough.

A phase profile is a Claude Code agent definition: the tools a session has.
When the harness is `claude`, `task new` starts the agent with
`entourage-write-up`, for the write-up phase, and `task build` with
`entourage-build`, for the build phase, so each agent has only the tools its
steps use, whatever your own sessions have. Each also gets Linear's MCP
server alone, from [agents/linear-mcp.json](agents/linear-mcp.json), not the
servers of your own sessions. Claude Code asks once to sign in to Linear as
`linear-server` on a machine where it is not signed in under that name.

Each of the four profiles, the two phase profiles and the two dev profiles,
runs on the model and effort you pick for it, kept in
`~/.config/entourage/settings.json`. `entourage install` makes the file, with
every profile on Opus at `xhigh` effort, and neither `install` nor `update`
changes it once it is there:

```sh
entourage profile ls                     # each profile's model and effort
entourage profile set build effort high  # change one
entourage profile set write-up model sonnet
```

| Profile | Kind | Runs |
|---|---|---|
| `write-up` | phase profile | the agent `task new` starts, for the write-up phase |
| `build` | phase profile | the agent `task build` starts, for the build phase |
| `reviewer`, `verifier` | dev profiles | the `entourage-reviewer` and `entourage-verifier` subagents, for work on entourage itself |

A model is one of claude's aliases (`fable`, `opus`, `sonnet`, `haiku`) or a
full model name like `claude-opus-5-5`, and an effort is `low`, `medium`,
`high`, `xhigh` or `max`. `profile set` refuses anything else and leaves the
file as it was. `task new` and `task build` start `claude` with `--model=` and
`--effort=`, which beat the phase profile's own model and your own Claude Code
settings; only `CLAUDE_CODE_EFFORT_LEVEL` beats the effort. A profile or value
the file leaves out is Opus at `xhigh`. A file that is not valid settings
stops `task new` and `task build` before an agent starts, saying what in it is
wrong, and `entourage status` says so too. The file is read with `jq`. In
Herdr, the Agents button at the right end of the tab bar shows and changes the
same values; see [herdr/README.md](herdr/README.md#agent-settings).

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

It asks Linear itself, with no agent running. `entourage status` checks the
saved key with Linear each time it runs: it says whose the key is when it
works, notes when no key is saved or when the key could not be checked, and
lists a key Linear rejects as a problem, which makes `status` exit non-zero.
See [herdr/README.md](herdr/README.md#seeing-a-projects-cards) for the details.

`task new` writes the card up. It opens a tab in the project's Herdr space and
starts an agent there for the write-up phase, with the `entourage-write-up`
phase profile on the `write-up` profile's model and effort. The agent runs
the phase's three skills on the card and then asks you to approve it:

```sh
entourage task new my-project ABC-122
```

Recording your approval moves the card in Linear to its team's first
not-started status (Todo in Lab), and each of its sub-issues with it. When a
card cannot be moved, the approval is still recorded, and the agent tells you
which card, and why.

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
project, opens a tab for it, and starts the agent there that runs the build
phase. The write-up phase gives you the command:

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
the write-up phase set on the card, and the short name is the first four
words of its title, leaving out a, an and the. "Insert the task here" gives
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

`task build` starts the agent for the build phase in the harness, `claude`
unless `ENTOURAGE_AGENT` names another, with the `entourage-build` phase
profile on the `build` profile's model and effort, and a first message that
has it build the card with the `sdlc-build` skill, check that work with the
`sdlc-review` skill, and then put it up as a pull request with the `sdlc-pr`
skill. If the agent stops, run the same command again in the tab. It runs only
in the card's own task folder. When a phase profile is not linked, `task new`
and `task build` stop before they start anything, and say to run
`entourage update`. Another harness, named by `ENTOURAGE_AGENT`, starts as it
always has, with no profile, model or effort. When the task has one repo and
Claude Code has not trusted that repo yet, `task start` says so: Claude Code
asks once in the tab, and not again for that repo. `task log` shows when the
work was started.

See [herdr/README.md](herdr/README.md#tasks) for the details.

The build step reads the card's Plan, makes the change in the task's
worktrees, runs the tests and commits on the task's branch. Since setup is
off, it first installs into each worktree what the tests need, the way that
repo's own docs say. It installs only: it starts no app, server or database,
and asks you when the tests need one running. It pushes nothing and opens no
pull request: that comes after the review step. Like each step of the write-up
phase, it records how it ended, and `task log` shows it: `done` only when the
tests pass, `needs-human` with a question, or `failed` with the reason. A card
with no Plan is not built.

Then the review step runs the tests itself, checks each Done when item against
the test the Plan names for it, and writes what it found on the card as a
Review. It changes no code, pushes nothing and opens no pull request. When
every item is met, it hands off `done` with `pr` next, and the pull request
comes next. When an item is not met or a test fails, it hands off with `build`
next, and `sdlc-build` builds only what the Review names. After one send-back,
it asks you whether to build again or stop.

Then the pr step. `sdlc-pr` reads the Review on the card and opens nothing
unless every item in it is met or left to you. Before it pushes anything, it
checks that `gh` is signed in and that each repo the work changed has an
`origin` GitHub knows; when one is not, it hands off `failed` with the reason
and what to run, and pushes nothing. Then, in each repo whose branch has
commits ahead of its default branch, and no other, it pushes the task's
branch, never forced, and opens a pull request into the default branch, by the
repo's own rules and pull request template. Each one links the card and says,
for each Done when item, how the review step showed it and what is left to
you. Once every one is open, it moves the card in Linear to In Review, the
team's last started status, with `entourage linear move <card> review`; in a
team with one started status the card stays in it. When the card cannot be
moved, it says so, and why, and goes on.

Then it asks you to merge them, as `needs-human` with their links. Merge each
one on GitHub yourself; you don't have to tell the agent. It watches them
with `entourage task watch`, run in the background: it asks GitHub every
minute for the first 10 minutes after the newest was opened, every 5 minutes
for the hour after that, then every 30 minutes, and the agent is woken only
when that is settled. Once every one has merged, the agent records the merge
as your answer, so `task log` shows how long the pull requests waited on
you, and hands off `done` with `merged` next, which ends the card: `task log`
shows the card as merged, and recording it moves the card to Done in Linear,
as your approval moved it to Todo, `task start` moved it to In Progress and
opening the pull requests moved it to In Review. Each move picks the team's
own status of that kind, goes only forward, never touches a card that is done
or canceled, and needs your Linear key to have Write permission. A move that
cannot be made is a note saying why, and the step goes on. Telling the agent
in the tab that they have merged makes it check at once, with
`task watch --once`; if one has not merged yet, it names it and asks again.
When one is closed without merging, it asks you whether to stop. No agent
merges a pull request.

When the default branch moves on and a pull request comes to conflict with it,
the agent brings it up to date without asking you. It merges the default
branch into the task's branch, never by a rebase, fixes what the repo's tests
then find and commits the merge, and the review step checks each Done when
item again and revises the card's Review. Then it pushes, never forced, adds a
line under **Brought up to date:** to the pull request's description, saying
which files conflicted and what the fix changed, and waits for you again. A
pull request with no conflict gets no push. It asks you, as `needs-human`
naming the pull request and the files in conflict, only when it cannot get the
tests to pass or when the fix would change what a Done when item says, and
pushes nothing until you answer.

```sh
entourage task watch my-project ABC-122 [--once]
```

`task watch` asks GitHub, with `gh`, for the pull request of each of the
task's worktrees, skipping one whose branch has none, and prints a line for
each: `merged`, `open`, `closed` or `conflict`, and its URL. `conflict` is an
open one that GitHub says conflicts with its default branch; while GitHub is
still working that out, it is `open`. It ends once every one has merged (exit
0), one is closed without merging (exit 3) or one is in conflict (exit 4). A
closed one comes first, so it is 3 whatever the others are. With `--once` it
checks once, and exits 2 while one is still open. It changes nothing.

To have something changed instead of merging, say what in the tab. The agent
makes the change on the task's branch, with its test, runs the whole test
suite, then commits and pushes it, never forced, so the pull request shows
it, and adds it to the pull request's description. Then it asks you again,
and `task log` shows another `pr` `needs-human` after your answer. A change
that would alter what you approved on the card, such as a Done when item or a
new dependency, it asks you about before it makes it. It takes changes only
from what you say in the tab, not from GitHub review comments or CI.

Once the merge is recorded, the agent ends the task with `task finish`, as its
last command, so you remove nothing by hand:

```sh
entourage task finish my-project ABC-122
```

It removes the task's worktrees, deletes its branch in each repo, deletes its
folder and, last, closes its tab, the one the agent runs in. It checks every
repo first, and removes nothing when that would lose work:
changes that are not committed, commits that never reached the default
branch (pushed or not), or git-ignored files that the repo's `made-by-setup`
recipe does not say its setup makes again. It names each one, and the agent
tells you all of it and leaves the task as it is. A pull request closed
without merging leaves the task too. Run the command yourself for a task the
agent left, once you have kept what it named. See
[herdr/README.md](herdr/README.md#finishing-a-task).

Each skill also runs on its own in any Claude Code session, as
`/sdlc-build ABC-122`, `/sdlc-review ABC-122` or `/sdlc-pr ABC-122`.

To work on entourage itself, clone the repo and run `cli/entourage install`
from the clone instead. A clone also writes the dev profiles, the
`entourage-reviewer` and `entourage-verifier` subagents, from
[.claude/profiles/](.claude/profiles/)
into `~/.claude/agents`, with the model and effort the settings file names for
the reviewer and the verifier, so a session can start them by name to review
a change or check what the reviewer found; see
[CLAUDE.md](CLAUDE.md#reviewing-a-change). It writes them again at each
`update`, and at each `profile set` for one of them, and replaces or removes
only a file it wrote: one of your own of the same name is left alone, and
`entourage status` lists each as written, stale, missing or skipped. Run the CLI's tests with `npm test`. The cases run
side by side, one per processor; `ENTOURAGE_TEST_JOBS=1 npm test` runs them
one at a time. Once a pull request merges, `scripts/after-merge <name>`, run
from the clone, removes the Claude Code worktree under `.claude/worktrees/`
that the work was done in, deletes its branch and updates the clone; see
[CLAUDE.md](CLAUDE.md#after-a-pull-request-merges).

A git worktree of the repo, such as the one `task start` makes for one of
entourage's own cards, holds a copy of the CLI that is a change being built.
Its `./cli/entourage` runs only the commands that read: `help`, `status`,
`project ls`, `project team <name>`, `profile ls`, `task ls`, `task log` and
`task watch`.
Any other command stops before it does anything, says that it is a
worktree's copy, and gives the command that runs it for real:
`ENTOURAGE_LIVE=1 ./cli/entourage …`, for that one run. The installed `entourage` is never stopped, whatever folder
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
