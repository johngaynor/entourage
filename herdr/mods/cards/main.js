// The open Linear cards of the project whose space is showing, under their
// statuses, with a button on each card that starts it.
//
// Which project a space is, and which cards are open, are the entourage
// command's to say: `entourage project ls --json` and
// `entourage task ls <project> --json`. This mod draws what they answer and
// holds no rules about projects or Linear. A card's button runs
// `entourage task new <project> <card>`, which opens the card's tab in the
// project's space with the agent running in it.
//
// A click on a status opens or closes its group.
import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { exec, spaces, run, notify, theme, layout, window, checking, appHome } from "herdr";

const LOOK_MS = 1000; // how often to see whether another space is showing
const REFRESH_MS = 60000; // how often to read the cards again
const TIMEOUT_MS = 10000;
const LIST_TIMEOUT_MS = 30000; // task ls waits up to 20s on Linear
const START_TIMEOUT_MS = 60000;
const ROW = 30;
const RAIL_CELL = 32;
// How this mod's own link into the repo that ships it ends.
const LINKED_AT = "/herdr/mods/cards";
const NOT_A_PROJECT = "The shown space is not an entourage project.";
const OLD_CLI = "This entourage cannot list a project's cards. Run: entourage update";
const CHEVRON = "mods/workspace-chrome/chevron";
const SPINNER = "mods/workspace-chrome/spinner.svg";

// `herdr-app check` draws the mod once, with no space showing, which would
// draw one line of text and none of the rows. It is given these to draw
// instead: an open group, a closed one, an empty one, a card being started
// and a card whose tab is open.
const SAMPLE = {
  project: "sample",
  statuses: [
    { name: "Backlog", type: "backlog", cards: [
      { id: "ABC-1", title: "A card", url: "" },
      { id: "ABC-2", title: "A card being started", url: "" },
    ] },
    { name: "Todo", type: "unstarted", cards: [{ id: "ABC-3", title: "A card in a closed group", url: "" }] },
    { name: "In Progress", type: "started", cards: [{ id: "ABC-4", title: "A card with its tab open", url: "" }] },
    { name: "In Review", type: "started", cards: [] },
  ],
};
const SAMPLE_STARTING = "ABC-2";
const SAMPLE_CLOSED = new Set(["sample/Todo"]);
const SAMPLE_TABS = new Map([["ABC-4", { space: { id: "s", active: true }, tab: { id: "t", active: true } }]]);

function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

// The sidebar's rail goes by its width, as in Herdr's own lists.
const narrow = () => (find(layout(), "sidebar")?.size?.px ?? Infinity) < 160;

function parse(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

// What a failed command said, without the name it starts its errors with.
const said = (r) => (r.stderr || r.stdout).trim().replace(/^entourage: /, "");
// An entourage from before `task ls` answers with its usage line, not JSON.
const failure = (r, what) => {
  const text = said(r);
  return text.startsWith("usage:") ? OLD_CLI : text || `${what} failed`;
};

// The shown space's folder, when that space is on this computer: the only
// place an entourage project can be.
function shownFolder() {
  const space = spaces().find((s) => s.active);
  return space && !space.machine ? space.folder : null;
}

// The tabs `task new` has opened in the project's spaces, by card: it names
// each one after its card.
function cardTabs(folder) {
  const tabs = new Map();
  for (const space of spaces()) {
    if (space.machine || space.folder !== folder) continue;
    for (const tab of space.tabs) {
      const id = tab.name.toUpperCase();
      // The shown space's tab wins over another space of the same folder.
      if (!tabs.has(id) || space.active) tabs.set(id, { space, tab });
    }
  }
  return tabs;
}

// Which groups are closed: "<project>/<status>", kept between starts.
function loadClosed() {
  try {
    const list = JSON.parse(localStorage.getItem("closed") ?? "[]");
    return new Set(Array.isArray(list) ? list : []);
  } catch {
    return new Set();
  }
}

export default class Cards extends View {
  init(_props, cx) {
    this.cmd = "entourage"; // the one on PATH, until that cannot start
    this.closed = loadClosed();
    // What the last listing said for each shown folder: { project, folder,
    // statuses } or { error }. A space shown again draws its last answer
    // while it is read again.
    this.lists = new Map();
    this.key = undefined; // the folder the last listing was read for
    this.readAt = 0;
    this.busy = false;
    this.starting = null; // the card whose `task new` is running
    if (checking()) return;
    cx.timer.every(LOOK_MS, (cx) => this.look(cx));
    this.refresh(cx);
  }

  // Runs the entourage command. With `fallback`, a command that cannot run is
  // tried again as the copy this mod is linked from (Herdr may have been
  // started without the user's PATH). Only the listing asks for that: it
  // only reads, and it has answered before there is a card to start. A start
  // never does, because its failure may be a timeout with the first run still
  // opening the tab.
  async entourage(args, { fallback = false, timeout = TIMEOUT_MS } = {}) {
    try {
      return await exec(this.cmd, args, { timeout });
    } catch (e) {
      if (!fallback || this.cmd !== "entourage") throw e;
      const link = await exec("readlink", [`${appHome()}/mods/cards`]);
      const at = link.stdout.trim();
      if (link.code !== 0 || !at.endsWith(LINKED_AT)) throw e;
      this.cmd = `${at.slice(0, -LINKED_AT.length)}/cli/entourage`;
      return exec(this.cmd, args, { timeout });
    }
  }

  // Read again when another space is showing, or the cards on hand are a
  // minute old. Nothing is read while nobody can see the window.
  look(cx) {
    if (this.busy || window()?.visible === false) return;
    if (shownFolder() === this.key && Date.now() - this.readAt < REFRESH_MS) return;
    this.refresh(cx);
  }

  refresh(cx) {
    if (this.busy) return;
    this.busy = true;
    const folder = shownFolder();
    cx.spawn(async (cx) => {
      cx.notify(); // the refresh button turns while the cards are read
      const got = await this.read(folder);
      this.lists.set(folder, got);
      this.key = folder;
      this.readAt = Date.now();
      this.busy = false;
      cx.notify();
    });
  }

  // The project whose folder is `folder`, and its open cards.
  async read(folder) {
    if (folder === null) return { project: null };
    try {
      const r = await this.entourage(["project", "ls", "--json"], { fallback: true });
      const projects = r.code === 0 ? parse(r.stdout)?.projects : null;
      if (!Array.isArray(projects)) return { error: r.code === 0 ? OLD_CLI : failure(r, "entourage project ls") };
      const project = projects.find((p) => p.folder === folder);
      if (!project) return { project: null };
      const c = await this.entourage(["task", "ls", project.name, "--json"], { timeout: LIST_TIMEOUT_MS });
      const list = c.code === 0 ? parse(c.stdout) : null;
      if (Array.isArray(list?.statuses)) return { project: project.name, folder, statuses: list.statuses };
      return { project: project.name, error: c.code === 0 ? OLD_CLI : failure(c, "entourage task ls") };
    } catch (e) {
      return { error: `Could not run entourage: ${e?.message ?? e}` };
    }
  }

  // Runs `task new` for a card, one at a time.
  start(project, card, cx) {
    if (this.starting) return;
    this.starting = card.id;
    cx.notify();
    cx.spawn(async (cx) => {
      let failed = null;
      try {
        const r = await this.entourage(["task", "new", project, card.id], { timeout: START_TIMEOUT_MS });
        if (r.code !== 0) failed = said(r) || "entourage task new failed";
      } catch (e) {
        failed = `Could not run entourage: ${e?.message ?? e}`;
      }
      if (failed !== null) notify({ title: `Could not start ${card.id}`, body: failed, level: "error" });
      this.starting = null;
      cx.notify();
    });
  }

  // Shows the card's tab, in its space.
  show(open) {
    if (!open.space.active) run("space.select", { id: open.space.id });
    run("tab.select", { id: open.tab.id });
  }

  // What a click on a card does: show its tab, or start it.
  act(project, card, open, cx) {
    if (open) this.show(open);
    else this.start(project, card, cx);
  }

  toggle(key, cx) {
    if (this.closed.has(key)) this.closed.delete(key);
    else this.closed.add(key);
    localStorage.setItem("closed", JSON.stringify([...this.closed]));
    cx.notify();
  }

  // A status's header row: its name and how many cards it has.
  header(project, s, i, closed, t) {
    const n = (s.cards ?? []).length;
    return h_flex().id(`status-${i}`).h(26).flex_none().mt(i ? 4 : 0).px(8).gap(7).items_center().rounded(7)
      .text_size(11).text_color(t.dim).cursor_pointer().hover((el) => el.bg(t.hover))
      .on_click((_e, cx) => this.toggle(`${project}/${s.name}`, cx))
      .child(div().flex_1().min_w(0).truncate().child(s.name))
      .child(div().flex_none().child(String(n)))
      .child(svg(`${CHEVRON}-${closed ? "right" : "down"}.svg`).size(11).flex_none());
  }

  // A card: its ID, its title and its button. `open`: its tab, or null.
  // `starting`: the card being started, if any.
  row(project, card, open, starting, t) {
    const on = Boolean(open?.space.active && open.tab.active);
    const mine = starting === card.id;
    const waiting = Boolean(starting) && !mine && !open; // another card is starting
    const label = open ? "Open" : mine ? "Starting…" : "Start";
    const tip = open ? `Show the tab of ${card.id}` : `Start ${card.id}: open its tab with the agent running`;
    const button = h_flex().id(`card-go-${card.id}`).h(22).flex_none().px(8).gap(5).items_center().rounded(6)
      .border_1().border_color(t.input).bg(t.raised).text_size(11.5).text_color(t.foreground)
      .when(mine, (el) => el.text_color(t.muted)
        .child(svg(SPINNER).size(10).flex_none().text_color(t.working).spin(900)))
      .when(waiting, (el) => el.opacity(0.45))
      .when(!mine && !waiting, (el) => el.cursor_pointer().tooltip(tip).hover((s) => s.bg(t.hover))
        .on_click((_e, cx) => this.act(project, card, open, cx)))
      .child(label);
    return h_flex().id(`card-${card.id}`).h(ROW).flex_none().px(8).gap(8).items_center().rounded(8)
      .when(on, (el) => el.bg(t.selected))
      .when(!on, (el) => el.hover((s) => s.bg(t.hover)))
      .child(div().flex_none().text_size(11.5).text_color(t.dim).child(card.id))
      .child(div().id(`card-title-${card.id}`).flex_1().min_w(0).truncate().tooltip(card.title ?? "")
        .text_color(open ? t.foreground : t.muted).child(card.title ?? ""))
      .child(button);
  }

  // On the sidebar's rail: the card's number. A click does what its button
  // would.
  compact(project, card, open, starting, t) {
    const on = Boolean(open?.space.active && open.tab.active);
    const mine = starting === card.id;
    const tip = `${card.id}: ${card.title ?? ""}\n${open ? "Click to show its tab" : mine ? "Starting…" : "Click to start it"}`;
    return h_flex().flex_none().justify_center().child(
      h_flex().id(`card-${card.id}`).w(RAIL_CELL).h(26).rounded(6).items_center().justify_center()
        .text_size(11).tooltip(tip)
        .when(on, (el) => el.bg(t.selected))
        .when(!on, (el) => el.hover((s) => s.bg(t.hover)))
        .on_click((_e, cx) => this.act(project, card, open, cx))
        .child(mine
          ? svg(SPINNER).size(11).text_color(t.working).spin(900)
          : div().text_color(open ? t.foreground : t.dim).child(card.id.split("-").pop())));
  }

  render() {
    const t = theme();
    const collapsed = narrow();
    const sample = checking();
    const folder = sample ? "sample" : shownFolder();
    const got = sample ? SAMPLE : this.lists.get(folder) ?? null;
    const closed = sample ? SAMPLE_CLOSED : this.closed;
    const starting = sample ? SAMPLE_STARTING : this.starting;
    const tabs = sample ? SAMPLE_TABS : got?.statuses ? cardTabs(got.folder) : new Map();
    const note = (text, color) =>
      div().px(8).py(6).text_size(12).text_color(color).whitespace_normal().child(text);
    const items = [];
    if (!got) {
      if (!collapsed) items.push(note(folder === null ? NOT_A_PROJECT : "Loading…", t.dim));
    } else if (got.error) {
      // On the rail there is no room for the words: a mark, with them in its tooltip.
      items.push(collapsed
        ? h_flex().flex_none().justify_center().child(div().id("cards-error").w(RAIL_CELL).h(26)
          .flex().items_center().justify_center().text_color(t.blocked).tooltip(got.error).child("!"))
        : note(got.error, t.blocked));
    } else if (!got.project) {
      if (!collapsed) items.push(note(NOT_A_PROJECT, t.dim));
    } else {
      got.statuses.forEach((s, i) => {
        const shut = closed.has(`${got.project}/${s.name}`);
        if (!collapsed) items.push(this.header(got.project, s, i, shut, t));
        if (shut) return;
        for (const card of s.cards ?? []) {
          const open = tabs.get(card.id.toUpperCase()) ?? null;
          items.push(collapsed
            ? this.compact(got.project, card, open, starting, t)
            : this.row(got.project, card, open, starting, t));
        }
      });
    }
    const spin = !sample && this.busy;
    return v_flex().size_full().min_h(0).bg(t.chrome).text_size(13)
      .child(h_flex().h(31).flex_none().pl(16).pr(10).gap(6).items_center().justify_between()
        .text_size(11.5).text_color(t.dim)
        .when(collapsed, (el) => el.pl(0).pr(0).justify_center())
        .when(!collapsed, (el) => el.child(div().flex_none().child("Cards"))
          .child(div().flex_1().min_w(0).truncate().text_right().child(got?.project ?? "")))
        .child(div().id("cards-refresh").size(26).flex_none().flex().items_center().justify_center()
          .rounded(6).tooltip("Read the cards again")
          .hover((s) => s.bg(t.hover).text_color(t.foreground))
          .on_click((_e, cx) => this.refresh(cx))
          .child(spin
            ? svg("mods/cards/refresh.svg").size(13).spin(900)
            : svg("mods/cards/refresh.svg").size(13))))
      .child(v_flex().id("card-list").flex_1().min_h(0).px(collapsed ? 0 : 8).pb(14)
        .overflow_y_scrollbar().mode("always").children(items));
  }
}
