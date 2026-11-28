# herdr

Shared setup for the [Herdr](https://herdr.dev) desktop app: mods (panels) and
layouts (whole-window arrangements of mods).

## What's here

| Path | What it is |
|---|---|
| `mods/cpu/` | Live CPU usage with a scrolling history. macOS only (reads `/usr/bin/top`). |
| `mods/layout-switch/` | A dropdown that shows the current layout and switches to another. |
| `mods/projects/` | Every project in your config, open or not. Click one to show its space; `+` makes a new one. |
| `mods/cards/` | The open Linear cards of the project whose space is showing, under their statuses. Start writes a card up with `task new`; Open shows the tab of a card already started. |
| `mods/steps/` | The steps of the card whose tab is selected: what each did, how long it took, and how long it waited on you. With no card's tab selected, the project's cards and where each stands. |
| `layouts/default.json` | Herdr's own layout, plus the layout dropdown. |
| `layouts/test.json` | `default` with the projects list in place of spaces, plus the Cards and Steps panels and the CPU mod in the sidebar. |
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
| `teams` | The keys of the project's Linear teams, one per line, `#` for comments. `entourage project team` writes it; you can edit it. See [Seeing a project's cards](#seeing-a-projects-cards). |
| `links/` | Generated: a link to each repo, named after its folder. |
| `tasks/` | One folder per task, holding a worktree of each repo. See [Tasks](#tasks). |
| `CLAUDE.md`, `AGENTS.md` | Generated: links to `PROJECT.md`, so an agent started in the space reads it. |

- **Make one:** `entourage project new <name>`, then
  `entourage project add <name> <path>` for each repo. The repo must already
  be cloned on this machine. Paths after the name add those repos as the
  project is made: `entourage project new <name> <path>...`. Every one is
  checked first, and a path that is not a repo stops it with nothing made.
- **Make one in Herdr:** click the `+` above the projects list (on the `test`
  layout) and choose a repo's folder. A dialog suggests a name from the
  folder, lists the repo, and can add more. Create makes the project with
  `entourage project new` and shows its space; whatever the command refuses
  (a name in use, a folder that is not a repo) is shown in the dialog.
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

A task is one piece of work in a project, usually a Linear card. You run two
commands, in this order: `task new`, then `task start`. Two more, `task
handoff` and `task log`, record and show how each step of the write-up ended.
`task ls` lists the cards there are to start.

### Seeing a project's cards

```sh
entourage task ls <project> [--json]
```

- **It lists the open cards of the project's Linear teams**, under their
  statuses, in the order Linear shows the statuses. Open means not done, not
  cancelled and not a duplicate, so a card in progress or in review is listed.
  Each card is its ID and its title. A status with no cards is listed with a
  count of 0.
- **It asks Linear itself, with no agent running.** That needs two things, each
  set once:

  | Set once | With | What it is |
  |---|---|---|
  | Your Linear API key | `entourage linear key` | Make the key in Linear, under Settings, Account, Security & access, Personal API keys. Read permission is enough to list cards. The command asks for it without showing it, checks it with Linear, and saves it. |
  | The project's teams | `entourage project team <project> <team>...` | A team's key is what its cards' IDs start with: `ABC` for `ABC-122`. A project can name several teams, and several projects can name the same team. With no team given, the command prints the ones that are set. |

- **The key is one of entourage's variables, `LINEAR_API_KEY`.** `linear key`
  writes it as a line of entourage's env file, `~/.config/entourage/.env`,
  which only you can read. A key you export in your shell works too, and wins
  over the file. See [entourage's variables](#entourages-variables).
- **The key is never shown.** It is handed to `curl` on its stdin, never as an
  argument, and no message prints it. To take it off the machine, delete its
  line from the env file.
- **When it cannot list, it says which thing is wrong:** no key saved, a key
  Linear rejects, Linear out of reach, something between this machine and
  Linear answering for it (a proxy's or a firewall's page), a project with no
  team, a line of the `teams` file that is not a team key, or a team key Linear
  does not have.
- **The `teams` file can be edited by hand.** Keys may be in lower case, a `#`
  starts a comment, and blank lines and spaces are skipped. A line that is
  still not a team key is named in the message.
- **A list it cannot fetch whole is not printed.** If Linear says it has more
  cards but not where they start, the command fails rather than list part of
  them. A card that comes on two pages is listed once, and a card in a status
  Linear did not name up front is listed under that status.
- **In the plain list, control characters in titles become spaces**, so a title
  cannot start what looks like another card or send escape sequences to your
  terminal. `--json` keeps the text as Linear gave it.
- **Your `~/.curlrc` is not read**, so a line there such as `--fail` cannot
  change what entourage reads back. A proxy set in the environment, such as
  `HTTPS_PROXY`, is still used.
- **`--json` prints the list as one line for programs**: the project, its
  teams, and each status with its `name`, its `type` (`triage`, `backlog`,
  `unstarted` or `started`) and its `cards`, each with an `id`, a `title` and a
  `url`. When it fails it prints nothing on stdout.
- **Two teams' cards share a group when the status has the same name**, such as
  Backlog. A status only one team has is a group of its own.
- **It needs `curl` and `jq`**, and says which is missing.

### Writing the card up

```sh
entourage task new <project> <card>
```

- **The card is its ID**, like `ABC-122`. Upper or lower case both work.
- **It opens a tab named after the card** in the project's space, in the
  project folder, and starts an agent in it. The agent is `claude`;
  `ENTOURAGE_AGENT` picks another command.
- **The project folder is trusted first.** Claude Code asks "do you trust this
  folder?" the first time it starts somewhere, which would leave the agent
  waiting. So `project new`, and `task new` before it opens the tab, mark the
  project's folder as trusted in Claude Code's own file (`~/.claude.json`).
  Only a project folder entourage made is marked: never a repo, and not a
  project folder you linked in from somewhere else. Where it cannot be done
  (no `jq`, or Claude Code has never run on the machine), entourage says so
  and Claude Code asks once.
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

### The Cards panel

On the `test` layout, the Cards panel under the projects list shows the open
cards of the project whose space is showing, each with a button that writes
the card up.

- **It shows what `task ls` lists**: the same statuses in the same order, each
  with its count, and the cards under them. A click on a status closes its
  group, and another opens it again. Which groups are closed is kept between
  starts of Herdr.
- **Start runs `entourage task new <project> <card>`**, so the card's tab
  opens in the project's space with the agent running. One card starts at a
  time. The button reads Starting… until the command is done, and if the
  command fails, a notification shows what it said.
- **A card whose tab is open reads Open**, and a click shows that tab rather
  than starting the card a second time. A tab is the card's when it is named
  after the card's ID, as `task new` names it.
- **When the cards cannot be listed, the panel shows why**, in the words of
  `task ls`: no Linear key saved, a project with no team, Linear out of reach.
  A space that is not a project says so.
- **It reads the cards again** when another space is shown, about once a
  minute while the window is visible, and when the refresh button above the
  list is clicked.
- **It works nothing out itself.** The project comes from
  `entourage project ls --json` and the cards from
  `entourage task ls <project> --json`, so the panel and the commands always
  agree. It needs what `task ls` needs: the Linear key and the project's teams.
- **On the sidebar's narrow rail**, each card shows as its number, and a click
  does what its button would.

### Hand-offs

Each step of a write-up ends by handing off: which step it was, how it ended
(`done`, `needs-human` or `failed`) and what comes next. So does the build,
which the `sdlc-build` skill runs in a started task: it hands off as `build`,
`done` only when the tests pass, with `review` next. Nothing runs a review
yet, so the build's commits wait on the task's branch for you. The agent records
each hand-off itself, with the block on stdin:

```sh
entourage task handoff <project> <card> <<'EOF'
phase: define
status: done
next: plan
summary: Set the type to fix. The Specification has six Done when items.
EOF
```

```sh
entourage task log <project> [<card>]
```

- **The command holds the rules.** It refuses a block with a missing line, an
  unknown status or step, a line that doesn't belong to that status, or a
  value that runs onto a second line, and says what to fix. Run it with no
  block to see the rules.
- **It is a command because wording wasn't enough.** An agent going from one
  skill straight into the next writes nothing in between, but it does run
  commands.
- **`task new` records the start,** so the time each step took can be read
  from the hand-offs alone.
- **It records your answers too.** When you reply to a question, the agent
  records a hand-off with `status: answered` and what you said in a few
  words. `task log` shows how long each step took, and the time a question
  waited on you as a line of its own, counted in no step. A question with no
  answer yet shows how long it has been waiting. A step that followed a
  question with no recorded answer is marked as including the wait.
- **With no card, it lists the project's cards.** `task log <project>` shows
  every card in the project that has hand-offs, newest first by its latest
  one, with where it stands (waiting on you, failed, or the step it finished
  and the one that comes next) and for how long. A card with no hand-offs is
  not listed: `task ls` lists the cards in Linear.
- **They are kept in `~/.config/entourage/entourage.db`,** a SQLite file
  beside your projects, on this machine only. It needs `sqlite3`, which macOS
  ships; `ENTOURAGE_SQLITE` picks another command. Without it `task new`
  still starts the agent, the hand-offs are not recorded, and
  `entourage status` says so.
- **The card stays in Linear.** The store records how a step ended, not what
  was written.
- **The Steps panel shows it in Herdr.** Select a card's tab, the one `task
  new` opened, and the panel lists that card's steps: the time of day, what
  the step did, how long it took, and its summary. A wait on you stands out,
  and so does a question still waiting. It shows the latest run of a card
  written up more than once. With no card's tab selected, it lists the
  project's cards instead, and a card waiting on you stands out. Click a card
  to see its steps, even when its tab is closed, and "All cards" to go back;
  selecting another tab goes back too. The panel draws what
  `entourage task log <project> [<card>] --json` prints and works nothing out
  itself, so the two always agree.

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
- **Setup is off for now**, while the local environment each task gets is
  worked out. The output says it was not run. Set `ENTOURAGE_SETUP=1` (see
  [entourage's variables](#entourages-variables)) to turn it on. The next
  two points describe it when it is on, and groups in targets only matter then.
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
| `setup` | Make a fresh checkout ready to work in: install dependencies and anything else a new worktree lacks. Safe to run twice. Called with group names (`just setup athlete coach`), make ready only what those groups need, and fail with a clear message for a group the repo does not have. | `entourage task start`, when `ENTOURAGE_SETUP=1` |

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
- **Say in the repo's docs how a fresh checkout is made ready.** While setup
  is off, the `sdlc-build` skill reads the repo's `CLAUDE.md`, `AGENTS.md` or
  `README` to learn what to install before it runs the tests, and installs
  that into the task's worktree. It installs only: it starts no app, server
  or database, and asks you when the tests need one running or a tool
  installed on the machine.

## entourage's variables

entourage reads a few environment variables. Each can be exported in your
shell, or written as a `NAME=value` line in entourage's env file,
`~/.config/entourage/.env`.

| Variable | What it sets |
|---|---|
| `LINEAR_API_KEY` | Your Linear API key. `entourage linear key` writes this line for you. |
| `ENTOURAGE_AGENT` | The agent `task new` starts. `claude` when it is not set. |
| `ENTOURAGE_SQLITE` | The command that records hand-offs. `sqlite3` when it is not set. |
| `ENTOURAGE_SETUP` | `1` makes `task start` run each repo's `setup` recipe. Off when it is not set, for now. |
| `HERDR_APP_HOME` | Herdr's folder. `~/.config/herdr-app` when it is not set. |
| `CLAUDE_CONFIG_DIR` | Claude Code's folder, where skills are linked. `~/.claude` when it is not set. |
| `ENTOURAGE_HOME` | entourage's own folder. `~/.config/entourage` when it is not set. Export only: it says where the env file is, so the file cannot set it. |

- **Use the file for anything a Herdr mod's run of entourage needs.** Herdr
  starts a command without your shell's exports, so a variable set only in your
  shell profile is missing there. The file is read every time, wherever
  entourage is started from.
- **A variable you export wins** over its line in the file, unless it is
  empty: an empty one counts as not set.
- **Of two lines for a name, the last is used**, so a line added at the end
  takes over.
- **The file is read, never run.** A line that is not `NAME=value` is skipped,
  and nothing in a value is expanded. These are allowed: `export` before the
  name, spaces around the `=`, one pair of quotes around the value, and a `#`
  comment after a value that has no quotes. Only entourage's own variables are
  taken from it: the ones in the table, and any other whose name starts with
  `ENTOURAGE_`. A line for anything else, such as `PATH`, is ignored.
- **The Linear key stays with entourage.** The other variables are passed on to
  the programs entourage starts, so they find the same folders it does. The key
  from the file is not: it reaches only `curl`, on its stdin.
- **Keep the file to yourself.** It holds your Linear key. `linear key` makes
  it readable only by you; if you make it by hand, run
  `chmod 600 ~/.config/entourage/.env`. A file entourage cannot read stops every
  command, with a message saying so, rather than being skipped.
- **A linked env file is left alone.** If `.env` is a link, for example into a
  dotfiles repo, `linear key` saves nothing and says so, so that the key does
  not land in that repo. Add the `LINEAR_API_KEY` line yourself.

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
