# Analysis

References are to **Lazarus main `b9cfd22ae9`** (2026-09-11) unless noted,
and to the LCL-gtk3 bindings shipped with it. Line numbers move; the symbol
names are the stable part.

## Symptom

On a touchscreen, tapping any control that LCL draws itself does nothing: no
`OnMouseDown`, `OnMouseUp`, `OnClick` or `OnMouseMove`. With a mouse the same
controls work. GTK-native controls such as `TButton` may still respond to a
tap, because GTK handles those touches with its own gestures.

## How a touch normally becomes a click

Under X11 with XInput 2, a touch is delivered as touch events (`TouchBegin`,
`TouchUpdate`, `TouchEnd`) to a client that has selected them on the window.
If no client has, the X server emulates pointer events - button press, motion,
button release - for the first touch instead.

GDK follows the widget's event mask. A widget whose mask includes
`GDK_TOUCH_MASK` gets `GdkEventTouch` (`GDK_TOUCH_BEGIN`, `GDK_TOUCH_UPDATE`,
`GDK_TOUCH_END`, `GDK_TOUCH_CANCEL`). The touch sequence standing in for the
pointer - the first finger - is flagged with `emulating_pointer = TRUE`.

**So a toolkit that selects touch events takes on the job of turning touches
into clicks.** LCL-gtk3 selects them, and does not do that job.

## What LCL-gtk3 does

### 1. It asks for touch events on every widget

`lcl/interfaces/gtk3/gtk3procs.pas`, `GDK_DEFAULT_EVENTS_MASK` (its
`GDK_TOUCH_MASK` entry is line 121):

```pascal
GDK_DEFAULT_EVENTS_MASK = [
  GDK_EXPOSURE_MASK, {2}
  ...
  GDK_SCROLL_MASK, {2097152}
  GDK_TOUCH_MASK {4194304}                        // line 121
// GDK_SMOOTH_SCROLL_MASK {8388608} //there is a bug in GTK3, ...
];
```

It is applied wherever LCL sets a widget's events - a number of
`set_events(GDK_DEFAULT_EVENTS_MASK)` and `gdk_window_set_events` calls
throughout `gtk3widgets.pas`.

In **4.0** (`43d904ed`) the same list is at `gtk3widgets.pas:921`.

### 2. Nothing handles the touch events

Every LCL widget connects its `event` signal to
`TGtk3Widget.WidgetEvent` (`gtk3widgets.pas:1386`). Its
`case event^.type_ of` (line 1433) has arms for `GDK_MOTION_NOTIFY`,
`GDK_BUTTON_PRESS`, `GDK_2BUTTON_PRESS`, `GDK_3BUTTON_PRESS`,
`GDK_BUTTON_RELEASE`, keys, focus, crossing, configure, scroll and so on - but
none for `GDK_TOUCH_*`, and no `else`. A touch event therefore returns
`gtk_false`, GTK carries on, and the event bubbles up to the parent widgets,
each of which ignores it the same way, up to the top-level window.

The only mentions of `GDK_TOUCH_BEGIN` / `GDK_TOUCH_END` anywhere in
LCL-gtk3 are the debug names in `Gtk3EventToStr`.

In 4.0 the dispatcher is the plain function `Gtk3WidgetEvent`
(`gtk3widgets.pas:1081`) and is the same in this respect. The main loop
`Gtk3MainEventLoop` (`gtk3object.inc:23`) passes every event, touch included,
to `gtk_main_do_event`, so nothing is lost before the dispatcher.

### 3. History

`git log -S GDK_TOUCH_MASK` over the gtk3 widgetset:

- `ac8db2aede` (2018-12-23) - "LCL: GTK3: Prevent SIGSEGV in
  Gtk3ScrolledWindowScrollEvent because of bug in GTK3" - where the mask list
  containing `GDK_TOUCH_MASK` comes from (it sits beside the smooth-scroll
  comment).
- `50b142a124` (2026-03-08) - "Gtk3: Added deferred resize for toplevels,
  code formatted" - where it moved to `gtk3procs.pas`.

No commit in `lcl/interfaces/gtk3` has ever handled touch events.

## Who is affected, and why it went unnoticed

Any LCL-gtk3 application on a touchscreen: tablets, 2-in-1 laptops, kiosks.
Custom-drawn interfaces are hit hardest, because they depend on LCL mouse
messages entirely.

It is easy to miss. Most development machines have no touchscreen, GTK-native
buttons keep working, and remote desktop setups usually send the remote side
pointer events even when the local screen is a touchscreen.

## Proposed fix - patches/0001

Four arms are added to `WidgetEvent`:

```pascal
GDK_TOUCH_BEGIN, GDK_TOUCH_UPDATE, GDK_TOUCH_END, GDK_TOUCH_CANCEL:
  Result := TouchAsMouse(Widget, Event, Data);
```

`TouchAsMouse` (a new static class function beside `WidgetEvent`):

- ignores any sequence that is not `emulating_pointer`, so only the first
  finger acts, as with pointer emulation;
- builds the matching `GDK_BUTTON_PRESS` (begin), `GDK_MOTION_NOTIFY` with
  `GDK_BUTTON1_MASK` (update) or `GDK_BUTTON_RELEASE` (end / cancel), copying
  window, time, coordinates, state and device from the touch - the event
  records share their leading layout;
- **feeds it back through `WidgetEvent`**, so everything the mouse path does
  still happens: setting focus before GTK does, leaving `TButtonControl` to
  GTK's own click handling, `OffsetMousePos`, capture, `LM_CONTEXTMENU`;
- copies `send_event` into the synthetic event and back out again. The mouse
  path uses `NO_PROPAGATION_TO_PARENT` (127) there to stop parents handling
  an event twice as it bubbles, and the touch bubbles the same way.

The mouse code has changed substantially between November 2025 and August
2026 (`CheckWidget`, context-menu propagation, triple click, key state on
release). Reusing it rather than copying it keeps this patch small, and keeps
touch behaving like the mouse as that code carries on changing.

### Choices worth a maintainer's eye

- **`GDK_TOUCH_CANCEL` becomes a button release.** That can produce a click
  where the system took the touch away, for example for a gesture. The
  alternative is to deliver the release outside the control, or to drop it
  and risk a control left "pressed".
- **No double-tap.** GDK does not synthesise `GDK_2BUTTON_PRESS` for touch, so
  a double tap gives two clicks, not `OnDblClick`. `TouchAsMouse` could count
  taps by time and distance if that is wanted.
- **No right-click.** Press-and-hold as right-click is left to applications.
- **Wayland** was not examined. The patch relies only on `emulating_pointer`,
  so it should behave the same wherever GDK sets that flag.

## Alternative - patches/0002

Take `GDK_TOUCH_MASK` out of `GDK_DEFAULT_EVENTS_MASK`. LCL widgets no longer
ask for touch events, and X / GDK go back to emulating the mouse for the first
finger. It is one line, and it leaves every touch decision with the platform.

The catch is that it depends on nothing else in the window selecting touch
events. If a GTK parent does - a client-side-decorated `GtkWindow` with
gestures, say - pointer emulation can still be suppressed. It also closes the
door on LCL ever seeing real touches. 0001 works whatever the rest of the
window asks for.

## What an application can do today - workaround/unittouch.pas

Because the dispatcher returns `gtk_false` for touch events, they bubble up to
the top-level `GtkWindow` as GTK `touch-event` signals. `unittouch.pas`
connects to that signal on the form's window and hands each touch - phase,
sequence and screen coordinates - to an application callback, which can
replay it through its own mouse handlers. It is only needed on gtk3, and it
does nothing on other widgetsets.

Two things learned along the way, in case they help others:

- Connect after the form is shown. Forcing the handle in `OnCreate`
  (`HandleNeeded`) makes the gtk3 window open at 0.8x its designed size.
- If a system both emulates the pointer *and* delivers touch, an application
  will see each tap twice. The game ignores mouse events for a short time
  after a touch to guard against that.
