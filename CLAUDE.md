# entourage

Published to npm as `@johngaynor/entourage`. Machines get changes only from a
published release, so merging to `main` does not ship anything.

Run the tests with `npm test`, or one area with `npm test -- task` (the areas
are the files in `test/`: `install`, `project`, `task`).

The CLI is `cli/entourage`, which sets the paths and sources the files in
`cli/lib/`. A new file in `cli/lib/` must be added to the list in
`cli/entourage`; a new test case must be added to `CASES` in its test file.

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
checks the tag against `package.json`, runs the tests and publishes. Confirm it
passed with `gh run watch`, then `npm view @johngaynor/entourage version`.

A published version can never be published again. If a release is wrong, fix it
and release the next patch version. Do not delete or move tags.

Never run `npm publish` by hand, and never read or print the `NPM_TOKEN` secret.
