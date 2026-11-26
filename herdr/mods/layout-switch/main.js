// A dropdown that shows the current layout and switches to another.
// One mod, two faces: the button a layout places, and the popup list it opens
// (the same mod again, with props { menu: true }).
import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { layouts, shared, run, theme, props, openOverlay, closeOverlay } from "herdr";

const ROW = 28;

export default class LayoutSwitch extends View {
  render() {
    return props()?.menu ? this.menu() : this.button();
  }

  button() {
    const t = theme();
    const current = shared("layout") ?? "main";
    return h_flex().size_full().px(12).items_center().bg(t.chrome).child(
      h_flex().id("layout-switch").flex_1().min_w(0).h(ROW).px(10).gap(8).items_center()
        .rounded(6).border(1).border_color(t.border).bg(t.surface)
        .text_size(12).hover((s) => s.bg(t.hover))
        .on_click(() =>
          openOverlay({
            mod: "layout-switch", kind: "popup", width: 220,
            height: layouts().length * ROW + 10, props: { menu: true },
          }))
        .child(div().flex_none().text_color(t.muted).child("Layout"))
        .child(div().flex_1().min_w(0).truncate().text_color(t.foreground).child(String(current)))
        .child(div().flex_none().text_color(t.dim).child("▾")));
  }

  menu() {
    const t = theme();
    const current = shared("layout") ?? "main";
    const pick = (name) => {
      closeOverlay(props().overlay);
      if (name !== current) run("layout.switch", { name });
    };
    return v_flex().size_full().p(4).bg(t.popover).text_size(12).children(
      layouts().map((name) =>
        h_flex().id(`layout-${name}`).h(ROW).px(8).gap(8).items_center().rounded(4)
          .hover((s) => s.bg(t.hover))
          .on_click(() => pick(name))
          .child(div().w(12).flex_none().text_color(t.accent).child(name === current ? "✓" : ""))
          .child(div().flex_1().min_w(0).truncate()
            .text_color(name === current ? t.foreground : t.muted).child(name))));
  }
}
