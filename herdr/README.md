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
| `mods/agent-settings/` | The Agents button at the right end of the tab bar, and the popup it opens: the model and effort of each phase profile and dev profile, which a click changes. See [Agent settings](#agent-settings). |
| `layouts/default.json` | Herdr's own layout, plus the layout dropdown, and the Agents button beside the tabs: the tab bar is a row of Herdr's `tabs` and `agent-settings`. |
| `layouts/test.json` | `default` with the projects list in place of spaces, plus the Cards and Steps panels and the CPU mod in the sidebar. |
| `projects/template/` | The starting `PROJECT.md` for every new project. |

The skills are in [../skills/](../skills/), outside this folder. They are
linked into `~/.claude/skills` (`CLAUDE_CONFIG_DIR` picks another `~/.claude`)
by the same `entourage install` and `entourage update`. So are the phase
profiles in [../agents/](../agents/), into `~/.claude/agents`: the ones
`task new` and `task build` start `claude` with.

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

   This installs the Herdr app, herdr-core (which runs the terminals, and so
   is the host of the agent in each tab), and the `herdr-app` and `hc`
   commands in `~/.local/bin`.

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

   It links every mod and layout into Herdr, every skill into
   `~/.claude/skills` and both phase profiles into `~/.claude/agents`, and
   refreshes Herdr if it is running. It also makes
   `~/.config/entourage/settings.json`, the model and effort each of the four
   profiles runs on, with every profile on Opus at `xhigh` effort (see
   [Agent settings](#agent-settings)). It is safe to re-run, and it never
   replaces a real file or someone else's link that is already there, or a
   settings file that is there.

5. Pick a layout from the Layout dropdown at the top of the sidebar, or press
   `ctrl-shift-l` to cycle. The dropdown only appears on our layouts, so the
   first switch from Herdr's own layout is `ctrl-shift-l`.

## Keeping a machine up to date

```sh
entourage update
```

This reinstalls the latest entourage through npm, links any mod, layout, skill
or phase profile that is new, removes links to ones that were deleted, makes
the settings file if it is missing, writes the dev profiles' subagents again
on a clone (see [Agent settings](#agent-settings)), and refreshes Herdr so it
re-reads everything.

- **Check a machine:** `entourage status` lists each mod, layout, skill and
  phase profile and whether it is linked, and on a clone each dev profile's
  subagent and whether it is written. A settings file that is not valid
  settings is a problem it names.
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
handoff` and `task log`, record and show how each step ended.
`task ls` lists the cards there are to start.

### Seeing a project's cards

```sh
entourage task ls <project> [--json]
```

- **It lists the open cards of the project's Linear teams**, under their
  statuses, in the order Linear shows the statuses. Open means not done, not
  cancelled and not a duplicate, so a card In Progress or In Review is listed.
  Each card is its ID and its title, and under each status the card changed
  last comes first. A status with no cards is listed with a count of 0.
- **It asks Linear itself, with no agent running.** That needs two things, each
  set once:

  | Set once | With | What it is |
  |---|---|---|
  | Your Linear API key | `entourage linear key` | Make the key in Linear, under Settings, Account, Security & access, Personal API keys. Read permission is enough to list cards; the card skills' writes need Write too (see [Writing the card up](#writing-the-card-up)), and so do the card's moves (see [Starting the work](#starting-the-work)). The command asks for it without showing it, checks it with Linear, and saves it. |
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
  team, a `teams` file it cannot read, a line of that file that is not a team
  key, or a team key Linear does not have.
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
- **Two teams' cards share a group when their statuses have the same name and
  the same type**, such as a Backlog of type `backlog` in each. A status only
  one team has is a group of its own, and so is one whose name another team
  gives to a status of another type.
- **It needs `curl` and `jq`**, and says which is missing.

### Writing the card up

```sh
entourage task new <project> <card>
```

- **The card is its ID**, like `ABC-122`. Upper or lower case both work.
- **It opens a tab named after the card** in the project's space, in the
  project folder, and starts an agent in it for the write-up phase. The
  harness is `claude`; `ENTOURAGE_AGENT` picks another command.
- **`claude` starts with the write-up phase profile**,
  [../agents/entourage-write-up.md](../agents/entourage-write-up.md), linked
  into `~/.claude/agents`, on the `write-up` profile's model and effort:
  `claude --agent=entourage-write-up --strict-mcp-config
  --mcp-config=<repo>/agents/linear-mcp.json --model=opus --effort=xhigh`.
  The profile gives the session only the tools the write-up phase uses, the
  MCP config gives it Linear's server alone, whatever your own sessions have,
  and the model and effort are the ones `~/.config/entourage/settings.json`
  names for the `write-up` profile, which beat your own Claude Code settings
  (see [Agent settings](#agent-settings)). Claude Code asks once to sign in to
  Linear as `linear-server` on a machine where it is not signed in under that
  name. Another harness starts as it is, with no profile, model or effort.
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
- **Your approval moves the card.** Once you approve it, and its sub-issues
  exist when it was sliced, the agent records the approval, and recording it
  moves the card in Linear to its team's first not-started status (Todo in
  Lab, Ready for Dev in PHY), and each of its sub-issues with it, by its own
  team's statuses (see [Hand-offs](#hand-offs)). A card already further
  along, done or canceled stays where it is. When a card cannot be moved, the
  approval is still recorded, and the agent tells you which card, and why.
- **It makes no branch, worktree or task folder.** The card has no type until
  the agent has defined it, and the type is the start of the branch name.
- **It checks first.** An unknown project, something that is not a card ID,
  Herdr not running, no harness on your `PATH`, the skills not linked into
  `~/.claude/skills`, or, for `claude`, the write-up phase profile not linked
  into `~/.claude/agents` stops it before anything is opened. Run
  `entourage update` to link them. So does a settings file that is not valid
  settings, for `claude`, saying what in it is wrong.
- **With a Linear key saved, it checks that Linear has the card**, so a
  mistyped ID stops it before an agent starts. It looks the card up by its
  team's key and number, so it does not check that the card is one of the
  project's teams. Only a definite no stops it: with no key saved, Linear is
  not asked, and when Linear cannot be asked (the network, a rejected key, no
  `curl` or `jq`), the card starts as before, with a note saying why.
- **The skills write to the card through entourage.** The agent reads the card
  with its own Linear tools, but sets the type and writes each section with two
  entourage commands, so those writes go the same way on every run. A third,
  which `sdlc-pr` runs once its pull requests are open, moves the card (see
  [Hand-offs](#hand-offs)):

  | Command | What it does |
  |---|---|
  | `entourage linear type <card> <feat\|fix\|chore>` | Sets the card's type: its one label in the `Type` label group, the team's or else the workspace's. Any other type comes off; the card's other labels are never touched. A missing label is refused, never made. |
  | `entourage linear section <card> <Specification\|Plan\|Breakdown> [--replace]` | Adds the section, its body on stdin, below the description. Specification and Plan are folded away, in the form Linear keeps them in, `+++ ## <name>` … `+++` (one written as `>>>` is read the same); the Breakdown is left open, because you read it to approve the card. A section of that name already there is refused, unless `--replace` puts the new one in its place; `--replace` with none there is refused too. A body is refused when a line in it would end the section early or start a second one: a fold line, and in the Breakdown a `#` or `##` heading. A line inside a fenced code block is never taken for a section. |
  | `entourage linear move <card> <approved\|started\|review\|done>` | Moves the card forward to its team's first not-started status (Todo in Lab, Ready for Dev in PHY), its first started status (In Progress), its last started one (In Review), or its first completed one (Done), picked by its kind and its place in the team's order, not by its name. `approved` moves each of the card's sub-issues after it the same way, by its own team's statuses, and is the move your approval makes. In a team with one started status, `review` is that status. A card already there, further on, done or canceled stays where it is, and the command says so and exits zero. A move that cannot be made, such as with Linear out of reach or a key without Write permission, exits non-zero, saying which card was not moved and why; the other cards still move. |

  All three read the card back before they say they are done: one type, the
  one asked for; the section there once, and the text above it as it was; the
  card in the status it was moved to. All three need your key to have Write
  permission. With no key saved, the skills write the type and the sections
  with the agent's Linear tools instead, and say so; the card is not moved then,
  and `sdlc-pr` says so.

### The Cards panel

On the `test` layout, the Cards panel under the projects list shows the open
cards of the project whose space is showing, each with a button that writes
the card up. Each card is under its status in Linear, which shows where its
work is: your approval moves a card and its sub-issues to Todo, `task start`
moves it to In Progress, opening its pull requests moves it to In Review, and
recording its merge moves it to Done, which takes it off the list (see
[Starting the work](#starting-the-work)).

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

Each step of the write-up phase ends by handing off: which step it was, how it
ended (`done`, `needs-human` or `failed`) and what comes next. Breakdown, the
last of them, hands off `done` with `start` next once you approve the card:
the next step is `entourage task start`, which you run. Recording that
hand-off moves the card in Linear to its team's first not-started status (Todo
in Lab, Ready for Dev in PHY), and each of its sub-issues with it, by its own
team's statuses. What happened to each card is said on stderr; when one cannot
be moved, the hand-off is still recorded, the note names each card that was
not moved and why, and the agent tells you. The build phase hands off too. The
build step, which the `sdlc-build` skill runs in a started task, hands off as
`build`, `done` only when the tests pass, with `review` next. So does the
review step after it, which the `sdlc-review` skill runs: it hands off as
`review`, `done` with `pr` next when every Done when item is met, or with
`build` next, naming each item that is not. Once it has sent the work back, it
asks you instead, as `needs-human`, whether to build again. So does the pr
step after that, which the `sdlc-pr` skill runs: it hands off as `pr`. Once
every pull request for the card is open, it moves the card in Linear to its
team's last started status (In Review) with
`entourage linear move <card> review`; in a team with one started status the
card stays in it. When the card cannot be moved, it still goes on, and says
so, and why, in its hand-offs. With the pull requests open it waits as
`needs-human`, with their links, while you merge them, and watches them on
GitHub with `entourage task watch`, run in the background, so you don't have
to tell it they have merged. A change you ask for in the tab instead goes on
the task's branch and into the same pull requests, and it waits as
`needs-human` again. Once GitHub says every pull request for the card has
merged, it records that as your answer, `answered`, so the log shows how long
the pull requests waited on you, and hands off `done` with `merged` next.
Recording that hand-off moves the card in Linear to its team's first completed
status (Done), whatever recorded it: your answer, or a watch on the pull
requests. A card that is done or canceled already stays as it is. When a pull
request is closed without merging, it records that the same way and asks you
whether to stop, and the card is not moved. When one is in conflict with its
default branch, it records that the same way and brings it up to date without
asking you: it merges the default branch in, never by a rebase, fixes what the
tests find, commits the merge and hands off `done` with `review` next. The
review step checks each Done when item again, with the merge, and hands back
to `pr`, which pushes only the branch that moved, never forced, adds a
**Brought up to date:** line to its pull request's description, with the files
that conflicted and what the fix changed, and waits as `needs-human` again. It
asks you about a conflict, as `needs-human` naming the pull request and the
files in conflict, only when the tests cannot be made to pass or the fix would
change what a Done when item says, and pushes nothing until you answer. What
happened to the card is said on stderr, so the block printed is the one
recorded; when the card cannot be moved, the hand-off is still recorded, and
the note says why. Right after that hand-off, as the run's last command, the
agent finishes the task with `entourage task finish` (see
[Finishing a task](#finishing-a-task)): its worktrees, its branch in each repo
and its folder go, and then its tab closes. When that would lose work, it
removes nothing, and the agent tells you everything it named and leaves the
task as it is. A pull request closed without merging finishes nothing either:
the agent asks you whether to stop. When it cannot push or open a pull
request, such as when `gh` is not signed in or a repo has no remote, it hands
off `failed` with the reason. `merged` is where a card ends: it is only ever
next, and `task handoff` refuses it in the `step:` line, which names the step
a hand-off is for. It does the same with `start`, since only `task start`
records that step. The agent records each hand-off itself, with the block on
stdin:

```sh
entourage task handoff <project> <card> <<'EOF'
step: define
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
  value that runs onto a second line, and says what to fix. A block from an
  agent that started before the step's line was called `step:` is refused
  once, with `step:` to write in its place. Run it with no block to see the
  rules.
- **It is a command because wording wasn't enough.** An agent going from one
  skill straight into the next writes nothing in between, but it does run
  commands.
- **`task new` records the start,** so the time each step took can be read
  from the hand-offs alone.
- **`task start` records a start too,** as `start` in the log, with `build`
  next, so the build phase's first step is timed from it and not from your
  approval. It is the step breakdown named, so the log reads
  `breakdown  done, then start` and then `start  done, then build`. A
  hand-off recorded before the step was called `start` keeps the name it was
  recorded with, `setup`. Like the start of the write-up phase it shows as
  started, with no time, but it begins no new run: the Steps panel shows the
  write-up phase and the build phase of a card together.
- **It records your answers too.** When you reply to a question, the agent
  records a hand-off with `status: answered` and what you said in a few
  words. `task log` shows how long each step took, and the time a question
  waited on you as a line of its own, counted in no step. A question with no
  answer yet shows how long it has been waiting. A step that followed a
  question with no recorded answer is marked as including the wait.
- **With no card, it lists the project's cards.** `task log <project>` shows
  every card in the project that has hand-offs, newest first by its latest
  one, with where it stands (waiting on you, failed, the step it finished
  and the one that comes next, or merged once its pull requests have) and
  for how long. A card with no hand-offs is
  not listed: `task ls` lists the cards in Linear.
- **They are kept in `~/.config/entourage/entourage.db`,** a SQLite file
  beside your projects, on this machine only. It needs `sqlite3`, which macOS
  ships; `ENTOURAGE_SQLITE` picks another command. Without it `task new`
  still starts the agent, the hand-offs are not recorded, and
  `entourage status` says so. A store made before the block's line was
  called `step:` keeps each step in a column called `phase`. The first
  hand-off recorded into it renames that column to `step` and keeps every
  hand-off it held; until then `task log` reads it as it is and changes
  nothing.
- **The card stays in Linear.** The store records how a step ended, not what
  was written.
- **The Steps panel shows it in Herdr.** Select a card's tab, the one `task
  new` opened, and the panel lists that card's steps: the time of day, what
  the step did, how long it took, and its summary. A wait on you stands out,
  and so does a question still waiting. It shows the latest run of a card
  written up more than once. With no card's tab selected, it lists the
  project's cards instead, and a card waiting on you stands out. A card
  whose pull requests have merged shows as merged. Click a card
  to see its steps, even when its tab is closed, and "All cards" to go back;
  selecting another tab goes back too. The panel draws what
  `entourage task log <project> [<card>] --json` prints and works nothing out
  itself, so the two always agree.

### Starting the work

One branch for an approved card, checked out as a git worktree of the repos
the task needs, and shown as a tab in the project's space.

```sh
entourage task start <project> <card> [<repo>[:<group>[,<group>...]] ...]
```

- **The card is its ID**, like `ABC-122`, as for `task new`. The write-up
  phase gives you this command once you approve the card. For a card that was
  sliced, it gives the first sub-issue's ID.
- **Linear names the branch.** `task start` asks Linear for the card, with
  the key `linear key` saved (see
  [Seeing a project's cards](#seeing-a-projects-cards)), and makes the branch
  `<type>/<card-id>-<short-name>`. The type is the card's label in the `Type`
  group, which the write-up phase sets. The short name is the first four words
  of the card's title, in lowercase with hyphens, leaving out a, an and the,
  and anything a branch name cannot hold. "Insert the task here" gives
  `feat/abc-122-insert-task-here`.
- **It stops before it makes anything** when Linear has no such card, the
  card has no type yet (write it up first with `task new`), no key is saved,
  or Linear cannot be asked. It says what to do. A branch in place of the
  card is refused too, with a note that `task start` takes the card now.
- **Targets say what the task works on.** Each one names a repo of the
  project by its folder name, and optionally groups inside it:

  | After the card | The task gets |
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

- **The branch follows [Conventional Branch](https://conventionalbranch.org).**
  A card's type is `feat`, `fix` or `chore`. A type label that is not one of
  the spec's types (`feature`, `feat`, `bugfix`, `fix`, `hotfix`, `release`,
  `chore`, `ai`, `claude`, `codex`, `copilot` or `cursor`) stops it.
- **Everything after the type names the task.** `feat/abc-122-insert-task-here` makes
  the folder `tasks/abc-122-insert-task-here` and a tab of that name.
- **Each of the task's repos gets a worktree** at `tasks/<task>/<repo>`, on the new branch,
  cut from the remote's default branch after a fetch. A repo that cannot be
  fetched starts from what is local, with a warning.
- **The repos' own checkouts are not touched.** They stay on whatever branch
  they were on.
- **Where the tab starts:** in the worktree when the task has one repo; in
  the task folder when it has several. That folder has `CLAUDE.md` and
  `AGENTS.md` links to the project's `PROJECT.md`.
- **The agent starts in the tab.** Once the tab is open, `task start` types
  `entourage task build <project> <card>` into its shell, after setup when
  setup runs, so the agent starts on the card with no one typing there, and
  not before setup has finished. `task build` starts the agent for the build
  phase in its harness (`ENTOURAGE_AGENT`, or `claude`) in the folder it is
  run in, with the first message in
  [prompts/task-build.md](../prompts/task-build.md). `claude` starts with the
  build phase profile,
  [../agents/entourage-build.md](../agents/entourage-build.md), and Linear's
  server alone, as `task new` starts the write-up phase's: the tools the build
  phase uses, on the model and effort the settings file names for the `build`
  profile. The first message has it build the card with `sdlc-build`, then
  check that work with `sdlc-review`, and go back to the build step when the
  review step sends it back. When the review step finds every item met,
  `sdlc-pr` pushes the branch and opens the pull requests, and waits for you
  to merge them, watching them on GitHub with `entourage task watch
  <project> <card>` in the background. The watch asks GitHub every minute
  for the first 10 minutes after the newest pull request was opened, every 5
  minutes for the hour after that, then every 30 minutes, printing a line for
  each pull request (`merged`, `open`, `closed` or `conflict`, and its URL),
  and ends once every one has merged (exit 0), one is closed without merging
  (exit 3) or one is in conflict with its default branch (exit 4), which the
  agent then brings up to date. A closed one comes first. It changes nothing, and wakes the agent only when it ends. Telling the agent in
  the tab that they have merged makes it check at once, with `--once`, which
  checks once and exits 2 while one is still open. Once it hands off with
  `merged` next, it finishes the task with `task finish`, which closes the
  tab, and the run is over. No agent merges a pull request. `task build`
  refuses to run outside the card's own task folder, with no harness on your
  `PATH`, with the skills not linked, or, for `claude`, with the build phase
  profile not linked or a settings file that is not valid settings. If the agent stops, run the same command again in the
  tab.
- **The card moves to In Progress.** Once the tab is open, `task start` moves
  the card in Linear to its team's first started status: picked by its kind
  and its place in the team's order, not by its name, so it is In Progress in
  a team that calls it that and Doing in one that calls it Doing. A card only
  moves forward: one already further along, such as In Review, stays there,
  and one that is done or canceled is never moved; the output says why. The
  move needs your key to have Write permission. When Linear cannot be
  reached, or refuses the move, the task is still made and open, and the
  output says that the card was not moved, and why. Move it by hand then.
  Once every pull request is open, `sdlc-pr` moves it to In Review, and once
  every one has merged, recording the merge moves it to Done (see
  [Hand-offs](#hand-offs)).
- **Claude Code asks once to trust a repo it does not know.** With one repo,
  the tab starts in its worktree, and a worktree takes the trust of its repo's
  own checkout, not of the project folder above it. When Claude Code's file
  (`~/.claude.json`) has not trusted the repo yet, `task start` says that
  Claude Code will ask once in the tab. entourage never answers that question
  for a repo. With several repos the tab is in the task folder, inside the
  project folder that `project new` trusted, so there is nothing to ask.
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
  typed into the tab, the output gives you the line to run yourself: setup,
  then `entourage task build`, which starts the agent.
- **Nothing is made unless everything can be.** A task or branch of that name
  that already exists, a missing repo, or Herdr not running stops it first,
  and a worktree that fails partway is undone.
- **When the work has merged**, the agent runs `task finish` itself, which
  removes the task and closes its tab (see
  [Finishing a task](#finishing-a-task)).

### Finishing a task

Once a task's pull requests have merged, one command ends it. The build
phase's agent runs it itself, as its last command once it has recorded the
merge, so you run it only for a task it left, such as one it refused.

```sh
entourage task finish <project> <card>
```

- **It removes what `task start` made**: each of the task's worktrees, the
  task's branch in each repo, and the task's folder with its `CLAUDE.md` and
  `AGENTS.md` links. Then it closes the task's tab, the one named after the
  task in the project's space. The tab of the card's write-up phase, named
  after the card, stays open.
- **Run it anywhere, the task's own tab included.** It works from the project
  folder, so it can remove the worktree it was run in. Closing the tab is the
  last thing it does, so from the task's own tab everything else is done, and
  said, before the tab closes. When it is the space's last tab, Herdr asks
  first, since closing it closes the space. When Herdr is not running, `jq` is
  missing or no such tab is open, it says so and leaves the tab.
- **It finds the task from the card**, as the folder `tasks/<card>-…` that
  `task start` made, without asking Linear. A card with no task on this
  machine stops it, and nothing is changed.
- **It checks every repo of the task before it removes anything**, and
  removes nothing when that would lose work. It names every problem in every
  repo in one go, then says that nothing was removed:

  | It stops for | It names |
  |---|---|
  | Changes that are not committed: staged, unstaged or untracked | each file, as `git status` shows it |
  | Commits on the branch that are not in the remote's default branch, pushed or not, such as a fix pushed to the branch after its pull request merged | each commit |
  | Git-ignored files that the repo's setup does not make again (see [What a repo provides](#what-a-repo-provides)), such as `.env` or notes in an ignored `docs/` | each file |
  | Anything in the task folder outside its worktrees | each one |
  | A worktree that is locked, or not on the task's branch | the worktree |

- **Merged means in the default branch's history**, where a merge commit puts
  a pull request's commits. A pull request merged by squash or rebase leaves
  them out, so its task is refused, which loses nothing.
- **It fetches each repo first.** A repo that cannot be fetched is checked
  against what is local, with a warning, which can only make it refuse.
- **Ignored files the repo's setup makes again**, such as `node_modules`, are
  removed with the worktree without a word. Without `just`, or in a repo with
  no `made-by-setup` recipe, every ignored file counts as work, and it says
  why.
- **It forces nothing.** `git worktree remove` keeps git's own refusal, and
  the branch is deleted only while it is still on the commit that was
  checked.
- **It leaves the rest alone**: the branch on the remote, the card in Linear
  and the card's hand-offs, so `task log` still shows the card.
- **To throw away a task it refuses**, remove it by hand: in each repo run
  `git worktree remove --force <project folder>/tasks/<task>/<repo>` and
  `git branch -D <branch>`, then delete the task's folder and close its tab.

## Agent settings

Each of the four profiles, the two phase profiles and the two dev profiles,
runs on a model and an effort of its own, kept in
`~/.config/entourage/settings.json` (`ENTOURAGE_HOME` picks another
`~/.config/entourage`). It is not Herdr's `settings.json`, nor Claude Code's.

```sh
entourage profile ls [--json]
entourage profile set <profile> <model|effort> <value>
```

| Profile | Kind | What starts on it | How the values reach it |
|---|---|---|---|
| `write-up` | phase profile | the agent `task new` starts, for the write-up phase | `--model=` and `--effort=` on its `claude` command |
| `build` | phase profile | the agent `task build` starts, for the build phase | the same |
| `reviewer` | dev profile | the `entourage-reviewer` subagent, for work on entourage itself | written into its file in `~/.claude/agents` |
| `verifier` | dev profile | the `entourage-verifier` subagent, the same | the same |

- **`install` makes the file**, with every profile on Opus at `xhigh` effort,
  and `update` makes it again when it is missing. Neither changes a file that
  is there, even one that is not valid settings.
- **`profile ls` shows each profile's model and effort**, and what starts on
  it. `--json` prints them as one line for programs, with the models and
  efforts there are to choose from; the Agents button reads it.
- **`profile set` changes one value**, and the file then holds it. It takes a
  model that is one of claude's aliases (`fable`, `opus`, `sonnet`, `haiku`)
  or a full model name like `claude-opus-5-5` or `claude-opus-5-5[1m]`, an
  effort of `low`, `medium`, `high`, `xhigh` or `max`, and one of the four
  profiles. Anything else is refused, saying what it takes, and the file is
  left as it was. With no file yet, it makes one that names every profile.
- **The next agent starts with it.** A change reaches the next `task new` or
  `task build`, not an agent that is already running. `--model=` and
  `--effort=` beat the phase profile's own `model:` and your own Claude Code
  settings; only `CLAUDE_CODE_EFFORT_LEVEL` beats the effort.
- **A profile or a value the file leaves out is Opus at `xhigh`**, and so is
  every profile when there is no file.
- **A file that is not valid settings stops `task new` and `task build`**
  before an agent starts, and says what in it is wrong: not JSON, a profile
  that is not one of the four, or a model or effort it does not take.
  `profile ls` and `profile set` stop the same way, and `entourage status`
  reports it as a problem. Fix the file, or move it aside to go back to the
  defaults.
- **The dev profiles, the reviewer and the verifier, are written, not
  linked.** A subagent runs on the model and effort in its own file, and the
  Agent tool cannot give it an effort. So a clone of entourage writes
  [../.claude/profiles/](../.claude/profiles/)`entourage-reviewer.md` and
  `entourage-verifier.md` into `~/.claude/agents`, with `model:` and
  `effort:` from the settings file and a comment naming the source, at
  `install`, at `update`, and at each `profile set` for one of them. It
  replaces or removes only a file with that comment: one of your own of the
  same name is left alone, and named. `entourage status` lists each as
  `written`, `stale`, `missing` or `skipped`. Their names start with
  `entourage-`, so they do not take the place of a `reviewer` of your own. An
  npm install writes neither, since only a clone works on entourage.
- **It needs `jq`.** Without it `profile` stops and says so, and `task new`
  and `task build` stop only when there is a file to read.
- **Another harness**, named by `ENTOURAGE_AGENT`, starts with no model or
  effort, as before, and the file is not read.

### The Agents button

On both layouts, the tab bar is a row: Herdr's tabs, which take the room and
drag the window as before, then the Agents button at the right end.

- **A click opens a popup** with a row for each of the four profiles: its
  name, its model and its effort. Hover a name to see what starts on it.
- **A click on a model or an effort lists the choices**: claude's aliases,
  and the profile's own model when it is a full name, or the five efforts.
  Picking one runs `entourage profile set`, then reads the profiles again, so
  the popup shows what the file now holds and `entourage profile ls` agrees.
  The next `task new` or `task build` starts with it.
- **What entourage refuses shows in the popup**, in its words, such as a
  settings file that is not valid settings.
- **It works nothing out itself.** The profiles, their values and the choices
  come from `entourage profile ls --json`, and a change is made with
  `entourage profile set`, so the button and the command always agree. When
  `entourage` is not on Herdr's `PATH`, it runs the copy the mod is linked
  from.

## What a repo provides

entourage knows nothing about how a repo is built or run. A repo says so
itself, in a [justfile](https://just.systems) at its root, with recipes that
have the same names in every repo. entourage only knows the names.

| Recipe | What it must do | Used by |
|---|---|---|
| `setup` | Make a fresh checkout ready to work in: install dependencies and anything else a new worktree lacks. Safe to run twice. Called with group names (`just setup athlete coach`), make ready only what those groups need, and fail with a clear message for a group the repo does not have. | `entourage task start`, when `ENTOURAGE_SETUP=1` |
| `made-by-setup` | Print what `setup` makes again, as patterns like `.gitignore`'s, one per line, such as `node_modules/`. Print nothing else, and change nothing. | `entourage task finish`, which removes the git-ignored files these match with the worktree, and stops for any other ignored file |

```just
setup:
    npm install

# What setup makes again, so a task can throw it away.
made-by-setup:
    @echo node_modules/
    @echo dist/
```

- **`made-by-setup` says which ignored files are not work.** A task's
  worktree is checked out from the branch, so the recipe is the branch's own.
  It runs in the worktree, and its `@` keeps `just` from printing each line
  before it runs. A pattern that matches a folder matches everything in it;
  a folder it matches only part of is checked file by file. A repo without
  the recipe can still finish a task with no ignored files in it.

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
| `ENTOURAGE_AGENT` | The harness: the command `task new` and `task build` start the agent with. `claude` when it is not set, which starts with a phase profile. Another harness starts as it is, with no profile. Its name says agent, but what it names is the harness. |
| `ENTOURAGE_SQLITE` | The command that records hand-offs. `sqlite3` when it is not set. |
| `ENTOURAGE_SETUP` | `1` makes `task start` run each repo's `setup` recipe. Off when it is not set, for now. |
| `HERDR_APP_HOME` | Herdr's folder. `~/.config/herdr-app` when it is not set. |
| `CLAUDE_CONFIG_DIR` | Claude Code's folder, where skills and phase profiles are linked and the dev profiles written. `~/.claude` when it is not set. |
| `ENTOURAGE_HOME` | entourage's own folder. `~/.config/entourage` when it is not set. Export only: it says where the env file is, so the file cannot set it. |
| `ENTOURAGE_LIVE` | `1` lets the copy of entourage in a git worktree of its repo change the machine, for that run (see [Changing things](#changing-things)). Export only, best on the command line: the file cannot set it, so it is never left on. |

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
  command, with a message saying so, rather than being skipped, and so does
  anything at `.env` that is not a file, such as a folder.
- **A linked env file, or one in a git repo, is left alone.** If `.env` is a
  link, for example into a dotfiles repo, or entourage's folder is inside a git
  repo, as it is when GNU Stow links the whole folder into one, `linear key`
  saves nothing and says so, so that the key does not land in that repo. Add
  the `LINEAR_API_KEY` line yourself, once the repo ignores the file.

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
- A worktree's copy of the CLI, `./cli/entourage` in a git worktree of this
  repo, runs only the commands that read: `help`, `status`, `project ls`,
  `project team <name>`, `profile ls`, `task ls`, `task log` and
  `task watch`. Any other command stops
  before it changes anything, and says to run plain `entourage` for a card's
  own steps, to write a test case to try the command, or to run it for real
  with `ENTOURAGE_LIVE=1 ./cli/entourage …`. Plain `entourage` is never
  stopped.
- Herdr's shipped layouts and mods are read-only. To build on one, clone it
  (`herdr-app do layout.clone '{"name":"main","as":"<name>"}'`) and move the
  clone here.
