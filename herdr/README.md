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

## Use it on a machine

Herdr reads everything from `~/.config/herdr-app`. Link this repo's mods and
layouts into it, from the repo root:

```sh
for m in herdr/mods/*/; do ln -s "$PWD/${m%/}" ~/.config/herdr-app/mods/; done
for l in herdr/layouts/*.json; do ln -s "$PWD/$l" ~/.config/herdr-app/layouts/; done
```

Then switch layout with `ctrl-shift-l`, or the Layout dropdown once you are on
one of these layouts.

## Changing things

- Edit files here, not in `~/.config/herdr-app`: the links mean they are the
  same files.
- Herdr does not notice edits made through a link straight away. Switch to
  another layout and back, or restart Herdr, to pick them up.
- Run `herdr-app check herdr/mods/<name>` after editing a mod.
- Herdr's shipped layouts and mods are read-only. To build on one, clone it
  (`herdr-app do layout.clone '{"name":"main","as":"<name>"}'`) and move the
  clone here.
