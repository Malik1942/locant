# Locant: the component and source line of a web element (prototype, Chrome)

**Status:** Prototype, Nov 4, 2026, on `am/locant-html-scraping-comparison-4ba746`; not merged. Asked by Malik after comparing a Locant capture with Claude Code Desktop's Browser picker on bricks-build (`localhost:5176`): the picker gave `<Card />`, its props, `Source /src/Library.tsx:150:39` and `Rendered at :92:24`; Locant gave `#caption-g2 · .card-caption`. Accessibility publishes the DOM's id and classes, never what React keeps on the node. Measured Nov 3: React 19 keeps `_debugOwner` and `_debugStack` on every fiber in development, and Vite's inline source maps turn the stack's frames into the picker's lines. Chrome runs page JavaScript sent as an Apple Event (`execute … javascript`) once the user turns on View › Developer › Allow JavaScript from Apple Events. Chrome first, at Malik's word. Numbered from R146 (first-run.md holds R141–R145).
**Scope:** a Point capture of one web node in Google Chrome (stable, beta, dev, canary).
**Out of scope:** Dia (same command, but Dia answers that it needs the `--enable-applescript-javascript` launch flag), Safari (`do JavaScript`, behind Develop › Allow JavaScript from Apple Events), Shift sets, drawn frames, frameworks other than React, and any setting or onboarding for the Chrome toggle.

## 1. Requirements

**R146. Ask the page.** When a Point click locks a web node (`dom` is present) in Chrome, Locant starts one lookup at once, beside the crop. It runs `osascript`, which finds the frontmost Chrome window whose active tab's URL starts with the capture's URL without its fragment, and runs a script there. Nothing waits for it until Enter.

**R147. The script.** `web-source.js` finds the DOM node by its id; else, from the accessibility frame converted to a client point (window origin, toolbar height and page zoom from `outerWidth`/`innerWidth`), the node under the point whose class list matches; else the node under the point whose size matches the frame best; else, by classes alone, the one whose size and place match best. From the React fiber on it (or the nearest ancestor that has one) it reads: the owner chain's component names, the nearest owner's props (values shortened, `children` left out), the element's own `_debugSource` or `_debugStack`, and the owner's. A stack frame is the first one outside React and `node_modules`; its module's source map (inline or by URL, fetched synchronously) maps it to the original file, line and column. It changes nothing on the page but one script element it removes at once, and returns one JSON string.

**R148. The page's own world.** Chrome runs Apple Event JavaScript in an isolated world, where React's properties on the DOM nodes are not visible. The script runs in the page's world through a script element and returns its answer in a DOM event with a random name. A page whose Content-Security-Policy forbids inline scripts answers with an error, and the capture has no component.

**R149. At Enter.** The capture waits at most 1.5 s for the lookup. The lookup itself may run 30 s, so the first-use Automation prompt can be answered; an answer that comes late is dropped. For a localhost page, server paths (`/src/Library.tsx`) become absolute paths under the folder the listening process runs in, when the file is there.

**R150. In the payload.** The element gets `component` (`schema/capture.schema.json`). The markdown shows, after the element's head line: `Component: Card in Grid › Library › Routes › Page › … (React, read from the page)`, `Props: …`, `Source: <file:line:col> (this element's JSX)`, and `Rendered at: <file:line:col> (where <Card> is used)`. A Source line replaces the "Grep the class names" advice. A production build gives names only, no lines. Every failure leaves the capture as it was.

## 2. Files

- New: `Locant/Resolve/WebSourceLocator.swift`, `Locant/Resolve/web-source.js`, `Locant.entitlements` (`com.apple.security.automation.apple-events`; the hardened runtime needs it).
- Changed: `Capture.swift` (`ComponentInfo`, `ComponentProp`, `SourceLocation`), `MarkdownBuilder.swift`, `AppState.swift` (start at the click, wait at Enter), `project.pbxproj` (entitlements, `NSAppleEventsUsageDescription`), `schema/capture.schema.json`.

## 3. Tests

- `WebSourceLocatorTests`: Chrome's real reply parses; errors and non-React pages give nothing; production names without lines; the payload lines and their order; the grep advice gives way; paths become absolute only when the file exists; only Chrome; the URL match drops the fragment; the script parses as JavaScript with the handles filled in; the page-world wrapper returns the dispatched answer and says so when the page never ran it (JavaScriptCore with a fake DOM); the 1.5 s wait gives up without stopping the lookup; `sidecar-web-component.json` decodes, round-trips, and passes CI's schema check.
- In Chrome on bricks-build (Nov 4, a scratch profile with the toggle on): by id, by classes and frame, and by frame alone, the caption gives `Card`, Source `/src/Library.tsx:150:7`, Rendered at `:93:24`; the Tailwind-only grid gives `Grid`, Source `:92:5`, Rendered at `:51:44`. Each line matches the file. 0.14 to 0.85 s per lookup.
- In the app (Nov 4): a scratch Debug build's Point capture of the caption locked `#caption-g2 · .card-caption` and ran the lookup at the click; macOS showed "Locant wants to control Google Chrome", which took longer than 1.5 s to answer, so that first capture went out without the lines (R149 as designed). With the grant, the real `WebSourceLocator` run from the Locant test host gave `Card`, Source `…/bricks-build/src/Library.tsx:150:7`, Rendered at `:93:24`, by id and by frame alone, in 0.27 to 0.34 s. A second full Point run was stopped by its own guard when the mouse moved; the click-to-Enter path with the grant is not yet seen end to end.

## 4. Open before it ships

- The first capture after install has no lines (the Automation prompt). Ask once from Settings, or keep the first answer and fill the sidecar late.
- The Chrome toggle is off by default and lives in View › Developer. Locant can tell "turned off" from Chrome's error and say how to turn it on.
- Sync XHR for source maps, and one script element added and removed: both visible to a page that watches for them.
- Dia and Safari, Shift sets and drawn frames, Next.js and webpack source maps (`webpack://` paths) are untried.
