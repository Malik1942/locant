# Locant: freeze the screen while you point

**Status:** Spec written Oct 26, 2026, after Malik could not capture a window that opens from the menu bar. His capture of Monister's window (a SwiftUI `MenuBarExtra` in `.window` style) named it (`window`, 360×468) but its image was wallpaper. Measured the same day with the installed 1.0.1: that window stays open through ⌃⌃, the overlay, and the overlay taking key focus, and closes within 0.3 s of the click. Point takes its crop after the click, so the window is gone by then. A standard menu (`NSMenu`; Cursor's status menu was tested) closes as soon as the overlay becomes key, before any hover. While one is open it takes every mouse event, so an overlay that is not key gets no hover and no click (a probe panel counted 0 moves). A click on the ball closes either one before Point opens. Decided the same day: the screen freezes when an action starts, as Malik asked. Numbered from R119 (PR #72 holds R116–R118).
**Scope of this spec:** the freeze for Point, Snap, Text, and Cut; crops from it; a window that closed since the freeze; the ball while a menu is open.
**Out of scope:** Color (its magnifier stays live); the items inside a standard menu (it is closed before the hover can read them); iterations (R52), which stay live.

This spec overrides `specs/v0.1.md` R2's "No frozen frame". R2 counted on the front app keeping focus to keep menus open. A standard menu closes anyway, and a window-style one closes at the click.

## 1. Requirements

**R119. The freeze.** When Point, Snap, Text, or Cut opens, from any entry (a hotkey, the ball, the menu bar, the ring, Try it), the overlay panels come up first without key focus, which leaves any menu open. Then Locant captures every display at full resolution, its own windows excluded, puts each image under the dim on its display, and only then takes key focus. From then on the overlay shows the screen as it was: a menu that closes, a video that plays on, or a window that moves underneath shows only once the overlay closes. The dim fades in as before; the image goes in under it in place, so nothing flickers. The images are released when the session ends. On Malik's Mac (the built-in display and two 6K displays) the capture takes 130–160 ms, 350 ms the first time. Without Screen Recording permission, or when the capture fails or has not answered within 1 s, the overlay takes key focus over the live screen, as before this spec.

**R120. Crops from the freeze.** Point (an element, a set, a drawn frame), Snap, Text, and Cut cut their image from the frozen image of the display that holds the crop's center, with the same pixel math as a live crop: `ScreenCapture.crop(_:from:display:scale:)`, pure. With no frozen image of that display, the crop is taken live as before, and a stuck capture service is handled as in R110.

**R121. A window that closed.** The window list is read when the action starts (R3). When the frontmost window under the cursor in that list (any layer, Locant's own skipped) is no longer on screen, the hover does not read what is now behind it. The selection is that window: role `window`, its app's name as the label, its bounds as the frame, no Option levels. A click captures it from the frozen image, with that app as the source and no window title. Snap, Text, and Cut take the same selection; a frame drawn from a point on such a window keeps no elements. The test is pure: `Geometry.vanishedWindow(at:windows:excludingPID:isOnScreen:)`. A window that is still open, as Monister's is until the click, resolves as before.

**R122. The ball while a menu is open.** Another app has a menu open when it has an on-screen window from the pop-up menu level (101) up to, not including, the screen saver level (1000). Status items (25) and the transparent panels some apps keep at 1000 (Wispr Flow) do not count. Pure: `Geometry.hasOpenMenu(windows:excludingPID:)`. While the ball is awake or ready, Locant keeps a session event tap on the left mouse button. A press on the disc while a menu is open is taken by Locant before any app sees it, so the menu stays open, and its release starts Point, which then freezes the menu (R119). That press neither opens the ring nor drags the ball. Every other press, and every press while no menu is open, passes through untouched. Without the tap (no Accessibility trust) the ball behaves as before.

**R123. Words elsewhere.** README's limitation "Menus and popovers stay open under the overlay, but an element inside another app's menu may not resolve." says what R119 and R121 do instead. CHANGELOG gains one bullet under Unreleased.

## 2. Files

- New: `Locant/Launcher/BallPressTap.swift` (R122) and `LocantTests/FrozenScreenTests.swift`.
- Changed: `ScreenCapture.swift` (`FrozenScreen`, the freeze, the pure crop), `Geometry.swift` (a window id on `WindowRecord`, `vanishedWindow`, `hasOpenMenu`), `ContextCollector.swift` (`WindowList` reads the id and whether a window is still on screen), `SelectionOverlay.swift` (panels without key focus, the frozen image under the dim), `AppState.swift` (R119–R121), `FloatingBall.swift` (R122), `README.md` and `CHANGELOG.md` (R123).

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
