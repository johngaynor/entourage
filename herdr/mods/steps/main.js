// The steps of the card whose tab is selected: what each step of its write-up
// did, how long it took, and how long it waited on the human.
//
// All of that is worked out by `entourage task log <project> <card> --json`.
// This mod draws the view that command returns and holds no rules about
// hand-offs: every label and every length of time arrives as text.
import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { exec, spaces, theme, layout, window, checking, appHome } from "herdr";

const LOOK_MS = 2000; // how often to see whether another card is selected
const REREAD_MS = 6000; // how often to read the selected card's steps again
const PROJECTS_MS = 60000; // projects change rarely
const TIMEOUT_MS = 10000;
// How this mod's own link into the repo that ships it ends.
const LINKED_AT = "/herdr/mods/steps";
// A tab is a card's when it is named as `entourage task new` names it.
const CARD = /^[A-Za-z][A-Za-z0-9]*-[0-9]+$/;
// A time longer than this goes on a line of its own.
const SHORT = 14;

// `herdr-app check` draws the mod once, with no card selected, which would
// show one line of text and none of the rows. It is given these to draw, so a
// mistake in a row fails the check.
const SAMPLE = {
  run: 1,
  steps: [
    { run: 1, clock: "10:00", kind: "start", label: "started", took: "" },
    { run: 1, clock: "10:00", kind: "step", label: "define done", took: "50s", summary: "A summary.", flags: "A flag." },
    { run: 1, clock: "10:09", kind: "wait", label: "answered", took: "waited 7m 04s", answer: "approve" },
    { run: 1, clock: "10:17", kind: "step", label: "plan done", took: "7m 24s, includes waiting on the human" },
    { run: 1, clock: "10:17", kind: "step", label: "breakdown asked a question", took: "5s", question: "Approve?", waiting: "waiting on the human for 2m 05s" },
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

const OLD_CLI = "This entourage cannot give a card's steps as JSON. Run: entourage update";
// An entourage from before --json answers with its usage line, not JSON.
const failure = (r, what) => {
  const text = said(r);
  return text.startsWith("usage:") ? OLD_CLI : text || `${what} failed`;
};

// What is selected on this computer: the shown space's folder, and the card
// its shown tab is for, if it is a card's tab.
function selected() {
  const space = spaces().find((s) => s.active && !s.machine) ?? null;
  const tab = space?.tabs.find((t) => t.active) ?? null;
  const card = tab && CARD.test(tab.name) ? tab.name.toUpperCase() : null;
  return { folder: space?.folder ?? null, card, key: `${space?.folder ?? ""}\n${card ?? ""}` };
}

export default class Steps extends View {
  init(_props, cx) {
    this.cmd = "entourage"; // the one on PATH, until that cannot start
    this.projects = null; // the last listing of projects
    this.projectsAt = 0;
    this.key = null; // what the view on hand was read for
    this.project = null; // the entourage project of the shown space, or null
    this.view = null;
    this.error = null;
    this.busy = false;
    this.readAt = 0;
    this.drawn = null; // what the last redraw showed, to redraw only on a change
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

  // Read again when another card is selected, or the one on hand is stale.
  // Nothing is read while nobody can see the panel, and a tab that is not a
  // card's has nothing to read again.
  look(cx) {
    if (this.busy || window()?.visible === false || narrow()) return;
    const now = selected();
    const stale = Boolean(now.card) && Date.now() - this.readAt >= REREAD_MS;
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
        if (!error && project && now.card) {
          const r = await this.entourage(["task", "log", project, now.card, "--json"]);
          const got = r.code === 0 ? parse(r.stdout) : null;
          if (got && Array.isArray(got.steps)) view = got;
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
      // shows has changed.
      const drawn = JSON.stringify([now.key, project, view, error]);
      if (drawn !== this.drawn) {
        this.drawn = drawn;
        cx.notify();
      }
    });
  }

  // One hand-off. `s` is a step of the view: its clock, label and took are
  // text to show as they are, and its kind says whether it is a wait.
  row(s, i, t) {
    const wait = s.kind === "wait";
    const start = s.kind === "start";
    const took = s.took ?? "";
    const beside = took.length <= SHORT;
    const detail = s.question ?? s.answer ?? s.reason ?? s.summary ?? null;
    const small = (text, color) =>
      div().pl(46).pr(4).text_size(11.5).text_color(color).whitespace_normal().child(text);
    return v_flex().id(`step-${i}`).flex_none().px(8).py(5).gap(2).rounded(8)
      .child(h_flex().gap(8).items_center()
        .child(div().w(38).flex_none().text_size(11.5).text_color(t.dim).child(s.clock ?? ""))
        .child(div().flex_1().min_w(0).truncate()
          .text_color(wait ? t.blocked : start ? t.muted : t.foreground).child(s.label ?? ""))
        .when(beside && took !== "", (el) =>
          el.child(div().flex_none().text_size(11.5).text_color(wait ? t.blocked : t.dim).child(took))))
      .when(!beside, (el) => el.child(small(took, t.dim)))
      .when(Boolean(detail), (el) => el.child(small(detail, t.muted)))
      .when(Boolean(s.flags), (el) => el.child(small(`Flags: ${s.flags}`, t.dim)))
      .when(Boolean(s.waiting), (el) => el.child(small(s.waiting, t.blocked)));
  }

  render() {
    const t = theme();
    if (narrow()) return v_flex().size_full().bg(t.chrome);
    const sample = checking();
    const now = selected();
    const view = sample ? SAMPLE : this.view;
    const note = (text, color) =>
      div().px(8).py(6).text_size(12).text_color(color).whitespace_normal().child(text);
    const items = [];
    // The latest run only: a card written up twice keeps both in its log.
    const steps = (view?.steps ?? []).filter((s) => s.run === view.run);
    if (sample) steps.forEach((s, i) => items.push(this.row(s, i, t)));
    else if (!now.card) items.push(note("Select a card's tab to see its steps.", t.dim));
    else if (now.key !== this.key) items.push(note("Loading…", t.dim));
    else if (this.error) items.push(note(this.error, t.blocked));
    else if (!this.project) items.push(note("This space is not an entourage project.", t.dim));
    else if (steps.length === 0) items.push(note(`No hand-offs recorded for ${now.card} yet.`, t.dim));
    else steps.forEach((s, i) => items.push(this.row(s, i, t)));
    return v_flex().size_full().min_h(0).bg(t.chrome).text_size(13)
      .child(h_flex().h(31).flex_none().pl(16).pr(14).items_center().justify_between()
        .text_size(11.5).text_color(t.dim)
        .child("Steps")
        .child(div().child(now.card ?? "")))
      .child(v_flex().id("step-list").flex_1().min_h(0).px(8).pb(14)
        .overflow_y_scrollbar().mode("always").children(items));
  }
}
