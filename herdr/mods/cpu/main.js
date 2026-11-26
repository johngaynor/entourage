// Live CPU usage, drawn as a scrolling history like Activity Monitor's.
// macOS only: it reads the "CPU usage" line that /usr/bin/top prints.
import { View, div } from "gpui-kit";
import { h_flex, v_flex } from "gpui-base";
import { exec, theme, window, checking, settings } from "herdr";

const SAMPLE_MS = 2000; // one reading every two seconds
const BAR = 3; // px per reading
const GAP = 1;
const KEEP = 600; // readings kept, enough for a very wide panel

export default class Cpu extends View {
  init(_props, cx) {
    this.samples = [];
    this.busy = false;
    this.error = null;
    this.graph = { width: 240, height: 40 };
    if (checking()) return;
    cx.timer.every(SAMPLE_MS, (cx) => this.sample(cx));
    this.sample(cx);
  }

  sample(cx) {
    // Skip while a reading is in flight or nobody can see the window.
    if (this.busy || window()?.visible === false) return;
    this.busy = true;
    cx.spawn(async (cx) => {
      try {
        // top's first sample averages since boot; the second covers the last second.
        const r = await exec("/usr/bin/top", ["-l", "2", "-n", "0", "-s", "1"], { timeout: 10000 });
        const line = r.stdout.split("\n").filter((l) => l.startsWith("CPU usage:")).at(-1);
        const m = line?.match(/([\d.]+)% user, ([\d.]+)% sys/);
        if (m) {
          this.samples.push({ user: Number(m[1]), sys: Number(m[2]) });
          if (this.samples.length > KEEP) this.samples.shift();
          this.error = null;
        } else {
          this.error = "no CPU reading from top";
        }
      } catch (e) {
        this.error = String(e?.message ?? e);
      }
      this.busy = false;
      cx.notify();
    });
  }

  render() {
    const t = theme();
    const userColor = t.ansi4;
    const sysColor = t.ansi1;
    const last = this.samples.at(-1);
    const total = last ? Math.round(last.user + last.sys) : null;

    const fit = Math.max(1, Math.floor(this.graph.width / (BAR + GAP)));
    const shown = this.samples.slice(-fit);
    const h = Math.max(1, this.graph.height);
    const px = (pct) => Math.round((Math.min(100, pct) / 100) * h);

    const legend = (color, text) =>
      h_flex().gap(5).items_center().child(div().size(6).rounded(3).bg(color)).child(text);

    const readout = v_flex().flex_none().w(132).gap(2).justify_center()
      .child(h_flex().gap(8).items_end()
        .child(div().text_size(11).text_color(t.muted).child("CPU"))
        .child(div().text_size(20).font_semibold().text_color(t.foreground).child(total === null ? "–" : `${total}%`)))
      .child(this.error
        ? div().text_size(11).text_color(t.blocked).truncate().child(this.error)
        : h_flex().gap(10).text_size(11).text_color(t.muted)
            .child(legend(userColor, last ? `user ${Math.round(last.user)}%` : "user"))
            .child(legend(sysColor, last ? `sys ${Math.round(last.sys)}%` : "sys")));

    const bars = h_flex().id("cpu-graph").flex_1().h_full().min_w(0).overflow_hidden()
      .items_end().justify_end().gap(GAP).rounded(4).bg(t.surface)
      .on_size_change((size, cx) => {
        const zoom = Number(settings().zoom) || 1;
        this.graph = { width: size.width / zoom, height: size.height / zoom };
        cx.notify();
      })
      .children(shown.map((s) =>
        v_flex().flex_none().w(BAR)
          .child(div().h(px(s.sys)).bg(sysColor))
          .child(div().h(px(s.user)).bg(userColor))));

    return h_flex().size_full().px(14).py(8).gap(12).items_center()
      .bg(t.chrome).border_t(1).border_color(t.border)
      .child(readout)
      .child(bars);
  }
}
