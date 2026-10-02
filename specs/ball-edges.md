# Locant: the ball rests beside the Dock, and comes back where it rests

**Status:** Spec written Oct 1, 2026, after Malik asked, before the official launch, for the ball to rest at the bottom as well as the sides, and for the way it tucks and wakes to be more intuitive. Decided the same day: bottom tucks sit on the real screen edge beside the Dock, never on or behind it; the trigger gets all three refinements (wake where it rests, a ghost while dragging, throw to tuck). Ships with the next release.
**Scope of this spec:** where the ball may tuck (left, right, and bottom edges, minus the Dock, the corners, and edges shared with another display), the tuck spot as the ball's home, a ghost that shows where a release will tuck, and throwing the ball.
**Out of scope:** the top edge (menu bar, notch); the ring; the 80 pt wake radius and the glide out to the cursor; the 2 s idle wait; first-launch placement; following the Dock to another display; new settings.

Read `CLAUDE.md`, `specs/v0.3.md` (the ball, R20), and `Locant/Launcher/FloatingBall.swift`.

## 1. What is wrong today

- **The bottom never looks tucked.** `dock(ifWithin:)` already offers the bottom, but measures it from `visibleFrame`, which ends at the top of the Dock. On Malik's Mac (2056×1329, Dock at the bottom, 52 pt, tiles from x 330 to 1726) a bottom tuck floats 33 pt above the screen edge beside the Dock, or sits half behind the Dock over it. Only the left and right tucks read as tucks.
- **The ball runs from the cursor.** An idle tuck from the middle of the screen keeps `freeOrigin` in the middle. Coming near the tucked ball wakes it, and waking glides it to `ringSafeOrigin(freeOrigin)`: back across the screen, away from the cursor. When the cursor leaves, it tucks again two seconds later.
- **Nothing says where a drop will go.** A drop within 48 pt of an edge tucks; nothing shows that before the release. Beside the Dock the spot will not be under the cursor, so it matters more now.
- **A flick is a drop.** The ball stops dead wherever the button comes up.

## 2. Requirements

**R80. Free edges, pure.** `BallEdges` (new, `Launcher/BallEdges.swift`, no AppKit) is built from one screen's `frame` and `visibleFrame`, the Dock's tile frame when it lies on that screen (AppKit coordinates, optional), and the other screens' frames. It knows, for the disc's center, the free stretches of the left, right, and bottom edges:
- The edges are the screen's real edges (`frame`), not `visibleFrame`. The left and right edges run from the bottom of the screen to the top of `visibleFrame` (under the menu bar).
- **The Dock.** Its orientation follows its frame: wider than tall is a bottom Dock; otherwise it is on the left or right, whichever side its middle is nearer. Its span along that edge, widened by `FloatingBall.Tokens.approach` (80 pt) at each end, is not free, so reaching for the Dock's end icons does not wake the ball. When the Dock frame is unknown but `visibleFrame` is inset from `frame` by more than 8 pt on the left, right, or bottom, that whole edge is not free.
- **Corners.** The center keeps `FloatingBall.Tokens.diameter` (48 pt) from the two ends of each edge.
- **Other displays.** Where another screen's frame touches an edge (within 1 pt), that span is not free.
- An empty stretch is dropped; an edge may have none.

It answers three questions:
- `tuck(nearest:)`: the free tuck nearest a point (straight-line distance from the point to the tucked center), or nil when no edge is free. A tuck is the edge and the tucked center: `dockedVisible` (60 percent) of the disc shows, so the center sits 4.8 pt inside the edge.
- `home(for:)`: the same spot with the whole disc on screen, touching the edge (center one radius inside it).
- `ringSafe(_:)`: a center pulled in far enough for the ring (`ringMargin`, 100 pt) to open on screen. The top bound is `visibleFrame`. The left, right, and bottom bounds are the real edge, except across the Dock's widened span (or a whole Dock edge when the span is unknown), where they are `visibleFrame`'s edge. So waking from a bottom tuck beside the Dock rises about 95 pt, the same as from a side, and the awake disc never sits behind the Dock.

**R81. The Dock's frame.** `AccessibilityReader.dockFrame()` returns the frame of the Dock's `AXList` (the tiles), in CG coordinates, or nil when the Dock is not running, not trusted, or has no list. The ball has a reader of its own, as the agent label does (R63), and keeps the last answer, converted to AppKit coordinates. It asks again when it appears, when a drag starts, when the idle timer starts, when the screens change, and 0.6 s after any app launches or quits (the Dock grows and shrinks with running apps). Decisions use the cached frame and never wait on the read. A failed read clears the cache, and R80's fallback applies.

**R82. The tuck is home.** Every tuck, idle or on release, goes to `BallEdges.tuck(nearest:)` of the disc's landing point (R83), on the screen the ball is on. Over the Dock that is the nearer of the Dock's end and a side edge. The tuck sets the ball's home (`freeOrigin`) to `home(for:)` that tuck and saves it (`onMoved`), so:
- waking glides out from the tucked spot toward the cursor (`ringSafe(home)`), never back to where the ball was before an idle tuck;
- leaving an awake ball glides it to its home, and two seconds later it tucks again, as a ball dropped at an edge does today;
- the next launch starts at that spot. `onScreenOrigin` accepts an origin whose center lies on any screen's `frame` (a home on the bottom edge beside the Dock is below `visibleFrame`); an origin off every screen is still pulled into the nearest `visibleFrame`.

When a refreshed Dock frame (R81) or a screen change leaves a tucked ball's spot no longer free, it glides to the nearest free tuck and saves the new home. When no edge is free, the ball does not tuck and rests where it is.

**R83. The release.** The release has a landing point:
- **A drop:** the disc's center when the button comes up.
- **A throw:** the drag's velocity, measured over the last 80 ms of drag samples, of at least 700 pt/s. The landing point is the center carried along the velocity by `v · d / (1 − d)` with `d = 0.998` per ms (UIScrollView's normal deceleration, the projection iOS uses for Picture in Picture), stopped where that path leaves the screen's `frame`.

With Auto-hide on, a landing point within `edgeSnap` (48 pt) of the left, right, or bottom edge of `visibleFrame`, or past it, tucks into the free spot nearest it (R82). A throw whose path left the screen across the left, right, or bottom edge counts as at that edge. Any other landing point is open space: a drop rests there and stays ready under the cursor, as today; a throw glides there, kept inside `visibleFrame`, and rests. Either tucks after two seconds as usual. With Auto-hide off, nothing tucks: a drop stays put and a throw glides to its landing point inside `visibleFrame`.

A throw keeps the hand's speed: `Glide` takes an initial velocity, and the spring starts from it (`Spring` gains the displacement-and-velocity form; the zero-velocity form is today's curve). A tuck uses `.tuck`, a glide into open space `.settle`. Under Reduce Motion the ball goes straight to the spot, as every glide does.

**R84. The ghost.** While a drag is in progress with Auto-hide on and the disc's center within `edgeSnap` of an edge (the drop rule of R83), a ghost of the ball shows at the spot a drop would tuck into: the same glass disc, 35 percent opaque, no hand, no glow, in a borderless panel of its own, ordered just under the ball, that ignores the mouse, partly past the edge exactly as the tucked ball will be. It fades in and out over `DesignTokens.reveal` and `.dismiss`, and moves (without a glide) when the spot changes. It goes as the button comes up. A throw shows no ghost of its own: the flight is the preview.

**R85. Copy.** README's ball row: it tucks into the nearest edge (left, right, or the bottom beside the Dock) after two seconds without use, wakes where it rests, and can be dragged anywhere or flicked at an edge. The site's Awake card: "Move toward it and it comes back out. Drag it anywhere, or flick it at an edge." A CHANGELOG line under Unreleased. Settings' Auto-hide footnote stays as it is.

## 3. Tests

- `BallEdgesTests`: a bottom Dock splits the bottom edge into two stretches 80 pt clear of the Dock's ends; no Dock leaves the whole bottom free; an unknown Dock with a bottom inset leaves the bottom closed; a left Dock splits the left edge; corners keep 48 pt; a display touching the right edge closes that span; `tuck(nearest:)` from over the Dock picks the Dock's end when it is nearer and a side edge when that is; the tucked center sits 4.8 pt inside its edge and `home(for:)` one radius inside it; `ringSafe` beside the Dock measures from the real bottom and over it from `visibleFrame`; nothing free returns nil.
- `SpringTests`: with zero velocity the new form equals `value(at:)`; with velocity it starts at that velocity and still settles inside its settle time.
- `ThrowTests` (pure helpers next to `BallEdges` or in `Motion.swift`): velocity from samples ignores samples older than 80 ms; a slow release is not a throw; the projection is `v · 0.499` s; a path is stopped at the screen's frame and reports the edge it crossed.
- `FloatingBallTests`: a home on the real bottom edge, below `visibleFrame`, survives `onScreenOrigin`; an origin off every screen still comes back inside the nearest visible frame.
- The existing tests pass.
- By hand, on Malik's Mac: drag toward the bottom right beside the Dock and see the ghost on the real edge, release and see it tuck there; drop just above the middle of the Dock and see it glide to the Dock's end; flick toward the bottom left and see it fly and tuck there; leave it in the middle, wait for the tuck, come near it and see it come out at the edge, not in the middle; quit and relaunch and see it at the same spot; hover the Dock's end icons and see the ball stay tucked.
