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
| `CLAUDE.md`, `AGENTS.md` | Generated: links to `PROJECT.md`, so an agent started in the space reads it. |

- **Make one:** `entourage project new <name>`, then
  `entourage project add <name> <path>` for each repo. The repo must already
  be cloned on this machine.
- **Open it:** `entourage project open <name>` rebuilds the links and shows
  the project's space, making it if it is not open. The space's folder is the
  project folder.
- **Check them:** `entourage status` reports a repo that has moved or gone,
  and a `PROJECT.md` that is still the template. Delete the template's first
  line once you have filled it in.
- **Remove a repo:** delete its line from `repos`; the next `open` drops its
  link. To remove a project, close its space and delete its folder.
- **The linked repos are shared.** A repo in two projects is the same clone
  in both, so switching branches in one changes it in the other.

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
