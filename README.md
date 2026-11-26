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
