# entourage

A collection of agent skills for the software development lifecycle (SDLC).

## Status

Early setup. Skills are being ported in.

## Setting up a machine

```sh
npm install -g github:johngaynor/entourage
entourage install
```

`entourage install` links this repo into the tools on a machine, and
`entourage update` keeps it current. Today that covers the Herdr setup; see
[herdr/README.md](herdr/README.md) for the full walkthrough.

To work on entourage itself, clone the repo and run `cli/entourage install`
from the clone instead. Run the CLI's tests with `npm test`.
