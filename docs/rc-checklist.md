# Running Locant on a Mac that is not the author's

specs/v0.9.md R75. Fifteen steps, in order, about twenty minutes. Each says what to look for. When you are done, the [tester form](https://github.com/Malik1942/locant/issues/new?template=tester.yml) takes the diagnostics block and which steps passed.

| # | Do | Look for |
|---|---|---|
| 1 | Download `Locant.dmg`, drag Locant to Applications, open it. Try it once with Wi-Fi off. | It opens with no "unidentified developer" or "cannot be verified" dialog, online or offline. A pointing hand appears in the menu bar; no Dock icon. |
| 2 | Click Continue on the two permission sentences; grant Accessibility, then Screen Recording. | System Settings opens on the right list each time. After Screen Recording, Locant offers to relaunch; after that, Settings › General shows both as granted. |
| 3 | Close the help page that opened. | Settings › General › Locant Help › Show… brings it back. |
| 4 | Double-tap ⌃ (Control) over a native app: Finder, Mail, System Settings. Hover, then click a button. | The screen dims, the outline follows the cursor, the label reads `role · identifier` or a label. A note field appears; type a word, press Return. A short note sounds, and `## Locant capture` is on the clipboard (paste into TextEdit). A PNG and a JSON are in `~/Pictures/Locant`. |
| 5 | If you have Xcode: run any app in the iOS Simulator, point at a button in it. | The label shows the identifier when the app declares one; the payload's `App:` line names the simulated app, and the mode is fix. |
| 6 | Point at a button on a web page in Chrome, Safari, or an Electron app (VS Code, Slack). | The label carries the DOM id or class; the payload records the page URL. The first hover over Electron may take half a second. |
| 7 | On the overlay, drag a frame around several controls instead of clicking. | The payload has `### Elements in frame` listing what was inside. |
| 8 | Hover a control, press ⌥ once, then again. | The outline steps to the parent, then the grandparent. |
| 9 | Hold ⇧ and click two elements, then press Return. | Both are outlined and numbered; the payload has Element 1 and Element 2. |
| 10 | Press ⌃⌥2 (Snap), click a window. Press ⌃⌥3 (Text), drag over some text. | Snap: a PNG lands in `~/Pictures/Locant`. Text: the recognized text is on the clipboard and nothing is on disk. |
| 11 | Press ⌃⌥4 (Color), click a pixel. Press ⌃⌥5 (Cut), click a window with a clear subject. | Color: a magnifier follows the cursor; the value (hex by default) is on the clipboard. Cut: a PNG with a transparent background. |
| 12 | Turn on the floating ball in Settings › General. Click it; then hold it half a second and release on Snap. | It rests at a screen edge, wakes as the cursor nears, starts Point on click, shows the four-way ring on hold. |
| 13 | Settings › Agents › Connect one agent you have (Claude Code, Cursor, or Codex), then ask it "what did I just point at". | The agent calls `latest_capture` and answers with the element and the image path. Disconnect afterwards if you like. |
| 14 | Settings › General › Check Now…, then Copy Diagnostics; paste it somewhere. | An alert says you are up to date or offers the newer version. The block has every line, and your user name does not appear in it. |
| 15 | Quit Locant from the menu, reopen it, then uninstall as the README says. | Nothing asks for permissions again. After uninstall, nothing of Locant is left in System Settings › Privacy & Security once the two `tccutil` lines have run. |

If a step fails, note the step number and what you saw; the tester form has a field for it. Steps 5 and 13 are optional when you have neither Xcode nor an agent.
