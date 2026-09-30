# Locant: Product Requirements Document

**Status:** Living document. The specs in `specs/` are the record of what was built and when; where this PRD and a spec disagree, the spec wins.
**Owner:** Malik Zhang
**Platform:** macOS 15+, Apple silicon and Intel, Swift 6 + SwiftUI/AppKit; the MCP server is inside the app (`Locant --mcp`), no TypeScript

---

## One-line description

Locant is a native macOS tool that lets you point at any element in any app and hand a coding agent a precise, grep-able description of it, then shows you what the agent changed. Screenshot, OCR, color picking, and subject cutout are supporting tools around that loop.

The name is a term from chemical nomenclature: the locant is the number in a compound name that says exactly which position a group is attached to. A screenshot says roughly where; Locant says exactly which. See Appendix C.

**Positioning line:** Appshots gives your agent the window. Locant gives it the element.

---

## 1. Problem statement

Coding agents (Claude Code, Codex, Cursor, Xcode 27's agent) work through text and code, but UI polish starts as a visual observation: "this button is misaligned," "this card needs more padding." Today the designer-builder has to translate what they see into a file path and a description, or paste a screenshot and hope the agent guesses right.

People want control and precision over their intent; they do not want to spend time learning how to describe a button to a model. Pointing is how humans resolve this between each other.

Browser tools (Agentation, Stagewise, Cursor Design Mode) solve this for web apps by capturing CSS selectors when you click an element. Platform features (Codex Appshots, Claude Desktop quick entry) send a whole window to one specific agent. Agent-side tools (Peekaboo, Xcode 27 Device Hub, Microsoft's winapp CLI) let the agent read the accessibility tree itself. None of them lets a human point at one element in a native app and hand the result to any agent.

The cost is felt every time a SwiftUI builder iterates on UI with an agent: describe, wait, see the wrong file changed, redescribe. For a solo builder shipping multiple SwiftUI apps, that loop runs dozens of times a day.

## 2. Target user

**Primary (v1):** Malik. A product designer who builds native SwiftUI apps solo, uses Claude Code as the primary implementation tool, and reviews his own UI in the iOS Simulator and on Mac.

**Secondary (post-v1):** Designer-builders and indie Mac/iOS developers who use any coding agent and want to give feedback by pointing rather than describing. Not targeting teams, not targeting web-only developers (browser tools already serve them).

## 3. Goals

1. **Pointing replaces describing.** For UI changes in Malik's own apps, the agent modifies the correct view file on the first attempt in at least 8 of 10 captures where the target element exposes an accessibility identifier.
2. **One gesture, zero mode switching.** From hotkey to payload on the clipboard in under 3 seconds of user time, with no dialog and no window to dismiss.
3. **Works everywhere, degrades honestly.** The same gesture produces a useful payload on any app. When the accessibility tree is poor, the payload says so and falls back to image plus note rather than failing.
4. **Agent-agnostic output.** The payload works in Claude Code, Codex, Cursor, and Xcode 27's agent via clipboard, and via MCP wherever the agent supports it. No agent gets a private integration the others lack.
5. **The loop closes.** After the agent edits, Locant can show before and after for the pointed element alongside the code diff, without the user re-pointing.
6. **Lightweight by design.** Idle memory under 30 MB, no Dock icon, no accounts, no network calls, no telemetry.

## 4. Non-goals

- **Not window-level context.** Codex Appshots and Claude Desktop quick entry already send the front window to their own agent. Locant captures the element under the cursor and its crop, not the window.
- **Not a visual regression suite.** Chromatic, Percy, Playwright snapshots, and swift-snapshot-testing capture everything on every commit and fail CI on pixel diffs. Locant captures one element when a human pointed at it and shows the human the change; it never judges pass or fail.
- **Not a screen recorder, GIF tool, or scrolling-capture tool.** CleanShot X and a dozen open-source alternatives own this.
- **Not a cloud upload or share-link service.** Locant is local.
- **Not an annotation editor.** No arrows or shapes on images in v1. The payload is the annotation.
- **Not an asset library.** No browsing UI, no smart folders. Locant writes metadata (Finder tags, extended attributes) so Finder, Raycast, and Eagle can find captures.
- **Not a web DOM inspector.** For browser pages Locant uses the browser's accessibility tree, not the DOM.
- **Not an autonomous agent.** Locant never edits code and never talks to a model. It produces input for agents the user already runs.

## 5. User stories

Ordered by priority.

**Core: pointing at your own app**
- As a SwiftUI builder, I want to press a hotkey, click a button in the iOS Simulator, type "make this rounded," and paste into Claude Code, so that the agent edits the exact view without me naming the file.
- As a SwiftUI builder, I want the payload to include the element's accessibility identifier, role, label, frame, and ancestry, so that the agent can grep for it.
- As a SwiftUI builder, I want to know immediately when the element under my cursor has no identifier, so that I can add one in code instead of getting a vague payload.
- As a SwiftUI builder, I want to drag a region instead of clicking one element, so that I can point at a layout problem that spans several views.

**Core: the agent fetches it**
- As a Claude Code or Cursor user, I want to say "fix what I just pointed at" and have the agent pull the capture itself over MCP, so that I never paste anything.
- As a Codex user, I want the same MCP tool to give me the image path and structured text, so that Codex can read the image with its own viewer even though it cannot consume MCP image blocks reliably.

**Core: seeing what changed**
- As a SwiftUI builder, after the agent edits and the app rebuilds, I want Locant to re-capture the same element by identifier and show me before and after next to the git diff, so that I can judge the change without re-pointing.
- As a SwiftUI builder, when the agent makes three passes, I want the three afters chained under my original capture, so that I can see the iteration, not just the endpoint.

**Core: pointing at someone else's app**
- As a designer, I want to capture an element or region of any app (Figma, Safari, a competitor's Mac app) with its text recognized, so that I can paste "make mine like this" with the reference intact.
- As a designer, I want the payload to record which app and window the capture came from, so that when I find it a week later I know what I was looking at.

**One-shot actions (things you grab and move on)**
- As a builder, I want a normal screenshot (Snap) that lands in a folder and expires after 30 days, and a clipboard-only variant when I know I will paste it right away, so that nothing piles up on the Desktop.
- As a designer, I want to pull recognized text (Text) out of any region and have it on the clipboard without a file.
- As a designer, I want to pick a color (Color) from anywhere on screen in the format I last used.
- As a designer, I want to cut a subject (Cut) out of the screen with a transparent background and drag it into Figma.

**Entry points**
- As a trackpad user, I want an optional floating ball that is nearly invisible at rest, wakes as my cursor approaches, starts Point on click, and opens a four-way ring on press-and-hold.
- As a keyboard user, I want to keep the ball off and use hotkeys only.
- As a Raycast user, I want to trigger each Locant action from Raycast.

**Edge cases**
- As a user, when resolution, OCR, or cutout produces nothing, I want a short visible failure signal and an unchanged clipboard.
- As a user, when the front app is Electron or draws its own UI and exposes no accessibility tree, I want the payload to say so and still include the image and my note.

## 6. Design language

Locant has almost no interface, only moments. Of its eleven surfaces, eight live for a few seconds, two are always present but tiny, and only Settings and the before/after panel are conventional windows. The visual language is therefore specified as "what one appearance should feel like," not as pages.

### 6.0 Feel in one sentence
**A system-level transient.** Locant should feel like something macOS grew, in the family of the ⌘⇧4 crosshair, Live Text's selection, and Spotlight: it appears, is used, and is gone. The user should feel "the system has a new gesture," never "I opened an app." From Oryne it borrows quietness; from macOS it borrows nativeness.

### 6.1 Principles
1. **Borrow, don't brand.** System accent color, SF Pro, system materials, system cursors. No logo color, no custom font, no drawn window chrome. The only Locant-specific mark is the pointing-hand glyph.
2. **Nothing lingers.** Every capture surface dismisses itself. No panel stays open waiting for the user; confirmation is one second, then gone.
3. **Quiet until approached.** Rest states are nearly invisible (the ball, the menu bar glyph). Proximity and intent reveal detail. The only permitted rest motion is the ball's slow glow; nothing pulses at notification speed, badges, or bounces to get attention.

### 6.2 Tokens (map to system constants; agents use these names directly)

| Token | Value | Use |
|---|---|---|
| `dim` | `NSColor.black` at 20 percent | overlay backdrop over the frozen frame |
| `highlight.stroke` | `NSColor.controlAccentColor`, 2 pt | element outline |
| `highlight.radius` | element's own corner radius when known, else 6 pt | outline corners |
| `highlight.fallback` | `NSColor.secondaryLabelColor`, 2 pt dashed | no-element state |
| `label.bg` | `.hudWindow` material, 6 pt radius | element label, note field, toast |
| `label.text` | `NSColor.labelColor` | primary text on hud material |
| `label.mono` | SF Mono 11 pt | identifiers and paths only |
| `label.sans` | SF Pro 12 pt | everything else in overlays |
| `field.width` | max(element width, 320 pt) | note field |
| `space.s / m / l` | 4 / 8 / 12 pt | padding and gaps inside hud elements |
| `motion.reveal` | 200 ms, ease-out | anything appearing |
| `motion.dismiss` | 120 ms, ease-in | anything disappearing |
| `motion.hover` | 80 ms | highlight moving between elements |
| `toast.life` | 1000 ms | confirmation and failure toasts |
| `ball.rest` | 28 pt disc on `.hudWindow` material, fill `labelColor` 10 percent, 1 px `separatorColor` edge, no shadow | floating ball at rest |
| `ball.glow` | fill drifts 8 → 14 → 8 percent over 6 s, ease-in-out, continuous; off under Reduce Motion | the only motion at rest; slow enough to read as light, not as a pulse |
| `ball.docked` | half-disc, fill 6 percent, glow continues | edge-docked ball |
| `settings.window` | 520 pt wide, height to content, not resizable | Settings scene |
| `settings.padding` | 20 pt window inset; 8 pt between rows; 24 pt between groups | matches System Settings |
| `settings.group` | grouped `Form` rows on `controlBackgroundColor`, 10 pt corner radius, 1 px `separatorColor` hairline between rows | System Settings row look |
| `settings.type` | `.body` for labels and values, `.footnote` in `secondaryLabelColor` for descriptions under a row | Dynamic Type via `NSFont.preferredFont(forTextStyle:)` |
| `settings.controls` | `Toggle` (switch style), `Picker` (menu style), `TextField` (rounded border), `Button` (bordered) | system controls only, default sizes |
| `settings.tabs` | `TabView` inside the `Settings` scene, SF Symbol per tab | toolbar-style tabs like System Settings |

Dark and light appearance come free from the system constants; no second palette is designed.

### 6.3 Surface specs

**Overlay (Point, v0.1).** Frozen frame under `dim`. Cursor becomes the pointing hand. The hovered element gets `highlight.stroke` with `highlight.radius`, no fill. A label on `label.bg` sits 8 pt below the element (above it when within 40 pt of the screen bottom) reading `role · identifier` with the identifier in `label.mono`; the label follows the highlight with `motion.hover`. No toolbar, no instructions, no branding anywhere on the overlay. Esc dismisses with `motion.dismiss`.

**Note field (v0.1).** Appears on click, anchored to the element's bottom edge, `field.width`, on `label.bg`, `label.sans`, placeholder "What should change?" (the product's voice; never reworded). A right-aligned hint in `secondaryLabelColor` reads `↩ copy · esc skip`. The highlight stays while the field is open.

**Toast (v0.1).** A pill on `label.bg` near where the element was, never in a screen corner. Success: `Copied · captureButton` with the identifier in mono. Failure: the error's one-line message. Lives `toast.life`, then `motion.dismiss`. Feels like macOS's own transient feedback, not a notification banner.

**No-element state (v0.1).** Same overlay, `highlight.fallback` around the approximate region, label reads `no element info · image only`. Honest, not broken.

**Menu bar (v0.1).** `hand.point.up.left` as an 18×18 template image. Standard `NSMenu`, no custom views, no icons on items.

**Permissions (v0.1).** The two system prompts appear as macOS presents them. Before each, one sentence in a standard alert explains why: Screen Recording captures the element; Accessibility reads what is under your cursor; nothing leaves the machine.

**Floating ball and ring (v0.3).** As specified in P1.11. The ring's segments use `label.bg`, outline SF Symbols, `label.sans` labels; the center is the filled hand.

**Color magnifier (v0.3).** 150×150 pt panel on `label.bg`, 15×15 native pixels at 10x, 1 px `separatorColor` grid, the center pixel outlined with `highlight.stroke`, current value in `label.mono` beneath. Follows the cursor with no smoothing.

**Cut instance picker (v0.3).** Each detected instance gets `highlight.stroke` at 60 percent; the hovered one at 100 percent; click selects, Enter accepts all. No masks are drawn as fills.

**Text selection layer (v0.3).** Recognized lines drawn as selectable regions with the system text-selection color; behaves like Live Text.

**Settings (v0.3).** The one place Locant is a window, so it must be indistinguishable from an Apple app's preferences. A SwiftUI `Settings` scene with `TabView`; `Form` with `.formStyle(.grouped)`; `settings.*` tokens throughout; no custom drawing, no custom colors, no header art or app name. Two tabs: **General** (`gearshape`: hotkeys per action, capture folder with a Choose… button, retention picker 7 / 30 / 90 days / never, floating ball toggle, URL scheme toggle) and **My Apps** (`app.badge.checkmark`: the bundle ids that count as fix mode, one grouped row per app with a Remove button, and a group that adds one by choosing an .app or typing an id). Each toggle that needs a sentence gets a `.footnote` description beneath it, the way System Settings does. Nothing in Settings is required for first use; a fresh install works with every default.

**Before/after panel (v0.4).** A single standard window, two images side by side with a shared zoom, the diff stat and file list in `label.mono` beneath, the original note above. No timeline, no gallery, no annotations.

### 6.4 Native fidelity check
Two surfaces prove the language: the overlay must feel like a system gesture, and Settings must feel like an Apple preferences window. A quick test for each: put a Locant screenshot next to ⌘⇧5's toolbar and next to System Settings > Desktop & Dock; if either Locant surface looks like it came from a different vendor, fix it before shipping that version. Reference: Apple Human Interface Guidelines for macOS (Settings, Menus, Materials).

### 6.5 What the language forbids
Custom window chrome, brand colors, drop shadows on overlays, animated icons, onboarding tours, empty-state illustrations, badges, and any element that waits for the user.

## 7. Requirements

### 7.1 P0: the pointing flow (v0.1, the 3-hour build)

**P0.1 Hotkey.** Double-tap Control (350 ms window) opens the selection overlay. Chosen to avoid Codex's ⌘⌘ and Claude Desktop's ⌥⌥. Configurable later.

**P0.2 Selection overlay.** Full-screen transparent `NSPanel` per display showing a frozen frame from ScreenCaptureKit, with Locant's own windows excluded via `SCContentFilter`. Hover highlights the accessibility element under the cursor. Click captures it. Esc cancels with no side effects.
- Acceptance: overlay appears within 150 ms; Locant never appears in its own capture.

**P0.3 Context at trigger time.** Front app bundle ID and name, window title, Safari/Chrome tab URL, Simulator device and app bundle ID where obtainable. Collected before the overlay appears.

**P0.4 Element resolution.** `AXUIElementCopyElementAtPosition` at the click point. Read role, subrole, title, description, value, identifier, frame; walk up to 6 ancestors. Map to a platform-neutral `element` object (see 9.2). All AX work off the main thread.
- Acceptance: a SwiftUI Button with `.accessibilityIdentifier("saveButton")` in Simulator yields `identifier=saveButton`, `role=button`, a frame in screen points, and an ancestry path.
- Acceptance: an app with no accessibility tree yields `element: null` and the payload says so.

**P0.5 Mode.** `fix` when the front app is Simulator, in the user's "my apps" list, or the URL host is localhost; else `reference`. Affects payload wording and order only.

**P0.6 Crop.** The PNG is the element's frame plus 8 pt padding, not the window.

**P0.7 Note.** Single-line inline field under the element. Enter confirms; Esc skips the note but keeps the capture.

**P0.8 Payload.** One `NSPasteboardItem` with PNG and Markdown. The Markdown's first line after the heading is `Image: <absolute path>` because terminal agents receive only the text representation on paste and read the PNG from disk.

```
## Locant capture (fix)
Image: /Users/malik/Pictures/Locant/locant-moti-20260912-140312.png
App: Simulator (com.malikzhang.moti) · Window: iPhone 17 Pro
Captured: 2026-09-12 14:03 · Element region: 320×88 pt @2x

### Target element
button "Save" · id=saveButton
Frame: x=312 y=88 w=64 h=32
Path: navigationBar > group > button#saveButton

### Note
make this rounded, match the other pill buttons
```

**P0.9 Storage.** PNG plus a JSON sidecar conforming to `schema/capture.schema.json` in `~/Pictures/Locant/`. The sidecar is the contract for the MCP server and the verify feature; the app never needs to change for either.

**P0.10 Failure feedback.** Typed `CaptureError`. Permission errors open System Settings once. Capture failure shows a 1-second toast and leaves clipboard and disk untouched.

### 7.2 P1: MCP server (v0.2)

**P1.1 Package.** `locant-mcp`, TypeScript, `@modelcontextprotocol/sdk`, stdio transport, installed with `npx locant-mcp`. Reads the JSON sidecars; no HTTP server, no watcher, no state.

**P1.2 Tools.**
- `list_captures(unresolved_only?: boolean)` → id, createdAt, mode, app, note summary
- `get_capture(id, include_image?: boolean = false)` → full JSON as text, plus the absolute image path. When `include_image` is true, also an MCP image content block.
- `resolve_capture(id)` → sets `resolved: true`

**P1.3 Compatibility rules** (from testing of each agent's MCP image handling, Sep 2026):
- Primary return is always text plus path. Claude Code and Cursor consume image blocks; Codex does not reliably (two open issues), Gemini/Antigravity unconfirmed.
- Never return `structuredContent` together with an image block (Codex drops `content[]` when both are present).
- README carries an agent compatibility table with the date each row was tested.

**P1.4 Config.** One `.mcp.json` / `mcp.json` / `config.toml` snippet each for Claude Code, Cursor, Codex, documented in README.

### 7.3 P1: the action set and the entry points (v0.3)

The v0.3 surface is one primary action plus four one-shot actions, organized by **what you are about to paste**, not by feature name. The rule that decides file behavior is one sentence: **actions that produce an image keep a file for 30 days; actions that produce text or a value keep nothing.**

| Action | You paste | Trigger | Clipboard | Disk |
|---|---|---|---|---|
| **Point** (primary) | element reference + crop + note | ⌃⌃, ball click, `locant://capture` | yes | yes, 30 days; captures the agent resolved or the user pinned are kept |
| **Snap** | an image | ring ↑, hotkey | yes | yes, 30 days. Hold ⌥: clipboard only, no file |
| **Text** | recognized text (OCR) | ring →, hotkey | yes | no (text is also written as an xattr on any Snap it came from) |
| **Color** | a color value | ring ↓, hotkey | yes | no; last 10 colors in memory |
| **Cut** | an image with transparent background | ring ←, hotkey | yes | yes, 30 days. Hold ⌥: clipboard only |

Point is the only action that leaves a record the agent and Verify can return to. The four ring actions are things you grab and move on.

**P1.5 Snap.** Region or window capture from the frozen frame; ⌥ suppresses the file. This is the "normal screenshot" replacement: same speed as ⌘⇧4, but files go to the Locant folder and expire instead of piling up on the Desktop.

**P1.6 Text (OCR).** `VNRecognizeTextRequest`, `.accurate`, zh-Hans and en-US, language correction off for code editors, reading order rebuilt by line geometry. A second hotkey keeps the overlay and makes each recognized line drag-selectable.

**P1.7 Color.** Own magnifier (15×15 native pixels at 10x, pixel grid, arrow-key nudge), sRGB conversion with a Display P3 option, formats hex / rgb / hsl / SwiftUI Color / nearest Tailwind, remembers last format. Magnifier and ball are excluded from sampling.

**P1.8 Cut.** `VNGenerateForegroundInstanceMaskRequest` with instance picking; flood-fill fallback for flat UI; PNG with alpha. Saved by default because cutouts are usually dragged into Figma rather than pasted.

**P1.9 Drag selection for Point.** Hold ⇧ while pointing to drag a region; every element at least 50 percent inside is included, capped at 12.

**P1.10 Lifecycle.** Daily cleanup moves image files older than N days (default 30) to Trash unless pinned via extended attribute. Pin-last available from the menu bar and `locant://pin-last`.

**P1.11 Floating ball.** Optional second entry point, off by default (the hotkey is the default). Its design principle is borrowed from Oryne's orbs, not copied: quiet at rest, present when approached. The ball and Oryne's orb should read as relatives, not twins.

*Rest state.* A 28 pt translucent disc, no icon, no shadow: `ball.rest` on system material so it takes on whatever is behind it and follows light and dark appearance automatically. Its only motion is `ball.glow`, a six-second drift in luminance so slow it reads as the disc catching light rather than as an animation; it is disabled under Reduce Motion. After 5 seconds without interaction it slides to the nearest screen edge and shows as `ball.docked`, a faint half-disc that is a bump on the edge rather than an object on the desktop. Position is remembered across Spaces and launches. The disc should sit in the same family as Oryne's orbs: quiet, luminous, native to its surface, not a copy of them.

*Proximity states* (distance-driven, not hover-driven, so the target is ready before the cursor arrives):

| Cursor | State | Change |
|---|---|---|
| farther than 80 pt | rest | as above |
| within 80 pt | awake | opacity to 100 percent in 200 ms, `hand.point.up.left` fades in at center, an edge-docked ball slides back out |
| over the ball | ready | edge turns system accent color, cursor becomes the pointing hand |
| click | Point | starts the primary action directly, no ring |
| press and hold 300 ms | ring | four segments unfold from the disc; the disc becomes the ring's center |

*Ring.* Four segments at the cardinal directions (Snap ↑, Text →, Color ↓, Cut ←), release over a segment to choose, release at center to cancel. 90 degrees per target makes mis-selection rare and the gesture learnable without looking. Segment icons are SF Symbols in outline; the center is the filled pointing hand, the one visual rule that separates the primary action from the one-shot ones. One-word labels fade in below each icon 200 ms after the ring opens; holding ⌥ appends a small ⌥ to Snap and Cut to signal clipboard-only. Hover-to-expand is explicitly rejected: it collides with edge docking and causes accidental opens.

*Discoverability floor.* First launch places the ball near the lower-right edge with a single 800 ms fade-in. The menu bar icon is always at normal visibility; the ball is the quiet entry, the menu bar is the reliable one.

*Icons.* Menu bar and ring center: `hand.point.up.left` (template, 18×18). Snap: `camera.viewfinder`. Text: `text.viewfinder` (Apple's own Live Text glyph). Color: `eyedropper`. Cut: `person.and.background.dotted` (fallback `scissors`). Verify symbol names against the installed SF Symbols release.

**P1.12 URL scheme and Raycast.** `locant://capture`, `locant://snap`, `locant://text`, `locant://color`, `locant://cut`, `locant://pin-last`. Off by default. Thin Raycast extension calling these.

**P1.13 Settings.** Hotkeys per action, capture folder, retention days, "my apps" list, ball on/off, URL scheme on/off.

**Menu bar.** Capture ⌃⌃, Snap, Text, Color, Cut, Pin last capture, Open capture folder, Settings, Quit. Settings, pin, and folder live here on purpose; they are not ring material.

### 7.4 P2: Verify (v0.4)

The third act: point → fix → see what changed.

**P2.1 Trigger.** After a fix-mode capture, Locant arms a one-shot listener for "the app was rebuilt." Trigger sources, in order of preference: Xcode build-succeeded notification, git `post-commit` hook installed by Locant in the project, Claude Code `Stop` hook. The user can also trigger manually ("Capture after" in the menu).

**P2.2 Re-find.** Locant locates the same element by `source.app` plus `element.identifier` (fallback: role plus label plus nearest frame) in the rebuilt app, retrying every 500 ms for up to 5 seconds while the UI comes up. Anchoring by identifier, not by pixel position, is what makes this work when the element moves.

**P2.3 Iteration record.** Each after is stored as an `iteration` under the original capture: after-image path, git SHA before and after, `git diff --stat` between them, and the list of files touched. A capture can hold many iterations.

**P2.4 View.** A single before/after panel (slider or side by side), the diff stat, the files list, and the original note. Reachable from the menu bar and from `get_capture` over MCP (iterations are included in the JSON). No timeline browser, no gallery.

**P2.5 No judgment.** No pixel-diff threshold, no pass/fail, no alerts. The human decides.

- Acceptance: point at `saveButton`, note "make this rounded", agent edits, app rebuilds, Locant shows the button before and after with "1 file changed" and the file name, without the user pointing again.
- Acceptance: three consecutive agent edits produce three iterations under one capture.
- Blocking spike before P2 starts: confirm the rebuilt Simulator app exposes the same identifier within 5 seconds and that at least one trigger source fires reliably.

### 7.5 Future considerations (P3)

- AX quality scoring per app, stored locally, to warn before capture.
- Structured document OCR via `RecognizeDocumentsRequest` (macOS 26).
- Two-color contrast picking (WCAG and APCA).
- **Web, native.** Two steps. First, zero-install: Safari and Chrome expose the DOM through the accessibility tree, so Point already returns role, label, and frame for page elements plus the tab URL; enough for reference mode. Second, an optional companion browser extension that, when Point lands in a browser, returns the element's CSS selector, tag, classes, id, and key computed styles over native messaging, upgrading the payload to Agentation-level precision on any page, without installing anything into the project. The schema gains an optional `web: { selector, tag, classes, id, computedStyles }` field; the MCP server does not change. Locant on the web stays the same sentence: point at an element, give the agent a reference. No DOM export, no "copy as component."
- Windows port. The element schema is already platform-neutral because Windows UI Automation exposes the same concepts; the MCP server would be shared.
- Reuse Peekaboo's `see` for AX parsing if its output proves richer than `ElementResolver` at low cost.

## 8. Success metrics

Measured on Malik's own usage for 30 days after v0.3, revisited if released.

**Leading**
- Captures per working day: 15 or more (replaces the built-in screenshot tool).
- First-attempt correct-file rate for fix-mode captures: 80 percent, tallied by hand.
- Median trigger-to-clipboard time: under 3 seconds of user time.
- Share of fix-mode captures that get at least one verify iteration (after v0.4): tracked, no target.

**Lagging**
- Built-in macOS screenshot hotkeys stay remapped to Locant.
- Zero screenshot files on the Desktop at day 30.
- If released: GitHub stars and release download counts are reported, not success criteria.

## 9. Technical notes and constraints

### 9.1 Frameworks and constraints
ScreenCaptureKit, Vision, Accessibility API, AppKit NSPanel, SwiftUI for Settings. Swift 6 with strict concurrency complete. No third-party dependencies in the app. Permissions: Screen Recording and Accessibility, both signature-bound; use a stable signing identity in development. Distribution: signed and notarized dmg via GitHub Releases, Homebrew cask later, not the Mac App Store.

### 9.2 Contract: `schema/capture.schema.json` (v1)
```json
{
  "schemaVersion": 1,
  "id": "20260912-140312",
  "createdAt": "2026-09-12T14:03:12-07:00",
  "mode": "fix",
  "image": { "path": "...png", "widthPt": 320, "heightPt": 88, "scale": 2 },
  "source": {
    "app": { "bundleId": "com.apple.iphonesimulator", "name": "Simulator" },
    "window": { "title": "iPhone 17 Pro" },
    "url": null,
    "simulator": { "device": "iPhone 17 Pro", "appBundleId": "com.malikzhang.moti" }
  },
  "element": {
    "role": "button", "rawRole": "AXButton", "label": "Save", "identifier": "saveButton", "value": null,
    "frame": { "x": 312, "y": 88, "w": 64, "h": 32 },
    "path": [ { "role": "navigationBar", "identifier": null }, { "role": "group", "identifier": null }, { "role": "button", "identifier": "saveButton" } ]
  },
  "note": "make this rounded",
  "ocr": null,
  "iterations": [],
  "resolved": false
}
```
Role names are lowercase and platform-neutral (`button`, `textField`, `staticText`, `image`, `group`, `navigationBar`, `unknown`); the raw platform role is kept in `rawRole`. `iterations` entries (v0.4): `{ "capturedAt", "imagePath", "gitBefore", "gitAfter", "diffStat", "files": [] }`.

### 9.3 Module boundaries
```
Locant/      Swift app
  Capture/   HotkeyMonitor, SelectionOverlay, FrozenFrame, ContextCollector
  Resolve/   ElementResolver (pure, tested), ModeClassifier
  Modules/   Screenshot, OCR, ColorPicker, Cutout   (protocol CaptureModule)
  Payload/   MarkdownBuilder (pure, tested), PasteboardWriter
  Store/     FileStore, Lifecycle, Xattr
  Verify/    RebuildTrigger, ElementRefinder, IterationStore, BeforeAfterPanel
  Launcher/  FloatingBall, URLScheme
mcp/         TypeScript, three tools, one store.ts, types generated from schema/
schema/      capture.schema.json, the only interface between app and mcp
```
The app and the MCP server communicate only through files on disk. Neither knows the other is running.

### 9.4 Known limitation to state in the README
Element data quality depends on the target app's accessibility implementation. SwiftUI and AppKit apps and the iOS Simulator work well. Electron apps, Figma, games, and custom-drawn UIs often expose little; Locant falls back to image plus note there.

## 10. Open questions

**Blocking**
- (Engineering, v0.1) Does `AXUIElementCopyElementAtPosition` reach the iOS Simulator's tree on macOS 15 and 26? 30-minute spike, hard stop; fallback demo target is a native AppKit window.
- (Engineering, v0.4) Which rebuild trigger fires reliably: Xcode notification, git post-commit, or Claude Code `Stop`? Spike before P2.

**Non-blocking**
- (Design) Ball on or off by default at first launch? Current answer: off.
- (Engineering) Cleanup via LaunchAgent or only while the app runs?
- (Product) Register `locant.app` or `locant.dev` before public release. Name check as of Sep 14, 2026: no software product with the exact name on the app stores, GitHub, Product Hunt, or general web search. The earlier name was dropped that day because three unrelated products in the same space already used it; see Appendix C.

## 11. Phasing

| Tag | Content | Story beat |
|---|---|---|
| **v0.1** (3 hours) | P0.1 to P0.10: hotkey, click element, payload, clipboard, JSON sidecar | "Point, capture, paste." |
| **v0.2** | P1.1 to P1.4: MCP server, agent compatibility table, signed dmg, README, website | "The agent fetches it." |
| **v0.3** | P1.5 to P1.13: Snap, Text, Color, Cut, drag, lifecycle, floating ball with ring, URL scheme, Settings | "It replaced my screenshot tool." |
| **v0.4** | P2.1 to P2.5: verify, before/after, iterations | "And I see what changed." |

Public launch (site, X, LinkedIn, download count) after v0.2. Palantir submission uses v0.1 as the 3-hour artifact and whatever tag exists at submission time as the download. Video narrative: "The first three hours got me to v0.1. I liked it enough to keep going."

---

## Appendix A: Competitive context (as of September 12, 2026)

| Tool | Who triggers | Granularity | Note | Output goes to | Platform |
|---|---|---|---|---|---|
| Codex Appshots (May 2026) | Human (⌘⌘) | Window + AX text incl. offscreen | No | Codex only | Any Mac app |
| Claude Desktop quick entry (Oct 2025) | Human (⌥⌥) | Region or window | Yes (chat message) | Claude chat only | Any Mac app |
| EYHN/appshots (OSS) | Human (⌥⌥) | Window | No | Clipboard | Any Mac app |
| Agentation | Human (click) | Element (CSS selector, React fiber) | Yes | Clipboard, MCP, Claude Code hook | Localhost web only |
| Stagewise (YC S25) | Human (click) | Element (DOM) | Yes | Its own agent | Localhost web only |
| Cursor Design Mode | Human (click, drag) | Element (DOM) | Yes | Cursor only | Browser-rendered UI |
| Peekaboo (Swift, MCP) | Agent | Element (AX tree) | No | MCP, CLI | Any Mac app |
| Xcode 27 Device Hub + agent | Agent | Element (AX tree) | No | Xcode, mcpbridge | Simulator, device |
| Microsoft winapp `ui` (Apr 2026) | Agent | Element (UI Automation) | No | CLI | Any Windows app |
| Windows-Use, CliGate, ScreenHand, agent-aid | Agent | Element (UIA / AX) | No | MCP, Python | Windows, some macOS |
| Chromatic, Percy, swift-snapshot-testing | CI | Everything | No | Test report | Web, iOS tests |
| CleanShot X, Shottr, Snapzy, macshot | Human | Pixels | No | Clipboard, file | Any Mac app |
| **Locant** | **Human (click)** | **Element (AX), platform-neutral schema** | **Yes** | **Clipboard + MCP, any agent** | **Any Mac app, Simulator** |

The empty cell across platforms: human-triggered, element-level, with a note, agent-agnostic, native. Web has Agentation and Stagewise; macOS, Windows, and Linux have only agent-driven tools.

## Appendix B: Agent MCP image support (tested or sourced, Sep 2026)

| Agent | MCP image block | Locant strategy |
|---|---|---|
| Claude Code | Consumed (Peekaboo depends on it) | Text + path; `include_image` optional |
| Cursor | Consumed (official docs) | Same |
| Codex | Unreliable (issues #4819, #10334 open) | Text + path; agent uses `view_image` |
| Gemini CLI / Antigravity | Unconfirmed (issue #2136) | Text + path; mark untested |
| Anything else | Unknown | Clipboard Markdown as the floor |

## Appendix C: Naming

"Locant" is a term from chemical nomenclature. In a compound name such as 2-methylbutane, the "2" is the locant: the number that tells you exactly which position on the carbon chain the methyl group is attached to. Without it, the name describes a family of possible molecules. With it, the name describes one molecule, unambiguously.

That is the job of this tool. A screenshot tells an agent roughly where something is. Locant tells it exactly which element, with a reference the agent can grep for. The name carries the precision half of the positioning; the tagline, "Point, don't describe.", carries the other half.

The name is pronounced LOH-kant, two syllables. It is a word borrowed from outside software on purpose: terms that feel obviously fitting to tool builders (pointer, index, deixis) tend to be taken already.
