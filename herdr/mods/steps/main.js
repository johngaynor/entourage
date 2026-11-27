// The steps of the card whose tab is selected: what each step of its write-up
// did, how long it took, and how long it waited on the human. With no card's
// tab selected, the project's cards that have hand-offs, newest first, with
// where each stands. A click on a card shows its steps, even when its tab is
// closed.
//
// All of that is worked out by `entourage task log <project> [<card>] --json`.
// This mod draws the views that command returns and holds no rules about
// hand-offs: every label and every length of time arrives as text.
//
// A step is one line. A click on it opens what the step said.
import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { exec, spaces, theme, layout, window, checking, appHome } from "herdr";

const LOOK_MS = 2000; // how often to see whether another card is selected
const REREAD_MS = 6000; // how often to read what is shown again
const PROJECTS_MS = 60000; // projects change rarely
const TIMEOUT_MS = 10000;
// How this mod's own link into the repo that ships it ends.
const LINKED_AT = "/herdr/mods/steps";
// A tab is a card's when it is named as `entourage task new` names it.
const CARD = /^[A-Za-z][A-Za-z0-9]*-[0-9]+$/;

// `herdr-app check` draws the mod once, with no card selected, which would
// show one line of text and none of the rows. It is given these to draw, all
// of them open, so a mistake in a row fails the check: a list of cards and a
// card's steps, with the way back from one to the other.
const SAMPLE_CARDS = {
  project: "demo",
  cards: [
    { card: "ABC-3", state: "waiting on the human", waiting: "waiting on the human for 2m 05s", for: "2m 05s" },
    { card: "ABC-1", state: "plan done, then breakdown", waiting: null, for: "3d 04h" },
  ],
};
const SAMPLE = {
  run: 1,
  state: "waiting on the human",
  waiting: "waiting on the human for 2m 05s",
  steps: [
    { run: 1, at: "a", clock: "10:00", kind: "start", label: "started", took: "", short: "" },
    { run: 1, at: "b", clock: "10:00", kind: "step", label: "define done", took: "50s", short: "50s", summary: "A summary.", flags: "A flag." },
    { run: 1, at: "c", clock: "10:09", kind: "wait", label: "answered", took: "waited 7m 04s", short: "7m 04s", answer: "approve" },
    { run: 1, at: "d", clock: "10:17", kind: "step", label: "plan done", took: "7m 24s, includes waiting on the human", short: "7m 24s" },
    { run: 1, at: "e", clock: "10:17", kind: "step", label: "breakdown asked a question", took: "5s", short: "5s", question: "Approve?", waiting: "waiting on the human for 2m 05s" },
  ],
};

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

const OLD_CLI = "This entourage is too old for the Steps panel. Run: entourage update";
// An entourage from before --json answers with its usage line, not JSON, and
// one from before the list of cards asks which card.
const failure = (r, what) => {
  const text = said(r);
  return text.startsWith("usage:") || text.startsWith("which card?") ? OLD_CLI : text || `${what} failed`;
};

// What is selected on this computer: the shown space's folder, the card its
// shown tab is for, if it is a card's tab, and which tab that is.
function selected() {
  const space = spaces().find((s) => s.active && !s.machine) ?? null;
  const tab = space?.tabs.find((t) => t.active) ?? null;
  const card = tab && CARD.test(tab.name) ? tab.name.toUpperCase() : null;
  return { folder: space?.folder ?? null, card, tab: `${space?.id ?? ""}\n${tab?.id ?? ""}` };
}

export default class Steps extends View {
  init(_props, cx) {
    this.cmd = "entourage"; // the one on PATH, until that cannot start
    this.projects = null; // the last listing of projects
    this.projectsAt = 0;
    this.key = null; // what the view on hand was read for
    this.project = null; // the entourage project of the shown space, or null
    this.picked = null; // a card chosen from the list, and the tab it was chosen in
    this.view = null; // a card's steps, or the list of cards
    this.error = null;
    this.busy = false;
    this.readAt = 0;
    this.drawn = null; // what the last redraw showed, to redraw only on a change
    this.open = null; // the step whose lines are showing, by its time
    if (checking()) return;
    cx.timer.every(LOOK_MS, (cx) => this.look(cx));
    this.look(cx);
  }

  // Runs the entourage command. One that cannot run is tried again as the
  // copy this mod is linked from: Herdr may have been started without the
  // user's PATH. Everything this mod runs only reads, so twice is safe.
  async entourage(args) {
    try {
      return await exec(this.cmd, args, { timeout: TIMEOUT_MS });
    } catch (e) {
      if (this.cmd !== "entourage") throw e;
      const link = await exec("readlink", [`${appHome()}/mods/steps`]);
      const at = link.stdout.trim();
      if (link.code !== 0 || !at.endsWith(LINKED_AT)) throw e;
      this.cmd = `${at.slice(0, -LINKED_AT.length)}/cli/entourage`;
      return exec(this.cmd, args, { timeout: TIMEOUT_MS });
    }
  }

  // What the panel shows: the card of the selected tab; else the card chosen
  // from the list; else the list. A card chosen from the list is let go as
  // soon as another tab is seen selected, so coming back to that tab shows
  // the list. The panel is drawn again whenever a tab is selected.
  shown() {
    const now = selected();
    if (this.picked && (now.card || this.picked.tab !== now.tab)) this.picked = null;
    const card = now.card ?? this.picked?.card ?? null;
    return { folder: now.folder, card, picked: Boolean(this.picked), key: `${now.folder ?? ""}\n${card ?? ""}` };
  }

  // Show a card chosen from the list, or the list again with null.
  pick(card, cx) {
    this.picked = card ? { card, tab: selected().tab } : null;
    this.open = null;
    cx.notify();
    this.look(cx);
  }

  // Read again when something else is to be shown, or what is on hand is
  // stale. Nothing is read while nobody can see the panel, and a space that
  // is not an entourage project has nothing to read again.
  look(cx) {
    if (this.busy || window()?.visible === false || narrow()) return;
    const now = this.shown();
    const stale = Boolean(this.project) && Date.now() - this.readAt >= REREAD_MS;
    if (now.key === this.key && !stale) return;
    this.busy = true;
    cx.spawn(async (cx) => {
      let project = null;
      let view = null;
      let error = null;
      try {
        if (!this.projects || Date.now() - this.projectsAt > PROJECTS_MS) {
          const r = await this.entourage(["project", "ls", "--json"]);
          const list = r.code === 0 ? parse(r.stdout)?.projects : null;
          if (Array.isArray(list)) {
            this.projects = list;
            this.projectsAt = Date.now();
          } else {
            error = r.code === 0 ? OLD_CLI : failure(r, "entourage project ls");
          }
        }
        project = (this.projects ?? []).find((p) => p.folder === now.folder)?.name ?? null;
        if (!error && project) {
          const card = now.card ? [now.card] : [];
          const r = await this.entourage(["task", "log", project, ...card, "--json"]);
          const got = r.code === 0 ? parse(r.stdout) : null;
          if (got && Array.isArray(now.card ? got.steps : got.cards)) view = got;
          else error = r.code === 0 ? OLD_CLI : failure(r, "entourage task log");
        }
      } catch (e) {
        error = `Could not run entourage: ${e?.message ?? e}`;
      }
      this.key = now.key;
      this.project = project;
      this.view = view;
      this.error = error;
      this.readAt = Date.now();
      this.busy = false;
      // A redraw of a mod redraws the whole window, so only when what it
      // shows has changed. A card's seconds change at every read, and only
      // the time drawn from them counts.
      const cards = view?.cards?.map(({ seconds, ...c }) => c);
      const drawn = JSON.stringify([now.key, project, cards ? { ...view, cards } : view, error]);
      if (drawn !== this.drawn) {
        this.drawn = drawn;
        cx.notify();
      }
      // A card chosen while this was being read is read now, not at the
      // next look.
      if (this.shown().key !== now.key) this.look(cx);
    });
  }

  // One card of the list: its ID and how long it has stood where it is,
  // then where that is. A card waiting on the human stands out. A click shows
  // its steps.
  card(c, i, t) {
    const color = c.waiting ? t.blocked : t.dim;
    return v_flex().id(`card-${i}`).flex_none().px(8).py(4).gap(1).rounded(8)
      .hover((el) => el.bg(t.hover))
      .on_click((_e, cx) => this.pick(c.card, cx))
      .child(h_flex().gap(8).items_center()
        .child(div().flex_1().min_w(0).truncate().text_color(t.foreground).child(c.card ?? ""))
        .child(div().flex_none().text_size(11.5).text_color(color).child(c.for ?? "")))
      .child(div().text_size(11.5).text_color(c.waiting ? t.blocked : t.muted).whitespace_normal()
        .child(c.state ?? ""));
  }

  // The way from a card chosen from the list back to the list.
  back(t) {
    return div().id("back").flex_none().px(8).py(4).rounded(8).text_size(11.5).text_color(t.dim)
      .hover((el) => el.bg(t.hover))
      .on_click((_e, cx) => this.pick(null, cx))
      .child("‹ All cards");
  }

  // One hand-off, on one line: its clock, its label and the time alone. A
  // click opens the rest of what the view says about it. `s` is a step of the
  // view, and its kind says whether it is a wait.
  row(s, i, t, open) {
    const wait = s.kind === "wait";
    const start = s.kind === "start";
    // An entourage from before `short` gives the whole of `took` here.
    const short = s.short ?? s.took ?? "";
    const full = s.took && s.took !== short ? s.took : null;
    const lines = [full, s.question, s.answer, s.reason, s.summary, s.flags ? `Flags: ${s.flags}` : null]
      .filter(Boolean);
    const small = (text, color) =>
      div().pl(46).pr(4).text_size(11.5).text_color(color).whitespace_normal().child(text);
    return v_flex().id(`step-${i}`).flex_none().px(8).py(4).gap(2).rounded(8)
      .hover((el) => el.bg(t.hover))
      .on_click((_e, cx) => {
        this.open = this.open === s.at ? null : s.at;
        cx.notify();
      })
      .child(h_flex().gap(8).items_center()
        .child(div().w(38).flex_none().text_size(11.5).text_color(t.dim).child(s.clock ?? ""))
        .child(div().flex_1().min_w(0).truncate()
          .text_color(wait ? t.blocked : start ? t.muted : t.foreground).child(s.label ?? ""))
        .child(div().flex_none().text_size(11.5).text_color(wait ? t.blocked : t.dim).child(short)))
      // A question still waiting shows whether or not the step is open.
      .when(Boolean(s.waiting), (el) => el.child(small(s.waiting, t.blocked)))
      .when(open, (el) => el.children(lines.map((text) => small(text, t.muted))));
  }

  render() {
    const t = theme();
    const now = this.shown();
    if (narrow()) return v_flex().size_full().bg(t.chrome);
    const sample = checking();
    const read = now.key === this.key;
    const view = sample ? SAMPLE : this.view;
    const list = sample ? SAMPLE_CARDS : this.view;
    const note = (text, color) =>
      div().px(8).py(6).text_size(12).text_color(color).whitespace_normal().child(text);
    const items = [];
    // The latest run only: a card written up twice keeps both in its log.
    const steps = (view?.steps ?? []).filter((s) => s.run === view.run);
    const cards = list?.cards ?? [];
    const rows = () => {
      // Where the card stands, as the view words it.
      if (view.state) items.push(note(view.state, view.waiting ? t.blocked : t.dim));
      steps.forEach((s, i) => items.push(this.row(s, i, t, sample || this.open === s.at)));
    };
    // A card chosen from the list always has the way back, even while it
    // loads or when it could not be read.
    if (sample || now.picked) items.push(this.back(t));
    if (sample) {
      cards.forEach((c, i) => items.push(this.card(c, i, t)));
      rows();
    } else if (!read) items.push(note("Loading…", t.dim));
    else if (this.error) items.push(note(this.error, t.blocked));
    else if (!this.project) items.push(note("This space is not an entourage project.", t.dim));
    else if (now.card) {
      if (steps.length === 0) items.push(note(`No hand-offs recorded for ${now.card} yet.`, t.dim));
      else rows();
    } else if (cards.length === 0) items.push(note("No hand-offs recorded in this project yet.", t.dim));
    else cards.forEach((c, i) => items.push(this.card(c, i, t)));
    return v_flex().size_full().min_h(0).bg(t.chrome).text_size(13)
      .child(h_flex().h(31).flex_none().pl(16).pr(14).items_center().justify_between()
        .text_size(11.5).text_color(t.dim)
        .child("Steps")
        .child(div().child(now.card ?? (read ? this.project : null) ?? "")))
      .child(v_flex().id("step-list").flex_1().min_h(0).px(8).pb(14)
        .overflow_y_scrollbar().mode("always").children(items));
  }
}
