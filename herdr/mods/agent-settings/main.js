// The model and effort each of entourage's agent profiles runs on: a button
// at the right end of the tab bar, and the popup it opens, which shows them
// and changes them. One mod, two faces: the popup is the same mod again, with
// props { menu: true }.
//
// What the profiles are, what each is set to, and which models and efforts
// there are to choose from, are the entourage command's to say:
// `entourage profile ls --json`. A change is made with
// `entourage profile set <profile> <model|effort> <value>`, which refuses a
// value it does not take. This mod draws what entourage answers and holds no
// rules of its own.
import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { exec, theme, props, openOverlay, closeOverlay, checking, appHome } from "herdr";

const TIMEOUT_MS = 10000;
const ROW = 28;
const WIDTH = 330;
const HEIGHT = 262;
// How this mod's own link into the repo that ships it ends.
const LINKED_AT = "/herdr/mods/agent-settings";
const OLD_CLI = "This entourage cannot list the agent profiles. Run: entourage update";

// `herdr-app check` draws the mod once, with no entourage to ask. It draws
// the button, the popup's list and its choices from these instead.
const SAMPLE = {
  profiles: [
    { name: "write-up", model: "opus", effort: "xhigh", for: "task new" },
    { name: "build", model: "sonnet", effort: "high", for: "task build" },
    { name: "reviewer", model: "claude-opus-5-5", effort: "xhigh", for: "the entourage-reviewer subagent" },
    { name: "verifier", model: "opus", effort: "max", for: "the entourage-verifier subagent" },
  ],
  models: ["fable", "opus", "sonnet", "haiku"],
  efforts: ["low", "medium", "high", "xhigh", "max"],
};

function parse(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

// What a failed command said, without the name it starts its errors with.
const said = (r) => (r.stderr || r.stdout).trim().replace(/^entourage: /, "");
// An entourage from before `profile` answers with its help text, not JSON.
const failure = (r, what) => {
  const text = said(r);
  return text.startsWith("usage:") || text.startsWith("set up and maintain") ? OLD_CLI : text || `${what} failed`;
};

// The choices for a profile's model or effort: entourage's list, and for a
// model the profile's own when it is a full name the list does not have.
function choices(list, profile, field) {
  if (field === "effort") return list.efforts ?? [];
  const models = [...(list.models ?? [])];
  if (profile.model && !models.includes(profile.model)) models.push(profile.model);
  return models;
}

export default class AgentSettings extends View {
  init(_props, cx) {
    this.cmd = "entourage"; // the one on PATH, until that cannot start
    this.list = null; // what `profile ls --json` answered
    this.error = null; // what went wrong last, in entourage's words
    this.picking = null; // { profile, field } whose choices are shown
    this.busy = false; // a read or a change is running
    if (checking() || !props()?.menu) return;
    this.refresh(cx);
  }

  // Runs the entourage command. One that cannot start is tried again as the
  // copy this mod is linked from: Herdr may have been started without the
  // user's PATH, so the first run never happened.
  async entourage(args) {
    try {
      return await exec(this.cmd, args, { timeout: TIMEOUT_MS });
    } catch (e) {
      if (this.cmd !== "entourage") throw e;
      const link = await exec("readlink", [`${appHome()}/mods/agent-settings`]);
      const at = link.stdout.trim();
      if (link.code !== 0 || !at.endsWith(LINKED_AT)) throw e;
      this.cmd = `${at.slice(0, -LINKED_AT.length)}/cli/entourage`;
      return exec(this.cmd, args, { timeout: TIMEOUT_MS });
    }
  }

  // Reads the profiles. Returns what went wrong, or null.
  async read() {
    try {
      const r = await this.entourage(["profile", "ls", "--json"]);
      const list = r.code === 0 ? parse(r.stdout) : null;
      if (Array.isArray(list?.profiles)) {
        this.list = list;
        return null;
      }
      return r.code === 0 ? OLD_CLI : failure(r, "entourage profile ls");
    } catch (e) {
      return `Could not run entourage: ${e?.message ?? e}`;
    }
  }

  refresh(cx) {
    if (this.busy) return;
    this.busy = true;
    cx.spawn(async (cx) => {
      this.error = await this.read();
      this.busy = false;
      cx.notify();
    });
  }

  // Sets one value with entourage, then reads the profiles again, so what is
  // shown is what the file now holds.
  set(profile, field, value, cx) {
    this.picking = null;
    if (this.busy || profile[field] === value) {
      cx.notify();
      return;
    }
    this.busy = true;
    cx.notify();
    cx.spawn(async (cx) => {
      let failed = null;
      try {
        const r = await this.entourage(["profile", "set", profile.name, field, value]);
        if (r.code !== 0) failed = failure(r, "entourage profile set");
      } catch (e) {
        failed = `Could not run entourage: ${e?.message ?? e}`;
      }
      const unread = await this.read();
      this.error = failed ?? unread;
      this.busy = false;
      cx.notify();
    });
  }

  render() {
    if (checking()) {
      // Every face, so that a check draws each of them once.
      return v_flex().size_full().child(div().h(42).child(this.button()))
        .child(this.menu({ list: SAMPLE, error: "A sample of what entourage says when it refuses.", picking: null, busy: false }, "rows"))
        .child(this.menu({ list: SAMPLE, error: null, picking: { profile: "reviewer", field: "model" }, busy: true }, "pick"));
    }
    if (!props()?.menu) return this.button();
    return this.menu(this, "menu");
  }

  // The button, at the right end of the tab bar, drawn as the tab bar is.
  button() {
    const t = theme();
    return h_flex().size_full().px(10).items_center().justify_end().bg(t.chrome).border_b(1).border_color(t.border)
      .child(h_flex().id("agent-settings").h(26).px(8).gap(6).flex_none().items_center().rounded(6)
        .text_size(12).text_color(t.muted).tooltip("The model and effort each agent runs on")
        .hover((s) => s.bg(t.hover).text_color(t.foreground))
        .on_click(() => openOverlay({
          mod: "agent-settings", kind: "popup", width: WIDTH, height: HEIGHT, props: { menu: true },
        }))
        .child("Agents")
        .child(div().text_color(t.dim).child("▾")));
  }

  // The popup: a row for each profile, or the choices for one of its values.
  //   s     what to draw: { list, error, picking, busy }
  //   key   what the ids in it start with
  menu(s, key) {
    const t = theme();
    const profiles = s.list?.profiles ?? [];
    const picked = s.picking && profiles.find((p) => p.name === s.picking.profile);
    const title = picked ? `${picked.name}: ${s.picking.field}` : "Agent settings";
    const header = h_flex().h(ROW).flex_none().px(8).gap(8).items_center()
      .when(Boolean(picked), (el) => el.child(div().id(`${key}-back`).flex_none().px(4).rounded(4)
        .text_color(t.muted).cursor_pointer().hover((h) => h.bg(t.hover).text_color(t.foreground))
        .on_click((_e, cx) => { this.picking = null; cx.notify(); })
        .child("‹")))
      .child(div().flex_1().min_w(0).truncate().text_color(t.foreground).font_medium().child(title))
      .child(div().flex_none().text_size(11).text_color(t.dim)
        .child(s.busy ? "Saving…" : picked ? "" : "model · effort"));
    const items = [];
    if (picked) {
      const current = picked[s.picking.field];
      for (const value of choices(s.list, picked, s.picking.field)) {
        const on = value === current;
        items.push(h_flex().id(`${key}-choice-${value}`).h(ROW).flex_none().px(8).gap(8).items_center().rounded(4)
          .cursor_pointer().hover((h) => h.bg(t.hover))
          .on_click((_e, cx) => this.set(picked, s.picking.field, value, cx))
          .child(div().w(12).flex_none().text_color(t.accent).child(on ? "✓" : ""))
          .child(div().flex_1().min_w(0).truncate().text_color(on ? t.foreground : t.muted).child(value)));
      }
    } else if (!s.list && !s.error) {
      items.push(div().px(8).py(6).text_color(t.dim).child("Loading…"));
    } else {
      for (const p of profiles) items.push(this.row(p, s.busy, key, t));
    }
    if (s.error) {
      items.push(div().id(`${key}-error`).mt(6).px(8).py(4).text_size(11.5).text_color(t.blocked)
        .whitespace_normal().child(s.error));
    }
    return v_flex().size_full().min_h(0).p(4).bg(t.popover).text_size(12)
      .child(header)
      .child(v_flex().id(`${key}-body`).flex_1().min_h(0).gap(1).overflow_y_scrollbar().children(items));
  }

  // A profile's row: its name, and its model and effort, each a button that
  // shows the choices for it.
  row(p, busy, key, t) {
    const value = (field, width) => h_flex().id(`${key}-${p.name}-${field}`).w(width).h(22).flex_none().px(7)
      .items_center().rounded(5).border_1().border_color(t.input).bg(t.raised).text_color(t.foreground)
      .when(busy, (el) => el.opacity(0.5))
      .when(!busy, (el) => el.cursor_pointer().hover((h) => h.bg(t.hover))
        .on_click((_e, cx) => { this.picking = { profile: p.name, field }; cx.notify(); }))
      .child(div().flex_1().min_w(0).truncate().child(p[field]))
      .child(div().flex_none().text_color(t.dim).child("▾"));
    return h_flex().id(`${key}-${p.name}`).h(ROW).flex_none().px(8).gap(6).items_center()
      .child(div().id(`${key}-${p.name}-name`).flex_1().min_w(0).truncate().text_color(t.foreground)
        .tooltip(p.for ? `Runs ${p.for}` : p.name).child(p.name))
      .child(value("model", 128))
      .child(value("effort", 74));
  }
}
