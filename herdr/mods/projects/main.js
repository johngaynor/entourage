// Every project in the entourage config, open or not. Herdr only knows a
// project while its space has a tab, so the list comes from the entourage
// command, which owns where projects live and what counts as one. Click a
// project to show its space; one with no space is opened by the command.
import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { exec, spaces, run, notify, theme, layout, window, checking, appHome } from "herdr";

const REFRESH_MS = 15000; // projects change rarely; the open marks are live anyway
const TIMEOUT_MS = 10000;
const ROW = 30;
const RAIL_CELL = 32;
// How this mod's own link into the repo that ships it ends.
const LINKED_AT = "/herdr/mods/projects";
const EMPTY = "No projects yet. Make one with: entourage project new <name>";
const OLD_CLI = "This entourage cannot list projects as JSON. Run: entourage update";

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

// The listing, or null when the output is not the JSON this mod reads (an
// older entourage prints the plain list whatever the option).
function parse(text) {
  try {
    const list = JSON.parse(text).projects;
    return Array.isArray(list) ? list : null;
  } catch {
    return null;
  }
}

// What a failed command said, without the name it starts its errors with.
const said = (r) => (r.stderr || r.stdout).trim().replace(/^entourage: /, "");

export default class Projects extends View {
  init(_props, cx) {
    this.projects = null; // null until the first listing answers
    this.error = null;
    this.busy = false;
    this.opening = null; // the project a click is making a space for
    this.cmd = "entourage"; // the one on PATH, until that cannot start
    if (checking()) return;
    cx.timer.every(REFRESH_MS, (cx) => this.refresh(cx));
    this.refresh(cx);
  }

  // Runs the entourage command. With `fallback`, a command that cannot run is
  // tried again as the copy this mod is linked from (Herdr may have been
  // started without the user's PATH). Only the listing asks for that: it is
  // safe to run twice, and it has answered before there is a row to click. An
  // open never does, because its failure may be a timeout with the first run
  // still making the space.
  async entourage(args, { fallback = false } = {}) {
    try {
      return await exec(this.cmd, args, { timeout: TIMEOUT_MS });
    } catch (e) {
      if (!fallback || this.cmd !== "entourage") throw e;
      const link = await exec("readlink", [`${appHome()}/mods/projects`]);
      const at = link.stdout.trim();
      if (link.code !== 0 || !at.endsWith(LINKED_AT)) throw e;
      this.cmd = `${at.slice(0, -LINKED_AT.length)}/cli/entourage`;
      return exec(this.cmd, args, { timeout: TIMEOUT_MS });
    }
  }

  refresh(cx) {
    // Skip while a listing is in flight or nobody can see the window.
    if (this.busy || window()?.visible === false) return;
    this.busy = true;
    cx.spawn(async (cx) => {
      try {
        const r = await this.entourage(["project", "ls", "--json"], { fallback: true });
        const list = r.code === 0 ? parse(r.stdout) : null;
        if (list) this.projects = list;
        this.error = list ? null : r.code === 0 ? OLD_CLI : said(r) || "entourage project ls failed";
      } catch (e) {
        this.error = `Could not run entourage: ${e?.message ?? e}`;
      }
      this.busy = false;
      cx.notify();
    });
  }

  // `space`: the project's open space, or null.
  pick(p, space, cx) {
    if (space) {
      run("space.select", { id: space.id });
      return;
    }
    // One at a time: a second open would not see the first one's space yet.
    if (this.opening) return;
    this.opening = p.name;
    cx.notify();
    cx.spawn(async (cx) => {
      let failed = null;
      try {
        const r = await this.entourage(["project", "open", p.name]);
        if (r.code !== 0) failed = said(r);
      } catch (e) {
        failed = String(e?.message ?? e);
      }
      if (failed !== null) notify({ title: `Could not open ${p.name}`, body: failed, level: "error" });
      this.opening = null;
      this.refresh(cx);
      cx.notify();
    });
  }

  row(p, space, t) {
    const on = Boolean(space?.active);
    const n = (p.repos ?? []).length;
    const tail = this.opening === p.name ? "Opening…" : `${n} repo${n === 1 ? "" : "s"}`;
    const dot = div().size(7).rounded(4).flex_none();
    return h_flex().id(`project-${p.name}`).h(ROW).flex_none().px(8).gap(9).items_center().rounded(8)
      .when(on, (el) => el.bg(t.selected))
      .when(!on, (el) => el.hover((s) => s.bg(t.hover)))
      .on_click((_e, cx) => this.pick(p, space, cx))
      .child(h_flex().size(18).flex_none().items_center().justify_center()
        .child(space ? dot.bg(t.ansi2) : dot.border_1().border_color(t.dim)))
      .child(div().flex_1().min_w(0).truncate().text_color(space ? t.foreground : t.muted).child(p.name))
      .child(div().flex_none().text_size(11.5).text_color(t.dim).child(tail));
  }

  // On the sidebar's rail: the project's first letter.
  compact(p, space, t) {
    const on = Boolean(space?.active);
    return h_flex().flex_none().justify_center().child(
      h_flex().id(`project-${p.name}`).w(RAIL_CELL).h(26).rounded(6).items_center().justify_center()
        .tooltip(p.name)
        .when(on, (el) => el.bg(t.selected))
        .when(!on, (el) => el.hover((s) => s.bg(t.hover)))
        .on_click((_e, cx) => this.pick(p, space, cx))
        .child(div().text_color(space ? t.foreground : t.dim).child((p.name[0] ?? "?").toUpperCase())));
  }

  render() {
    const t = theme();
    const collapsed = narrow();
    // A project is open when a space on this computer has its folder.
    const local = spaces().filter((s) => !s.machine);
    const note = (text, color) => div().px(8).py(6).text_size(12).text_color(color).child(text);
    const items = [];
    if (!collapsed) {
      if (this.error) items.push(note(this.error, t.blocked));
      else if (this.projects === null) items.push(note("Loading…", t.dim));
      else if (this.projects.length === 0) items.push(note(EMPTY, t.dim));
    }
    for (const p of this.projects ?? []) {
      const space = local.find((s) => s.folder === p.folder) ?? null;
      items.push(collapsed ? this.compact(p, space, t) : this.row(p, space, t));
    }
    return v_flex().size_full().min_h(0).bg(t.chrome).text_size(13)
      .child(h_flex().h(31).flex_none().pl(16).pr(10).items_center().text_size(11.5).text_color(t.dim)
        .when(!collapsed, (el) => el.child("Projects")))
      .child(v_flex().id("project-list").flex_1().min_h(0).px(collapsed ? 0 : 8).pb(14)
        .overflow_y_scrollbar().mode("always").children(items));
  }
}
