# Locant: Settings say less

**Status:** Spec written Oct 19, 2026, after Malik said Settings had far too much text: small descriptions under nearly every row, footnotes, and status nobody acts on. Decided the same day, option B of three ("trim and regroup"): every setting stays; the words around them go, duplicates merge, and the help page and the menu bar menu get the same treatment. Numbered from R91 (`specs/ball-edges.md` ends at R90). Revised the same evening after Malik saw it built: the menu goes back to its old layout without Help (R97), the window gets one compact width and fits each tab's height (R101), and My Apps loses its inline bundle id field (R95).
**Scope of this spec:** the five Settings tabs and the Settings window's size, the help page, the menu bar menu, the update alerts, and the docs that name Settings rows.
**Out of scope:** stored preferences (no key added, removed, or renamed; no default changes); what any setting does; the overlay, the ring, the toasts and hints (already one line each); the two permission sentences at first launch; the Diagnostics block; the site and its Settings screenshots (a follow-up retakes them).

Read `CLAUDE.md`, `docs/PRD.md` §6.2–6.3 (the `settings.*` tokens), `Locant/App/SettingsView.swift`, `Locant/App/HelpView.swift`, and `Locant/App/LocantApp.swift`.

This spec overrides PRD §6.3's "each toggle that needs a sentence gets a `.footnote` description beneath it": no row has one now.

## 1. What is wrong today

- Every General row carries one to three lines of footnote-size text, and the other four tabs carry one or two footnotes of one to three sentences each. The words explain mechanisms the README already covers: the Developer ID, the MCP command line, Finder tags, the file each agent's configuration lives in.
- Status shows when nothing needs doing: two "Granted" rows, "Last checked 3 hours ago", and an orange warning on every agent that is simply not connected.
- Point appears twice under two names, "Capture hotkey" (⌃⌃) and "Point" (⌃⌥1), and needs a sentence to explain why.
- Every action hotkey shows a Clear button at rest.
- The capture folder is a greyed-out text field.
- The menu says "Capture" where every other surface says "Point".
- The help page repeats four settings and runs to 900 pt of footnote-size text.

## 2. Requirements

**R91. The rule.** A Settings row is a title and a control. No row has a line beneath it and no group ends in a footnote. Only four things add words: a missing permission (its row exists only then), a hotkey clash (one line under its row, as today), an agent connect or disconnect that failed (its error under the row, as today), and an empty My Apps list (one line saying what the list is for, R95). The one group header is Agents' "MCP" (R96). Titles use Apple's words; a button that acts at once has no ellipsis. The `Footnote` view is deleted.

**R92. General.** Five groups:
1. Permissions, only while a grant is missing, with no header: "Accessibility" and "Screen Recording", one row per missing grant, an orange exclamation and **Grant…** trailing. Still re-read every second, so the group leaves as soon as both are granted. The signature footnote goes; the README's Troubleshooting table has it.
2. **Floating ball**; **Auto-hide**, disabled while the ball is off.
3. **Sounds**; **Haptic feedback** (was "Trackpad taps"). Turning either on still previews its channel.
4. **Check for updates automatically** (was "Check for updates"); **Version** and the running version ("Version 0.9.2") with **Check Now** trailing ("Last checked …" goes); **Diagnostics** with **Copy** trailing, reading "Copied" for two seconds.
5. **Locant Help** with **Show** trailing. It stays in Settings: the menu bar menu is for what is used often (R97).

**R93. Hotkeys.** One group of five rows: Point, Snap, Text, Color, Cut. Point's row carries two recorders, the capture hotkey (Double-tap ⌃ by default) and Point's action hotkey (⌃⌥1); the others carry one. The "Capture hotkey" row, its description, and the footnote go.
- At rest a recorder shows its key and, only when that differs from the default, **Reset** before it, as today. **Clear** no longer shows at rest.
- While recording, the recorder reads "Press keys…", and for an action that may be left without a key and has one, **Clear** shows before it. ⌫ or ⌦ pressed alone clears it too. The capture hotkey always has a key, so for it they show the modifier hint as any bare key does. Esc cancels.
- Recorders are at least 120 pt wide (was 150), so Point's two and a Reset fit beside the title at the window's 480 pt width (R101).
- Clash lines stay under their row. They name the capture hotkey Point ("Already used for Point."), and the macOS one shortens to "Also a macOS shortcut; Locant takes it first."

**R94. Captures.** Three groups:
1. **Save to**: the folder's path with the home folder as `~`, in secondary text, truncated in the middle, and **Choose…** trailing; it replaces the disabled text field. **Organize** (was "Organize captures"): One folder, By app, By project, By month. **Keep captures** (was "Keep images"): 7 days, 30 days, 90 days, Forever.
2. **Adjust selection before capturing**; **Recapture when your app changes** (was "Collect iterations").
3. **Color format**; **Color space**.

Both footnotes go.

**R95. My Apps.** Two groups:
1. One row per app: its icon at 24 pt and its name, **Remove** trailing. An app that is not on this Mac shows its bundle id as its name, with the generic app icon. The bundle id line under installed apps and "Not on this Mac; matched by bundle id." go. An empty list is one line in secondary text, "Locant finds apps you build on its own. Add any it misses.", which replaces "No apps added" and the footnote.
2. One row, **Add an app**, with **Bundle ID…** and **Choose…** trailing. Bundle ID… opens an alert, "Add a Bundle ID", with one line ("For an app that runs only in the Simulator."), a field (prompt `com.example.app`), Cancel, and Add; a typed id is no longer a field in the tab. Both descriptions go.

**R96. Agents.** Three groups:
1. **Paste into your agent**. Its description and footnote go.
2. Under the header "MCP": Claude Code, Cursor, Codex. Trailing, by state: not connected, **Connect** alone, with no icon and no "Not connected"; connected, the green check, "Connected", and **Disconnect**; connected to another copy, the orange exclamation, "Connected to another copy", **Reconnect**, and **Disconnect**; working, the spinner and "Working…". The configuration-file line under each agent (`Agent.detail`, deleted) and the footnote go.
3. **Other agents** (was "Any other agent") with **Copy Config** trailing (was "Copy"), reading "Copied" for two seconds. Its description goes.

**R97. The menu bar menu.** It keeps the layout it had before this spec (R10, R44): **Point**, **Show before & after**; **Snap**, **Text**, **Color**, **Cut**; **Open capture folder**, **Settings…**; **Quit Locant**. "Capture" becomes "Point", still "Point (⌃⌃)" when its only hotkey is a double-tap; nothing else changes and nothing is added. The help page is rarely opened, so it stays in Settings (R92). A first version put the five actions together, used title case, and added Locant Help; Malik preferred the old, shorter menu.

**R98. The help page.** Same window, symbols, keys, and footer buttons (Settings…, Try it now). The line beneath each title is one short sentence:
- Top: "Point at anything." / "Locant hands your coding agent the element under your cursor, so it finds the right code."
- Point: Open the overlay, "Press the hotkey or click the ball."; Pick the element, "Click it, or drag a frame. ⌥ steps to the parent."; Say what should change, "Type a note, press Return, and paste into your agent."; Select more than one, "⇧-click to add elements, from any app."
- The other actions: Snap, "A window, element, or frame as an image."; Text, "The text in an element or frame."; Color, "The color under the cursor."; Cut, "The subject without its background."; The ring, "Hold the ball, release on an action."
- Your agent: Let your agent fetch captures, "Connect Claude Code, Cursor, or Codex.", **Agents…** trailing.

The rows that repeat Settings go: Keep the ball?, Change the hotkeys, Collect iterations, Keep images, Check for updates. The footer line reads "Open this again from Settings › General." The window takes the content's height instead of up to 900 pt, and still scrolls on a short display.

**R99. Alerts.** The update alert's text becomes "You have 0.9.2. Drag the new copy over the old one in Applications; your permissions carry over." The Developer ID clause goes. Check Now's answers: "Locant 0.9.2 is up to date." with no second line, and "Locant could not reach GitHub." / "Try again later." The first-launch permission sentences are unchanged.

**R100. Words elsewhere.** README, CONTRIBUTING, the bug and tester issue forms, and `docs/rc-checklist.md` name the new labels and places: Haptic feedback, Recapture when your app changes, Check Now, Settings › General › Diagnostics, Locant Help › Show, and no Granted rows. Code comments that quote a renamed label follow. CHANGELOG gains an Unreleased section with one bullet. The site's Settings screenshots are retaken in a follow-up.

**R101. One width, each tab as tall as its rows.** The window is 480 pt wide and the user does not resize it. Its height fits the open tab's rows when it opens and on every tab change (animated, as Apple's settings windows do), keeping the top edge in place; a tab taller than the screen scrolls. A restored frame of another width (Malik's was 900 pt) gives way to it. Added after Malik asked for a tighter, more compact default width.

## 3. Layout

| File | Change |
|---|---|
| `Locant/App/SettingsView.swift` | R91–R96, R101 |
| `Locant/App/HelpView.swift` | R98 |
| `Locant/App/LocantApp.swift` | R97, R101 (`windowResizability(.contentSize)`) |
| `Locant/App/AppState.swift` | R99; comments |
| `Locant/Capture/HotkeyConflicts.swift` | R93's clash wording |
| `Locant/MCP/AgentConfig.swift` | `Agent.detail` deleted |
| README, CONTRIBUTING, CHANGELOG, `.github/ISSUE_TEMPLATE/{bug,tester}.yml`, `docs/rc-checklist.md` | R100 |

No preference, model, or schema change.

## 4. Tests

- `HotkeyTests`: a clash with the capture hotkey reads "Already used for Point."; the macOS clash reads R93's sentence. The recorder's key handling moves into a pure `HotkeyRecorder.press`, tested in the same file: Esc cancels; ⌫ and ⌦ alone clear an action's key and ask for a modifier on the capture hotkey; with modifiers they are a chord; a bare key needs a modifier and a function key does not.
- Every existing test passes; the build is green.
- By hand, in both appearances: each Settings tab at its 480 pt width and fitted height, with no row on two lines and Point's two recorders on one row; recording an action's key, Clear while recording, ⌫ clearing, Esc cancelling, Reset after a change; the permission group with a grant missing; the menu in its new order; the help page from Locant Help; Check Now's alert.
