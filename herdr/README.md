# herdr

Shared setup for the [Herdr](https://herdr.dev) desktop app: mods (panels) and
layouts (whole-window arrangements of mods).

## What's here

| Path | What it is |
|---|---|
| `mods/cpu/` | Live CPU usage with a scrolling history. macOS only (reads `/usr/bin/top`). |
| `mods/layout-switch/` | A dropdown that shows the current layout and switches to another. |
| `layouts/default.json` | Herdr's own layout, plus the layout dropdown. |
| `layouts/test.json` | `default` plus the CPU mod in the sidebar. |
| `projects/template/` | The starting `PROJECT.md` for every new project. |

The skills are in [../skills/](../skills/), outside this folder. They are
linked into `~/.claude/skills` (`CLAUDE_CONFIG_DIR` picks another `~/.claude`)
by the same `entourage install` and `entourage update`.

## How it works

Herdr reads its whole interface from files in `~/.config/herdr-app`. This repo
holds the mods and layouts we own, and each machine symlinks them into that
folder. The linked files are the tracked files, so a `git pull` is all it
takes to update a machine.

Per-machine things stay out of the repo: the Herdr account, `settings.json`,
`keys.json`, and which layout is showing.

## Set up a clean machine

1. Install Herdr:

   ```sh
   curl -fsSL https://releases.herdr.dev/app/install.sh | sh
   ```

   This installs the Herdr app, herdr-core (which runs the terminals), and the
   `herdr-app` and `hc` commands in `~/.local/bin`.

2. Open Herdr once and sign in. The first start creates
   `~/.config/herdr-app` and fills it with Herdr's own mods and layouts.

3. Install entourage (needs Node):

   ```sh
   npm install -g @johngaynor/entourage
   ```

4. Run the installer:

   ```sh
   entourage install
   ```

   It links every mod and layout into Herdr and refreshes Herdr if it is
   running. It is safe to re-run, and it never replaces a real file that is
   already in Herdr's folder.

5. Pick a layout from the Layout dropdown at the top of the sidebar, or press
   `ctrl-shift-l` to cycle. The dropdown only appears on our layouts, so the
   first switch from Herdr's own layout is `ctrl-shift-l`.

## Keeping a machine up to date

```sh
entourage update
```

This reinstalls the latest entourage through npm, links any mod or layout that
is new, removes links to ones that were deleted, and refreshes Herdr so it
re-reads everything.

- **Check a machine:** `entourage status` lists each mod and layout and whether
  it is linked.
- **Remove one from a machine:** delete its link in `~/.config/herdr-app/mods`
  or `layouts`. The next `entourage update` will link it again, so remove it
  from the repo to drop it everywhere.
- **Herdr updates itself:** it replaces its own shipped mods and layouts on
  every start and leaves ours alone, because ours have different names.
- **Something broke the window:** `ctrl-alt-shift-escape` always returns Herdr
  to its own default layout.

## Projects

A project is a group of repos that shows up in Herdr as one space. Only the
template is in this repo. Your own projects are in
`~/.config/entourage/projects` (`ENTOURAGE_HOME` picks another
`~/.config/entourage`), one folder each:

| In a project folder | What it is |
|---|---|
| `PROJECT.md` | What the project is and what belongs in each repo. You write this. |
| `repos` | One repo path per line. `entourage project add` writes it; you can edit it. |
| `links/` | Generated: a link to each repo, named after its folder. |
| `tasks/` | One folder per task, holding a worktree of each repo. See [Tasks](#tasks). |
| `CLAUDE.md`, `AGENTS.md` | Generated: links to `PROJECT.md`, so an agent started in the space reads it. |

- **Make one:** `entourage project new <name>`, then
  `entourage project add <name> <path>` for each repo. The repo must already
  be cloned on this machine.
- **Open it:** `entourage project open <name>` rebuilds the links and shows
  the project's space, making it if it is not open. The space's folder is the
  project folder.
- **List them:** `entourage project ls`. `--json` prints the same list as
  JSON with each project's folder; the projects mod reads it.
- **Check them:** `entourage status` reports a repo that has moved or gone,
  and a `PROJECT.md` that is still the template. Delete the template's first
  line once you have filled it in.
- **Remove a repo:** delete its line from `repos`; the next `open` drops its
  link. To remove a project, close its space and delete its folder.
- **The linked repos are shared.** A repo in two projects is the same clone
  in both, so switching branches in one changes it in the other.

## Tasks

A task is one piece of work in a project, usually a Linear card. It has two
commands, used in this order.

### Writing the card up

```sh
entourage task new <project> <card>
```

- **The card is its ID**, like `ABC-122`. Upper or lower case both work.
- **It opens a tab named after the card** in the project's space, in the
  project folder, and starts an agent in it. The agent is `claude`;
  `ENTOURAGE_AGENT` picks another command.
- **The agent's first message** is [prompts/task-new.md](../prompts/task-new.md)
  with the card and project filled in. It tells the agent to start with
  `sdlc-define` and follow each skill's handoff block to the next
  (`sdlc-plan`, then `sdlc-breakdown`), in that one session, and to wait for
  your approval at the end. Edit that file to change what the agent is told.
- **It makes no branch, worktree or task folder.** The card has no type until
  the agent has defined it, and the type is the start of the branch name.
- **It checks first.** An unknown project, something that is not a card ID,
  Herdr not running, no agent on your `PATH`, or the skills not linked into
  `~/.claude/skills` stops it before anything is opened. Run
  `entourage update` to link the skills.

### Starting the work

One branch, checked out as a git worktree of the repos the task needs, and
shown as a tab in the project's space.

```sh
entourage task start <project> <branch> [<repo>[:<group>[,<group>...]] ...]
```

- **Targets say what the task works on.** Each one names a repo of the
  project by its folder name, and optionally groups inside it:

  | After the branch | The task gets |
  |---|---|
  | nothing | every repo of the project, each with its whole setup |
  | `app:athlete` | the `app` repo, set up for its `athlete` group |
  | `app:athlete,coach` | `app`, set up for both groups |
  | `app:athlete billing` | two repos: `app` for `athlete`, and all of `billing` |

  A repo that is not named gets no worktree and no setup; read it through the
  project's `links/`. A group is the repo's own word for a part of itself
  (see [What a repo provides](#what-a-repo-provides)): lowercase letters,
  digits and dashes. entourage passes it on and does not check that the repo
  knows it. A repo whose folder name has a colon in it cannot be named as a
  target.

- **The branch is `<type>/<description>`**, following
  [Conventional Branch](https://conventionalbranch.org): `feat/abc-122-insert-task-here`,
  `fix/abc-140-header-bug`, `chore/update-dependencies`. Put the card's ID in
  the description. The types are `feature`, `feat`, `bugfix`, `fix`, `hotfix`,
  `release` and `chore`, plus `ai`, `claude`, `codex`, `copilot` and `cursor`.
- **The description names the task.** `feat/abc-122-insert-task-here` makes
  the folder `tasks/abc-122-insert-task-here` and a tab of that name.
- **Each of the task's repos gets a worktree** at `tasks/<task>/<repo>`, on the new branch,
  cut from the remote's default branch after a fetch. A repo that cannot be
  fetched starts from what is local, with a warning.
- **The repos' own checkouts are not touched.** They stay on whatever branch
  they were on.
- **Where the tab starts:** in the worktree when the task has one repo; in
  the task folder when it has several. That folder has `CLAUDE.md` and
  `AGENTS.md` links to the project's `PROJECT.md`.
- **Setup runs in the tab.** For each repo that has a `setup` recipe (see
  [What a repo provides](#what-a-repo-provides)), `just setup`, followed by
  the target's groups if it named any, is typed into
  the new tab's shell, so `task start` returns within a second or two and you
  watch the install where you will work. With several repos they run one after another,
  and one that fails stops the rest. A repo without the recipe is skipped and
  named in the output.
- **Setup never fails the task.** The task and its tab are there either way.
  Without `just`, the output says setup was skipped. If the line could not be
  typed into the tab, the output gives you the line to run yourself.
- **Nothing is made unless everything can be.** A task or branch of that name
  that already exists, a missing repo, or Herdr not running stops it first,
  and a worktree that fails partway is undone.
- **Remove a task by hand for now:** in each repo run
  `git worktree remove <project folder>/tasks/<task>/<repo>` and
  `git branch -D <branch>`, then delete the task's folder and close its tab.

## What a repo provides

entourage knows nothing about how a repo is built or run. A repo says so
itself, in a [justfile](https://just.systems) at its root, with recipes that
have the same names in every repo. entourage only knows the names.

| Recipe | What it must do | Used by |
|---|---|---|
| `setup` | Make a fresh checkout ready to work in: install dependencies and anything else a new worktree lacks. Safe to run twice. Called with group names (`just setup athlete coach`), make ready only what those groups need, and fail with a clear message for a group the repo does not have. | `entourage task start` |

```just
setup:
    npm install
```

- **Only a justfile at the repo's own root counts**: `justfile`, `Justfile` or
  `.justfile`. One in a folder above is never used.
- **A repo with several codebases names its own groups**, such as `athlete`
  for a web app with the API and database it needs. A target like
  `app:athlete` reaches the recipe as `just setup athlete`. A repo with one
  codebase needs none: its `setup` takes no arguments.
- **`entourage status` notes** each repo with no justfile or no `setup`
  recipe. A note is not a problem: tasks in that project still start, without
  setup.
- **`just` has to be installed** on the machine. Without it, tasks start
  without setup and `entourage status` says so.

## Changing things

- Work from a git clone, not the npm install: clone the repo and run
  `cli/entourage install` from it. A clone links Herdr to the working files and
  updates with `git pull`. If the machine was set up through npm first, remove
  the old links in `~/.config/herdr-app/mods` and `layouts` before installing
  from the clone, because existing links are never replaced.
- Edit files in the clone, not in `~/.config/herdr-app`: the links mean they
  are the same files.
- Herdr does not notice edits made through a link straight away. Run
  `entourage update --no-pull` to refresh it without pulling.
- Run `herdr-app check herdr/mods/<name>` after editing a mod.
- Herdr's shipped layouts and mods are read-only. To build on one, clone it
  (`herdr-app do layout.clone '{"name":"main","as":"<name>"}'`) and move the
  clone here.
