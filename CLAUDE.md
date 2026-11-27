# entourage

Published to npm as `@johngaynor/entourage`. Machines get changes only from a
release: `entourage update` installs npm's `latest`, and only a release moves
it. Every push to `main` is published too, as a merge build under the npm tag
`next`, which no machine installs unless asked.

Run the tests with `npm test`, or one area with `npm test -- task` (the areas
are the files in `test/`: `install`, `project`, `task`, `skills`, `handoff`,
`runner`, `release`). The `handoff` tests use the real `sqlite3`, and the
`release` tests the real `git` and `jq`; they have to be in `/usr/bin` or
`/bin`. Cases run side by side, each in a process of its own, so a case must
not depend on another case or on anything outside its own throwaway folder. To
run one case at a time, set `ENTOURAGE_TEST_JOBS=1`.

The CLI is `cli/entourage`, which sets the paths and sources the files in
`cli/lib/`. A new file in `cli/lib/` must be added to the list in
`cli/entourage`; a new test case must be added to `CASES` in its test file; a
new test area must be added to `AREAS` in `test/run.sh`.

## Versions and releases

**Never change `"version"` in `package.json` as part of a feature or fix PR.**
Parallel PRs would conflict on that line, and a merge is not a release.

**Cut a release only when the user asks for one.** Publishing reaches every
machine that runs `entourage update`.

### Picking the level

Look at the commits since the last release tag (`git describe --tags --abbrev=0`;
if there is no tag, since the commit that set the current version):

- **major**: a change that breaks a machine already set up, such as renaming or
  removing a layout, mod or CLI command.
- **minor**: at least one `feat:` commit.
- **patch**: only `fix:`, `docs:`, `chore:`, `refactor:` or `test:` commits.

If the level is unclear, ask the user.

### Steps

On an up-to-date `main` with a clean working tree:

```sh
npm test
npm version <patch|minor|major>   # edits package.json, commits, tags vX.Y.Z
git push --follow-tags
gh release create vX.Y.Z --generate-notes
```

Publishing the GitHub release starts the `Publish to npm` workflow, which
checks the tag against `package.json`, runs the tests and publishes. The push
starts a run of its own, for a merge build; the release's run is the one to
watch. Confirm it passed with `gh run watch`, then
`npm view @johngaynor/entourage version`.

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
a build was made from.

In `publish.yml`, the merge build's `npm publish` must keep `--tag next`.
Without it the build becomes `latest` and reaches every machine.

Runs wait their turn, so every push gets a build of its own. A merge build is
never published over a newer one: when `next` is already on a build that
contains the run's commit, the run fails without publishing
(`.github/scripts/next-moves-forward.sh`). That is what re-running an old run
does, so re-run a failed merge build only when it is for the newest commit on
`main`; otherwise the next push publishes. A push whose `package.json` version
has no tag also fails without publishing; that is what happens when a release
commit is pushed without `--follow-tags`.
