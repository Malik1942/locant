# Locant: point at the shapes you see

**Status:** Spec written Oct 23, 2026, after Malik reported that Point lands too small (on the text or icon inside what he meant) and jumps too big (to a whole group or the screen). His captures from Oct 18–23 show why. In SwiftUI, the shapes people point at are not accessibility elements: the Recent/Currents capsule, the share/edit/delete capsule, the "Thought deleted · Undo" pill, and the Notification sheet. SwiftUI exposes the text and buttons inside them and large hosting groups around them, nothing in between. So Point offered `staticText "Thought deleted"` for a note about the pill, and its 40 pt crop cut off Undo. It offered `group · _TtGC7SwiftUI32NavigationStackHosting` (360×48) for a note about the toolbar buttons, and a 334×726 group for a note about the sheet. Malik worked around it: he Shift-clicked Recent and Currents to get the switch, and drew a frame around the three toolbar icons, which listed 0 elements. Decided the same day: Locant finds those shapes in the pixels on screen, makes them steps of the ladder, and hover lands on what is under the pointer. The v0.1 cluster stays as the fallback, now under any parent. Numbered from R116 (`specs/capture-recovery.md` ends at R115).
**Scope of this spec:** finding shapes, hover and the ⌥ ladder with shapes in them, the cluster under any parent, the readout and payload of a shape, and the drawn frame that found nothing in Device Hub.
**Out of scope:** drawn frames snapping to shapes; a gesture that steps inside a shape (⌥ goes up, pointing goes in); the 40 pt crop padding; a setting to turn shapes off; new schema fields; shapes in apps with no accessibility tree at all (iPhone Mirroring, canvases), which keep the fallback square because a shape there has no members to grep.

Read `CLAUDE.md`; `specs/v0.1.md` R2, R2a, and R4; `specs/v0.2.md` R11–R16; `specs/v0.8.1.md` R59; `specs/v0.9-snap.md` R77; `Locant/Resolve/ElementResolver.swift` (`HitRefiner`); `Locant/Resolve/AccessibilityReader.swift` (`refine`, `snapshot(of:)`, `elements(in:pid:)`); `Locant/Capture/ScreenCapture.swift`; `Locant/Capture/SelectionOverlay.swift` (`Readout`); `Locant/Payload/MarkdownBuilder.swift`; and in `Locant/App/AppState.swift`, `drainHover`, `renderHover`, `resolveClicked`, `click`, `pin`, and `region`.

This spec overrides `specs/v0.1.md` R2a: rules (1) and (2) no longer apply inside a shape (R117), and rule (4)'s condition that the parent span half the window is dropped (R120). The live overlay of R2 stands: the screen sample (R118) is read for analysis only and never shown.

## 1. Requirements

**R116. Shapes, defined.** A shape is a region of the screen that reads as one container: one fill, bounded by visible edges, such as a pill, a capsule, a card, or a sheet. Locant finds shapes in the screen's pixels (R118, R119) and treats each one as an element:
- `role` `cluster`, `rawRole` `LocantShape`, `label` and `identifier` null, `identifierSource` `unknown`, `value` null.
- `frame`: the shape's bounds, in global CG points.
- `members`: the accessibility elements at least half inside the frame, in reading order (R121).
- `path`: the path of the innermost accessibility ancestor whose frame contains the shape, then `cluster`.

The cluster computed from neighboring elements (v0.1 R2a rule 4, R120 here) keeps `rawRole` `LocantCluster`. The two differ only in `rawRole` and in the payload's wording (R121).

**R117. Hover lands on what is under the pointer.** For a pointer at point `p`, rung 0 of the ladder is chosen in this order:
1. **On an element.** The accessibility hit (after the reader's refinement) is a non-container and its frame contains `p`: that element.
2. **Holding inside a shape.** The pointer is inside a shape (step 3 finds one at `p`), rung 0 was an element inside that shape, and `p` is within 3 pt of that element's frame: the element stays. This replaces the 12 pt stickiness inside shapes.
3. **In a shape.** `ShapeFinder` finds a shape at `p` (R119): that shape. A shape beats an element that the reader reached only through the 8 pt tolerance, whose frame does not contain `p`.
4. **Otherwise,** today's rules: the element reached through the 8 pt tolerance, the 12 pt stickiness, the cluster (R120), the container, or nothing (the fallback square).

The rest of the ladder runs from rung 0 outward: the shapes around rung 0 (R119, up to 3), the accessibility ancestors, and in Snap and Cut the window (R77). Rungs are ordered by containment: each one contains the one before it, give or take 2 pt. A shape is placed after the last rung it contains and before the first rung that contains it. A shape that neither contains nor is contained by its neighbors on the ladder is dropped. A shape whose frame matches an accessibility rung within 2 pt on every edge is merged with it, and the accessibility rung is kept because it carries a handle to grep. `collapsingSameFrames` still applies after that. Snap and Cut still open on the window rung, and ⌥ takes them to rung 0. Text takes the outline at its level, grown by the 8 pt tolerance, as today.

Haptics follow R59 unchanged: a move of the outline, into a shape or out of one, taps `.alignment`, and ⌥ taps `.levelChange`.

**R118. The screen sample.** `ScreenSampler` (new, `Locant/Capture/ScreenSampler.swift`, a class: it owns a capture task) keeps one recent image of the display under the pointer while the overlay is up, in every overlay mode. The image is a `PixelGrid`: RGBA, 8 bits per channel, one sample per point, top row first, with the global CG origin of its first sample and a generation number that increases with each new image.
- **Source:** `ScreenCapture`, through the same filter as every capture, so Locant's own windows are never in it. ScreenCaptureKit scales to one sample per point (`SCStreamConfiguration` width and height in points).
- **When:** once when the overlay shows, then every 1 s while it stays up, and at once when the pointer moves to another display. At most one capture is in flight. The overlay takes the pointer's scrolling, so the screen under it changes only through animation and video.
- **Hover never waits for it.** Hover reads the newest image. With none yet, `ShapeFinder` is not asked, and R117 step 4 decides.
- **Fails soft.** A failed or slow capture leaves the previous image, or none. No toast, no sound, no recovery alert. The click's own capture and its stuck-service handling (R109–R113) are unchanged.
- **Permission.** Without Screen Recording permission (`ScreenCapture.hasPermission()` false), the sampler never calls ScreenCaptureKit, so it can never cause a prompt, and hover runs on R117 step 4 alone.
- **Privacy.** The image lives in memory only, is never written, and is dropped when the overlay closes.

**R119. Finding a shape.** `ShapeFinder` (new, `Locant/Resolve/ShapeFinder.swift`, pure) answers two questions from a `PixelGrid` and a bounding rectangle. The bound is the simulated screen in Device Hub (`HitRefiner.simulatedScreen`), else the window under the pointer, else the display.
- **The shape at a point** `p`. The seed color is the most common color in the 5×5 pt patch around `p`, so a pointer on an icon stroke seeds from the fill around it.
- **The shape around a rectangle** `r` (an element or a shape). The seed color is the most common color in a ring 2 pt outside `r`, and every ring sample of that color is a seed.

Both grow the same way: from the seeds, a 4-connected fill takes each neighboring sample whose color differs from the sample it came from by at most 6, and from the seed color by at most 24. A difference is the largest of the three channel differences, on a 0–255 scale. The first limit lets a gradient through. The second stops a slow drift across an edge too soft for the first. The fill never leaves the bound.

The result is the bounding box of the filled samples, accepted only if all of these hold. Otherwise there is no shape.
- It does not span the bound's full width or full height. A fill that touches two opposite sides is the background, not a shape.
- It covers less than 60% of the bound's area.
- It is at least 12 pt wide and 12 pt tall.
- For the shape around `r`: it contains `r` and is at least 2 pt larger than `r` on at least one side, so an element's own background is not its shape.

Enclosing shapes repeat the second question from the shape just found, up to 3 levels, and stop at the first that finds nothing.

`ShapeFinder` runs off the main actor. While the image's generation is unchanged and `p`'s sample lies in the last fill, the last answer is reused. The 6 and 24 are starting values; the real-screen fixtures (section 3) set the final ones, and the spec is amended when they change.

**R120. The cluster under any parent.** The reader reads the hovered element's siblings whenever its parent is a container, whatever the parent's size, with today's 400 ms cache and 60-child cap. When the hit is itself a container, its children are read whatever its size. v0.1 R2a rule 4 then applies under any parent: siblings group at a 24 pt gap, and the cluster's frame is the members' bounds plus 16 pt, kept inside the parent. The cluster is the fallback: it is offered only where `ShapeFinder` returned no shape. That covers no image yet, a fill that leaked or covered too much, and glass whose edges the fill could not hold. As today, a cluster is added as a rung only when it covers less than 90% of its parent's area.

**R121. What a shape says.**
- **The readout** names the members: `cluster · Recent, Currents`. Members are the elements already read near the pointer that lie at least half inside the shape, joined by `, `. A long list is cut in the middle by the label, as today. With none known at hover, the readout is `cluster`. The fallback cluster reads the same way, instead of `cluster · 2 elements`.
- **Members on commit.** When a shape is committed (a click, Return, or a Shift-click into a set), its `members` come from the drawn-frame walk over its frame (`AccessibilityReader.elements(in:pid:)`, then `RegionResolver.elements`): every non-container element at least half inside, in reading order, at most 12. So the payload can list more members than the readout named. The frame is the one that was outlined.
- **The Markdown head line** for a `LocantShape` reads `cluster · N elements (shape found on screen by Locant, not an accessibility element; frame from its visible edges)`. A `LocantCluster` keeps today's line, which ends `frame approximate`.
- **The crop** is the shape's frame plus the usual 40 pt (v0.1 R4).
- **The schema** gains no field. The `role` description in `schema/capture.schema.json` names both computed kinds: `LocantShape`, found from the visible edges, and `LocantCluster`, computed from neighboring elements.

**R122. A drawn frame finds the elements hover finds.** On Oct 18, a frame drawn in Device Hub around the share, pencil, and trash buttons listed 0 elements, though hover reads those buttons. The walk in `AccessibilityReader.elements(in:pid:)` must reach every element the hover hit test reaches inside the frame, in Device Hub, the Simulator, Chromium, and AppKit. The suspects are the walk's depth cap (14) and its 800-node budget against Device Hub's deep tree. The cause is confirmed with the probe (`AccessibilityReader.swift`, `ElementResolver.swift`, `Geometry.swift`, and `Model/Capture.swift` compiled with a `main.swift`) before any change. R121's members depend on this.

**R123. Words elsewhere.** CHANGELOG's Unreleased section gains one bullet: Point lands on the pill, capsule, card, or sheet under the pointer, even where the app exposes none to accessibility. No hint text changes.

## 2. Files

- New:
  - `Locant/Capture/ScreenSampler.swift` (R118) and `Locant/Resolve/ShapeFinder.swift` (R119, with `PixelGrid`).
  - `LocantTests/ShapeFinderTests.swift`.
  - `LocantTests/Fixtures/shapes/`: the real-screen PNGs and `shapes.json`, their expected rectangles.
  - `scripts/blur-fixture-text.swift`: finds text with Vision and blurs it with Core Image, so fixtures from Malik's own screens can be public.
- Changed:
  - `ElementResolver.swift`: `HitRefiner`, R117 and R120.
  - `AccessibilityReader.swift`: R120 and R122.
  - `ScreenCapture.swift`: one sample per point, R118.
  - `AppState.swift`: hover, commit, and members, R117 and R121.
  - `SelectionOverlay.swift`: `Readout`, R121.
  - `MarkdownBuilder.swift` (R121), `schema/capture.schema.json` (description only, R121), `CHANGELOG.md` (R123).
- Tests changed: `ElementResolverTests.swift`, `MarkdownBuilderTests.swift`, and `RegionResolverTests.swift` with a Device Hub–depth fixture in `LocantTests/Fixtures/`.

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
- `ShapeFinderTests`, on the real-screen fixtures (text blurred), each with a hand-measured expected rectangle (±2 pt):
  - the Notification sheet in Oryne's Library;
  - the share/pencil/trash capsule in the thought detail;
  - the "Thought deleted · Undo" pill;
  - the Recent/Currents capsule;
  - Claude's Environment menu;
  - a web page with cards in Dia.

  Each comes at native scale from macOS's `screencapture` of the window and is reduced to one sample per point by the same conversion `ScreenSampler` uses. A `measure` test on the full iPhone screen keeps `ShapeFinder` under 5 ms at p95.
- `ElementResolverTests`:
  - **Ordering:** rungs ordered by containment; a shape placed between the rung it contains and the rung that contains it.
  - **Dropped:** a shape that neither contains nor is contained by its neighbors.
  - **Merged:** a shape and an accessibility rung within 2 pt merge, and the accessibility rung is kept.
  - **The hold:** inside a shape, an element is rung 0 only when its frame contains the pointer, and holds it for 3 pt beyond its edge.
  - **Shape beats tolerance:** a shape beats an element reached only through the 8 pt tolerance.
  - **The cluster** forms under a parent that covers less than half the window.
- `MarkdownBuilderTests`: the `LocantShape` head line, and the `LocantCluster` line unchanged.
- `RegionResolverTests`: the Device Hub–depth fixture in which today's walk finds nothing returns the three buttons.
- The existing tests pass.
- In the app, a Debug build, over Oryne in Device Hub (the five captures above), first with the headless probe printing the readout and ladder, then by hand:
  - **The pill.** The pointer in the "Thought deleted" pill's padding outlines the pill, and the readout reads `cluster · Thought deleted, Undo`. Committed, the crop holds the whole pill.
  - **The toolbar.** The pointer on the toolbar capsule's rim outlines the capsule, and on the pencil it outlines `button · pencil`. ⌥ from the pencil goes to the capsule, then up.
  - **Recent/Currents.** ⌥ from Recent outlines the capsule in one press.
  - **The sheet.** The pointer in the sheet's margin outlines the sheet, not the 334×726 group. On "Add a thought" it outlines the button.
  - **The background.** The pointer on the screen's plain background outlines what it outlines today.
  - **A drawn frame** around the three toolbar icons lists the three buttons.
  - **The taps.** Every outline move taps once on a Force Touch trackpad.
- Without Screen Recording permission, hover works as before this spec and no system prompt appears.
