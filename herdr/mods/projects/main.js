// Every project in the entourage config, open or not. Herdr only knows a
// project while its space has a tab, so the list comes from the entourage
// command, which owns where projects live and what counts as one. Click a
// project to show its space; one with no space is opened by the command.
//
// One mod, two faces: the list a layout places, and the New project dialog
// (the same mod again, with props { create: true }). The + above the list
// asks for a repo's folder with the system's picker, then opens the dialog on
// it. The dialog makes the project with the command too.
import { View, div } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import {
  exec, spaces, run, notify, theme, layout, window, checking, appHome, home, props,
  pickFolder, openOverlay, closeOverlay, nextCommand,
} from "herdr";

const REFRESH_MS = 15000; // projects change rarely; the open marks are live anyway
const TIMEOUT_MS = 10000;
const ROW = 30;
const RAIL_CELL = 32;
// How this mod's own link into the repo that ships it ends.
const LINKED_AT = "/herdr/mods/projects";
const EMPTY = "No projects yet. Make one with the + above.";
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

// A picked folder without the slash a picker may end it with.
const tidy = (path) => (path.length > 1 ? path.replace(/\/+$/, "") : path);
const base = (path) => path.split("/").pop();
const tilde = (path) => (path.startsWith(`${home()}/`) ? `~${path.slice(home().length)}` : path);
// A name to start the dialog with, from the first repo's folder. Only a
// suggestion: the command decides what a project may be called.
const suggest = (text) => text.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");

export default class Projects extends View {
  init(_props, cx) {
    this.projects = null; // null until the first listing answers
    this.error = null;
    this.busy = false;
    this.opening = null; // the project a click is making a space for
    this.cmd = "entourage"; // the one on PATH, until that cannot start
    this.picking = false; // the system's folder picker is up
    if (props()?.create) return this.initForm(cx);
    if (checking()) return;
    cx.timer.every(REFRESH_MS, (cx) => this.refresh(cx));
    // The dialog says when it has made a project, so its row need not wait
    // for the timer.
    cx.spawn(async (cx) => {
      for (;;) {
        if ((await nextCommand()) === "refresh") this.refresh(cx);
        cx.notify();
      }
    });
    this.refresh(cx);
  }

  // The dialog. props: { create: true, folder: the first repo, cmd: the
  // entourage command the list found, overlay }.
  initForm(cx) {
    const p = props() ?? {};
    if (p.cmd) this.cmd = p.cmd;
    this.repos = p.folder ? [tidy(p.folder)] : [];
    this.name = suggest(base(this.repos[0] ?? ""));
    this.error = "";
    this.working = false;
    this.input = InputState.new({ value: this.name, placeholder: "my-project" });
    if (this.name) this.input.set_selected_range({ start: 0, end: this.name.length });
    this.input.on("change", (_e, cx) => { this.name = this.input.value(); this.error = ""; cx.notify(); });
    this.input.on("submit", (_e, cx) => this.submit(cx));
    this.inputFocused = true;
    this.input.on("focus", (_e, cx) => { this.inputFocused = true; cx.notify(); });
    this.input.on("blur", (_e, cx) => { this.inputFocused = false; cx.notify(); });
    this.handle = cx.focus_handle();
    // Twice, as Herdr's own prompt does: the first lands before the dialog shows.
    this.input.focus();
    cx.timer.after(600, () => this.input.focus());
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

  // The + above the list: choose the first repo, then name the project.
  create(cx) {
    if (this.picking) return;
    this.picking = true;
    cx.spawn(async (cx) => {
      let folder = null;
      try {
        folder = await pickFolder({ prompt: "Choose" });
      } catch (e) {
        notify({ title: "Could not open the folder picker", body: String(e?.message ?? e), level: "error" });
      }
      this.picking = false;
      if (folder) {
        openOverlay({
          mod: "projects", kind: "dialog", modal: true, width: 480,
          props: { create: true, folder, cmd: this.cmd },
        });
      }
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
    return props()?.create ? this.form() : this.list();
  }

  list() {
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
      .child(h_flex().h(31).flex_none().pl(16).pr(10).items_center().justify_between()
        .text_size(11.5).text_color(t.dim)
        .when(collapsed, (el) => el.pl(0).pr(0).justify_center())
        .when(!collapsed, (el) => el.child("Projects"))
        .child(div().id("project-new").size(26).flex_none().flex().items_center().justify_center()
          .rounded(6).text_size(15).tooltip("New project")
          .hover((s) => s.bg(t.hover).text_color(t.foreground))
          .on_click((_e, cx) => this.create(cx))
          .child("+")))
      .child(v_flex().id("project-list").flex_1().min_h(0).px(collapsed ? 0 : 8).pb(14)
        .overflow_y_scrollbar().mode("always").children(items));
  }

  // --- the New project dialog ----------------------------------------------

  close() {
    closeOverlay(props().overlay);
  }

  // Another repo for the project, from the system's picker.
  addRepo(cx) {
    if (this.picking || this.working) return;
    this.picking = true;
    cx.spawn(async (cx) => {
      try {
        const folder = await pickFolder({ prompt: "Add" });
        if (folder && !this.repos.includes(tidy(folder))) this.repos.push(tidy(folder));
        this.error = "";
      } catch (e) {
        this.error = `Could not open the folder picker: ${e?.message ?? e}`;
      }
      this.picking = false;
      this.input.focus();
      cx.notify();
    });
  }

  // Makes the project and shows its space. The command checks the name and
  // every repo before it makes anything, so what it refuses is shown here and
  // the dialog stays open to be put right.
  submit(cx) {
    if (this.working) return;
    const name = this.name.trim();
    this.working = true;
    this.error = "";
    cx.notify();
    cx.spawn(async (cx) => {
      let failed = null;
      try {
        const r = await this.entourage(["project", "new", name, ...this.repos]);
        if (r.code !== 0) failed = said(r) || "entourage project new failed";
      } catch (e) {
        failed = `Could not run entourage: ${e?.message ?? e}`;
      }
      if (failed !== null) {
        this.working = false;
        this.error = failed;
        cx.notify();
        return;
      }
      // Tell the list. With no list showing there is nobody to tell, and that
      // must not stop the space from opening.
      try { run("projects.refresh"); } catch {}
      // The project is made, so a space that will not open is not this
      // dialog's to keep asking about: say so and leave it in the list.
      let unopened = null;
      try {
        const r = await this.entourage(["project", "open", name]);
        if (r.code !== 0) unopened = said(r);
      } catch (e) {
        unopened = String(e?.message ?? e);
      }
      if (unopened !== null) notify({ title: `Made ${name}, but could not open it`, body: unopened, level: "error" });
      this.close();
    });
  }

  form() {
    const t = theme();
    const label = (text) => div().pt(16).pb(7).text_size(11.5).text_color(t.dim).child(text);
    const button = (id, text, primary, action) =>
      h_flex().id(id).h(32).px(14).items_center().rounded(8)
        .border_1().border_color(primary ? t.solid : t.input).bg(primary ? t.solid : t.raised)
        .text_color(primary ? t.solid_foreground : t.foreground).text_size(12.5).font_medium()
        .cursor_pointer().hover((s) => s.opacity(0.88)).on_click(action).child(text);
    const repo = (path, i) =>
      h_flex().h(ROW).flex_none().pl(10).pr(4).gap(10).items_center().rounded(8).bg(t.raised)
        .child(div().flex_none().max_w(180).truncate().child(base(path)))
        .child(div().flex_1().min_w(0).truncate().text_size(11.5).text_color(t.dim).child(tilde(path)))
        .child(div().id(`project-new-drop-${i}`).size(22).flex_none().flex().items_center().justify_center()
          .rounded(6).text_color(t.dim).tooltip("Leave this repo out")
          .hover((s) => s.bg(t.hover).text_color(t.foreground))
          .on_click((_e, cx) => { this.repos.splice(i, 1); this.error = ""; cx.notify(); })
          .child("×"));
    return v_flex().id("project-new-form").track_focus(this.handle)
      .on_key_down((e, cx) => { if (e.key === "escape") { this.close(); cx.stop_propagation(); } })
      .w_full().min_h(0).p(18).bg(t.popover).text_color(t.foreground).text_size(13)
      .child(h_flex().items_center()
        .child(div().flex_1().text_size(15).font_semibold().child("New project"))
        .child(div().text_size(11).text_color(t.dim).child("Esc")))
      .child(div().pt(6).text_size(12.8).text_color(t.muted)
        .child("A project groups the repos that belong together and opens as one space."))
      .child(label("Name"))
      .child(Input.new(this.input).h(36).px(10).rounded(9).border_1()
        .border_color(this.inputFocused ? t.accent : t.input).bg(t.background)
        .text_size(12.8).text_color(t.foreground))
      .child(label("Repos"))
      .child(v_flex().id("project-new-repos").max_h(200).min_h(0).flex_shrink(1).gap(4)
        .overflow_y_scroll().children(this.repos.map(repo)))
      .child(h_flex().id("project-new-add").h(ROW).flex_none().mt(this.repos.length ? 4 : 0).px(10)
        .items_center().rounded(8).text_color(t.muted).cursor_pointer()
        .hover((s) => s.bg(t.hover).text_color(t.foreground))
        .on_click((_e, cx) => this.addRepo(cx))
        .child(this.repos.length ? "+ Add another repo…" : "+ Add a repo…"))
      .when(Boolean(this.error), (el) =>
        el.child(div().pt(12).text_size(12).text_color(t.blocked).child(this.error)))
      .child(h_flex().pt(20).gap(8).justify_end()
        .child(button("project-new-cancel", "Cancel", false, () => this.close()))
        .child(button("project-new-create", this.working ? "Creating…" : "Create", true,
          (_e, cx) => this.submit(cx))));
  }
}
