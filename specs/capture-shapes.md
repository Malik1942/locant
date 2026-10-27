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
- **R124:** added Oct 26 for button rows like Oryne's toolbar capsule, after Malik's request: a row (or column) of touching controls is a rung on the ⌥ ladder.
- **R125:** added Oct 26 after the in-app check: Device Hub's parent links skip the screen's content group, and its tab bar hides nothing behind it from hit tests.
- **R124:** amended Oct 26: a gap up to a quarter of the control's smaller side joins (Filter, 8 pt behind the Library capsule's divider), after Malik's in-app check.
- **R126:** added Oct 26 after Malik's in-app check (the Product Ideas header's frame looked weird). Revised the same day: the frame is what is drawn, without a 1 pt margin, and only rungs at least 44 pt both ways tighten; after review, a click counts near the element's own frame only when that element is the rung drawn, and only rungs inside the simulated screen tighten.
- **R127:** added Oct 26 after Malik's in-app check (list cards and the tab bar had nothing smaller to land on).

**Scope of this spec:** finding shapes, hover and the ⌥ ladder with shapes in them, the cluster under any parent, a row of controls as a rung, Device Hub's parent links and floating bars, padded frames tightened in the phone, lines of text inside a merged element in the phone, the readout and payload of a shape, and the drawn frame that found nothing in Device Hub.
**Out of scope:** drawn frames snapping to shapes; a gesture that steps inside a shape (⌥ goes up, pointing goes in); the 40 pt crop padding; a setting to turn shapes off; new schema fields; shapes in apps with no accessibility tree at all (iPhone Mirroring, canvases), which keep the fallback square because a shape there has no members to grep.

Read `CLAUDE.md`; `specs/v0.1.md` R2, R2a, and R4; `specs/v0.2.md` R11–R16; `specs/v0.8.1.md` R59; `specs/v0.9-snap.md` R77; `Locant/Resolve/ElementResolver.swift` (`HitRefiner`); `Locant/Resolve/AccessibilityReader.swift` (`refine`, `snapshot(of:)`, `elements(in:pid:)`); `Locant/Capture/ScreenCapture.swift`; `Locant/Capture/SelectionOverlay.swift` (`Readout`); `Locant/Payload/MarkdownBuilder.swift`; and in `Locant/App/AppState.swift`, `drainHover`, `renderHover`, `resolveClicked`, `click`, `pin`, and `region`.

This spec overrides `specs/v0.1.md` R2a in two places. Inside a shape, rule (1)'s 8 pt reach and rule (2)'s 12 pt stickiness yield to the shape (R117). Rule (4)'s condition that the parent span half the window is dropped for forming clusters, while rule (5), the fallback square, still applies only to a container that spans the window (R120). The live overlay of R2 stands: the screen sample (R118) is read for analysis only and never shown.

## 1. Requirements

**R116. Shapes, defined.** A shape is a region of the screen that reads as one container: one fill, bounded by visible edges, such as a pill, a capsule, a card, or a sheet. Locant finds shapes in the screen's pixels (R118, R119) and treats each one as an element:
- `role` `cluster`, `rawRole` `LocantShape`, `label` and `identifier` null, `identifierSource` `unknown`, `value` null.
- `frame`: the shape's bounds, in global CG points.
- `members`: the accessibility elements at least half inside the frame, in reading order (R121).
- `path`: the path of the innermost node, among the hovered element and its ancestors, whose frame contains the shape, then `cluster`.

The cluster computed from neighboring elements (v0.1 R2a rule 4, R120 here) keeps `rawRole` `LocantCluster`. The two differ only in `rawRole` and in the payload's wording (R121). A row of controls (R124) is a third, `rawRole` `LocantGroup`.

**R117. Hover lands on what is under the pointer.** For a pointer at point `p`, rung 0 of the ladder is chosen in this order:
1. **On an element.** The accessibility hit (after the reader's refinement) is a non-container and its frame contains `p`: that element.
2. **Holding inside a shape.** Step 3 finds a shape at `p`, rung 0 was an element inside that shape, and that element's frame grown by 3 pt contains `p`: the element stays. This replaces the 12 pt stickiness inside shapes. With no screen sample yet (R118) there is no shape, so no hold either, and step 4's 12 pt stickiness applies as today.
3. **In a shape.** `ShapeFinder` finds a shape at `p` (R119): that shape. A shape beats an element that the reader reached only through the 8 pt tolerance, whose frame does not contain `p`.
4. **Otherwise,** today's rules: the element reached through the 8 pt tolerance, the 12 pt stickiness, the cluster (R120), the container, or nothing (the fallback square).

Steps 2 and 3 apply only where the accessibility hit test answered at `p`. Where no app answers (iPhone Mirroring, a canvas), hover is unchanged.

The rest of the ladder runs from rung 0 outward:
- the row or column of controls that rung 0 belongs to, right after it, when there is one (R124);
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

**R124. A row of controls is a rung.** On Oct 26 Malik pointed at the toolbar capsule on Oryne's thought-detail screen in Device Hub (capture 20261026-190816-8ngf) and could not take its three buttons together with the pointer or with ⌥, only by dragging a frame or Shift-clicking; ⌥ went to the whole screen. The buttons (`folder` at x=559.6, `square.and.arrow.up` at 599, `trash` at 638.3; each 39.4×39.3 at y=398.2) touch and tile the glass capsule. So R117 step 3 finds no rim to point into, the pixel ring around a button lies mostly outside the capsule (R119 finds no shape), and the cluster (R120) pads by 16 pt and groups at 24 pt, so it takes the meta line 23 pt below the capsule with it, or misses.

- **The group.** Among the hovered element's siblings (`ElementSnapshot.siblings`, read under any container since R120), the non-container controls that, with the element, form a chain along one axis. The chain runs outward from the element in both directions, and every member has a non-empty frame.
  - **Row:** each next control's left edge lies between an overlap of 2 pt and a gap of `max(2, 0.25 × min(w, h))` pt past where the chain ends, w and h being the element's (9.8 pt for 39.3 pt buttons, 2 pt for controls 8 pt tall). Every member's top and height match the element's within 1 pt.
  - **Column:** the same along y, with every member's left edge and width matching the element's within 1 pt.
  - **Ties:** when two controls could join at one step, the nearer joins (the smaller gap or overlap), then the first in sibling order. The chain's ends only move outward.
  - A group has at least 2 members, the element included. A row if there are two or more, else a column; else none.
- **Amended Oct 26: small gaps.** Malik's in-app check on Oryne's Library screen in Device Hub: Recent (567.1,220.0 39.4×39.3, `square.grid.2x2`) and Currents (606.5, `water.waves`) touch, and Filter (an `AXPopUpButton` at 653.9, `library.filter`) sits 8 pt past Currents, behind a divider drawn in the same glass capsule. Under the first rule (within 2 pt) ⌥ took Recent and Currents only. Now it takes the three: 567.1,220.0 126.2×39.3.
- **The rung.** `role` `cluster`, `rawRole` `LocantGroup`, `label`, `identifier`, and `value` null, `identifierSource` `unknown`. `frame`: the exact union of the members, with no padding. `members`: those controls in reading order. `path`: the ancestors' path, then `cluster`, as for any cluster.
- **Where it sits.**
  - **Today's ladder:** right after the element, before the sibling cluster (R120). It needs no screen sample and no permission.
  - **The shape-aware ladder (R117):** an accessibility-side rung. The cluster rule drops only a `LocantCluster`, so the group stays where a shape is found. It must hold rung 0 like any rung, takes its place by area, and a shape within 2 pt of it merges into it with the group kept. The shape would outline the same rectangle, so it adds nothing.
  - **Same frame as an accessibility rung** (`collapsingSameFrames`, unchanged): the one with an identifier stays, else the innermost, the group.
- **No seam zone.** Hover on a button stays on that button. Only ⌥ reaches the group.
- **What it says.** The readout names the members as for any cluster: `cluster · folder, square.and.arrow.up, trash` (R121, code unchanged). The Markdown head line reads `cluster · N elements (controls in one row or column, grouped by Locant, not an accessibility element; frame is their union)`; the `LocantShape` and `LocantCluster` lines are unchanged. The `role` description in `schema/capture.schema.json` gains: "rawRole LocantGroup: controls in one row or column lined up with small gaps, its frame their union." No field is added.
- **Members on commit.** The members found at hover stand: the drawn-frame walk of R121 applies only to a `LocantShape`.

**R125. Device Hub's tree.** Malik's in-app check on Oct 26 found faults only inside the simulated screen: ⌥ from a button in Oryne's Library toolbar capsule still went to the whole screen, and the pointer on the floating tab bar outlined the card behind it. The probe (Library screen, Oct 26): the screen is an `AXGroup`, subrole `iOSContentGroup`, at 347.9,137.5 359.7×780.9; its elements sit in an inner group of the same frame but name the screen as their `AXParent`; the "Tab Bar" group (347.9,844.3 359.7×74.2) has no children, and a hit test on it at 527,880 answers with the card behind it (362.2,830.9 331.1×75.9).

- **The parent that lists the element.** When the hovered element is not a container and its reported parent is a container that does not list it among its children, the reader searches below that parent for the container that does: depth first, through containers only, into nodes whose frame holds the element's within 1 pt, at most 4 levels down and 200 nodes. The parent's children are read once, through the neighbor cache, for this check and for the siblings. The answer is kept per element and reported parent for 400 ms, so an element whose reported parent changes is asked afresh, and no container joins the path twice.
  - **Found:** the siblings (R120) are that container's children, and it joins the path as the nearest ancestor, ahead of the reported parent (still at most 6 ancestors). So R124's group and R120's cluster form on the Library screen.
  - **Not found:** the siblings come from the reported parent, as before.
  - A container under the pointer reads its own children, which need no repair.
- **The neighbor cache** is keyed by the container itself as well as its app, role, subrole, and frame, so the screen's group and the inner group, of one role and frame, never share an entry.
- **A detached screen group.** Device Hub sometimes hands back a detached copy of the screen group as the parent (an empty frame, no parent or window; seen Oct 26 after switching devices), whose frame is then the union of its children's non-empty frames. The ancestors above it stay absent.
- **Floating bars.** When the answer lies on the simulated screen (it or an ancestor has subrole `iOSContentGroup`), the screen's direct children are checked, first as the neighbor cache has them: only when one of those could answer at the point, whichever child holds the answer, are they read afresh. So the pointer in the content group, the common case, reads nothing more. If the answer sits in (or is) a child that spans the screen, and the point lies in another direct child with a non-empty frame that does not span it, that child answers instead, refined as a hit is (R2). Of several, the smallest answers. Where the child that holds the answer cannot be told (a parent link that skips one), the point alone decides.
  - **Spans the screen:** its frame matches the screen's within 1 pt.
  - **Why:** a screen-sized content group lies under the chrome the simulator draws over it (the tab bar, toolbars, a sheet's grabber), whatever the reading order.
  - **Today** the tab bar has no children, so the pointer on it outlines the `Tab Bar` group, with the ladder of any container answer (R120).
  - Off the simulated screen, nothing more is read.
- **Unchanged:** R124's limits and R120's thresholds. Outside Device Hub, only the cache key changes, and it changes no answer.

**R126. Padded frames tighten, in the phone.** On Oct 26 Malik's in-app check on Oryne's Library screen in Device Hub found frames much larger than what they show: the "Product Ideas" header button is 362.2,318.3 331.1×61.7 around about 20 pt of text and a "1 >" at the right, and the button of the card "Weeknight noodles, yesterday" is 362.2,543.2 331.1×75.9 around a drawn card that R119's fill finds at 363.4,549.0 329.5×64.0. Inside the phone, the outline and the capture's frame hug what is drawn.
- **Where.** Only on Device Hub's simulated screen (`HitRefiner.simulatedScreen` finds one), only once a screen sample has landed (R118; the shape-aware ladder of R117), and only for accessibility rungs that are neither containers nor computed (`LocantShape`, `LocantCluster`, `LocantGroup`), lie inside the simulated screen (within 1 pt; the sample shows nothing beyond it), and are at least 44 pt both ways (`HitRefiner.tightenMinSide`). iOS pads a smaller control to its 44 pt tap target on purpose, so its frame is the control: the header (331.1×61.7) and the cards (331.1×75.9) tighten; the capsule's 39.4×39.3 buttons, a 74×39.3 chip, and a line of text do not. (Malik once found an icon's outline too small.)
- **What.** The rung's frame becomes what is drawn inside it: the bounding box of R119's edge samples inside the frame, cut to the frame. It is used only when it lies more than 2 pt inside the frame on at least one side; with no edge inside the frame, the frame stays. The rung's role, label, identifier, path, and members do not change. A drawn step marks a sample on each side of it (R119), so the frame ends one sample (half a point at 2x) outside a drawn card's edge or a glyph: it hugs them, with no margin added.
- **On the ladder.** The accessibility rungs, rung 0 included, are tightened before they are ordered and merged, so a shape found around the drawn card merges into the card's tightened rung within 2 pt, and the accessibility rung is kept: it carries the handle. Rung 0 is still chosen by the frames the accessibility tree reports (R117 step 1), since the pointer may be in an element's padding.
- **The source.** `ShapeSource.ink(inside:)` answers it: `ShapeLookup` from the edge map (`PixelGrid.edgeBounds(inside:)`, which gives nothing for a rectangle that is not finite or lies off the sample), kept per rectangle while the sample and its area stay the same.
- **Hover.** The 12 pt stickiness (R2a rule 2) is measured from the drawn outline, the tightened frame. When the first sample lands and only rung 0's frame changes, to its tightened frame (the same element: equal but for the frame, one inside the other, `HitRefiner.isRetightened`), a ⌥ level chosen before stays.
- **On commit.** The capture takes the selected rung's frame: the payload's frame, the crop (the element plus 40 pt), and the outline all use the tightened one. A click is on what hover drew (`HitRefiner.clickIsOnHover`) within 12 pt of that rung's frame, as everywhere, and on the simulated screen also within 12 pt of the accessibility frame of the snapshot's own element, when that element is the rung drawn, outlined tighter (equal but for its frame, which lies inside). So a click in its padding, or in the reader's 8 pt tolerance around it, commits the tightened outline, not a fresh read of the padded element. Where the rung drawn is another one (a shape at the point, an element held inside a shape, a line of text) and the snapshot's element only neighbors it, only the 12 pt around that rung count. Snap and Cut's click follows the same rule: at ⌥ level 0 it takes the tightened outline, not the window. Off the simulated screen, the 12 pt rule alone decides.
- **Outside the phone nothing changes.** Markdown and schema are unchanged: the frame is still `Frame:`.

**R127. Text lines inside a merged element are rungs, in the phone.** On Oct 26 Malik's in-app check on Oryne in Device Hub found elements with nothing smaller to land on. SwiftUI merges a card's texts into one button: "Weeknight noodles, yesterday" (362.2,543.2 331.1×75.9) has no accessibility children, so a note about its title could only take the whole card ("I can't capture the details inside this list card"). The floating tab bar is `AXGroup "Tab Bar"` (347.9,844.3 359.7×74.2) with no children, so since R125 the pointer on it answers with the group, and Tide, Ask, and Library are not in the tree at all. Decided the same day: Locant reads the lines of text inside such an element from the screen sample with Vision, as Text in image does (`specs/v0.2.md` R14), and the line under the pointer is a rung. Hovering "Weeknight noodles" lands on that line, labeled with its text, and ⌥ then goes to the card.
- **Where.** Only on Device Hub's simulated screen (`HitRefiner.simulatedScreen` finds one), only once a screen sample has landed (R118), and only for the hover answer, the snapshot's own element, when it has no accessibility children (a leaf, or a container whose children read empty, like the Tab Bar) and its accessibility frame holds the pointer (`HitRefiner.textArea`).
- **Reading.** The answer's accessibility frame, not R126's tightened one, cut to the sample, is taken from the `PixelGrid` as an image (`PixelGrid.image(of:)`, the same sRGB RGBA bytes) and read with `VNRecognizeTextRequest` at the `.fast` level, language `en-US`, no language correction. When that finds nothing and the answer's label holds CJK characters (Han, kana, or Hangul), it is read again at `.accurate` with Text in image's languages (`TextRecognizer.languages`), still without language correction: `.fast` reads none of them. Each observation is a line: its text, and its box in global points (Vision's box is normalized, its origin at the bottom left).
- **The rung.** When the answer holds two or more lines and the pointer lies inside one line's box grown by 2 pt (`HitRefiner.textReach`; of two, the nearer), that line is rung 0, ahead of the ladder R117 builds, which keeps the answer and what follows unchanged. One line alone (a heading) adds nothing. The pointer between two lines, more than 2 pt from both, lands on the answer as before.
  - `role` `staticText`, `rawRole` `LocantText` (`ElementResolver.textRawRole`), `identifier` and `value` null, `identifierSource` `unknown`, no `members`.
  - `label`: the part of the answer's label, split on ", ", that matches the line, compared case-insensitively on letters and digits only: an equal part, else one that contains the line or that the line contains. Else the text as read. So the card's second line, which Vision reads as "= yesterday" (the list icon as "="), is labeled "yesterday"; the tab bar's lines, which "Tab Bar" does not name, keep their text.
  - `frame`: the line's box grown by 2 pt, cut to the answer's accessibility frame.
  - `path`: the answer's path, then `staticText`.
  - A line is never held (R117 step 2): it is read again at each step.
- **In the background.** `TextLineReader` (new, `Locant/Capture/TextLineReader.swift`, a class: it owns the reading task) starts and stops with the screen sample (R118).
  - **Hover never waits for it.** It answers with the lines read for the rectangle's pixels, or with none and asks for them. When lines land, hover reads the spot again.
  - **One read at a time,** off the main actor. Of the requests that come meanwhile only the newest waits; an older one is dropped.
  - **Kept per rectangle and pixels:** the frame and a hash of the sample's bytes inside it, at most 32 entries, so the sample's 1 s refresh reads unchanged pixels once. A read that fails gives no lines for those pixels and is not an update.
  - **Dropped when hover ends,** with the sample (R118's privacy): a read still running then lands nowhere.
  - Vision is injected, so the tests run without it. Debug builds log each read's time (`Locant text lines:`), for information only.
- **What was measured, Oct 26** (iPhone 17, the Tide screen, boxes in global points): on a card, `.fast` read "Random" and "4 seconds ago" in 120 ms cold and `.accurate` in 227 ms, reading the list icon as "="; on the tab bar, `.fast` read "Tide", "Ask", and "Library" as three lines in 70 ms and `.accurate` in 129 ms. So a read never blocks hover.
- **On commit.** A line commits like any rung: the payload's frame, the crop (the line plus 40 pt), and the outline are the line's. Snap and Cut end their ladders as today, after it.
- **What it says.** The readout is unchanged code: `staticText · Weeknight noodles`. The Markdown prints the line like any element, its label grep-able, and adds one line under the head line: `Text read from the screen by Locant; not an accessibility element. The element it sits in is the next ⌥ level.` The `role` description in `schema/capture.schema.json` gains: "rawRole LocantText: a line of text Locant read from the screen inside an element that merges it (Device Hub)." No field is added.
- **Outside the phone nothing changes,** and nothing is read.

## 2. Files

- New:
  - `Locant/Capture/ScreenSampler.swift` (R118).
  - `Locant/Resolve/ShapeFinder.swift`: R119, with `PixelGrid`, and the `ShapeSource` that R117 reads (`ShapeLookup`, the live one).
  - `LocantTests/ShapeFinderTests.swift` and `LocantTests/ScreenSamplerTests.swift`.
  - `LocantTests/Fixtures/shape-*.png` and `LocantTests/Fixtures/shapes.json`: the real-screen fixtures and their expected rectangles, beside the existing fixtures.
  - `scripts/blur-fixture-text.swift`: finds text with Vision and blurs it with Core Image, so fixtures from Malik's own screens can be public.
  - `Locant/Capture/TextLineReader.swift` (R127), and `LocantTests/TextLineReaderTests.swift`.
- Changed:
  - `ElementResolver.swift`: `HitRefiner`, R117, R120, R124 (`groupRawRole`, `HitRefiner.groupElement`, `groupGapShare`; `clusterElement` and the group share `computedElement`), R125 (`HitRefiner.overlayIndex`, `HitRefiner.detachedScreenFrame`), R126 (`HitRefiner.tightFrame`, `tightenMinSide`, the shape-aware ladder), and R127 (`textRawRole`, `TextLine`, `HitRefiner.textArea`, `textRung`, `textLabel`, `textReach`, and a line never held).
  - `AccessibilityReader.swift`: R120, and R125 (the container that lists the element, the neighbor-cache key, the detached screen group's frame, floating bars). R122 changes nothing here.
  - `ScreenCapture.swift` (`regionImage`) and `Geometry.swift` (`sampleScale`), R118.
  - `ShapeFinder.swift`: R126 (`PixelGrid.edgeBounds(inside:)`, `ShapeSource.ink(inside:)`, `ShapeLookup`'s memo), and R127 (`PixelGrid.image(of:)`).
  - `AppState.swift`: hover, commit, and members, R117 and R121; R126, a click inside the hovered element's frame; R127, the line ahead of the ladder, and `TextLineReader` started, stopped, and read again with the sample.
  - `SelectionOverlay.swift`: `Readout`, R121.
  - `MarkdownBuilder.swift` (R121, R124, R127), `schema/capture.schema.json` (description only, R121, R124, R127), `CHANGELOG.md` (R123).
- Tests changed: `ElementResolverTests.swift`, `MarkdownBuilderTests.swift` (R127 too), `GeometryTests.swift`, and (R126) `ShapeFinderTests.swift`.

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
  - **What is drawn inside a rectangle (R126):** the bounds of its edge samples, one sample past what is painted; nothing for a flat background, a rectangle that is not finite, or one off the sample; a 30,000 pt tall one gives what the sample shows. The live source keeps each answer, nothing found included, for one sample.
  - **Tightened frames (R126):** a button's frame around a card drawn 6 pt inside it top and bottom, 2 pt at the sides, takes the card grown by half a point (one sample) on each side, within 0.01; a frame around a line of text and a "1 >" takes their edges; a frame with nothing drawn inside it, or nothing more than 2 pt inside, stays; a 40×40 control around an icon keeps its frame and a 44×44 one takes the icon; the ladder tightens on the simulated screen and nowhere else.
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
  - **The group (R124):**
    - The capsule fixture from capture 20261026-190816-8ngf: the three buttons as siblings under a screen-sized group, and the meta line as a sibling `AXStaticText` at x=391.5 y=460.5 (220×16, 23 pt below the capsule's bottom). From each button, rung 0 is the button and rung 1 is the group: `LocantGroup`, frame (559.6, 398.2, 118.1, 39.3) within 0.1, three members in order, the meta line not one. The sibling cluster follows, with four members.
    - Between 40 pt controls, a gap of 2 or 10 pt (a quarter) groups, on either side, and one of 11 pt does not; an overlap of 2 pt groups, and one of 3 pt does not. Between controls 8 pt tall, a gap of 2 pt groups and one of 3 pt does not. A height 2 pt off, or a top edge 2 pt off, does not group; 1 pt off still does. A container neighbor and a neighbor with an empty frame do not group. The chain stops at the first gap past the limit (10 pt after 39.3 pt buttons). Of two controls that could join, the nearer joins; of two equally near, the first in sibling order.
    - The Library capsule (R124 amended): from Recent, Currents, or Filter, rung 1 is the group of the three, frame 567.1,220.0 126.2×39.3 within 0.1, members `square.grid.2x2`, `water.waves`, `library.filter` in order.
    - The R120 toolbar fixture's share and pencil, 4 pt apart, are now a row too: it sits after the button, before the cluster or the capsule.
    - A column of two touching buttons groups; a width 2 pt off does not. A lone button, and an element with no siblings read, have no group. In a grid the row comes before the column.
    - Shape-aware: a `FixedShapes` capsule within 2 pt of the union (past it, exact, or inside it) leaves the group and no separate shape rung; one 8 pt past it is its own rung after the group. With no shape found the ladder is today's, group included.
  - **Device Hub's tree (R125):**
    - `HitRefiner.overlayIndex` on the Library screen's direct children (the content group with the screen's frame, a generic element of no size at its origin, the Tab Bar). At 527,880, with the hit under the content group or not known: the Tab Bar. At 527,500: none. The element of no size, a child reported with a negative width over the point (only the size check stops it: a rectangle of no width or height contains no point), and a second screen-sized child: never. With the hit already under the Tab Bar: none.
    - `HitRefiner.detachedScreenFrame`: those three children give the screen's frame; children with no non-empty frame give none.
    - Currents as the repaired reader reads it (ancestors the inner group, then the screen; siblings the Library elements): ⌥ goes to the group of Recent, Currents, and Filter (8 pt on, joined since R124's amendment), then the cluster, then the screen, and `simulatedScreen` still finds the screen. Read as before the repair, ⌥ goes from the button straight to the screen.
  - **Padded frames (R126),** with `FixedShapes` answering what is drawn from fixed rectangles:
    - The Library card's button, with the drawn card as both what is drawn and a shape: from its padding, rung 0 is the button with the card's frame; from a title inside the card, the card's fill merges into the tightened button, which is kept, label and all. Off the simulated screen the fill is its own rung inside the padded button.
    - From the "Product Ideas" header, with its title and "1 >" drawn: rung 0 is what is drawn; the column of headers and cards (R124), the cluster, and the screen's group keep their frames. With no shape at the point and the pointer off the header, today's ladder, tightened. Off the simulated screen, today's ladder unchanged.
    - From Currents (39.4×39.3), with its icon drawn: today's ladder, unchanged.
    - `HitRefiner.tightFrame`: nothing drawn, the frame; what is drawn, cut to the frame; 2 pt in on every side, the frame; 2.5 pt in on one side, tightened; 44 pt tall or wide, tightened; 43.9 pt either way, 39.4×39.3, or 74×39.3, the frame.
    - A non-container around the simulated screen, with what is drawn inside it: its own frame, still the top rung.
    - `HitRefiner.clickIsOnHover`: with the header tightened from 6 pt to its left (the reader's tolerance, no shape there), a click there and one in its padding are on it, one 20 pt below is not; off the simulated screen only the 12 pt around the outline count. A shape at the point over the card reached through the tolerance, and a pencil held in the capsule with trash reached through it: a click in the card or in trash, far from the rung, is not on it; one within 12 pt of the pencil is.
    - `HitRefiner.isRetightened`: the header and its tightened copy, either way, are one element; a frame outside the other, another label, or nothing, are not.
  - **Text lines (R127):**
    - The card (answer "Weeknight noodles, yesterday" 362.2,543.2 331.1×75.9; lines "Weeknight noodles" 377.0,560.0 120.0×12.0 and "= yesterday" 377.0,582.0 70.0×11.0): the pointer on line 1 gives `staticText` `LocantText` "Weeknight noodles", its box grown 2 pt, the card's path then `staticText`; 1 pt above line 2, "yesterday" (the label's part wins over "= yesterday"); between the lines, 5 pt from each, or 2.5 pt below line 1, nothing; one line alone, nothing; a label with no matching part, the text as read.
    - The tab bar (`group` "Tab Bar" 347.9,844.3 359.7×74.2, no children; lines "Tide", "Ask", and "Library"): the pointer on "Ask" gives `staticText` "Ask", its box grown 2 pt and cut to the tab bar; below the labels, nothing.
    - `HitRefiner.textLabel`: case, spaces, and punctuation do not matter; a part that holds the line, or a line that holds a part, matches; a line with no letters or digits is kept as read.
    - `HitRefiner.textArea`: a leaf on the simulated screen whose frame holds the point gives its frame; the point outside it, an element with children, a container with children, or the same leaf off the simulated screen give none; the Tab Bar with its children read empty gives its frame.
    - Inside a shape, a line is not held where an accessibility element would be (R117 step 2).
- `TextLineReaderTests`, with a stand-in for Vision: before `start()` nothing is read; a rectangle's lines are read once and kept for a new sample with the same pixels inside it (a change outside it included), and read again when the pixels inside change; `onUpdate` fires once per landing; of the requests that come during a read only the newest is read after it; `stop()` drops a read still running, which lands nowhere; a failed read is no update and is not tried again on the same pixels; a label with CJK characters asks for their read. `PixelGrid.image(of:)` gives the samples a rectangle covers with their own bytes, out to whole samples and cut to the sample, and nothing off the sample or for a rectangle that is not finite. Vision's normalized box is placed in global points. **The one test that runs Vision:** two lines drawn with AppKit at 2x, cut from the sample as hover cuts an element and read by the default recognizer, come back as two lines with their text, each box within 3 pt of the drawn ink (measured Oct 26 on a 300×90 pt cut: within 0.5 pt; 222 ms for the first read in a process, 5 to 7 ms after, in a Debug test run).
- `MarkdownBuilderTests`: the `LocantShape` head line, the `LocantCluster` line unchanged, the `LocantGroup` head line, and (R127) a `LocantText` element's lines, which an accessibility `staticText` does not have.
- R122 has no unit test: the walk reads live accessibility. The probe in R122 is its check.
- R125's parent repair has no unit test either, since unit tests have no accessibility tree. The live probe is its check: on the Library screen, the snapshots of Currents, the "Product Ideas" header, and a card have the inner group as their nearest ancestor and its children as their siblings, and at 527,880 the reader answers the `Tab Bar` group.
- The existing tests pass.
- In the app, a Debug build, over Oryne in Device Hub (the five cases in the status line), first with the headless probe printing the readout and ladder, then by hand:
  - **The pill** (no edge on screen, so the fallback). In the pill's padding the outline is as today, and ⌥ from "Thought deleted" outlines the cluster `cluster · Thought deleted, Undo`. Committed, the crop holds the whole pill.
  - **The toolbar.** The pointer on the toolbar capsule's rim outlines the capsule, and on the pencil it outlines `button · pencil`. ⌥ from the pencil goes to the capsule, then up.
  - **The toolbar's three buttons (R124).** On the thought-detail screen, ⌥ from `folder`, from `square.and.arrow.up`, or from `trash` outlines the three buttons together, the readout `cluster · folder, square.and.arrow.up, trash`, and a second ⌥ goes on, to the cluster that holds the meta line where no shape is found around the button. The pointer on a button stays on that button.
  - **Recent/Currents.** ⌥ from Recent outlines the capsule in one press.
  - **Device Hub's tree (R125).** On the Library screen, ⌥ from Currents outlines Recent, Currents, and Filter together (R124 amended), not the screen. The pointer on the tab bar outlines the `Tab Bar` group, not the card behind it.
  - **Padded frames (R126).** On the Library screen, the pointer on the "Product Ideas" header outlines its text and "1 >", not the 61.7 pt row; on a card, the drawn card. A click in the header's padding, or just beside it, captures that outline, and the crop is around it. A ⌥ pressed before the sample lands keeps its level when the outline tightens. Outside Device Hub's screen, outlines and clicks are as before.
  - **Text lines (R127).** On the Library screen, the pointer on a card's title outlines that line, `staticText · Weeknight noodles`, and ⌥ goes to the card; between the card's lines, the card. On the tab bar, the pointer on Ask outlines `staticText · Ask`, and ⌥ goes up from it to the tab bar. A click on a line captures it, and its Markdown says Locant read it from the screen. The lines appear shortly after the pointer arrives (a read takes about 70 to 230 ms) and hover never stalls for them.
  - **The sheet** (no edge at its bottom, so the fallback, and not solved by this spec).
    - Between the sheet's heading, button, and card, the outline is their cluster (R120).
    - In its empty margin, it is the 334×726 screen group, as today. That group is a container that does not span Device Hub's window, so R120 keeps it.
    - On "Add a thought" it outlines the button.
  - **The background.** The pointer on the screen's plain background outlines what it outlines today.
  - **A drawn frame** around the three toolbar icons lists the buttons hover reads there (R122).
  - **The taps.** Every outline move taps once on a Force Touch trackpad.
- Without Screen Recording permission, hover works as before this spec and no system prompt appears.
