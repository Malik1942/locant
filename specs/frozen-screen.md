# Locant: freeze the screen while you point

**Status:** Spec written Oct 26, 2026, after Malik could not capture a window that opens from the menu bar. His capture of Monister's window (a SwiftUI `MenuBarExtra` in `.window` style) named it (`window`, 360×468) but its image was wallpaper. Measured the same day with the installed 1.0.1: that window stays open through ⌃⌃, the overlay, and the overlay taking key focus, and closes within 0.3 s of the click. Point takes its crop after the click, so the window is gone by then. A standard menu (`NSMenu`; Cursor's status menu was tested) closes as soon as the overlay becomes key, before any hover. While one is open it takes every mouse event, so an overlay that is not key gets no hover and no click (a probe panel counted 0 moves). A click on the ball closes either one before Point opens. Decided the same day: the screen freezes when an action starts, as Malik asked. Numbered from R119 (PR #72 holds R116–R118).
**Amended Nov 13, 2026 (R119, R169):** Malik reported that Snap still did not freeze what he was looking at: what an app shows on hover was gone from the picture, often as soon as he moved the mouse. R119 put the overlay up first and captured the screen after. Measured that day with a probe window that shows a card only while the mouse is over it: with the mouse held still, the probe lost its hover 120 ms after the hotkey, because the overlay had come up under the cursor and taken the mouse, and the capture came 100 to 200 ms after that. The order is now the other way round: the capture first, the overlay after (R169). R119 is rewritten to match.
**Scope of this spec:** the freeze for Point, Snap, Text, and Cut; crops from it; a window that closed since the freeze; the ball while a menu is open.
**Out of scope:** Color (its magnifier stays live); the items inside a standard menu (it is closed before the hover can read them); iterations (R52), which stay live.

This spec overrides `specs/v0.1.md` R2's "No frozen frame". R2 counted on the front app keeping focus to keep menus open. A standard menu closes anyway, and a window-style one closes at the click.

## 1. Requirements

**R119. The freeze.** When Point, Snap, Text, or Cut opens, from any entry (a hotkey, the ball, the menu bar, the ring, Try it), Locant first captures every display at full resolution, its own windows excluded (R169). Then the overlay panels come up, each with its display's image already under the dim, and the first takes key focus at once. From then on the overlay shows the screen as it was: a menu that closes, a video that plays on, or a window that moves underneath shows only once the overlay closes. The dim fades in as before, over the same picture, so nothing flickers. The images are released when the session ends. Without Screen Recording permission, or when the capture fails or has not answered within 1 s, the overlay opens over the live screen, as before this spec.

**R120. Crops from the freeze.** Point (an element, a set, a drawn frame), Snap, Text, and Cut cut their image from the frozen image of the display that holds the crop's center, with the same pixel math as a live crop: `ScreenCapture.crop(_:from:display:scale:)`, pure. With no frozen image of that display, the crop is taken live as before, and a stuck capture service is handled as in R110.

**R121. A window that closed.** The window list is read when the action starts (R3). When the frontmost window under the cursor in that list (any layer, Locant's own skipped) is no longer on screen, the hover does not read what is now behind it. The selection is that window: role `window`, its app's name as the label, its bounds as the frame, no Option levels. A click captures it from the frozen image, with that app as the source and no window title. Snap, Text, and Cut take the same selection; a frame drawn from a point on such a window keeps no elements. The test is pure: `Geometry.vanishedWindow(at:windows:excludingPID:isOnScreen:)`. A window that is still open, as Monister's is until the click, resolves as before.

**R122. The ball while a menu is open.** Another app has a menu open when it has an on-screen window from the pop-up menu level (101) up to, not including, the screen saver level (1000). Status items (25) and the transparent panels some apps keep at 1000 (Wispr Flow) do not count. Pure: `Geometry.hasOpenMenu(windows:excludingPID:)`. While the ball is awake or ready, Locant keeps a session event tap on the left mouse button. A press on the disc while a menu is open is taken by Locant before any app sees it, so the menu stays open, and its release starts Point, which then freezes the menu (R119). That press neither opens the ring nor drags the ball. Every other press, and every press while no menu is open, passes through untouched. Without the tap (no Accessibility trust) the ball behaves as before.

**R123. Words elsewhere.** README's limitation "Menus and popovers stay open under the overlay, but an element inside another app's menu may not resolve." says what R119 and R121 do instead. CHANGELOG gains one bullet under Unreleased.

**R169. The picture comes first.** Nothing of Locant's goes on screen, and Locant takes no key focus, until the capture of R119 has answered or its 1 s is up. The overlay takes the mouse from the app under the cursor the moment it comes up, and that app then drops what it showed on hover: a hover menu on a web page, a tooltip, a row's hover buttons. A standard menu closes once the overlay is key. So the capture is the session's first act, started before the front app is read (R5), and the overlay waits for it. The displays and windows are listed once for all displays (`ScreenCapture.freeze()`), not once per display. Until the overlay shows, the mouse and keys still belong to the app in front, as they did before the hotkey. What the user gives up is the dim appearing at once: it now appears when the picture has arrived. Measured Nov 13, 2026 on Malik's Mac with the built-in display and one 6K display, from the hotkey to the overlay on screen, five sessions each: 70 to 90 ms before this requirement (120 ms the first session after launch), 170 to 210 ms with it (360 ms the first).

## 2. Files

- New: `Locant/Launcher/BallPressTap.swift` (R122) and `LocantTests/FrozenScreenTests.swift`.
- Changed: `ScreenCapture.swift` (`FrozenScreen`, the freeze, the pure crop), `Geometry.swift` (a window id on `WindowRecord`, `vanishedWindow`, `hasOpenMenu`), `ContextCollector.swift` (`WindowList` reads the id and whether a window is still on screen), `SelectionOverlay.swift` (the frozen image under the dim), `AppState.swift` (R119–R121), `FloatingBall.swift` (R122), `README.md` and `CHANGELOG.md` (R123).
- R169 (Nov 13, 2026): `AppState.swift` (`beginAction` starts the capture and waits for it before the overlay), `SelectionOverlay.swift` (`show(frozen:)` replaces `show()` and `freeze(_:)`), `ScreenCapture.swift` (one listing for all displays), `CHANGELOG.md`.

## 3. Tests

- `FrozenScreenTests`:
  - A crop from a 2× image of a display with a negative origin has the right point size, scale, crop rectangle, and pixels.
  - `FrozenScreen` crops from the display that holds the crop's center, and returns nil when none does.
- `GeometryTests`:
  - `vanishedWindow` returns the frontmost window under the point when it has left the screen; nil when it is still there, when the point is on no window, and for Locant's own window.
  - `hasOpenMenu` is true for another app's window at 101 or 500, false for status items at 25, a normal window, another app's panel at 1000, and Locant's own windows.
- `FloatingBallTests`: the disc takes a press within its radius plus 2 pt of its center, and not in the window's clear margin.
- The existing tests pass.
- In the app:
  - **Monister's window**, open from the menu bar: ⌃⌃, click a control inside it. The window closes at the click, but the overlay still shows it, and the PNG shows the control, not wallpaper.
  - **A standard menu** (Cursor's status menu): ⌃⌃. The overlay still shows the menu; the hover over it reads `window "Cursor"`; the click's PNG is the menu.
  - **The ball with Monister's window open:** a click leaves the window open, and Point opens over it frozen.
  - **The ball with no menu open:** click, hold for the ring, and drag all work as before.
  - **Nothing else changes:** Point on a normal window, Snap, Text, Cut, a drawn frame, Shift sets, and Esc.
  - **What shows on hover (R169):** a window that shows a card only while the mouse is over it. With the mouse on it, Snap's hotkey, then the mouse held still or moved a few points: the overlay shows the card, though the window itself hid it when the overlay came up. Before R169 the overlay showed the window without the card, even with the mouse held still.
