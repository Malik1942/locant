# Locant: point at the shapes you see

**Status:** Spec written Oct 23, 2026, after Malik reported that Point lands too small (on the text or icon inside what he meant) and jumps too big (to a whole group or the screen). His captures from Oct 18–23 show why. In SwiftUI, the shapes people point at are not accessibility elements: the Recent/Currents capsule, the share/edit/delete capsule, the "Thought deleted · Undo" pill, and the Notification sheet. SwiftUI exposes the text and buttons inside them and large hosting groups around them, nothing in between. So Point offered `staticText "Thought deleted"` for a note about the pill, and its 40 pt crop cut off Undo. It offered `group · _TtGC7SwiftUI32NavigationStackHosting` (360×48) for a note about the toolbar buttons, and a 334×726 group for a note about the sheet. Malik worked around it: he Shift-clicked Recent and Currents to get the switch, and drew a frame around the three toolbar icons, which listed 0 elements. Decided the same day: Locant finds those shapes in the pixels on screen, makes them steps of the ladder, and hover lands on what is under the pointer. The v0.1 cluster stays as the fallback, now under any parent. Numbered from R116 (`specs/capture-recovery.md` ends at R115). Amended the same day while planning, after measuring real screens:
- **R118:** the sample is taken at the display's scale, not one sample per point.
- **R119:** the fill finds edges first. The first rule, a step-to-step limit of 6, leaked out of every glass shape at every tolerance tried.
- **R122:** the drawn-frame miss is checked before anything changes.
- **Section 3:** the real-screen fixtures are Malik's captures of the failing cases. Two of them, the pill and the sheet, have no drawn edge to find; they fall back to the cluster. The speed target is the one measured.

Amended Oct 26, after the R122 check and the final review:
- **R118:** the sample stops as soon as hover ends, not when the overlay closes, and an area whose capture failed waits for the next refresh.
- **R120:** a container under the pointer reads its children, not its siblings, so the sibling cluster that used to follow a small container hit is gone.
- **R121:** a committed shape's members are read after the crop has started, so the crop never waits for them.
- **R122:** no change to the walk; the Oct 26 "miss" was the probe's 12-element cap.

**Scope of this spec:** finding shapes, hover and the ⌥ ladder with shapes in them, the cluster under any parent, the readout and payload of a shape, and the drawn frame that found nothing in Device Hub.
**Out of scope:** drawn frames snapping to shapes; a gesture that steps inside a shape (⌥ goes up, pointing goes in); the 40 pt crop padding; a setting to turn shapes off; new schema fields; shapes in apps with no accessibility tree at all (iPhone Mirroring, canvases), which keep the fallback square because a shape there has no members to grep.

Read `CLAUDE.md`; `specs/v0.1.md` R2, R2a, and R4; `specs/v0.2.md` R11–R16; `specs/v0.8.1.md` R59; `specs/v0.9-snap.md` R77; `Locant/Resolve/ElementResolver.swift` (`HitRefiner`); `Locant/Resolve/AccessibilityReader.swift` (`refine`, `snapshot(of:)`, `elements(in:pid:)`); `Locant/Capture/ScreenCapture.swift`; `Locant/Capture/SelectionOverlay.swift` (`Readout`); `Locant/Payload/MarkdownBuilder.swift`; and in `Locant/App/AppState.swift`, `drainHover`, `renderHover`, `resolveClicked`, `click`, `pin`, and `region`.

This spec overrides `specs/v0.1.md` R2a in two places. Inside a shape, rule (1)'s 8 pt reach and rule (2)'s 12 pt stickiness yield to the shape (R117). Rule (4)'s condition that the parent span half the window is dropped for forming clusters, while rule (5), the fallback square, still applies only to a container that spans the window (R120). The live overlay of R2 stands: the screen sample (R118) is read for analysis only and never shown.

## 1. Requirements

**R116. Shapes, defined.** A shape is a region of the screen that reads as one container: one fill, bounded by visible edges, such as a pill, a capsule, a card, or a sheet. Locant finds shapes in the screen's pixels (R118, R119) and treats each one as an element:
- `role` `cluster`, `rawRole` `LocantShape`, `label` and `identifier` null, `identifierSource` `unknown`, `value` null.
- `frame`: the shape's bounds, in global CG points.
- `members`: the accessibility elements at least half inside the frame, in reading order (R121).
- `path`: the path of the innermost node, among the hovered element and its ancestors, whose frame contains the shape, then `cluster`.

The cluster computed from neighboring elements (v0.1 R2a rule 4, R120 here) keeps `rawRole` `LocantCluster`. The two differ only in `rawRole` and in the payload's wording (R121).

**R117. Hover lands on what is under the pointer.** For a pointer at point `p`, rung 0 of the ladder is chosen in this order:
1. **On an element.** The accessibility hit (after the reader's refinement) is a non-container and its frame contains `p`: that element.
2. **Holding inside a shape.** Step 3 finds a shape at `p`, rung 0 was an element inside that shape, and that element's frame grown by 3 pt contains `p`: the element stays. This replaces the 12 pt stickiness inside shapes. With no screen sample yet (R118) there is no shape, so no hold either, and step 4's 12 pt stickiness applies as today.
3. **In a shape.** `ShapeFinder` finds a shape at `p` (R119): that shape. A shape beats an element that the reader reached only through the 8 pt tolerance, whose frame does not contain `p`.
4. **Otherwise,** today's rules: the element reached through the 8 pt tolerance, the 12 pt stickiness, the cluster (R120), the container, or nothing (the fallback square).

Steps 2 and 3 apply only where the accessibility hit test answered at `p`. Where no app answers (iPhone Mirroring, a canvas), hover is unchanged.

The rest of the ladder runs from rung 0 outward:
- the shapes around rung 0 (R119, up to 3);
- the cluster (R120), only where there is no shape around rung 0;
- today's rungs: the accessibility ancestors and, in Snap and Cut, the window (R77).

**Order.** Rungs are ordered by containment: each one contains the one before it, give or take 2 pt. A rung that does not contain rung 0 is dropped, such as the leaf the reader reached through the 8 pt tolerance when rung 0 is a shape. A shape is placed after the last rung it contains and before the first rung that contains it. A shape that neither contains nor is contained by its neighbors on the ladder is dropped.

**Merging.** A shape whose frame matches an accessibility rung within 2 pt on every edge is merged with it, and the accessibility rung is kept because it carries a handle to grep. The 2 pt allows for pixel edges read at one sample per point. Two accessibility rungs still merge only within 1 pt (`collapsingSameFrames`, unchanged).

**Other modes.** Snap and Cut still open on the window rung, and ⌥ takes them to rung 0. Text takes the outline at its level, grown by the 8 pt tolerance, as today.

Haptics follow R59 unchanged: a move of the outline, into a shape or out of one, taps `.alignment`, and ⌥ taps `.levelChange`.

**R118. The screen sample.** `ScreenSampler` (new, `Locant/Capture/ScreenSampler.swift`, a class: it owns a capture task) keeps one recent image of the area hover reads shapes in, while the Point, Snap, Text, or Cut overlay is up for hover. Color does not use it. The area is R119's bound: the simulated screen in Device Hub, else the window under the pointer, else the display.

The image is a `PixelGrid`: RGBA, 8 bits per channel, top row first, at the display's own scale (2 samples per point on a Retina display). It carries the area it shows in global CG points, its scale, a generation number that increases with each new image, and R119's edge map. The conversion and the edge map are computed off the main actor when the image lands: about 27 ms for an iPhone screen, so hover never pays for them.

**Why the display's scale.** Measured on Oct 23 on Malik's Recent/Currents capsule, a glass edge is a one-pixel step of 8 to 10 levels at the display's scale. At one sample per point it splits into two steps of about 5, which an edge limit of 4 (R119) would barely catch. An area that would hold more than 4,000,000 samples is taken at a lower scale (`Geometry.sampleScale`), so a large browser window stays affordable.

- **Source:** `ScreenCapture.regionImage`, through the same filter as every capture, so Locant's own windows are never in it.
- **When:**
  - At once when hover wants an area other than the one the newest image shows, then every 1 s while the overlay stays up.
  - At most one capture is in flight.
  - When a new image lands, hover reads the spot under the pointer again.
  - The overlay takes the pointer's scrolling, so the screen under it changes only through animation and video.
- **Hover never waits for it.** Hover reads the newest image when it shows the area it wants. Otherwise `ShapeFinder` is not asked, and R117 step 4 decides.
- **Fails soft.** A failed or slow capture leaves the previous image, or none. An area whose capture failed is taken again at the next refresh, not each time hover wants it: a stuck capture service fails at once. No toast, no sound, no recovery alert. The click's own capture and its stuck-service handling (R109–R113) are unchanged.
- **Permission.** Without Screen Recording permission (`ScreenCapture.hasPermission()` false), the sampler never calls ScreenCaptureKit, so it can never cause a prompt, and hover runs on R117 step 4 alone.
- **Privacy.** The image lives in memory only, is never written, and is dropped as soon as hover ends: at a click, a drawn frame, or when the overlay closes. Shift-clicks into a set stay in hover.

**R119. Finding a shape.** `ShapeFinder` (new, `Locant/Resolve/ShapeFinder.swift`, pure) answers two questions from a `PixelGrid` and a bounding rectangle. The bound is the simulated screen in Device Hub (`HitRefiner.simulatedScreen`), else the window under the pointer, else the display.
- **The shape at a point** `p`. The seed color is the most common color in the 5×5 pt patch around `p`, so a pointer on an icon stroke seeds from the fill around it. Every patch sample within 4 of the seed color is a seed.
- **The shape around a rectangle** `r` (an element or a shape). The seed color is the most common color in a ring 2 pt outside `r`. Every ring sample within 4 of the seed color is a seed.

"Most common color": samples are counted after dropping the three low bits of each channel, and the seed color is the mean of the samples in the largest bucket. Distances in points are converted with the image's scale. A difference between two colors is the largest of the three channel differences, on a 0–255 scale.

**Edges first.**
- **An edge sample** is one whose color differs from one of its four neighbors by more than 4. Edges are mapped once per image (R118).
- **Both questions grow the same way:** from the seeds, a 4-connected fill takes each neighboring sample that is not an edge sample and is within 24 of the seed color. The fill never leaves the bound.
- **What that buys:**
  - A gradient of a level or two per sample is not an edge, so the fill crosses it.
  - A thin rim between two equal fills is an edge on both sides, so the fill stops before it. That is how a glass capsule is told from a background of its own color.
  - The seed limit stops a drift through a gap in an edge.
- **The background** is recognized as soon as the fill reaches two opposite sides of the bound, and the fill stops there.

**What was measured, Oct 23.** On the six real-screen fixtures (section 3), these rules find the Recent/Currents capsule, the toolbar capsule, a Claude message card, and a GitHub file row, and find no shape on any of the six backgrounds. The first rule, "within 6 of the sample it came from", leaked out of every glass shape at every tolerance tried: an antialiased corner ramps a few levels a sample.

They find neither:
- **the "Thought deleted" pill:** along most of its top edge, inside and outside match within 1 level and no rim is drawn;
- **the Notification sheet:** its bottom fades into the black margin over 8 samples without a step.

Neither has an edge on screen to find, so both fall back to the cluster (R120).

The result is the bounding box of the filled samples, accepted only if all of these hold. Otherwise there is no shape.
- It does not reach both the left and right edges of the bound, nor both the top and bottom (within 1 pt). A fill that touches two opposite sides is the background, not a shape. A sheet that meets only the bottom edge is still a shape.
- It covers less than 60% of the bound's area.
- It is at least 12 pt wide and 12 pt tall.
- For the shape around `r`: it contains `r` and is at least 2 pt larger than `r` on at least one side, so an element's own background is not its shape.

Enclosing shapes repeat the second question from the shape just found, up to 3 levels, and stop at the first that finds nothing.

`ShapeFinder` runs off the main actor. While the image's generation is unchanged and `p`'s sample lies in the last fill, the last answer is reused. The 4 and 24 were set by the real-screen fixtures on Oct 23; a change to either reruns them, and the spec is amended.

**R120. The cluster under any parent.** The reader reads the hovered element's siblings whenever its parent is a container, whatever the parent's size, with today's 400 ms cache and 60-child cap. When the hit is itself a container, its children are read whatever its size. A container under the pointer reads its children, not its siblings, so the sibling cluster that used to follow a small container hit is gone. v0.1 R2a rule 4 then applies under any parent: siblings group at a 24 pt gap, and the cluster's frame is the members' bounds plus 16 pt, kept inside the parent. As today, a cluster is added as a rung only when it covers less than 90% of its parent's area.

The cluster is the fallback for a shape:
- **At rung 0:** offered (R117 step 4) only when there is no shape at `p`.
- **After an element:** offered only when there is no shape around that element.

That covers no image yet, a fill that leaked or covered too much, and glass whose edges the fill could not hold.

**A container under the pointer** with no cluster around `p`:
- **It spans the window:** today's fallback square, `element: null` on click, and the container only through ⌥.
- **It does not span the window** (the 360×48 toolbar group): the container itself, as today.

**R121. What a shape says.**
- **The readout** names the members: `cluster · Recent, Currents`. At hover, the members are the non-container nodes the hover snapshot already holds that lie at least half inside the shape: the element, its `siblings`, and its `children` (R120 reads both under any parent). Each is named by its label, else its identifier, in reading order, joined by `, `; nodes with neither are left out. A long list is cut in the middle by the label, as today. With no names, the readout is `cluster`. The fallback cluster reads the same way, instead of `cluster · 2 elements`.
- **Members on commit.** When Point commits a shape (a click, Return, or a Shift-click into a set), its `members` come from the drawn-frame walk over its frame (`AccessibilityReader.elements(in:pid:)`, then `RegionResolver.elements`): every non-container element at least half inside, in reading order, at most 12. So the payload can list more members than the readout named. If the walk finds none, the members known at hover are kept. They run after the crop has started, so the crop never waits for them (`specs/capture-recovery.md` R110). The frame is the one that was outlined. Snap, Text, and Cut write no members, as today.
- **The Markdown head line** for a `LocantShape` reads `cluster · N elements (shape found on screen by Locant, not an accessibility element; frame from its visible edges)`. A `LocantCluster` keeps today's line, which ends `frame approximate`.
- **The crop** is the shape's frame plus the usual 40 pt (v0.1 R4).
- **The schema** gains no field. The `role` description in `schema/capture.schema.json` names both computed kinds: `LocantShape`, found from the visible edges, and `LocantCluster`, computed from neighboring elements.

**R122. A drawn frame finds the elements hover finds.** On Oct 18, a frame drawn in Device Hub around the share, pencil, and trash buttons listed 0 elements. That same evening, hover over the same toolbar outlined `NavigationStackHosting` (360×48), not a button, so the buttons may not have been in the tree at all.

On Oct 23 the probe ran the real walk on Oryne's Library screen in Device Hub. It found all 10 elements hover reads, at depth 9 of an 11-level, 553-node tree, well inside its depth cap (14) and node budget (800). The probe compiles `AccessibilityReader.swift`, `ElementResolver.swift`, `RegionResolver.swift`, `Geometry.swift`, `Model/Capture.swift`, `AgentPaste.swift`, `HandoffPasteboard.swift`, and `PasteboardWriter.swift` with a `main.swift`.

Before any change, the thought-detail toolbar is checked with the probe:
- **If hover reads buttons there that the walk misses,** the walk is fixed until it finds every non-container element hover reads inside the frame.
- **If hover too reads only the group,** the tree exposes no buttons, and the walk stays as it is.

**The check, Oct 18–26.** The Oct 18 toolbar miss did not reproduce: on the thought-detail screen the toolbar's buttons are in the tree, and the walk finds them. An Oct 26 probe seemed to show a miss of two buttons hover reads there, "Ask Ocean" and "Grow a branch", but that was the probe comparing hover's list against `RegionResolver.elements(in:among:)`, which caps a frame's list at 12, and those two buttons come last in reading order. The plain `AccessibilityReader.elements(in:pid:)` walk over the whole simulated screen returned all 29 elements, both buttons included. So the walk stays as it is and nothing is added. A probe that checks the walk compares against the walk's own list, not the capped one.

The existing region tests keep passing either way. R121's members depend on the walk.

**R123. Words elsewhere.** CHANGELOG's Unreleased section gains one bullet: Point lands on the capsule, card, or panel under the pointer whose edges are drawn on screen, even where the app exposes none to accessibility. No hint text changes.

## 2. Files

- New:
  - `Locant/Capture/ScreenSampler.swift` (R118).
  - `Locant/Resolve/ShapeFinder.swift`: R119, with `PixelGrid`, and the `ShapeSource` that R117 reads (`ShapeLookup`, the live one).
  - `LocantTests/ShapeFinderTests.swift` and `LocantTests/ScreenSamplerTests.swift`.
  - `LocantTests/Fixtures/shape-*.png` and `LocantTests/Fixtures/shapes.json`: the real-screen fixtures and their expected rectangles, beside the existing fixtures.
  - `scripts/blur-fixture-text.swift`: finds text with Vision and blurs it with Core Image, so fixtures from Malik's own screens can be public.
- Changed:
  - `ElementResolver.swift`: `HitRefiner`, R117 and R120.
  - `AccessibilityReader.swift`: R120. R122 changes nothing here.
  - `ScreenCapture.swift` (`regionImage`) and `Geometry.swift` (`sampleScale`), R118.
  - `AppState.swift`: hover, commit, and members, R117 and R121.
  - `SelectionOverlay.swift`: `Readout`, R121.
  - `MarkdownBuilder.swift` (R121), `schema/capture.schema.json` (description only, R121), `CHANGELOG.md` (R123).
- Tests changed: `ElementResolverTests.swift`, `MarkdownBuilderTests.swift`, and `GeometryTests.swift`.

## 3. Tests

- `ShapeFinderTests`, on synthetic grids:
  - **A rounded rectangle** on a flat background: its bounds, from a point in its padding and from the ring around an element inside it.
  - **A capsule whose two buttons touch,** joined only by a 3 pt rim, one button lighter than the fill: the capsule, from the ring around either button.
  - **A fill with a vertical gradient** of 20 levels: one shape.
  - **A dark fill with a 1 pt light rim** on a dark background, the glass case: stops at the rim.
  - **The background:** a fill that spans the bound's full width or height gives no shape.
  - **Too big or too small:** 60% of the bound or more gives no shape, and so does less than 12 pt either way.
  - **A pill inside a sheet:** the pill from its padding, and the sheet as its enclosing shape; the background beyond gives nothing more.
  - **A pointer on an icon stroke** inside a pill: the pill.
  - **Frames from other apps:** an infinite, NaN, or 30,000 pt tall rectangle, a NaN point, and a bound that is not finite or is empty give no shape, and nothing traps.
- `ShapeFinderTests`, on six real-screen fixtures. Four are Malik's own captures of the failing cases, and two are cards outside SwiftUI. Text is blurred with `scripts/blur-fixture-text.swift`. Expected rectangles were measured on Oct 23 with a scanline tool independent of `ShapeFinder` (±2 pt):
  - `shape-segments` (capture 20261023-022759-bkzx): the Recent/Currents capsule, from its rim and from the ring around either button.
  - `shape-toolbar` (20261018-231612-95js): the share/pencil/trash capsule, from between two icons.
  - `shape-pill` (20261023-023725-uoyv): the "Thought deleted" pill, from its padding and from around the text: no shape (R119). Along most of its top edge, inside and outside match within 1 level and no rim is drawn.
  - `shape-sheet` (20261023-023021-yu3f): the Notification sheet, from its margin and from around "Add a thought": no shape (R119). Its bottom fades into the black margin without a step.
  - `shape-claude-card` (20261019-000746-vtbd): a Claude message card whose fill is the background's, bounded by a 1 px border.
  - `shape-web-list` (20261003-182251-7706): a row of a bordered GitHub file list in Dia, in light mode.

  Each fixture also has a point on its background that must give no shape. Fixtures load at the capture's 2x scale through `PixelGrid(image:frame:scale:generation:)`, the conversion `ScreenSampler` uses.
- `ScreenSamplerTests`: without permission nothing is captured; an area is captured once, and again only when hover wants another area; an area whose capture failed is taken again at the next refresh, not when hover wants it again; stopping drops the image.
- `GeometryTests`: `sampleScale` keeps the display's scale up to 4,000,000 samples and lowers it above.
- **Speed:** with the probe built at `-O`, 100 shape lookups on the iPhone screen of capture 20261023-023021-yu3f, unblurred and kept out of the repo (668×1453 samples, edge map precomputed) have a median under 5 ms and a 95th percentile under 15 ms. On Oct 23 they measured 4.6 ms and 13.4 ms; the edge map took 27 ms once. On the blurred `shape-sheet` fixture the text smudges add fill work: p50 5.6 ms. The unit tests run unoptimized, so they check results, not speed. Debug builds log each lookup's time, for information only.
- `ElementResolverTests`:
  - **Ordering:** rungs ordered by containment; a shape placed between the rung it contains and the rung that contains it.
  - **Dropped:** a shape that neither contains nor is contained by its neighbors.
  - **Merged:** a shape and an accessibility rung within 2 pt merge, and the accessibility rung is kept.
  - **The hold:** inside a shape, an element is rung 0 only when its frame contains the pointer, and holds it for 3 pt beyond its edge.
  - **Shape beats tolerance:** a shape beats an element reached only through the 8 pt tolerance.
  - **The cluster** forms under a parent that covers less than half the window, and is not offered where a shape was found.
  - **Containers:** a container that does not span the window, with no cluster around the point, is rung 0 itself; one that spans the window gives the fallback square, as today.
  - **No answer:** with no accessibility answer at the point, no shape is asked for.
- `MarkdownBuilderTests`: the `LocantShape` head line, and the `LocantCluster` line unchanged.
- R122 has no unit test: the walk reads live accessibility. The probe in R122 is its check.
- The existing tests pass.
- In the app, a Debug build, over Oryne in Device Hub (the five cases in the status line), first with the headless probe printing the readout and ladder, then by hand:
  - **The pill** (no edge on screen, so the fallback). In the pill's padding the outline is as today, and ⌥ from "Thought deleted" outlines the cluster `cluster · Thought deleted, Undo`. Committed, the crop holds the whole pill.
  - **The toolbar.** The pointer on the toolbar capsule's rim outlines the capsule, and on the pencil it outlines `button · pencil`. ⌥ from the pencil goes to the capsule, then up.
  - **Recent/Currents.** ⌥ from Recent outlines the capsule in one press.
  - **The sheet** (no edge at its bottom, so the fallback, and not solved by this spec).
    - Between the sheet's heading, button, and card, the outline is their cluster (R120).
    - In its empty margin, it is the 334×726 screen group, as today. That group is a container that does not span Device Hub's window, so R120 keeps it.
    - On "Add a thought" it outlines the button.
  - **The background.** The pointer on the screen's plain background outlines what it outlines today.
  - **A drawn frame** around the three toolbar icons lists the buttons hover reads there (R122).
  - **The taps.** Every outline move taps once on a Force Touch trackpad.
- Without Screen Recording permission, hover works as before this spec and no system prompt appears.
