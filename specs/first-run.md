# Locant: the first five minutes

**Status:** Spec written Nov 3, 2026, before the Product Hunt launch (suggested for Tuesday, Nov 17). A visitor from Product Hunt gives a new app about a minute, so the first run has to be clean. The Nov 2 review left a "still standing" list, and four of its items are things a new user runs into in the first minutes. First, the ball tucks itself into the edge 2 s after the first launch, while Help (open by then) says to click it. Second, the menu bar menu hides ⌃⌃: it shows Point with ⌃⌥1, while Help shows ⌃⌃ and the README teaches ⌃⌃ first. Third, "Recapture when your app changes" is on by default and nothing explains it: the first sign of it is an "After #1 · …" toast over your app that you never asked for. Fourth, every failure is a 1 s "Capture failed" toast and nothing is logged, so a bug report from a stranger carries no reason. Numbered from R141. main ends at R136 (`specs/region-windows.md`). Open PR #78 holds R136–R139 in its branch, which clash with region-windows' R136; renumbered, they become R137–R140.
**Scope of this spec:** the ball on a first launch, the words that name Point's hotkeys, what explains recapturing, and what a failure leaves behind.
**Out of scope:** the rest of the Nov 2 list; PR #78; new words in the failure toast; turning Recapture off by default (one line, if Malik prefers it); key labels on non-US layouts; the site.

Read `CLAUDE.md`, `specs/ball-findable.md` (R102–R104), `specs/settings-cleanup.md` (R91, R93, R97, R98), `specs/v0.6.md` R52, `specs/v0.1.md` R9, `specs/capture-recovery.md` (R109–R113), and `specs/v0.9.md` R70 (Diagnostics).

This spec changes these earlier requirements. In `specs/ball-findable.md` R102, the ball no longer tucks after the 2 s wait on a first launch (R141). In `specs/settings-cleanup.md`, it changes R97's Point title and R98's first Point row (R142), and brings back a Help row about iterations, which R98 dropped because that row repeated Settings (R143). It adds a log line to `specs/v0.1.md` R9 and one line to `specs/v0.9.md` R70's Diagnostics block (R144).

## 1. Requirements

**R141. The ball waits to be found.** On a first launch (no saved `ballPosition`), the ball fades in whole at R102's spot and stays there, at rest, until it is found. It is found when the cursor wakes it (comes within 80 pt, `Tokens.approach`) or when it is pressed. From then on, the 2 s idle wait tucks it into the edge as any rest does (R87). Its first tuck saves its home, so the next launch is not a first launch. Until it is found, nothing tucks it: not the idle wait, not a display change, and not turning Auto-hide on. A launch with a saved `ballPosition` is unchanged. With Auto-hide off the ball never tucks, as before. The rule is pure: `FloatingBall.tucksWhenIdle(autoHide:state:dragging:found:)`. The app now does what the site's demo does (R103), without the demo's label and pulse.

**R142. One story for Point's keys.** Point has two hotkeys: the capture hotkey (double-tap Control, ⌃⌃, by default) and Point's action hotkey (⌃⌥1). Settings › Hotkeys shows both on Point's row (R93). Every place that names Point's keys names both, the capture hotkey first, and none of them hides one:
- **The menu bar menu.** The first of Point's keys that can be a key equivalent (a chord with a one-character key) becomes the item's key equivalent, grey and right-aligned like ⌘,. Every other key, a double-tap included, stays in the title. By default the item reads "Point (⌃⌃)" with ⌃⌥1 beside it. Before, it read "Point" with ⌃⌥1, and showed ⌃⌃ only when that was Point's only key (R97).
- **Help.** "Open the overlay" spells out the capture hotkey: "Double-tap Control, or click the ball." For a chord it reads, for example, "Press ⇧⌘D, or click the ball." The key column reads "⌃⌃ or ⌃⌥1". Before, it read "Press the hotkey or click the ball." beside ⌃⌃ (R98).
- **The README.** The first step of Use names both keys. The Hotkeys row says the same, in the same order.

When Point's action hotkey is cleared, it drops out everywhere, and a newly recorded key takes its place. The helpers are pure: `Hotkey.pointKeys(capture:action:)`, `Hotkey.pointMenuItem(_:)`, `Hotkey.names(_:)`, `Hotkey.spoken`, and `Hotkey.keyEquivalent`. The menu builds its `KeyboardShortcut` from `keyEquivalent`.

**R143. Recapture says what it does.** "Recapture when your app changes" (R52) stays on by default. A new user meets it in four places, and each now says what it does:
- **The first iteration Locant keeps.** The toast that would read "After #1 · summary" instead reads "Your app changed; Locant captured it again · Show before & after in the menu bar". It stays up 6 s (`hintLife`) and shows once per install (hint key `iteration`). Every later iteration shows "After #n · summary", as before.
- **Settings › Captures.** The switch gets a tooltip: "After you point at an app you build, Locant captures that element again whenever the app comes forward in the next day, and keeps the image if it changed." No line goes under the row (R91 holds).
- **Help.** "Your agent" gains a row, "Before & after": "Run your app after the agent's edit; Locant captures it again." It has no key. `HelpView.contentHeight` is measured again.
- **The README.** The Before & After bullet says the feature is on by default and where to turn it off.

The text is pure: `AutoVerify.iterationToast(index:summary:first:)`.

**R144. A failure says why.** Some failures show a toast or an alert: Point (one element, a set, or a drawn frame), Snap, Text, Cut, and Color's permission check (R9, R109–R113). Each of them logs one line, at error level, in the unified log, under subsystem `com.malikzhang.deixis` and category `capture`. The line says what failed and why, and both parts are public: "Snap failed: ScreenCaptureFailure.noDisplay". Recapture's failures (R52) log the same line at notice level and stay silent on screen.
- **The reason** is pure: `CaptureError.reason`.
  - A missing permission, a missing element, or the stuck service is said in words.
  - An error of Locant's own is named by its type and case (`ScreenCaptureFailure.cropOutsideImage`).
  - Cancellation reads `cancelled`.
  - Any other error is named by its domain and code, then its underlying error's ("NSCocoaErrorDomain 513 (NSPOSIXErrorDomain 13)").
  - An error's description and user info are never used, since they can name a file or a window.
- **Diagnostics.** Settings › General › Diagnostics gains one line after Captures: "Last failure:" with the newest failure since launch, its reason, and the time. With none, it reads "none since launch". It is kept in memory only.

The toast's words are unchanged. `Logger` comes from `os`, which `ScreenCapture.swift` already imports, so no framework is added. Nothing leaves the Mac.

**R145. Words elsewhere.** CHANGELOG Unreleased gains one bullet each for R141–R144. In the README: R142 changes Use step 1 and the Hotkeys row, R143 changes the Before & After bullet, and a new Troubleshooting row for "Capture failed" names Diagnostics' Last failure line and the `log show` command. The PRD, the site, and `docs/rc-checklist.md` need no change.

## 2. Files

- Changed: `Launcher/FloatingBall.swift` (R141), `Store/Preferences.swift` (R142), `App/LocantApp.swift` (R142), `App/HelpView.swift` (R142, R143), `App/SettingsView.swift` (R143), `Verify/AutoVerify.swift` (R143), `Model/CaptureError.swift` (R144), `Store/Diagnostics.swift` (R144), `App/AppState.swift` (R143, R144), `README.md` and `CHANGELOG.md` (R145).
- New: `LocantTests/CaptureErrorTests.swift` (R144).

## 3. Tests

- `FloatingBallTests` (R141): `tucksWhenIdle` is false on a first launch until the ball is found. Once it is found, it is true at rest with Auto-hide on. It is false while awake, ready, docked, or being dragged, and false with Auto-hide off.
- `HotkeyTests` (R142):
  - By default, Point's keys are ⌃⌃ then ⌃⌥1, the menu item is "Point (⌃⌃)" with ⌃⌥1 as its key equivalent, and Help's column reads "⌃⌃ or ⌃⌥1".
  - With Point's action hotkey cleared, the item is "Point (⌃⌃)" with no key equivalent.
  - With the capture hotkey a chord (⇧⌘D), the item is "Point (⌃⌥1)" with ⇧⌘D as its key equivalent.
  - A chord on a function key has no key equivalent and stays in the title.
  - `spoken` reads "Double-tap Control" and "Press ⇧⌘D".
- `AutoVerifyTests` (R143): the first iteration's toast is R143's sentence, and a later one reads "After #2 · …".
- `CaptureErrorTests` (R144):
  - Each permission and the stuck service give their words.
  - `ScreenCaptureFailure.noDisplay` gives its type and case, and cancellation gives `cancelled`.
  - A Cocoa write error gives its domain and code with the underlying POSIX error's, and contains no part of the path in its user info.
- `DiagnosticsTests` (R144): the block has the Last failure line in its place, and "none since launch" when there was none.
- The existing tests pass.
- In the app, by hand, on the release build before it ships. Export `com.malikzhang.deixis` first and restore it afterwards.
  - **First launch.** With `ballPosition` deleted: the ball fades in on the right edge and is still whole after Help opens and after 10 s of reading. Move the cursor onto it and away, and it tucks 2 s later. Relaunch: it starts tucked at that home.
  - **The menu** reads "Point (⌃⌃)" with ⌃⌥1 right-aligned. Help's first row reads "Double-tap Control, or click the ball." beside "⌃⌃ or ⌃⌥1".
  - **A failure.** Set Save to a folder you cannot write, then point and press Return. The toast reads "Capture failed", Diagnostics' Last failure names Point and a Cocoa error, and `log show --last 5m --predicate 'subsystem == "com.malikzhang.deixis"'` has the same line.
