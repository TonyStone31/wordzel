# Bug report - ready to paste

For https://gitlab.com/freepascal.org/lazarus/lazarus/-/issues. Attach
`patches/0001-gtk3-deliver-touch-as-mouse.patch`, and optionally the `repro/`
folder.

---

**Title:** GTK3: touchscreen taps never reach LCL controls (`GDK_TOUCH_MASK`
is selected but `GDK_TOUCH_*` events are not handled)

**Widgetset:** gtk3
**Lazarus:** main `b9cfd22ae9` (2026-09-11); also 4.0 (`43d904ed`)
**FPC:** 3.3.1 (main), 3.2.2 (4.0)
**OS:** Linux, X11 (Linux Mint, touchscreen laptop)

### Summary

On a touchscreen, tapping an LCL-gtk3 application does nothing on controls
LCL paints itself (`TPaintBox`, `TPanel`, custom-drawn controls): no
`OnMouseDown`, `OnMouseUp` or `OnClick`. The same controls work with a mouse.
GTK-native controls such as `TButton` may still respond.

### Steps to reproduce

1. Build the attached repro with the gtk3 widgetset:
   `lazbuild --ws=gtk3 touchrepro.lpi`
2. Run it on a machine with a touchscreen.
3. Tap the large panel with a finger.

**Expected:** the panel counts presses and clicks, as it does with a mouse.

**Actual:** the counters stay at 0. The repro also listens for GTK's own
`touch-event` signal on the window, and its log shows a
`GTK touch BEGIN` / `END` for every tap. GTK is delivering the touches and
LCL is dropping them.

### Cause

- `GDK_DEFAULT_EVENTS_MASK` (`lcl/interfaces/gtk3/gtk3procs.pas`, line 121)
  includes `GDK_TOUCH_MASK`, and it is applied to LCL widgets throughout
  `gtk3widgets.pas`. Selecting touch events makes X/GDK stop emulating
  pointer events for touches.
- `TGtk3Widget.WidgetEvent` (`gtk3widgets.pas:1386`, `case` at 1433) has no
  `GDK_TOUCH_*` arms and no `else`, so touch events return `gtk_false` and
  are ignored all the way up the widget tree. The only references to
  `GDK_TOUCH_*` in the widgetset are the debug names in `Gtk3EventToStr`.

The mask has been in the list since `ac8db2aede` (2018-12-23), and no
commit in `lcl/interfaces/gtk3` has handled touch events since.

### Proposed fix (patch attached)

Add `GDK_TOUCH_BEGIN/UPDATE/END/CANCEL` arms to `WidgetEvent`. For the
pointer-emulating sequence (`emulating_pointer`, the first finger) they build
the equivalent `GDK_BUTTON_PRESS` / `GDK_MOTION_NOTIFY` / `GDK_BUTTON_RELEASE`
and feed it back through `WidgetEvent`, so all existing mouse handling -
focus, the `TButtonControl` exceptions, `OffsetMousePos`, capture,
`LM_CONTEXTMENU` - applies unchanged. `NO_PROPAGATION_TO_PARENT` is carried
between the synthetic event and the touch so parents do not handle it twice.

A one-line alternative is to drop `GDK_TOUCH_MASK` from
`GDK_DEFAULT_EVENTS_MASK` and rely on pointer emulation. That only works if
nothing else in the window selects touch events.

The patch applies cleanly to `b9cfd22ae9` and compiles against it with FPC
3.3.1 with no errors, including every unit that depends on `gtk3widgets`. It
has not been tested on touch hardware; test notes are available.

### Workaround for applications

Connect to `touch-event` on the form's top-level `GtkWindow` - touch events
bubble up to it because `WidgetEvent` ignores them - and replay them through
the application's own mouse handlers. An example unit is available.
