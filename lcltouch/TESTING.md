# Testing on a touchscreen

What is needed to turn "should work" into "works": a Linux machine with a
touchscreen, running X11.

## 1. Make sure the touchscreen speaks XInput 2 touch

```bash
xinput list                  # find the touchscreen's id
xinput test-xi2 --root       # tap the screen: expect TouchBegin / TouchEnd
```

If only button events show up here, the touchscreen is configured as a mouse
and the bug cannot occur on that machine.

## 2. See the bug with stock LCL

```bash
cd repro
lazbuild --ws=gtk3 touchrepro.lpi
./touchrepro
```

Tap the big panel with a finger.

- **Bug present:** the panel counters stay at 0, and the log shows
  `GTK touch BEGIN ... LCL did not handle it` / `GTK touch END ...` for each
  tap.
- Also tap **Tap this button** and note whether its counter moves. It is a
  GTK-native button, so it may work even while the panel does not. That
  difference is worth recording in the report.
- Click both with a mouse as a control: both counters move.

## 3. Try the proposed fix

In a Lazarus main checkout:

```bash
git apply --check /path/to/lcltouch/patches/0001-gtk3-deliver-touch-as-mouse.patch
git apply         /path/to/lcltouch/patches/0001-gtk3-deliver-touch-as-mouse.patch
```

(Or `patch -p1 < ...` - the patch carries a short description above the diff,
which both tools skip.)

Rebuild the LCL gtk3 widgetset with that Lazarus - in the IDE, *Tools > Build
Lazarus* with LCL gtk3 selected, or with `lazbuild --build-all --ws=gtk3` on
the LCL package - then rebuild and run the repro.

- **Fixed:** tapping the panel moves its counters; the log shows `LCL panel
  OnMouseDown` / `OnClick` lines, and **no** `GTK touch` lines, because LCL
  now handles the touch before it reaches the window.

## 4. Behaviour to check with the fix

| Try | Expect |
|---|---|
| tap a `TPanel` / `TPaintBox` | `OnMouseDown`, `OnMouseUp`, `OnClick` |
| drag a finger across a `TPaintBox` | `OnMouseMove` with `ssLeft` in `Shift` |
| tap a `TEdit` | it takes focus |
| tap a `TButton` | exactly **one** `OnClick` (GTK still handles buttons itself) |
| two fingers down | only the first one acts |
| touch taken away by the system (a system gesture, palm rejection) | nothing left stuck "pressed" (see the `GDK_TOUCH_CANCEL` note in ANALYSIS.md) |
| double tap | two clicks - there is no `OnDblClick` from touch (see ANALYSIS.md) |
| mouse, as before | unchanged |

## 5. The alternative patch

For `patches/0002` the steps are the same. Also try it with
`GTK_CSD=1 ./touchrepro`: a client-side-decorated window may select touch
events itself, which would bring the bug back under this approach.

## Reporting back

Worth including: the Lazarus revision, `xinput list` output for the
touchscreen, the X11 or Wayland session, the GTK version
(`pkg-config --modversion gtk+-3.0`), and the repro's log for a few taps,
before and after.
