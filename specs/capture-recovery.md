# Locant: fix stuck screen capture from inside the app

**Status:** Spec written Oct 21, 2026, after every capture on Malik's Mac toasted "Capture failed", also after relaunching Locant. Permissions were fine. ScreenCaptureKit returned the windows but no displays, while the Mac had three (the built-in screen and two LG UltraFine 6K). The cause was replayd, the macOS process behind ScreenCaptureKit: it had run for two days, through a sleep and a monitor reconnect, and was hung (it ignored SIGTERM with no work pending). `killall -9 replayd` fixed it; launchd started a fresh replayd on the next capture, which returned all three displays. Decided the same day: Locant recognizes this case and offers the same fix in one click, in a standard alert. Numbered from R109 (`specs/simulator-project-root.md`, open in PR #66, holds R105–R108).
**Scope of this spec:** recognizing the stuck service, the alert, the restart, what happens after it, and a Debug switch to test it.
**Out of scope:** clearer words for other capture failures; logging; a timeout for a ScreenCaptureKit call that never returns (not seen yet); restarting replayd without asking.

Read `CLAUDE.md`, `specs/v0.1.md` R9 (failure feedback), `specs/v0.8.1.md` R60 (sounds), `Locant/Capture/ScreenCapture.swift`, `Locant/Model/CaptureError.swift`, and in `Locant/App/AppState.swift` the lock paths, `finishSet`, `runOneShot`, `commit`, `fail`, and `offerUpdate` (the alert pattern).

This spec overrides `specs/v0.1.md` R9 for this one case: a stuck service shows an alert, not the 1-second toast.

## 1. Requirements

**R109. Stuck, defined.** The capture service is stuck when `SCShareableContent` returns no displays while CoreGraphics' active display list (`CGGetActiveDisplayList`) has at least one. `ScreenCapture.crop` and `ScreenCapture.displayImage` then throw `ScreenCaptureFailure.serviceStuck`. With no active display either, they still throw `.noDisplay`. The test is pure: `ScreenCapture.isServiceStuck(captureDisplays:activeDisplays:)`. `CaptureError` gains `.captureServiceStuck`, with the message "macOS screen capture stopped responding". `AppState` maps `ScreenCaptureFailure.serviceStuck` to it, and maps every other error to `.captureFailed` as today.

**R110. Only when you capture.** The alert (R111) comes only from captures the user starts: Point (one element, a set, a drawn frame), Snap, Text, and Cut. Verify's after-image (R52) and the Color magnifier stay silent on any failure, as today.
- **Point** takes its crop at the click, but today a failure shows only after the note is typed and Enter is pressed, and the note is lost. On `.captureServiceStuck`, Point stops as soon as the crop fails, about 0.1 s after the click: the note field and the overlay close, nothing is written, and the alert shows. Any of a set's crops failing this way counts. Other crop failures keep today's behavior.
- **Snap, Text, Cut** show the alert in place of the toast.

**R111. The alert.** An `NSAlert`; Locant activates first, as the update alert does. Title "macOS screen capture stopped responding". Text "Locant can restart it. Any screen recording or sharing in progress will stop." Buttons: **Restart Screen Capture** (the default, Return) and **Not Now**. The `.missed` sound plays first, as for any failure (R60). The clipboard and the capture folder are left untouched (R9).

**R112. Restart.** Locant runs `/usr/bin/killall -9 replayd` with `Process`. The signal comes from `killall`, an Apple binary running as the user, so Locant needs no entitlement, and its hardened runtime does not apply. While Locant waits, a toast reading "Restarting screen capture…" stays up. Then it asks `SCShareableContent` again every 250 ms for up to 3 s, whatever `killall` returned. Asking is what makes launchd start a new replayd. Screen capture has recovered when an answer has at least one display. The decision is pure: `CaptureRecovery.outcome(displaysAfter:)` returns `.recovered` for one or more, `.restartMac` for none. replayd's name is not public API. If Apple renames it, `killall` finds nothing, the displays stay empty, and the user gets the R113 alert that says to restart the Mac.

**R113. After.**
- **Recovered:** Locant gives focus back to the app that was frontmost when the failed capture began (its context's source app). It waits up to 1 s for that app to be frontmost, shows the toast "Screen capture restarted" near the failed capture's spot, and begins the same action again (`beginAction` with the failed action). It must wait for focus, because `ContextCollector.collect` takes the frontmost app as the source, which would otherwise be Locant.
- **Still stuck:** a second alert, "Screen capture still isn't responding", with the text "Restart your Mac to fix it." and one button, OK.
- **Not Now:** nothing else happens. The next capture that hits the stuck service asks again.

**R114. A switch to test it.** In Debug builds only, the launch argument `-simulateStuckCapture once` or `-simulateStuckCapture always` makes `ScreenCapture` throw `.serviceStuck` without asking ScreenCaptureKit. `once` lasts until the first Restart Screen Capture; `always` lasts until quit. The R112 re-check obeys the switch too, so `once` recovers and `always` reaches the second alert. The real `killall` still runs. Release builds compile none of it.

**R115. Words elsewhere.** CHANGELOG gains an Unreleased section with one bullet.

## 2. Files

- New: `Locant/Capture/CaptureRecovery.swift` (`outcome(displaysAfter:)`, the restart, and the re-check) and `LocantTests/CaptureRecoveryTests.swift`.
- Changed: `ScreenCapture.swift` (R109, R114), `CaptureError.swift` (R109), `AppState.swift` (R110–R113), `CHANGELOG.md` (R115).

## 3. Tests

- `CaptureRecoveryTests`:
  - `isServiceStuck` is true only for no capture displays with at least one active display; it is false for no displays at all and whenever capture has any display.
  - `outcome(displaysAfter:)` is `.recovered` for 1 and 3, `.restartMac` for 0.
  - `CaptureError.captureServiceStuck.message` is "macOS screen capture stopped responding".
- The existing tests pass.
- In the app, a Debug build launched with `-simulateStuckCapture once`:
  - **Point an element in another app:** the alert appears before you can type, the note field and overlay are gone, the clipboard is unchanged, and no file is written.
  - **Restart Screen Capture:** replayd's PID changes, the restarting toast and then "Screen capture restarted" show, and Point opens again over the same app. That app, not Locant, is the source. Point at something, type a note, press Enter: a PNG and its JSON are written, and the clipboard holds the capture.
  - **The same for Snap,** which then puts its image on the clipboard.
  - **Not Now:** nothing is written, and the next Point asks again.
- With `-simulateStuckCapture always`:
  - Restart Screen Capture leads to the "still isn't responding" alert.
  - Neither Verify nor Color shows an alert.
