# entourage

Published to npm as `@johngaynor/entourage`. A machine installed through npm
gets changes only from a release: `entourage update` installs npm's `latest`,
and only a release moves it. Every push to `main` is published too, as a merge
build under the npm tag `next`, which such a machine gets only when asked. A
machine running from a clone gets whatever `git pull` brings.

Run the tests with `npm test`, or one area with `npm test -- task` (the areas
are the files in `test/`: `install`, `space`, `task`, `skills`, `handoff`,
`linear`, `runner`, `release`, `guard`, `after-merge`, `profile`). The
`handoff` tests use the real `sqlite3` and `jq`, the `install`, `linear`,
`task`, `skills` and `profile` tests the real `jq`, the `release` tests the
real `git` and `jq`, the `guard` tests all three, and the `after-merge` tests
the real `git`; they have to be in `/usr/bin` or `/bin`.
No test reaches Linear: a
stand-in `curl` answers from canned files. Cases run side by side, each in a
process of its own, so a case must not depend on another case or on anything
outside its own throwaway folder. To run one case at a time, set
`ENTOURAGE_TEST_JOBS=1`.

The `justfile` at the root has the `setup` recipe entourage asks every repo
for. It installs nothing today, since the tests need nothing installed in the
checkout; anything a new worktree comes to need goes there.

The CLI is `cli/entourage`, which sets the paths and sources the files in
`cli/lib/`. A new file in `cli/lib/` must be added to the list in
`cli/entourage`; a new test case must be added to `CASES` in its test file; a
new test area must be added to `AREAS` in `test/run.sh`.

## Words

The words the docs use are in [GLOSSARY.md](GLOSSARY.md): software factory,
orchestrator, step, phase, the build step and the build phase, the review
step and the Review, the phase profiles and the dev profiles, agent, harness
and herdr-core. When you write or change a doc, a skill, a prompt or a
profile, use each of those words only in the sense the glossary gives it, and
never build or review alone as a noun. When a word comes to mean something
new, change the glossary in the same pull request.

## Working in a worktree

A task's worktree of this repo holds a second copy of the CLI, the change
being built. Which copy to run for what:

- **Plain `entourage` for the card's own steps**, such as recording a
  hand-off, `task log` and `task ls`. It is the copy this machine runs, the
  main checkout or the npm install, and it is never stopped, whatever folder
  it is run from.
- **`./cli/entourage` to try the change.** It runs the worktree's code against
  the real machine, so it runs only the commands that read: `help`, `status`,
  `space ls`, `space team <name>` with no teams, `profile ls`, `task ls`,
  `task log` and `task watch`. Any other command stops before it does
  anything and says so, and the hand-off store is opened read-only.
- **A test case to try a command that changes the machine.** Each case has a
  throwaway home and stand-ins for Herdr and Linear.
- **`ENTOURAGE_LIVE=1 ./cli/entourage …` only when the human asks for it.** It
  runs the worktree's copy on the real machine, as the main checkout's would,
  for that one run. The env file cannot set it.

The guard is `cli/lib/guard.sh`. It lists the commands a worktree's copy may
run, so a new command is refused there until it is added to that list, and
it is added only if it changes nothing.

## Reviewing a change

To review a change, or to check what the reviewer found, start the
`entourage-reviewer` or the `entourage-verifier` subagent, not
`general-purpose`. They are the dev profiles, `reviewer` and `verifier`, and
their sources are in `.claude/profiles/`. A clone that is
the live copy writes them into `~/.claude/agents` at `entourage install`, at
`entourage update` and at each `entourage profile set` for the reviewer or
the verifier, so any session on this machine can start them by name. Each
runs on the model and effort `~/.config/entourage/settings.json` names for
it, Opus at `xhigh` unless changed with
`entourage profile set <reviewer|verifier> <model|effort> <value>`. A change
to a source in a worktree reaches them only once it has merged and the live
copy has run `entourage update`. Each has only the tools it uses, and
carries the rules every prompt to them used to repeat: which docs to read,
bash 3.2, the read-only worktree and the `mktemp -d` scratch folders, the
real Herdr and Linear left alone, the env file and its key never read, no
subagents of its own, and how to report. So give it only what to check: the
branch, diff or files, and what to look for. The `entourage-reviewer` grades
what it finds; the `entourage-verifier` tries to refute each finding and
judges it `fix-now`, `fix-later` or `skip`.

The phase profiles in `agents/`, `write-up` and `build`, are a different
thing: the ones `task new` and `task build` start `claude` with, which
`entourage install` links into `~/.claude/agents`. Each starts with
`--model=` and `--effort=` from the same settings file, for the write-up
phase and for the build phase.

## Herdr's docs

Herdr's docs for mods are `AGENTS.md`, `herdr.d.ts` and `gpui-kit.d.ts` in
`~/.config/herdr-app`. They are large, so never read one whole. Find the part
you need: list the headings with `grep -n '^#' ~/.config/herdr-app/AGENTS.md`,
where a section ends at the next heading of its level, or grep a `.d.ts` file
for the declaration, such as `export function exec`. Then read only that
range, with `sed -n '<from>,<to>p'` or `Read` with an offset and a limit.

## After a pull request merges

This is for working on entourage from a clone that is the live copy: the one
this machine's `entourage` command and Herdr's links run from. A Claude Code
session that worked in a worktree under `.claude/worktrees/` cleans up in one
call once its pull request has merged. Leave the worktree first, so that the
session is back in the live checkout, then run this there:

```sh
scripts/after-merge <name>
```

`<name>` is the worktree's folder under `.claude/worktrees/`. Run it instead
of doing what it does by hand. It checks that every commit on the branch is in
`main` on GitHub, and that the worktree has nothing that removing it would
lose, such as uncommitted changes or ignored specs under `docs/`. Then it
removes the worktree and deletes its branch with `git branch -d`. When the
live checkout is on `main` with no changes and can fast-forward, it also runs
`cli/entourage update`, which pulls, and `cli/entourage status`; otherwise it
says why it left the checkout alone. When a check fails, or the session still
has the worktree locked, it changes nothing and says why. It never merges and
never forces anything. It is not for the task worktrees that
`entourage task start` makes.

## Versions and releases

**Never change `"version"` in `package.json` as part of a feature or fix PR.**
Parallel PRs would conflict on that line, and a merge is not a release.

**Cut a release only when the user asks for one.** A release reaches every
machine installed through npm the next time it runs `entourage update`.

### Picking the level

Look at the commits since the last release tag (`git describe --tags --abbrev=0`;
if there is no tag, since the commit that set the current version):

- **major**: a change that breaks a machine already set up, such as renaming or
  removing a layout, mod or CLI command.
- **minor**: at least one `feat:` commit.
- **patch**: only `fix:`, `docs:`, `chore:`, `refactor:` or `test:` commits.

If the level is unclear, ask the user.

### Cutting the release

On an up-to-date `main` with a clean working tree:

```sh
npm test
npm version <patch|minor|major>   # edits package.json, commits, tags vX.Y.Z
git push --follow-tags
gh release create vX.Y.Z --generate-notes
```

Publishing the GitHub release starts the `Publish to npm` workflow, which runs
the tests, checks the tag against `package.json` and publishes. The push starts
a run of its own, for a merge build, so name the release's run when you watch
it:

```sh
gh run watch --exit-status "$(gh run list --workflow publish.yml --event release --limit 1 --json databaseId --jq '.[0].databaseId')"
```

Then `npm view @johngaynor/entourage version`. npm can take a few minutes to
show a new version, so right after the run it may still print the old one.

A published version can never be published again. If a release is wrong, fix it
and release the next patch version. Do not delete or move tags.

Never run `npm publish` by hand. The workflow signs in to npm by trusted
publishing, so there is no npm token; do not add one.

### Merge builds

Every push to `main` starts the same workflow, which publishes a merge build
under the npm tag `next`. Its number is `X.Y.(Z+1)-next.N`: `X.Y.Z` is the
version in `package.json`, and `N` is the number of commits since the tag
`vX.Y.Z`. `.github/scripts/merge-build-version.sh` works it out in the
workflow, and nothing is committed. The commit `npm version` makes is a push
too, so a release also publishes `X.Y.(Z+1)-next.0`.

`entourage update` never installs a merge build. To try one on a machine that
was installed through npm:

```sh
ENTOURAGE_NPM_SPEC=@johngaynor/entourage@next entourage update
```

A plain `entourage update` puts that machine back on the latest release.
`npm view @johngaynor/entourage dist-tags` shows where `latest` and `next`
point, and `npm view @johngaynor/entourage@<version> gitHead` names the commit
a version was made from.

In `publish.yml`, the merge build's `npm publish` must keep `--tag next`.
Without a tag npm refuses it, since a prerelease needs one; under `latest` it
would reach every machine installed through npm. `test/release.sh` pins the
workflow's lines that decide what is published, when and under which tag, so
an edit to them fails the tests until the tests change too. The tests run in a
job of their own, which cannot sign in to npm, and the publish job waits for
it.

Runs wait their turn, so every push gets a merge build of its own. A merge
build is never published over a newer one: when `next` is already on a merge
build that contains the run's commit, the run fails without publishing
(`.github/scripts/next-moves-forward.sh`). That is what re-running an old run
does, so re-run a failed merge build only when it is for the newest commit on
`main`; otherwise the next push publishes. A push whose `package.json` version
has no tag also fails without publishing; that is what happens when a release
commit is pushed without `--follow-tags`.

npm takes a few minutes to show a new merge build, and the check on `next`
sees the same delay. So it stops a re-run of an old run, but cannot tell apart
two runs that publish within minutes of each other. GitHub starts waiting runs
in the order they were queued, though it does not promise to.
