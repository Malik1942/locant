# Locant: the ball is easy to find

**Status:** Spec written Oct 19, 2026, after Malik said nobody can find the ball in the site's Try it here demo: it appears at the bottom right, and two seconds later tucks 40 percent of itself into the right edge over the dark rock of the wallpaper. Decided the same day: the ball starts on the right edge, high up, in the app and on the site alike, and the site adds a label and a pulse until the ball is first found. The design said a quarter of the way down; built, the label there covered the iPhone window's header, so it is an eighth. Numbered from R102 (`specs/settings-cleanup.md` ends at R101).
**Scope of this spec:** the app's first-launch spot, the demo ball's first spot, and a hint beside the demo ball.
**Out of scope:** a saved `ballPosition` (it is kept as it is); the tuck, wake, ring, and throw (`specs/ball-edges.md`); any hint in the app itself.

Read `CLAUDE.md`, `specs/v0.3.md` §7 (the ball, R20), `specs/ball-edges.md`, `Locant/Launcher/FloatingBall.swift`, and the demo script in `site/index.html`.

This spec overrides `specs/v0.3.md` §7 and PRD §"Discoverability floor" on where the first launch places the ball: the right edge an eighth of the way down, not the lower right.

## 1. Requirements

**R102. First launch, app.** With no saved `ballPosition`, the ball fades in whole, `firstLaunchInset` (24 pt) in from the right edge of the main screen's `visibleFrame`, its center an eighth of the way down from the top of that frame (about 135 pt below the menu bar on a laptop). That keeps it below the menu bar's right-hand icons and notification banners, and close to where Malik keeps his. After the 2 s idle wait it tucks into the right edge at that height, as any rest does. `FloatingBall.firstLaunchOrigin(visibleFrame:)` is pure, and the call site passes the main screen's `visibleFrame`.

**R103. First spot, site.** The demo ball follows R102 on its desktop: whole, 24 pt in from the right edge of the stage, its center an eighth of the way down. That is above the iPhone window, over the sky, so the label (R104) has open wallpaper to its left instead of the phone's header, and the disc reads as a grey lens on light blue rather than vanishing into the dark rock. Until the ball has been found (R104) it stays out, whole, and does not tuck; afterwards it behaves as before (two seconds idle, then it tucks into the nearest edge). The line above the demo reads "Click the ball on the right edge. Hold it for more tools." ("Tap" on a touch screen).

**R104. The hint, site.** While the ball has not been found:
- **A label** sits to the left of the ball, centered on it, in the overlay's HUD glass (the `.hud` look: dark glass, a light hairline, 12 px text), with a short tail pointing at the ball: "Click to point" ("Tap to point" on a touch screen). It fades in just after the ball appears.
- **A pulse:** a thin light ring grows out of the disc to about twice its size and fades, once every 3 s. Under Reduce Motion there is no pulse; the label stays.
- **Found** is the first time the cursor wakes the ball (within 80 pt, the hand shows), or the first press, tap, or keyboard press on it. Both fade out then and do not come back during the visit.

## 2. Tests

- `FloatingBallTests`: on a visible frame with a menu bar and a Dock, `firstLaunchOrigin(visibleFrame:)` puts the disc's center 24 pt plus one radius in from the right edge and an eighth of the frame's height below its top; on a second frame with a non-zero origin, the same holds relative to that frame.
- The existing tests pass.
- Site, in a browser at 1440 pt and at phone width: the ball appears on the right edge an eighth of the way down with the label and the pulse, the label clear of the iPhone window; it does not tuck while they show; moving the cursor near it removes both, and two seconds after the cursor leaves it tucks into the right edge at that height; a tap on a phone removes both and starts Point; with Reduce Motion there is no pulse.
