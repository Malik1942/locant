# Locant: where the element is in the source (native apps)

**Status:** R157–R162 written and built Nov 13, 2026, merged in PR #92 (cfa9198). R163–R172 added the same day on `am/locant-source-hints-2`; not merged. Nothing here is released: 1.3.0 does not have it. Asked by Malik after a reply on X asked how Locant tells apart the same component repeated in a list. Numbered from R157 (`specs/web-source.md` holds R146–R156, released in 1.3.0).
**Scope:** a Point capture in fix mode: an element of a native app (the iOS Simulator and Device Hub first, and any Mac app built on this Mac), and, from R166, a web node on a localhost page that the page itself did not locate.
**Out of scope:** web nodes the page located (`specs/web-source.md`); the screen's title or selected tab as a line of their own; strings built at run time; a setting to turn the search off.

Read `CLAUDE.md`, `specs/v0.1.md` section 4 (identifier source), `specs/v0.3.md` R17 (project folder), `specs/v0.2.md` R14 (text in the image), `specs/capture-shapes.md` R128 (siblings), and `specs/v0.7.1.md` R55 (payload order).

This spec changes two earlier requirements. R163 moves R157's reading of the folder from Enter to the click. And `specs/v0.1.md` section 4 said `possiblySymbolName` applies only when the role is `image`; R161 extends it to any role when the name is one of the system's symbols.

## 0. What the captures showed

Measured Nov 13 on the 67 iOS captures in `~/Pictures/Locant`, against the Oryne commit each one recorded.

- 32 distinct handles. Of the 8 identifiers, one (`composer.attach`) was declared; the others were SF Symbol names (`gearshape`, `folder`, `waveform`, `pencil`) or SwiftUI type names. Of the 24 labels, a plain grep of the word found one file for 3, several for 14, none for 7.
- Searched as a whole string literal (`"Recent"`, with its quotes) the same labels land far tighter: "Recent" is in 1 file, not 17; "Ask" in 3, not 39.
- In 65 of 67 captures the only named step of the path was Device Hub's own window (`com.apple.dt.DeviceKit.DeviceManagementWindow-AppWindow-1, SidebarNavigationSplitView`).
- A/B, 11 captures that can be located, one Sonnet agent each, same prompt, task "find the code that draws this element, do not edit": the payload with the hint took 62 tool calls against 83 (25% fewer) and 159 s against 203 s (22% less). Tokens were within 2%, since a fixed context dominates. Both payloads led to the same code in all 11. A twelfth capture ("Tide") could not be located by either: the recorded commit does not hold the string. With R160's `none` line the agent still searched (32 tool calls) and guessed with low confidence, so that line states the fact but does not stop a search.

## 1. Requirements

**R157. Look it up at Enter.** In a fix capture whose project folder is known (R17), Locant searches that folder for the strings of every pointed-at element (the one element, or each element of a Shift set) before the sidecar is written, and stores what it found on the element as `sourceHint`. One walk of the folder serves all the elements. A reference capture, a capture with no project folder, and a web node get no hint. `SourceHints.annotate(_:root:neighbors:)`.

**R158. What is looked for.** The element's own strings are its identifier (unless it is a mangled Swift type name, `_Tt…`) and its label; a label that SwiftUI merged from several texts with ", " is also tried in its parts. The text around it is: its members when it is a cluster, the other elements of the set, the elements in a drawn frame and the nearby ones (v0.2), the labels of its siblings on screen, nearest first, at most 24 (in Device Hub the device's screen is one flat list, so these are the screen's own title, tabs and neighbors), and the lines of text read from the image (R14). A line read from the image is also tried without a leading glyph or a leading word of one or two letters, since an icon is read that way ("•ll Transcript", "Q Search the Ocean"). A string with a quote, a backslash or a line break, shorter than 2 characters or longer than 80, is left out. At most 6 own strings and 40 around. `SourceHints.query(for:neighbors:ocr:)`, `SourceHints.neighborLabels(of:among:)`.

**R159. The search.** Files with the extensions `swift`, `m`, `mm`, `h`, `kt`, `java`, `dart`, `xib`, `storyboard` under the project folder, at most 1 MB each. Folders whose name starts with a dot (`.git`, `.build`, `.claude`), packages, test folders (`…Tests`, `__tests__`) and `node_modules`, `build`, `Build`, `DerivedData`, `Pods`, `Carthage`, `dist`, `vendor`, `out`, `coverage` are not entered, and files named `…Tests.swift` are not read; the project folder itself may sit under a dot folder. An own string matches as a whole string literal, quotes included. A string from around the element matches by its start (text read from the image is often cut off), or whole when it is shorter than 6 characters. The search gives up after 0.8 s or 8,000 source files, and then there is no hint: an unfinished search proves nothing. `SourceHints.scan(root:needles:deadline:)`.

**R160. What it concludes, and what the payload says.** Each file scores 10 for every own string it holds and 1 for every surrounding string. `SourceHints.rank(_:hits:)` is pure. The line goes under the element's head line and takes the place of the advice to grep.

| kind | when | line |
|---|---|---|
| `only` | own strings in one file | `In source: Oryne/Features/Library/LibraryView.swift:543 (the only file in the project with the string "Recent").` |
| `likeliest` | several files, one scores highest | `In source: "Ask" is a string in 3 files. Likeliest: …/AskView.swift:52, :284 (it also has "Find a though" from this capture). Others: …` |
| `several` | several files, the top two tie | `In source: "Cancel" is a string in 12 files, and nothing in this capture says which: … and 6 more. Use the image and the note to choose.` |
| `beside` | own strings in no file; one file holds two or more of the surrounding strings and more than any other, else the rarest surrounding string when it is in at most 3 files | `In source: no string in the project matches this element's own text, so that text is probably data or the system's. Fixed text in or beside it: "Transcript" at …` |
| `none` | own strings looked for, nothing matched | `In source: no "Tide" string in the project. The text may be data, or the app on screen was built from other code than this folder holds now.` |

At most 6 places are listed, each with up to 3 lines. The hint is a lead, not proof: a row whose text comes from an enum or from data is found where the string is defined, not where the row is drawn.

**R161. A symbol's name is not an identifier.** SwiftUI publishes the symbol's name as the accessibility identifier of a button drawn with `Image(systemName:)`. An identifier that reads like a symbol name and is one of the system's symbols (`NSImage(systemSymbolName:)`) is `possiblySymbolName` on any role, and the payload says so as before. It is still searched for as a string, beside the label. `SymbolCatalog.contains(_:)`.

**R162. The host's window is not the app's path.** In a simulated device, the path is cut after its last step whose identifier begins `com.apple.` (the Simulator's or Device Hub's own window). When no step before the element then carries an identifier, the Path line is left out. A path with no such step, and every path outside a simulated device, is shown whole. The sidecar keeps the full path. `MarkdownBuilder.pathLine(_:mirrored:)`.

**R163. Read at the click, search at Enter.** Reading the folder is the slow part, so it starts when an element is locked (one element, a set, or a drawn frame), while the note is typed. `SourceHints.Corpus.load(root:)` walks the folder once under R159's limits (0.8 s, 8,000 files, and 64 MB in all) and keeps the files in memory with the string catalogs' keys (R165). At Enter the capture waits at most 300 ms more for it (`SourceHints.commitWait`) and then searches what is in memory: bytes first, and only a file that holds a needle is split into lines. A read that has not finished by then means no hint. Measured on Oryne (247 source files): read 11 to 89 ms, search 1 to 123 ms.

**R164. The file that draws it.** The words of a menu row or a tab are often defined in one file (an enum) and drawn in another. When a file holds two or more of the strings around the element, none of the element's own, and more of those strings than the first place does, the hint names it as `around`, and the line adds: `Other text from this capture ("All kinds" and "Show archived") is in …/LibraryView.swift:509, which may be what draws it.` Native elements only: a page's surrounding words are mostly data.

**R165. Translations.** `.xcstrings` and `.strings` files in the folder (up to 8 MB each) are read for "text on screen → key in code". A string of the element or around it that is a translation is also looked for under its key, and a found key is listed in `localized`; the line adds: `"Add a thought" is the key for "添加想法" in Localizable.xcstrings.` Plural and device variations count. `Catalogs.xcstrings`, `Catalogs.strings`.

**R166. A web node the page did not locate.** In a fix capture of a web node with no `component.source` (the browser cannot be asked, the page is not React, or it did not answer), the folder searched is the one the localhost dev server runs in (`WebSourceLocator.devServerRoot`), in files with the extensions `tsx`, `jsx`, `ts`, `js`, `mjs`, `vue`, `svelte`, `astro`, `html`, `mdx`, `css`, `scss`; `*.test.*`, `*.spec.*`, `*.stories.*`, `*.min.*` and `*.d.ts` are left out. The node's `id` and classes are looked for as whole words (`card` is not found in `card-caption`). A class in more than 8 files is a utility and does not count; when nothing but utilities was found there is no hint, since "no such string" would be untrue. When the id and the classes lead nowhere, the node's own label or text value is looked for the same way. Markup is listed before a stylesheet, and when every place is a stylesheet the line says the name is built at run time. Places are absolute paths, since a web capture has no Project line. The text around a web node is not used.

**R167. The place among siblings.** A single pointed-at element gets `row` when siblings of its role line up with it: the same left edge and width within 2 pt (a column, counted top to bottom), or the same top edge and height (a row, left to right); the larger group wins, a column on a tie. The payload line is `Position: 3 of 12 alike on screen, top to bottom (as drawn now; not the item's place in the data).` The words in brackets are there because a list that sorts or scrolls moves the count. `SourceHints.rowPosition(of:rawRole:among:)`.

**R168. A page is not a SwiftUI view.** Two things in a capture of a page were wrong. A frame drawn on a page had no `URL:` line, since only a click on one node recorded the address; the frame now takes it from the elements it read. And a capture with no element advised `.accessibilityElement()` on a page; on a page (an address is known, or the app is a browser Locant can ask) it now reads "If this page is yours, give the element an id so Locant can point at it next time."

**R169. A tree that is not built yet is waited for.** Electron and Chromium build their accessibility tree only when asked, and R3 assumed half a second. A React page in Electron 45 took 2.06 s (measured with a 50 ms poll, Nov 13), and a click inside that time recorded `element: null` and "app exposes no accessibility tree". Locant now asks the frontmost app for its tree when the capture starts, and a click that finds nothing, or only the native container around the page (`AppState.isUnbuilt`), is read again every 150 ms while the tree was asked for less than 4 s ago (`AccessibilityReader.treeWarmUp`). The wait ends at the first real element. It happens once per app per session, and only for an app that was asked.

**R170. The page address is looked for from the element.** `pageURL` climbed from the last ancestor a snapshot keeps (the sixth). For a node six levels or fewer below the web area that start is the web area's parent, the climb never meets the web area, and the capture has no `url`: a localhost page then reads as someone else's (reference mode, no hint, no component lines). True in browsers as well as Electron since v0.8. The climb starts at the element.

**R171. A node with no handle borrows its parent's.** Pointing at a link's words hits the text inside it, which has no id and no class, so the search had nothing but the words; a bare `li` is the same. For a web node with neither, `element.dom.parent` records the nearest element one or two steps up that has an id or a class (`role`, `id`, `classes`); the search uses its id and classes with the text as context, and the payload names it: `Inside: link · .nav-link (a text node has no id or class of its own; these are its parent's).` That line takes the place of "No id or class. Grep the label text; give the element an id", which asked for something a text node cannot have. For an element that is not a text node the line says "this element has no id or class of its own". An element with a handle of its own never borrows. An id is looked for as a quoted string first (`"projects"`) and as a bare word only when no file has it quoted: a borrowed `#projects` was in 33 files as a word and in one as `id="projects"`.

**R172. Utility classes are a handle together.** In a Tailwind project every class is in every file, so R166's rule (a class in more than 8 files is no handle) left such an element with nothing. The list is the handle where it is written out: the lines of markup that hold every one of the node's classes (the first 8) at once, when the node has at least two and at most 8 files have such a line. The whole list, because a part of it is shared: in the first run below, seven of a link's nine classes sat on one line of another component that copies its focus ring, and that file was named. Those files are the candidates; the node's own text breaks a tie. `sourceHint.together` is true and the line reads `…/SiteHeader.tsx:195 (the only file with "h-6", "w-auto" and "select-none" on one line)`, or `… are on one line in 2 files. Likeliest: …`, or `…, and nothing in this capture says which: …`. Stylesheets are not counted. A node with an id is looked up by R166 as before; with no such line the rare-class rule applies.

`none` (R160) now ends "so a search for that text will find nothing. … If the image and the path do not settle where it is drawn, say so rather than guess." Section 0 recorded that the old line did not stop a search. On the same "Tide" capture, same prompt and model, two agents given the new line stopped after 16 and 19 tool calls (40 s and 47 s) and both answered that no file in the folder draws the element, where the old line took 29 calls and 92 s in the A/B (32 in section 0's run) and ended in a guess. Two runs, one capture.

## 2. Files

- R157–R162: `Locant/Resolve/SourceHints.swift`, `Locant/Resolve/SymbolCatalog.swift`, `LocantTests/SourceHintsTests.swift`, `LocantTests/Fixtures/sidecar-source-hint.json`; `Capture.swift` (`sourceHint`), `ElementResolver.swift` (R161), `MarkdownBuilder.swift` (R160, R162), `AppState.swift`, `schema/capture.schema.json`, `ElementResolverTests.swift`, `MCPServerTests.swift`.
- R163–R168: `SourceHints.swift` (`Corpus`, `Needle`, `Catalogs`, `rowPosition`, the web query), `Capture.swift` (`row`), `MarkdownBuilder.swift` (the added sentences, `positionLine`, `isWeb`, the page's advice), `AppState.swift` (`startReadingSource`, the row at the lock, the frame's address), the schema (`sourceHint.around`, `sourceHint.localized`, `row`), the fixture, `README.md`, `CHANGELOG.md`.
- R169–R172: `AccessibilityReader.swift` (`warm`, `isWarming`, where `pageURL` starts), `AppState.swift` (`resolveClicked`, `isUnbuilt`, the warm at the hotkey), `ElementResolver.swift` and `Capture.swift` (`dom.parent`), `SourceHints.swift` (`together`, the parent in the web query), `MarkdownBuilder.swift` (`insideLine`, the together lines, `none`), the schema (`dom.parent`, `sourceHint.together`), `LocantTests/Fixtures/sidecar-web-text.json` and `sidecar-web-classes.json` (two captures from the Electron run below, as written).

## 3. Tests

- `SourceHintsTests`, 35 tests: the query; what cannot be a literal; each kind; a neighbor telling two "Cancel" apart; identifier and label together; a cluster by its members; skipped folders; the file limit and the clock; a set; neighbor order; every payload line; the fixture's Markdown; the path; the other file; both catalog formats and a search through each; a web node by its rare class, by its id, by its own text, and with only utility classes; where a word ends; a corpus read once; the row position; the page's advice; a project under a hidden folder; a folder with no source; a Mac row found by the text beside its control.
- On real captures (Nov 13), by a temporary test that ran the real code: the 12 iOS sidecars against their own Oryne commits gave the same lines as before, and the Library filter's "Whisper" row now also names `LibraryView.swift` (R164). Of 375 Chinese strings in Oryne's catalogs, 282 led to a source file through their key (R165). Of 12 localhost captures taken in Dia, 7 got a line, 3 got none (a utility class, or text that is not in the folder), and 2 said the handle is not in the folder, which is true of today's checkout (R166).
- R169–R172, 8 more tests: an id that is also a plain word found quoted; a text node looked up by its parent's class and named on the `Inside:` line; an element's own handles before its parent's; `dom.parent` and `together` optional in the sidecar; three utility classes found on their one line among ten files that hold them apart, with one, two and tied candidates; two common classes in ten files, and four of a list of five on another component's line, giving no fingerprint; what counts as an unbuilt tree.
- 488 tests pass.

## 4. Open before it ships

- A row's `Position` counts what is on screen and lined up; a list whose rows differ in width, or a grid, is counted by whichever edge matches.
- A declared identifier that happens to be a symbol's name (`.accessibilityIdentifier("trash")`) is reported as a possible symbol name.
- A localized app whose catalog lives outside the project folder, or in a package, is not read.
- On a page, a class name built at run time (`fit-${mode}`) is found only in the stylesheet; the line says so.
- No setting turns the search off.
- R171 borrows from one or two steps up, and Chromium leaves an inline `span` out of the tree, so the element named can be the section around the text and not the tag that holds it.
- A page's text is matched as written. Words drawn in capitals by CSS (`uppercase`) are not found by their on-screen spelling.
- R172 needs the whole class list on one line. A list split over lines (`cn("a b", cond && "c")`), assembled from variables or a recipe, or carrying a class added at run time (an active state) is not found that way; a rare class in it still is (R166).
- R169's wait is not shown: for up to 4 s after a click on a cold Electron app the overlay stands still.

## 5. In the running app (Nov 13)

A Debug build of this branch took seven Point captures, click to Enter, of the Settings window of a second copy of the same build, driven by synthetic mouse and key events while the Mac was idle. Both copies ran with volatile preferences; the saved preferences were compared before and after and nothing had changed.

- The project folder was this worktree, found by Locant itself (`builtHere`), and it sits under `.claude/worktrees/`.
- `Check Now` (a button): `likeliest`, `Locant/App/SettingsView.swift:203`, because the same file holds "Copy" and "Check for updates automatically", which were read from its siblings at the lock (R158).
- `Diagnostics` (a text): `only`, `SettingsView.swift:213`.
- The Sounds switch, which has no label: `beside`, "Haptic feedback" and "Sounds" at `SettingsView.swift:191, :195`, and `Position: 1 of 2 alike on screen, top to bottom`.
- From Enter to the sidecar on disk: 0.29 to 0.42 s, the same when Enter came 0.4 s after the click as when it came 1.8 s after. That time includes the crop, the text recognition and the write; the search itself was 1 to 123 ms in section 3's runs.

What the run found, fixed on this branch:

- **A project under a hidden folder was read as empty.** `FileManager`'s `.skipsHiddenFiles` hides every file when the folder walked is itself inside a dot folder, so a worktree in `.claude/worktrees/` gave "no such string in the project" for strings that are there. This is in main since PR #92 and is not released. Dot names are now skipped by hand below the root, and a folder with no source of the right kind gives no hint at all.
- **A Mac row's title was not read.** A switch has no label; the title is a text beside it, and on the Mac a text keeps its words in its value, which the sibling read left out. The value is now read for a sibling text that has no title and no description (so not in Device Hub, where a text carries a description and each read is slow), and a text's own value counts as its words.
- **Tests answered for the app.** `LocantTests/SourceHintsTests.swift` holds "Haptic feedback" too. Folders named `…Tests` or `__tests__` and files named `…Tests.swift` are left out (R159).

Not run: a capture in Device Hub. Two simulators were booted with builds of the same app from different folders, and for that Locant gives no Project line (`specs/simulator-project-root.md`), so there was no folder to search; a no-input read of the Device Hub window was blocked by a browser window in front of it. The Device Hub path differs from the Mac's in one way that matters here: the screen is one flat list, so the siblings are every element on screen (R158, R167). That is covered by unit tests and by the twelve recorded captures, not by a live run.

## 6. In an Electron app (Nov 13)

Asked by Malik after "how can Locant do better in Electron": try the folder search (R166) on a real Electron app in development before building anything new.

The app: Electron 45.3.2 from npm, in a scratch folder, with a 40-line main script whose one window loads `http://localhost:5191/`, the Vite dev server of malik-portfolio (React 18, Tailwind, class lists built by a recipe system). That is what an Electron app looks like under `electron-vite dev`. A Debug build of this branch captured it as in section 5. The true line of each element came from React's `_debugSource`, read inside the page by the main script.

**Before R169–R172** (5 captures): the first, 1.7 s after the cursor reached the cold window, recorded no element and advised `.accessibilityElement()`. One shallow element had no `url` and was a reference capture. A link's text got no line and the advice to give it an id. A logo with three utility classes got "12 files, and nothing in this capture says which". One of five named the right file first.

**After** (12 captures over two runs, the first click 0.6 s after the hotkey on a cold window): all 12 are fix captures with their `url`.

| Pointed at | True place | The line |
|---|---|---|
| "Work", "Connect" (nav link text) | `ui/TextLink.tsx:60` | likeliest `TextLink.tsx:8, :19`, by the parent's `nav-link`; `SiteHeader.tsx`, which uses it, second |
| Email icon link | `SiteHeader.tsx:18` | three classes on one line in 2 files, likeliest `SiteHeader.tsx:21, :30` (it has "Email"); `Position: 1 of 2` |
| "SHIPPED" chip | `ui/Chip.tsx:87` | likeliest `Chip.tsx:27`, by a rare class |
| "Apps I shipped…" | `StudioTeaser.tsx:112` | only `StudioTeaser.tsx:112` |
| "Go to Studio" | `StudioTeaser.tsx:121` | only `StudioTeaser.tsx:120`, the element around it |
| "RANGER, 2024" | `StudioTeaser.tsx:135` | only `StudioTeaser.tsx:84`, the card it sits in |
| Logo | `SiteHeader.tsx:195` | a tie of 2: `SiteHeader.tsx:195` and a design-system specimen that repeats the markup |
| "SCROLL" | `HeroSection.tsx` | a tie of 2: `HeroSection.tsx:182` and `AboutOverlay.tsx:230` |
| "SELECTED WORK" | `ui/Eyebrow.tsx:59` | 9 files by the section's `#projects`, the right one (`ProjectList.tsx`) sixth |
| "Work" (a bare `li`) | `Footer.tsx:45` | 8 files by the list's `space-y-4`, `Footer.tsx:43` first by its name's order only |
| "Designed, built…" | `StudioTeaser.tsx:115` | none: Locant selected a drawn shape there, not the text |

Seven name the right file first or alone, two tie it with one other file, two list it among eight or nine, one has no line, and none names a wrong file. From Enter to the sidecar: 0.23 to 0.63 s.

What the runs changed on the way: the first form of R172 took a line with most of the classes, and named another component whose line held seven of a link's nine (so R172 asks for the whole list); a borrowed id that is a plain word was in 33 files (so an id is looked up quoted first, which left 9).

Not shown by this: more than one project (this one has rare classes of its own and a recipe system; a plain Tailwind project would lean on R172 alone); an Electron app with several windows or a `<webview>`; a packaged app, which has no dev server and so no folder. One capture in the fourth run hit a system notification banner that had slid over the window, and is not counted.

