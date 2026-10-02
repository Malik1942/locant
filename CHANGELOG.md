# Changelog

Every release is a signed, notarized `Locant.dmg` on [GitHub Releases](https://github.com/Malik1942/locant/releases). Drag the new copy over the old one; the permissions carry over.

## Unreleased

- **A paste into an agent arrives whole.** The one clipboard item Return writes reached most agents in half: Cursor and Grok Bot kept the image and dropped the note and the identifier, Codex kept the text and dropped the image. Now, when you press ⌘V in the message box of Cursor, Codex, or Grok Bot, your own keystroke pastes the text and Locant adds the image right after; you choose where a capture goes by pasting it there. Your key is never held or replaced, the clipboard ends as Return left it, and `defaults write com.malikzhang.deixis completesPaste -bool NO` turns this off. Paste into your agent, still off by default, does the same after Return for the agent you used last, Grok Bot included: the text, then the image, into the message box and never into a code editor. Locant still never sends.
- **The ball rests at the bottom too.** Besides the left and right edges, it tucks into the bottom of the screen beside the Dock, never on or behind it, and far enough from the Dock's ends that reaching for them does not wake it. Where it tucks is its home: coming near brings it out right there, instead of back to wherever it was before. While you drag it toward an edge, a faint ghost shows where it will tuck; flick it at an edge and it flies there and tucks.

## 0.9.1 (2026-10-01)

- **Xcode 27.** The simulator now shows in Device Hub instead of Simulator.app. Pointing at an app there is fix mode again, and the payload names the device, the app, and its project; a physical device in Device Hub is reference mode. Snap and Cut on a simulated device open on its screen rather than the whole Device Hub window.
- A DerivedData folder that is a symlink no longer loses the Project line for simulator captures.
- **The Project line says what it is for.** Under `Project:`, the payload now says that folder built the app on screen, and that an agent working in a different checkout of the repo (another worktree or clone) should change the code there or ask which copy to change. Without it, agents in another worktree often found a look-alike in their own copy and changed that. In a 40-run test with the app on screen built from another worktree, Locant runs changed the wrong copy 0 times in 20 with this line, against 9 in 20 without it. The Locant skill follows the same rule.
- **The hover names what you see.** An app with a transparent window over the screen (Wispr Flow keeps one down the left side) no longer answers for what is under it: its menu bar or a button of its own hidden window used to stand in for the element, so a Simulator or Device Hub screen read "no element info" or the other app's control.
- **Option always moves the outline.** Containers that share one rectangle are one step: in the Simulator, Device Hub, and web pages, several presses used to leave the outline where it was.
- **Snap and Cut's top rung is the window** in apps whose content fills the whole window, such as Device Hub, and reads `window · Device Hub` instead of `group`.

## 0.9.0 (release candidate)

The version for feedback from Macs that are not the author's. No change to the capture flow, the payload, the schema, or the MCP server.

- **Option in Snap and Cut.** They still open on the window under the cursor. Option now picks the element under the cursor instead, the way Point does, and again its parent, up to the window; click or Return takes the outline exactly, a drag still takes a frame. Keeping a capture off disk moved from ⌥ to ⌘, on the overlay and on the ring.
- **A hover state survives.** Snap, Text, and Cut read the pixels before the overlay goes, so a lit button or a tooltip is what gets captured.
- **Copy Diagnostics** in Settings › General: version, macOS, chip, displays, the two permission grants, hotkeys, and settings as one block to paste into an issue. Your user name is replaced by `~`; nothing from any capture is included, and nothing is sent.
- **The app bundle is stapled**, not only the dmg, so a copy dragged out of the dmg opens without an online Gatekeeper lookup.
- **Homebrew**: `brew install Malik1942/locant/locant`. Each release also carries a versioned `Locant-<version>.dmg` for the cask.
- **CI**: every push and pull request builds and runs the tests on GitHub's macOS 26 runner.
- **Public-repo files**: this changelog, `CONTRIBUTING.md`, `SECURITY.md`, an Uninstall section in the README, and a tester form on GitHub with a checklist in `docs/rc-checklist.md`.
- **Updates stay manual and say so.** Locant tells you about a new version and opens the download; you drag it over the old copy. In-place update is a 1.0 decision.
- Tags are now the full version, `v0.9.0`; the update check reads both forms.

## 0.8.1 (2026-09-22)

- Paste into your agent, off by default. With the switch on in Settings › Agents, Return also brings forward the agent app you used last (Claude, Cursor, or Codex) and pastes the capture into its message field. It never sends: the paste waits where you can read, trim, or delete it. The note field shows where Return will paste; a newer capture or anything else written to the clipboard cancels a paste in flight.
- Trackpad taps. A light tap under your finger when the outline moves to a new element, when Option steps a level, when the ring opens and between its segments, and when a capture lands. At most one per 80 ms, never on a click. Needs a Force Touch trackpad. Settings › General.
- Sounds. A short, quiet note when a capture reaches the clipboard, a lower one when nothing did, each fired together with a tap of its own. They follow Play user interface sound effects in Sound settings. Settings › General, where each switch previews its own channel when turned on.
- Iterations. After-images move to the Trash, or stay, with the capture they document; a Shift set is armed for before & after, and a set that shares one image is compared whole.
- Feedback has somewhere to land: issue forms on GitHub for the app and for the site, and links to them from the site.

## 0.8.0 (2026-09-17)

- Web pages and Electron apps. A web element now carries its DOM id and class list, the path shows each ancestor's id or first class, and the page URL is recorded. A page on localhost counts as your own code. Works in Chromium browsers and Electron apps; Safari publishes the same attributes but has not been exercised.
- Select more than one element. Hold ⇧ and click to add elements to a set, from any app, each outlined and numbered. Return confirms the set, or click the last one without ⇧. The payload numbers them: Element 1 (this), Element 2 (that), and so on, each with its own app when it differs. One image when the set fits, otherwise one per element.
- The help page teaches the gesture, and a one-time hint appears the first time ⇧ is held over the overlay.

## 0.7.3 (2026-09-16)

- The help page has a Try it now button: it closes the page and opens the overlay, so the first capture happens in seconds. The page's rows are live: the floating ball, Collect iterations, Keep images, and Check for updates change right there, and Hotkeys… and Agents… open Settings on their tab.
- After the first Point capture, with no agent connected, a one-time hint says the agent can fetch the capture itself over MCP.
- Settings opens tall enough to show every row of the General tab.
- The menu bar menu shows each action's hotkey the way macOS does, grey and right-aligned.

## 0.7.2 (2026-09-15)

- The ring (press and hold on the ball) now reads over light pages. Over a white web page in Dark mode it opened as an empty disc; its symbols and labels were white on white. The ring now uses the regular glass, which tints itself against whatever is behind it.

## 0.7.1 (2026-09-15)

- Locant is its own MCP server: `Locant --mcp` speaks MCP over stdio and reads the sidecars in the capture folder. Settings › Agents connects Claude Code, Cursor, and Codex.

## 0.7.0 (2026-09-15)

- The first release under the new name. Locant was called Deixis until Sep 14, 2026. The bundle identifier stayed `com.malikzhang.deixis`, so the Accessibility and Screen Recording grants and the settings carried over. New captures go to `~/Pictures/Locant`; older captures stayed in `~/Pictures/Deixis`.

## 0.6.1 and 0.6.0 (2026-09-15)

- Built before the rename: the app inside `Deixis.dmg` is named Deixis. The daily release check, retention, and the first signed and notarized builds.

Earlier tags (`v0.1` to `v0.5`) were development milestones without a dmg; `specs/` holds what each one built.
