# Locant: where the element is in the source (native apps)

**Status:** Written and built Nov 13, 2026, on `am/locant-app-source-hints`; not merged, not released. Asked by Malik after a reply on X asked how Locant tells apart the same component repeated in a list. Numbered from R151 (`specs/web-source.md` on PR #87 holds R146–R150).
**Scope:** a Point capture in fix mode of an element that is not a web node: the iOS Simulator and Device Hub first, and any Mac app built on this Mac.
**Out of scope:** web nodes (PR #87 reads the page for those); a row index for repeated siblings; the screen's title or selected tab as a line of their own; localized strings whose key differs from the text on screen; strings built at run time.

Read `CLAUDE.md`, `specs/v0.1.md` section 4 (identifier source), `specs/v0.3.md` R17 (project folder), `specs/v0.2.md` R14 (text in the image), `specs/capture-shapes.md` R128 (siblings), and `specs/v0.7.1.md` R55 (payload order).

This spec changes one earlier requirement. `specs/v0.1.md` section 4 said `possiblySymbolName` applies only when the role is `image`; R155 extends it to any role when the name is one of the system's symbols.

## 0. What the captures showed

Measured Nov 13 on the 67 iOS captures in `~/Pictures/Locant`, against the Oryne commit each one recorded.

- 32 distinct handles. Of the 8 identifiers, one (`composer.attach`) was declared; the others were SF Symbol names (`gearshape`, `folder`, `waveform`, `pencil`) or SwiftUI type names. Of the 24 labels, a plain grep of the word found one file for 3, several for 14, none for 7.
- Searched as a whole string literal (`"Recent"`, with its quotes) the same labels land far tighter: "Recent" is in 1 file, not 17; "Ask" in 3, not 39.
- In 65 of 67 captures the only named step of the path was Device Hub's own window (`com.apple.dt.DeviceKit.DeviceManagementWindow-AppWindow-1, SidebarNavigationSplitView`).
- A/B, 11 captures that can be located, one Sonnet agent each, same prompt, task "find the code that draws this element, do not edit": the payload with the hint took 62 tool calls against 83 (25% fewer) and 159 s against 203 s (22% less). Tokens were within 2%, since a fixed context dominates. Both payloads led to the same code in all 11. A twelfth capture ("Tide") could not be located by either: the recorded commit does not hold the string. With R154's `none` line the agent still searched (32 tool calls) and guessed with low confidence, so that line states the fact but does not stop a search.

## 1. Requirements

**R151. Look it up at Enter.** In a fix capture whose project folder is known (R17), Locant searches that folder for the strings of every pointed-at element (the one element, or each element of a Shift set) before the sidecar is written, and stores what it found on the element as `sourceHint`. One walk of the folder serves all the elements. A reference capture, a capture with no project folder, and a web node get no hint. `SourceHints.annotate(_:root:neighbors:)`.

**R152. What is looked for.** The element's own strings are its identifier (unless it is a mangled Swift type name, `_Tt…`) and its label; a label that SwiftUI merged from several texts with ", " is also tried in its parts. The text around it is: its members when it is a cluster, the other elements of the set, the elements in a drawn frame and the nearby ones (v0.2), the labels of its siblings on screen, nearest first, at most 24 (in Device Hub the device's screen is one flat list, so these are the screen's own title, tabs and neighbors), and the lines of text read from the image (R14). A line read from the image is also tried without a leading glyph or a leading word of one or two letters, since an icon is read that way ("•ll Transcript", "Q Search the Ocean"). A string with a quote, a backslash or a line break, shorter than 2 characters or longer than 80, is left out. At most 6 own strings and 40 around. `SourceHints.query(for:neighbors:ocr:)`, `SourceHints.neighborLabels(of:among:)`.

**R153. The search.** Files with the extensions `swift`, `m`, `mm`, `h`, `kt`, `java`, `dart`, `xib`, `storyboard` under the project folder, at most 1 MB each. Hidden folders (`.git`, `.build`, `.claude`), packages, and `node_modules`, `build`, `Build`, `DerivedData`, `Pods`, `Carthage`, `dist`, `vendor` are not entered. An own string matches as a whole string literal, quotes included. A string from around the element matches by its start (text read from the image is often cut off), or whole when it is shorter than 6 characters. The search gives up after 0.8 s or 8,000 source files, and then there is no hint: an unfinished search proves nothing. `SourceHints.scan(root:needles:deadline:)`.

**R154. What it concludes, and what the payload says.** Each file scores 10 for every own string it holds and 1 for every surrounding string. `SourceHints.rank(_:hits:)` is pure. The line goes under the element's head line and takes the place of the advice to grep.

| kind | when | line |
|---|---|---|
| `only` | own strings in one file | `In source: Oryne/Features/Library/LibraryView.swift:543 (the only file in the project with the string "Recent").` |
| `likeliest` | several files, one scores highest | `In source: "Ask" is a string in 3 files. Likeliest: …/AskView.swift:52, :284 (it also has "Find a though" from this capture). Others: …` |
| `several` | several files, the top two tie | `In source: "Cancel" is a string in 12 files, and nothing in this capture says which: … and 6 more. Use the image and the note to choose.` |
| `beside` | own strings in no file; one file holds two or more of the surrounding strings and more than any other, else the rarest surrounding string when it is in at most 3 files | `In source: no string in the project matches this element's own text, so that text is probably data or the system's. Fixed text in or beside it: "Transcript" at …` |
| `none` | own strings looked for, nothing matched | `In source: no "Tide" string in the project. The text may be data, or the app on screen was built from other code than this folder holds now.` |

At most 6 places are listed, each with up to 3 lines. The hint is a lead, not proof: a row whose text comes from an enum or from data is found where the string is defined, not where the row is drawn.

**R155. A symbol's name is not an identifier.** SwiftUI publishes the symbol's name as the accessibility identifier of a button drawn with `Image(systemName:)`. An identifier that reads like a symbol name and is one of the system's symbols (`NSImage(systemSymbolName:)`) is `possiblySymbolName` on any role, and the payload says so as before. It is still searched for as a string, beside the label. `SymbolCatalog.contains(_:)`.

**R156. The host's window is not the app's path.** In a simulated device, the path is cut after its last step whose identifier begins `com.apple.` (the Simulator's or Device Hub's own window). When no step before the element then carries an identifier, the Path line is left out. A path with no such step, and every path outside a simulated device, is shown whole. The sidecar keeps the full path. `MarkdownBuilder.pathLine(_:mirrored:)`.

## 2. Files

- New: `Locant/Resolve/SourceHints.swift`, `Locant/Resolve/SymbolCatalog.swift`, `LocantTests/SourceHintsTests.swift`, `LocantTests/Fixtures/sidecar-source-hint.json`.
- Changed: `Capture.swift` (`sourceHint` on `ResolvedElement`), `ElementResolver.swift` (R155), `MarkdownBuilder.swift` (R154, R156), `AppState.swift` (neighbor labels at the lock, the search at Enter), `schema/capture.schema.json` (`sourceHint`), `ElementResolverTests.swift`, `MCPServerTests.swift` (the new fixture round-trips).

## 3. Tests

- `SourceHintsTests`: the query; what cannot be a literal; each kind; a neighbor telling two "Cancel" apart; identifier and label together; a cluster by its members; skipped folders; the file limit and the clock; a set; neighbor order; every payload line; the fixture's Markdown; the path.
- On the real captures (Nov 13): a temporary test ran `SourceHints.annotate` on 12 sidecars against their own Oryne commits (229 Swift files). 30 to 380 ms each. The lines matched the prototype's, and `Tide` and `Tab Bar` got the `none` and `beside` lines.
- 439 tests pass.

## 4. Open before it ships

- No capture has been taken end to end in the running app with this build: the neighbor labels read at the lock (R152) are untested on a real Device Hub screen, and so is the time the search adds at Enter on a large repository.
- CI's schema check of the fixtures was not run locally (`jsonschema` is not installed here).
- A menu row drawn from an enum (the Library filter's "Whisper") is led to the enum, not to the view that draws the menu. A file that holds several surrounding strings but none of the element's own is not yet named.
- A declared identifier that happens to be a symbol's name (`.accessibilityIdentifier("trash")`) is now reported as a possible symbol name.
- Localized apps: the string on screen is the translation, the key in code is not. `.xcstrings` and `.strings` are not read.
- README and CHANGELOG do not mention the hint yet.
