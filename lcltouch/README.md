# Touchscreen taps are lost in LCL-gtk3 applications

**For the Lazarus developers.** On a touchscreen, tapping an LCL-gtk3
application does nothing on any control LCL paints itself - `TPaintBox`,
`TPanel`, custom-drawn controls, and so on. It is a gap in the gtk3
widgetset, not in any one application:

1. LCL-gtk3 puts `GDK_TOUCH_MASK` in `GDK_DEFAULT_EVENTS_MASK`, so every LCL
   widget asks GDK for touch events.
2. Asking for touch events is exactly what tells X / GDK to *stop* emulating
   the mouse for touches.
3. Nothing in LCL-gtk3 handles `GDK_TOUCH_BEGIN` / `UPDATE` / `END` /
   `CANCEL`.

So touches arrive, are ignored, and never become mouse messages. Controls GTK
draws itself (`TButton`, `TEdit`, ...) can still respond, because GTK's own
gesture handling picks the touch up - which makes the bug look patchy and
easy to miss.

It is present in **Lazarus main `b9cfd22ae9` (2026-09-11)** and in **4.0
(`43d904ed`)**. It turned up while getting a children's game working on a
touchscreen laptop running Linux Mint.

## What is here

| | |
|---|---|
| [ANALYSIS.md](ANALYSIS.md) | the root cause, with file and line references and history |
| [BUGREPORT.md](BUGREPORT.md) | ready to paste into the Lazarus issue tracker |
| [TESTING.md](TESTING.md) | how to confirm it on a touchscreen, before and after a fix |
| [patches/0001-gtk3-deliver-touch-as-mouse.patch](patches/0001-gtk3-deliver-touch-as-mouse.patch) | **proposed fix** - the first finger is turned into mouse events inside `WidgetEvent` |
| [patches/0002-gtk3-stop-selecting-touch-events.patch](patches/0002-gtk3-stop-selecting-touch-events.patch) | smaller alternative - stop asking for touch events at all |
| [repro/](repro/) | minimal LCL application that shows the problem |
| [workaround/unittouch.pas](workaround/unittouch.pas) | what an application can do today without patching LCL |

## Status - what has and has not been checked

- **The diagnosis** comes from reading the LCL source, and is laid out with
  references in ANALYSIS.md. It has not been confirmed on touch hardware yet.
- **Both patches** apply cleanly to main `b9cfd22ae9` and compile against
  that tree with FPC 3.3.1, with no errors. For 0001 that includes every unit
  depending on `gtk3widgets`, because the new method changes its interface
  CRC. Neither has been tested on touch hardware.
- **The repro** builds with Lazarus 4.0 / FPC 3.2.2 and works with a mouse.
  It has not yet been run on a touchscreen.
- **The workaround** is what the game uses. It builds and runs; it has not yet
  been confirmed on touch hardware either.

TESTING.md is the checklist for closing those gaps.

## Using it locally, with fpcupdeluxe

fpcupdeluxe can re-apply a local patch after every update, so the tree does
not have to be patched by hand each time ("local auto-patch"):

1. Copy `patches/0001-gtk3-deliver-touch-as-mouse.patch` into the
   `patchlazarus/` folder of the fpcupdeluxe installation (the one beside
   `fpcupdeluxe.ini`, which also has `patchfpc/` and `patchuniversal/`).
2. In fpcupdeluxe, under **Source patching**, use **Add Laz. patch** and pick
   it. It is recorded under `[Patches] LazarusPatches=` in `fpcupdeluxe.ini`.
3. Update or rebuild Lazarus as usual; the patch is applied to the fresh
   sources each time.

If upstream changes that part of `gtk3widgets.pas`, applying it can fail -
fpcupdeluxe will say so, and it can be regenerated against the new source.

None of this is needed for the game, whose touch support is at application
level in `workaround/unittouch.pas`.

## If the fix lands

Applications using the workaround keep working. With the fix in place, LCL
handles each touch first and marks it handled, so it never reaches the
window's `touch-event` signal where the workaround listens - touches are not
delivered twice.
