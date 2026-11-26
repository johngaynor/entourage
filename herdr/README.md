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

3. Clone this repo anywhere:

   ```sh
   git clone https://github.com/johngaynor/entourage.git
   ```

4. From the repo root, link the mods and layouts into Herdr:

   ```sh
   for m in herdr/mods/*/; do m=${m%/}; [ -e ~/.config/herdr-app/mods/"${m##*/}" ] || ln -s "$PWD/$m" ~/.config/herdr-app/mods/; done
   for l in herdr/layouts/*.json; do [ -e ~/.config/herdr-app/layouts/"${l##*/}" ] || ln -s "$PWD/$l" ~/.config/herdr-app/layouts/; done
   ```

   These are safe to re-run: anything already there is left alone.

5. Switch to one of our layouts:

   ```sh
   herdr-app do layout.switch '{"name":"default"}'
   ```

   From then on, use the Layout dropdown at the top of the sidebar, or
   `ctrl-shift-l` to cycle.

## Keeping a machine up to date

- **Get changes:** `git pull` in the clone. Then switch to another layout and
  back, or restart Herdr: it does not notice edits made through a link straight
  away.
- **A pull added a new mod or layout:** re-run step 4. Links are made per mod
  and per layout, so new ones need linking.
- **Remove one from a machine:** delete its link in `~/.config/herdr-app/mods`
  or `layouts`. The repo is untouched.
- **Herdr updates itself:** it replaces its own shipped mods and layouts on
  every start and leaves ours alone, because ours have different names.
- **Something broke the window:** `ctrl-alt-shift-escape` always returns Herdr
  to its own default layout.

## Changing things

- Edit files here, not in `~/.config/herdr-app`: the links mean they are the
  same files.
- Herdr does not notice edits made through a link straight away. Switch to
  another layout and back, or restart Herdr, to pick them up.
- Run `herdr-app check herdr/mods/<name>` after editing a mod.
- Herdr's shipped layouts and mods are read-only. To build on one, clone it
  (`herdr-app do layout.clone '{"name":"main","as":"<name>"}'`) and move the
  clone here.
