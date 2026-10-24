# Capture Shapes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Point lands on the capsule, card, or panel under the pointer whose edges are drawn on screen, even where the app exposes none to accessibility (`specs/capture-shapes.md`, R116–R123). Shapes with no drawn edge (the "Thought deleted" pill, the Notification sheet's faded bottom) fall back to the cluster.

**Architecture:**
- **Two pure units.** `ShapeFinder` (new, pure) reads shapes from a `PixelGrid`, an RGBA screen sample at the display's own scale, by a tolerance-bounded flood fill. `HitRefiner` (pure) gains a shape-aware ladder that takes the shapes through a small `ShapeSource` protocol, so tests use fixed rectangles and the app uses `ShapeLookup` over the live sample.
- **The live sample.** `ScreenSampler` (new, a class) keeps one recent region image of the area hover reads. `AppState` asks it for the area, runs the ladder off the main actor, and reads the spot again when a new image lands.
- **The fallback.** The v0.1 cluster stays as the fallback, now under any parent (R120).
- **The payload.** A committed shape takes its members from the drawn-frame walk.

**Tech Stack:** Swift 6 (strict concurrency complete), CoreGraphics, ScreenCaptureKit (`SCScreenshotManager` with `sourceRect`), ApplicationServices (accessibility), XCTest. The blur script uses Vision and Core Image (scripts only, not the app). No packages, no new app frameworks.

## Global Constraints

- **Spec.** `specs/capture-shapes.md`, as amended in the commit that adds this plan. Requirement numbers below are that file's.
- **Frameworks:** Foundation, AppKit, SwiftUI, ScreenCaptureKit, Vision, ApplicationServices, AudioToolbox only (`docs/CLAUDE.md`). No `os`/`OSLog`: Debug timing uses `NSLog` under `#if DEBUG`.
- **Value types, singletons, errors:** value types for data; classes only for objects owning system resources (`ScreenSampler` owns a capture task); one `@Observable AppState`; typed errors.
- **Privacy:** Locant never appears in its own captures. Every ScreenCaptureKit call goes through the filter excluding Locant's windows. Screen samples live in memory only and are dropped when the overlay closes.
- **No private API.**
- **Copy, verbatim:**
  - rawRole: `LocantShape`
  - Markdown head line for a shape: `cluster · N elements (shape found on screen by Locant, not an accessibility element; frame from its visible edges)`
  - Readout of a shape or cluster: `cluster` · member names joined by `, ` (label, else identifier; nameless members left out); just `cluster` with no names.
- **Numbers (R117–R120):**
  - Edge tolerance 4, seed tolerance 24 (set by the real-screen fixtures on Oct 23; a change reruns them and amends the spec).
  - Patch 5 pt, ring 2 pt, minimum side 12 pt, minimum growth 2 pt, edge slack 1 pt, area limit 60%, enclosing levels 3.
  - Hold 3 pt, merge 2 pt.
  - Sampler refresh 1 s, max 4,000,000 samples.
- **Commits:** `area: what changed`. Never commit without a green build (`docs/CLAUDE.md`). No attribution lines. Don't push. Don't open a PR.
- **Comments:** match each file's density and voice. Cite `specs/capture-shapes.md R1xx` the first time in a file, then `R1xx`.
- **New files:** this repo's groups are file-system-synchronized, so new files need no `project.pbxproj` edit. Fixture PNGs and JSON in `LocantTests/Fixtures/` are copied into the test bundle and found by `Bundle(for:).url(forResource:withExtension:)`, as the JSON fixtures are.
- **zsh gotcha:** `=word` expands to a command path, so never `echo ====`; quote it.

Shell setup used by every task (zsh):

```bash
W=/Users/malik/Documents/Locant/.claude/worktrees/competent-liskov-6b2687
SP=/private/tmp/claude-501/-Users-malik-Documents-Locant--claude-worktrees-competent-liskov-6b2687/52a6a21e-c1a3-4427-9a9f-e30c60d3b025/scratchpad
DD=$SP/dd
cd $W
```

If you run this plan from another session, set `W` to that worktree and `SP` to that session's scratchpad. Everything else is relative to them.

- **Build:** `xcodebuild -project Locant.xcodeproj -scheme Locant -configuration Debug -destination 'platform=macOS' -derivedDataPath "$DD" build -quiet`. Expected: no output, exit 0.
- **Tests:** `xcodebuild -project Locant.xcodeproj -scheme Locant -destination 'platform=macOS' -derivedDataPath "$DD" test -quiet <-only-testing:LocantTests/…>`. Expected: exit 0. Without `-quiet`, the log ends with `** TEST SUCCEEDED **`; a failure prints the assertion and `** TEST FAILED **`.
- **The probe:** some tasks compile real app sources into a command-line tool in `$SP` to read the live screen with no input sent. The reader set that compiles on its own (checked Oct 23):

```bash
READER="$W/Locant/Resolve/AccessibilityReader.swift $W/Locant/Resolve/ElementResolver.swift $W/Locant/Resolve/RegionResolver.swift $W/Locant/Capture/Geometry.swift $W/Locant/Model/Capture.swift $W/Locant/Payload/AgentPaste.swift $W/Locant/Payload/HandoffPasteboard.swift $W/Locant/Payload/PasteboardWriter.swift"
```

Once Malik approves them, the spec amendments and this plan are committed together, before Task 1:

```bash
git add specs/capture-shapes.md docs/superpowers/plans/2026-10-23-capture-shapes.md
git commit -m "specs: capture shapes sample at the display's scale, check the drawn-frame miss first, and plan"
```

**What needs Malik.**
- **Task 1:** he opens a thought's detail screen in Oryne in Device Hub.
- **Task 3:** he decides only if no tolerance pair passes every fixture.
- **Task 9:** his hands and eyes for the feel.

Ask before each; don't send synthetic input while he is at the Mac.

---

### Task 1: Check the drawn-frame miss before changing the walk (R122)

On Oct 23 the real walk found all 10 elements of the Library screen. This task checks the thought-detail toolbar, where the Oct 18 frame found 0. It may end with no code change.

**Files:**
- Modify (only if Step 3 finds a miss): `Locant/Resolve/AccessibilityReader.swift` (`elements(in:pid:)`)
- No test file: the walk reads live accessibility and has no unit tests. The probe is the check.

**Interfaces:**
- Consumes: `AccessibilityReader.snapshot(at:candidates:fallbackPID:)`, `AccessibilityReader.elements(in:pid:)`, `HitRefiner.simulatedScreen(in:)`, `RegionResolver.elements(in:among:)`.
- Produces: nothing new. If Step 4a applies, `elements(in:pid:)` keeps its signature.

- [ ] **Step 1: Ask Malik** to open any thought's detail screen in Oryne on the booted iPhone 17 in Device Hub (the screen with the back button and the share/pencil/trash capsule at the top), and to leave the pointer off Device Hub.

- [ ] **Step 2: Write and build the probe.**

```bash
mkdir -p $SP/r122 && cat > $SP/r122/main.swift <<'EOF'
import AppKit
// specs/capture-shapes.md R122: at the top of the simulated screen in Device Hub (the thought detail's
// toolbar), does the drawn-frame walk find every element hover reads? Read-only: no input is sent.
guard let hub = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dt.Devices").first else { print("Device Hub is not running"); exit(1) }
let pid = hub.processIdentifier
let reader = AccessibilityReader()
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
guard let entry = info.first(where: { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }),
      let window = CGRect(dictionaryRepresentation: entry[kCGWindowBounds as String] as! CFDictionary) else { print("no Device Hub window"); exit(1) }
var screen: CGRect?
for i in 0..<100 where screen == nil {
    let p = CGPoint(x: window.minX + window.width * (0.05 + 0.9 * Double(i % 10) / 9), y: window.minY + window.height * (0.05 + 0.9 * Double(i / 10) / 9))
    if let s = await reader.snapshot(at: p, candidates: [], fallbackPID: pid) { screen = HitRefiner.simulatedScreen(in: s) }
}
guard let screen else { print("no simulated screen in the window"); exit(1) }
let band = CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: 130)
print("screen", screen, "band", band)
var hover: [String: CGRect] = [:]
var y = band.minY + 3
while y < band.maxY {
    var x = band.minX + 3
    while x < band.maxX {
        if let s = await reader.snapshot(at: CGPoint(x: x, y: y), candidates: [], fallbackPID: pid),
           let e = ElementResolver.resolve(s), !ElementResolver.containerRoles.contains(e.role) {
            hover["\(e.role) \(e.identifier ?? e.label ?? "-")"] = e.frame.cgRect
        }
        x += 6
    }
    y += 6
}
let walked = RegionResolver.elements(in: band, among: await reader.elements(in: band, pid: pid))
let walkedKeys = Set(walked.map { "\($0.role) \($0.identifier ?? $0.label ?? "-")" })
print("hover reads:", hover.keys.sorted())
print("walk finds: ", walkedKeys.sorted())
let missed = hover.filter { key, frame in !walkedKeys.contains(key) && frame.intersection(band).height >= frame.height / 2 }
print(missed.isEmpty ? "walk misses nothing" : "walk misses: \(missed.keys.sorted())")
EOF
eval xcrun swiftc -O -o $SP/r122/probe $SP/r122/main.swift $READER 2>&1 | grep -E "error" ; $SP/r122/probe
```

Expected: a `screen` line, then `hover reads:` and `walk finds:` lists, then one verdict line.

- [ ] **Step 3: Decide.**
  - **`walk misses nothing`, and `hover reads:` lists the toolbar's buttons:** R122 needs no code change. Go to Step 5.
  - **`hover reads:` lists no toolbar buttons** (only text below the toolbar, or nothing): the tree exposes no buttons there, so a drawn frame cannot list them. R122 needs no code change. Note it for the report and go to Step 5.
  - **`walk misses: […]`:** the walk is broken. Find out whether its limits cause it, by rebuilding the probe against a copy with the limits lifted:

```bash
sed -e 's/depth < 14/depth < 40/' -e 's/visited < 800/visited < 20000/' Locant/Resolve/AccessibilityReader.swift > $SP/r122/AccessibilityReader.swift
eval xcrun swiftc -O -o $SP/r122/probe-wide $SP/r122/main.swift $SP/r122/AccessibilityReader.swift ${READER#* } 2>&1 | grep -E "error"; $SP/r122/probe-wide
```

(`${READER#* }` is `$READER` without its first file, the real `AccessibilityReader.swift`.)
    - If the miss disappears: Step 4a.
    - If it doesn't: Step 4b.

- [ ] **Step 4a (only if the limits caused the miss): count only nodes that touch the frame, and allow deeper trees.** In `Locant/Resolve/AccessibilityReader.swift`, replace:

```swift
        func walk(_ node: AXUIElement, ancestors: [AttributeSet], depth: Int) {
            guard visited < 800, depth < 14 else { return }
            visited += 1
            let frame = frame(copy(node, Self.frameAttribute))
            if let frame, frame.w > 0, frame.h > 0, !frame.cgRect.intersects(region) { return }
```

with:

```swift
        // specs/capture-shapes.md R122: the budget counts only nodes that touch the region, so a large
        // sidebar does not use it up, and Device Hub's trees nest deeper than the Simulator's did.
        func walk(_ node: AXUIElement, ancestors: [AttributeSet], depth: Int) {
            guard visited < 800, depth < 24 else { return }
            let frame = frame(copy(node, Self.frameAttribute))
            if let frame, frame.w > 0, frame.h > 0, !frame.cgRect.intersects(region) { return }
            visited += 1
```

Rerun Step 2 against the real file (`$READER`). Expected: `walk misses nothing`.

- [ ] **Step 4b (only if the limits were not the cause): fall back to hit-testing a grid.** The miss then means the tree's children do not lead to what hit-testing reaches. Add to `AccessibilityReader`, after `elements(in:pid:)`:

```swift
    /// specs/capture-shapes.md R122: where the tree's children do not lead to what hit-testing reaches
    /// (seen in Device Hub), the non-container elements a grid of hit tests finds inside `region`, every
    /// 8 pt or wider, at most 400 tests.
    func hitElements(in region: CGRect, pid: pid_t) -> [ElementSnapshot] {
        let app = AXUIElementCreateApplication(pid)
        let step = max(8, ((region.width * region.height) / 400).squareRoot())
        var found: [ElementSnapshot] = []
        var seen = Set<Frame>()
        var y = region.minY + step / 2
        while y < region.maxY {
            var x = region.minX + step / 2
            while x < region.maxX {
                if let element = hit(app, at: CGPoint(x: x, y: y)) {
                    let attributes = lightAttributes(of: element)
                    if let frame = attributes.frame, !ElementResolver.isContainer(attributes), seen.insert(frame).inserted {
                        found.append(ElementSnapshot(element: attributes, ancestors: []))
                    }
                }
                x += step
            }
            y += step
        }
        return found
    }
```

In `AppState.region(_:start:)`, after the lazy-tree retry loop (`while snapshots.isEmpty, retry < 2 { … }`), add:

```swift
            // R122: the tree's children did not reach what hit-testing does.
            if RegionResolver.elements(in: rect, among: snapshots).isEmpty {
                snapshots = await reader.hitElements(in: rect, pid: pid)
            }
```

Rerun Step 2 with the probe's walk line changed to `walked = RegionResolver.elements(in: band, among: await reader.elements(in: band, pid: pid) + reader.hitElements(in: band, pid: pid))`. Expected: `walk misses nothing`. Task 8's `withWalkedMembers` must use the same fallback; Task 8 Step 5 says how.

- [ ] **Step 5: Build, test, commit (only if Step 4a or 4b changed code).**

```bash
xcodebuild -project Locant.xcodeproj -scheme Locant -configuration Debug -destination 'platform=macOS' -derivedDataPath "$DD" build -quiet
xcodebuild -project Locant.xcodeproj -scheme Locant -destination 'platform=macOS' -derivedDataPath "$DD" test -quiet
git add Locant/Resolve/AccessibilityReader.swift Locant/App/AppState.swift
git commit -m "region: a drawn frame in Device Hub finds the elements hover reads"
```

With no code change, write the probe's output to `$SP/r122/result.txt` and quote it in the final report.

---

### Task 2: PixelGrid and ShapeFinder (R119), on synthetic screens

**Files:**
- Create: `Locant/Resolve/ShapeFinder.swift`
- Create: `LocantTests/ShapeFinderTests.swift`

**Interfaces:**
- Produces:
  - `struct PixelGrid: Sendable`, with:
    - `frame: CGRect`, `scale: CGFloat`, `width: Int`, `height: Int`, `bytes: [UInt8]`, `generation: Int`, `edges: [Bool]`
    - `static func edgeMap(_ bytes: [UInt8], width: Int, height: Int, tolerance: Int) -> [Bool]`
    - `init(frame:scale:width:height:bytes:generation:)`
    - `init?(image: CGImage, frame: CGRect, scale: CGFloat, generation: Int)`
    - `func color(x: Int, y: Int) -> RGB`
    - `func sample(at: CGPoint) -> (x: Int, y: Int)?`
    - `func span(of: CGRect) -> SampleBox`
    - `func box(of: CGRect) -> SampleBox?`
    - `func rect(of: SampleBox) -> CGRect`
  - `struct SampleBox: Equatable, Sendable`: `minX`, `minY`, `maxX`, `maxY` (inclusive), `width`, `height`, `contains(x:y:)`.
  - `struct RGB: Equatable, Sendable`: `r`, `g`, `b: UInt8`, `func difference(_:) -> Int`.
  - `enum ShapeFinder`, with:
    - constants `edgeTolerance`, `seedTolerance`, `patchSide`, `ringOffset`, `minSide`, `minGrowth`, `edgeSlack`, `maxAreaFraction`, `enclosingLevels`
    - `struct Fill: Sendable { generation, box, taken: [Bool], shape: CGRect?; func covers(_: CGPoint, in: PixelGrid) -> Bool }`
    - `static func fill(at: CGPoint, in: PixelGrid, bound: CGRect) -> Fill?`
    - `static func shape(around: CGRect, in: PixelGrid, bound: CGRect) -> CGRect?`
    - `static func enclosing(_: CGRect, in: PixelGrid, bound: CGRect) -> [CGRect]`
    - `static func seedColor(of: [RGB]) -> RGB?`

- [ ] **Step 1: Write the failing tests.** Create `LocantTests/ShapeFinderTests.swift`:

```swift
import AppKit
import XCTest
@testable import Locant

/// specs/capture-shapes.md R119: shapes found in the pixels.
final class ShapeFinderTests: XCTestCase {
    /// A screen in points, `scale` samples per point, painted with rectangles, read as a grid at the origin.
    private struct Canvas {
        let widthPt: Int, heightPt: Int, scale: Int
        var bytes: [UInt8]

        init(_ widthPt: Int, _ heightPt: Int, scale: Int = 2, background: RGB) {
            self.widthPt = widthPt
            self.heightPt = heightPt
            self.scale = scale
            let samples = widthPt * scale * heightPt * scale
            bytes = [UInt8](repeating: 255, count: samples * 4)
            for i in 0..<samples {
                bytes[i * 4] = background.r
                bytes[i * 4 + 1] = background.g
                bytes[i * 4 + 2] = background.b
            }
        }

        var bounds: CGRect { CGRect(x: 0, y: 0, width: widthPt, height: heightPt) }

        /// Every sample whose center lies in `rect`, inside its corners of `radius`, takes `color(y)`.
        mutating func paint(_ rect: CGRect, radius: CGFloat = 0, _ color: (CGFloat) -> RGB) {
            let s = CGFloat(scale), width = widthPt * scale
            let x0 = max(0, Int((rect.minX * s).rounded(.down))), x1 = min(width, Int((rect.maxX * s).rounded(.up)))
            let y0 = max(0, Int((rect.minY * s).rounded(.down))), y1 = min(heightPt * scale, Int((rect.maxY * s).rounded(.up)))
            guard x0 < x1, y0 < y1 else { return }
            for y in y0..<y1 {
                for x in x0..<x1 {
                    let p = CGPoint(x: (CGFloat(x) + 0.5) / s, y: (CGFloat(y) + 0.5) / s)
                    guard rect.contains(p), Self.insideCorners(p, rect, radius) else { continue }
                    let c = color(p.y), i = (y * width + x) * 4
                    bytes[i] = c.r
                    bytes[i + 1] = c.g
                    bytes[i + 2] = c.b
                }
            }
        }

        mutating func paint(_ rect: CGRect, radius: CGFloat = 0, _ color: RGB) {
            paint(rect, radius: radius) { _ in color }
        }

        /// A `width` pt line along the inside of each edge of `rect`.
        mutating func outline(_ rect: CGRect, width: CGFloat = 1, _ color: RGB) {
            paint(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: width), color)
            paint(CGRect(x: rect.minX, y: rect.maxY - width, width: rect.width, height: width), color)
            paint(CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height), color)
            paint(CGRect(x: rect.maxX - width, y: rect.minY, width: width, height: rect.height), color)
        }

        func grid(generation: Int = 1) -> PixelGrid {
            PixelGrid(frame: bounds, scale: CGFloat(scale), width: widthPt * scale, height: heightPt * scale,
                      bytes: bytes, generation: generation)
        }

        private static func insideCorners(_ p: CGPoint, _ r: CGRect, _ radius: CGFloat) -> Bool {
            guard radius > 0 else { return true }
            let cx = min(max(p.x, r.minX + radius), r.maxX - radius)
            let cy = min(max(p.y, r.minY + radius), r.maxY - radius)
            return hypot(p.x - cx, p.y - cy) <= radius
        }
    }

    private let dark = RGB(r: 20, g: 20, b: 22)

    private func assertRect(_ found: CGRect?, _ expected: CGRect, within slack: CGFloat = 1, _ message: String = "",
                            file: StaticString = #filePath, line: UInt = #line) {
        guard let found else { return XCTFail("no shape; expected \(expected) \(message)", file: file, line: line) }
        for (a, b) in [(found.minX, expected.minX), (found.minY, expected.minY), (found.maxX, expected.maxX), (found.maxY, expected.maxY)] {
            XCTAssertEqual(a, b, accuracy: slack, "\(found) vs \(expected) \(message)", file: file, line: line)
        }
    }

    // A card on a flat background: from a point in its padding, and from the ring around a label in it.
    func testRoundedCardFromItsPaddingAndAroundALabel() {
        var canvas = Canvas(400, 300, background: dark)
        let card = CGRect(x: 100, y: 80, width: 160, height: 90)
        let label = CGRect(x: 120, y: 100, width: 60, height: 14)
        canvas.paint(card, radius: 12, RGB(r: 50, g: 50, b: 54))
        canvas.paint(label, RGB(r: 200, g: 200, b: 200))
        let grid = canvas.grid()
        assertRect(ShapeFinder.fill(at: CGPoint(x: 106, y: 125), in: grid, bound: canvas.bounds)?.shape, card)
        assertRect(ShapeFinder.shape(around: label, in: grid, bound: canvas.bounds), card)
    }

    // Oryne's Recent/Currents switch: two buttons fill a glass capsule but for a 3 pt rim, the selected
    // one lighter than the fill. The ring around either button finds the capsule, and so does its rim.
    func testCapsuleWhoseButtonsTouchFromEitherButton() {
        var canvas = Canvas(240, 120, background: RGB(r: 26, g: 27, b: 29))
        let capsule = CGRect(x: 37, y: 37.5, width: 162.5, height: 36.5)
        let recent = CGRect(x: 40, y: 40.5, width: 78, height: 30)
        let currents = CGRect(x: 118, y: 40.5, width: 78, height: 30)
        canvas.paint(capsule, radius: 18.25, RGB(r: 42, g: 42, b: 45))
        canvas.paint(currents, radius: 15, RGB(r: 80, g: 80, b: 84))
        canvas.paint(CGRect(x: 60, y: 50, width: 36, height: 10), RGB(r: 150, g: 150, b: 150)) // "Recent"
        let grid = canvas.grid()
        assertRect(ShapeFinder.shape(around: recent, in: grid, bound: canvas.bounds), capsule)
        assertRect(ShapeFinder.shape(around: currents, in: grid, bound: canvas.bounds), capsule)
        assertRect(ShapeFinder.fill(at: CGPoint(x: 38.5, y: 55), in: grid, bound: canvas.bounds)?.shape, capsule)
    }

    // A card whose fill runs through 20 levels top to bottom is one shape.
    func testGradientFillIsOneShape() {
        var canvas = Canvas(300, 300, background: RGB(r: 10, g: 10, b: 10))
        let card = CGRect(x: 50, y: 50, width: 200, height: 150)
        canvas.paint(card) { y in
            let level = UInt8(40 + Int((y - 50) / 150 * 20))
            return RGB(r: level, g: level, b: level)
        }
        assertRect(ShapeFinder.fill(at: CGPoint(x: 150, y: 125), in: canvas.grid(), bound: canvas.bounds)?.shape, card)
    }

    // The "Thought deleted" pill: its fill is the background's within 2 levels; only a 1 pt rim tells
    // them apart, and the fill stops at it.
    func testGlassRimStopsTheFill() {
        var canvas = Canvas(200, 120, background: RGB(r: 12, g: 14, b: 17))
        let pill = CGRect(x: 30, y: 30, width: 150, height: 44)
        canvas.paint(pill, radius: 22, RGB(r: 14, g: 14, b: 17))
        canvas.outline(pill, RGB(r: 30, g: 30, b: 34))
        let found = ShapeFinder.fill(at: CGPoint(x: 40, y: 52), in: canvas.grid(), bound: canvas.bounds)?.shape
        assertRect(found, pill.insetBy(dx: 1, dy: 1))
    }

    // The background touches two opposite sides of the bound: no shape. Nor is a strip that runs the
    // bound's full width, like a toolbar.
    func testBackgroundAndFullWidthStripGiveNoShape() {
        var canvas = Canvas(400, 300, background: dark)
        canvas.paint(CGRect(x: 100, y: 80, width: 160, height: 90), radius: 12, RGB(r: 50, g: 50, b: 54))
        canvas.paint(CGRect(x: 0, y: 260, width: 400, height: 40), RGB(r: 60, g: 60, b: 64))
        let grid = canvas.grid()
        XCTAssertNil(ShapeFinder.fill(at: CGPoint(x: 20, y: 20), in: grid, bound: canvas.bounds)?.shape)
        XCTAssertNil(ShapeFinder.fill(at: CGPoint(x: 200, y: 280), in: grid, bound: canvas.bounds)?.shape)
    }

    // 60% of the bound or more is not a shape, nor is anything under 12 pt either way.
    func testTooBigOrTooSmallGivesNoShape() {
        var canvas = Canvas(400, 300, background: dark)
        canvas.paint(CGRect(x: 10, y: 10, width: 370, height: 260), RGB(r: 50, g: 50, b: 54))
        canvas.paint(CGRect(x: 100, y: 100, width: 10, height: 30), RGB(r: 90, g: 90, b: 94))
        let grid = canvas.grid()
        XCTAssertNil(ShapeFinder.fill(at: CGPoint(x: 300, y: 200), in: grid, bound: canvas.bounds)?.shape)
        XCTAssertNil(ShapeFinder.fill(at: CGPoint(x: 105, y: 115), in: grid, bound: canvas.bounds)?.shape)
    }

    // A pill on a sheet that meets the bottom of the bound: the pill from its padding, the sheet around
    // it, and nothing beyond, since the background runs the bound's width.
    func testPillInsideASheet() {
        var canvas = Canvas(300, 600, background: RGB(r: 4, g: 4, b: 5))
        let sheet = CGRect(x: 10, y: 300, width: 280, height: 300)
        let pill = CGRect(x: 40, y: 340, width: 120, height: 36)
        canvas.paint(sheet, radius: 30, RGB(r: 30, g: 30, b: 34))
        canvas.paint(pill, radius: 18, RGB(r: 60, g: 60, b: 64))
        let grid = canvas.grid()
        assertRect(ShapeFinder.fill(at: CGPoint(x: 50, y: 358), in: grid, bound: canvas.bounds)?.shape, pill)
        let around = ShapeFinder.enclosing(pill, in: grid, bound: canvas.bounds)
        XCTAssertEqual(around.count, 1)
        assertRect(around.first, sheet)
        assertRect(ShapeFinder.fill(at: CGPoint(x: 20, y: 500), in: grid, bound: canvas.bounds)?.shape, sheet)
    }

    // A pointer on an icon's stroke seeds from the fill around it.
    func testPointerOnAnIconStrokeFindsThePill() {
        var canvas = Canvas(220, 120, background: RGB(r: 10, g: 10, b: 12))
        let pill = CGRect(x: 50, y: 40, width: 120, height: 40)
        canvas.paint(pill, radius: 20, RGB(r: 40, g: 40, b: 44))
        canvas.paint(CGRect(x: 100, y: 48, width: 1.5, height: 24), RGB(r: 220, g: 220, b: 220))
        assertRect(ShapeFinder.fill(at: CGPoint(x: 100.75, y: 60), in: canvas.grid(), bound: canvas.bounds)?.shape, pill)
    }

    func testSeedColorIsTheMeanOfTheLargestBucket() {
        let colors = [RGB(r: 16, g: 16, b: 16), RGB(r: 17, g: 17, b: 17), RGB(r: 23, g: 23, b: 23),
                      RGB(r: 200, g: 0, b: 0), RGB(r: 201, g: 0, b: 0)]
        XCTAssertEqual(ShapeFinder.seedColor(of: colors), RGB(r: 18, g: 18, b: 18))
        XCTAssertNil(ShapeFinder.seedColor(of: []))
    }

    // The conversion the live sample and the fixtures share keeps the top row first.
    func testGridFromAnImageIsTopRowFirst() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 2, width: 4, height: 2)) // Core Graphics' y runs up: the top half
        let image = try XCTUnwrap(context.makeImage())
        let grid = try XCTUnwrap(PixelGrid(image: image, frame: CGRect(x: 10, y: 20, width: 2, height: 2), scale: 2, generation: 1))
        XCTAssertEqual(grid.color(x: 0, y: 0), RGB(r: 255, g: 0, b: 0))
        XCTAssertEqual(grid.color(x: 0, y: 3), RGB(r: 0, g: 0, b: 255))
        XCTAssertEqual(grid.sample(at: CGPoint(x: 11.9, y: 21.9))?.x, 3)
        XCTAssertNil(grid.sample(at: CGPoint(x: 12, y: 20)))
    }

    // R119: while the pointer stays on the samples a fill took, its answer stands.
    func testAFillCoversTheSamplesItTook() throws {
        var canvas = Canvas(400, 300, background: dark)
        canvas.paint(CGRect(x: 100, y: 80, width: 160, height: 90), RGB(r: 50, g: 50, b: 54))
        let grid = canvas.grid()
        let fill = try XCTUnwrap(ShapeFinder.fill(at: CGPoint(x: 106, y: 125), in: grid, bound: canvas.bounds))
        XCTAssertTrue(fill.covers(CGPoint(x: 250, y: 160), in: grid))
        XCTAssertFalse(fill.covers(CGPoint(x: 20, y: 20), in: grid))
        XCTAssertFalse(fill.covers(CGPoint(x: 250, y: 160), in: canvas.grid(generation: 2)), "a newer sample")
    }
}
```

- [ ] **Step 2: Run them to see them fail.** `xcodebuild … test -quiet -only-testing:LocantTests/ShapeFinderTests`. Expected: a compile failure naming `RGB`, `PixelGrid`, and `ShapeFinder` as not found.

- [ ] **Step 3: Write the implementation.** Create `Locant/Resolve/ShapeFinder.swift`:

```swift
import CoreGraphics
import Foundation

/// specs/capture-shapes.md R118: a screen sample as `ShapeFinder` reads it. RGBA, 8 bits per channel,
/// top row first, `scale` samples per point; `frame` is the area it shows, in global CG points.
struct PixelGrid: Sendable {
    let frame: CGRect
    let scale: CGFloat
    let width: Int
    let height: Int
    let bytes: [UInt8]
    /// Rises with every new sample, so nothing read from an older one is reused (R119).
    let generation: Int
    /// R119: the edge samples, mapped once here so hover never pays for them.
    let edges: [Bool]

    init(frame: CGRect, scale: CGFloat, width: Int, height: Int, bytes: [UInt8], generation: Int) {
        precondition(bytes.count == width * height * 4, "four bytes a sample")
        self.frame = frame
        self.scale = scale
        self.width = width
        self.height = height
        self.bytes = bytes
        self.generation = generation
        self.edges = Self.edgeMap(bytes, width: width, height: height, tolerance: ShapeFinder.edgeTolerance)
    }

    /// R119: a sample is an edge when one of its four neighbors differs from it by more than `tolerance`.
    /// A thin rim between two equal fills is an edge on both sides; a gradient of a level or two is not.
    static func edgeMap(_ bytes: [UInt8], width: Int, height: Int, tolerance: Int) -> [Bool] {
        var edges = [Bool](repeating: false, count: width * height)
        bytes.withUnsafeBufferPointer { px in
            edges.withUnsafeMutableBufferPointer { e in
                for y in 0..<height {
                    for x in 0..<width {
                        let i = (y * width + x) * 4
                        let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
                        func far(_ j: Int) -> Bool {
                            max(abs(Int(px[j]) - r), abs(Int(px[j + 1]) - g), abs(Int(px[j + 2]) - b)) > tolerance
                        }
                        if (x > 0 && far(i - 4)) || (x < width - 1 && far(i + 4))
                            || (y > 0 && far(i - width * 4)) || (y < height - 1 && far(i + width * 4)) {
                            e[y * width + x] = true
                        }
                    }
                }
            }
        }
        return edges
    }

    /// The image drawn into an RGBA buffer of its own size. The one conversion for the live sample and
    /// the test fixtures, so both are read the same way.
    init?(image: CGImage, frame: CGRect, scale: CGFloat, generation: Int) {
        let width = image.width, height = image.height
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.init(frame: frame, scale: scale, width: width, height: height, bytes: bytes, generation: generation)
    }

    func color(x: Int, y: Int) -> RGB {
        let i = (y * width + x) * 4
        return RGB(r: bytes[i], g: bytes[i + 1], b: bytes[i + 2])
    }

    /// The sample under a global point; nil off the grid.
    func sample(at point: CGPoint) -> (x: Int, y: Int)? {
        let x = Int(((point.x - frame.minX) * scale).rounded(.down))
        let y = Int(((point.y - frame.minY) * scale).rounded(.down))
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        return (x, y)
    }

    /// The samples a global rectangle covers, unclipped: they may lie off the grid.
    func span(of rect: CGRect) -> SampleBox {
        SampleBox(minX: Int(((rect.minX - frame.minX) * scale).rounded(.down)),
                  minY: Int(((rect.minY - frame.minY) * scale).rounded(.down)),
                  maxX: Int(((rect.maxX - frame.minX) * scale).rounded(.up)) - 1,
                  maxY: Int(((rect.maxY - frame.minY) * scale).rounded(.up)) - 1)
    }

    /// `span(of:)` clipped to the grid; nil when nothing is left.
    func box(of rect: CGRect) -> SampleBox? {
        let raw = span(of: rect)
        let clipped = SampleBox(minX: max(raw.minX, 0), minY: max(raw.minY, 0),
                                maxX: min(raw.maxX, width - 1), maxY: min(raw.maxY, height - 1))
        return clipped.minX <= clipped.maxX && clipped.minY <= clipped.maxY ? clipped : nil
    }

    /// Samples back in global points.
    func rect(of box: SampleBox) -> CGRect {
        CGRect(x: frame.minX + CGFloat(box.minX) / scale, y: frame.minY + CGFloat(box.minY) / scale,
               width: CGFloat(box.width) / scale, height: CGFloat(box.height) / scale)
    }
}

/// Inclusive sample bounds.
struct SampleBox: Equatable, Sendable {
    var minX: Int, minY: Int, maxX: Int, maxY: Int

    var width: Int { maxX - minX + 1 }
    var height: Int { maxY - minY + 1 }

    func contains(x: Int, y: Int) -> Bool { x >= minX && x <= maxX && y >= minY && y <= maxY }
}

struct RGB: Equatable, Sendable {
    var r: UInt8, g: UInt8, b: UInt8

    /// R119: the largest of the three channel differences, on a 0–255 scale.
    func difference(_ other: RGB) -> Int {
        max(abs(Int(r) - Int(other.r)), abs(Int(g) - Int(other.g)), abs(Int(b) - Int(other.b)))
    }
}

/// specs/capture-shapes.md R119: the shape the pixels show at a point or around a rectangle: edges first,
/// then a fill through what is not an edge. Pure.
enum ShapeFinder {
    /// A sample is an edge when a neighbor differs from it by more than this; seeds are within it of the
    /// seed color. Set by the real-screen fixtures on Oct 23 (6 leaked out of every glass shape).
    static let edgeTolerance = 4
    /// The largest difference from the seed color a fill takes: stops a drift through a gap in an edge.
    static let seedTolerance = 24
    /// Points: the patch around the pointer, and the ring's distance outside a rectangle.
    static let patchSide: CGFloat = 5
    static let ringOffset: CGFloat = 2
    /// Points: the smallest shape, and how much larger than a rectangle the shape around it must be.
    static let minSide: CGFloat = 12
    static let minGrowth: CGFloat = 2
    /// Points: a fill this close to two opposite sides of the bound is the background.
    static let edgeSlack: CGFloat = 1
    static let maxAreaFraction = 0.6
    static let enclosingLevels = 3

    /// One fill from the pointer: the samples it took, so its answer stands while the pointer stays on
    /// them (R119), and the shape when R119 accepted it.
    struct Fill: Sendable {
        let generation: Int
        let box: SampleBox
        let taken: [Bool]
        let shape: CGRect?

        func covers(_ point: CGPoint, in grid: PixelGrid) -> Bool {
            guard grid.generation == generation, let s = grid.sample(at: point), box.contains(x: s.x, y: s.y) else { return false }
            return taken[(s.y - box.minY) * box.width + (s.x - box.minX)]
        }
    }

    /// The fill from the 5×5 pt patch around `point`; its `shape` is nil when R119 rejects it. Nil when
    /// the point lies outside the bound or the grid.
    static func fill(at point: CGPoint, in grid: PixelGrid, bound: CGRect) -> Fill? {
        guard let box = grid.box(of: bound), let center = grid.sample(at: point),
              box.contains(x: center.x, y: center.y) else { return nil }
        let half = Int((patchSide * grid.scale / 2).rounded(.down))
        var patch: [(x: Int, y: Int)] = []
        for y in (center.y - half)...(center.y + half) {
            for x in (center.x - half)...(center.x + half) where box.contains(x: x, y: y) {
                patch.append((x, y))
            }
        }
        guard let seed = seedColor(of: patch.map { grid.color(x: $0.x, y: $0.y) }) else { return nil }
        let seeds = patch.filter { grid.color(x: $0.x, y: $0.y).difference(seed) <= edgeTolerance }
        let grown = grow(from: seeds, seed: seed, in: grid, box: box)
        var shape = grown.extent.flatMap { accept($0, in: box, grid: grid) }
        if let found = shape, !found.contains(point) { shape = nil }
        return Fill(generation: grid.generation, box: box, taken: grown.taken, shape: shape)
    }

    /// The shape around `rect`: the fill from the ring 2 pt outside it, accepted only if it holds `rect`
    /// and is at least 2 pt larger on one side, so an element's own background is not its shape.
    static func shape(around rect: CGRect, in grid: PixelGrid, bound: CGRect) -> CGRect? {
        guard let box = grid.box(of: bound) else { return nil }
        let ring = ringSamples(around: rect.insetBy(dx: -ringOffset, dy: -ringOffset), in: grid, box: box)
        guard let seed = seedColor(of: ring.map { grid.color(x: $0.x, y: $0.y) }) else { return nil }
        let seeds = ring.filter { grid.color(x: $0.x, y: $0.y).difference(seed) <= edgeTolerance }
        guard let extent = grow(from: seeds, seed: seed, in: grid, box: box).extent,
              let shape = accept(extent, in: box, grid: grid),
              shape.insetBy(dx: -edgeSlack, dy: -edgeSlack).contains(rect) else { return nil }
        let growth = max(rect.minX - shape.minX, shape.maxX - rect.maxX, rect.minY - shape.minY, shape.maxY - rect.maxY)
        return growth >= minGrowth ? shape : nil
    }

    /// The shapes around `rect`, innermost first: each found around the one before, up to three,
    /// stopping at the first that finds nothing.
    static func enclosing(_ rect: CGRect, in grid: PixelGrid, bound: CGRect) -> [CGRect] {
        var found: [CGRect] = []
        var current = rect
        while found.count < enclosingLevels, let next = shape(around: current, in: grid, bound: bound) {
            found.append(next)
            current = next
        }
        return found
    }

    /// R119's "most common color": counted with each channel's three low bits dropped; the mean of the
    /// largest bucket, the lower bucket on a tie.
    static func seedColor(of colors: [RGB]) -> RGB? {
        var buckets: [Int: (count: Int, r: Int, g: Int, b: Int)] = [:]
        for c in colors {
            let key = Int(c.r >> 3) << 10 | Int(c.g >> 3) << 5 | Int(c.b >> 3)
            var bucket = buckets[key] ?? (0, 0, 0, 0)
            bucket.count += 1
            bucket.r += Int(c.r)
            bucket.g += Int(c.g)
            bucket.b += Int(c.b)
            buckets[key] = bucket
        }
        guard let best = buckets.max(by: { a, b in
            a.value.count < b.value.count || (a.value.count == b.value.count && a.key > b.key)
        }) else { return nil }
        let n = best.value.count
        return RGB(r: UInt8(best.value.r / n), g: UInt8(best.value.g / n), b: UInt8(best.value.b / n))
    }

    // MARK: Growing

    private struct Growth {
        var taken: [Bool]
        /// Nil when nothing was taken, or when the fill reached two opposite sides of the bound or passed
        /// `maxAreaFraction` of it, and stopped: the background.
        var extent: SampleBox?
    }

    private static let steps = [(-1, 0), (1, 0), (0, -1), (0, 1)]

    /// The 4-connected fill from `seeds` inside `box`: a neighbor joins when it is not an edge sample
    /// (`PixelGrid.edges`) and is within `seedTolerance` of the seed color.
    private static func grow(from seeds: [(x: Int, y: Int)], seed: RGB, in grid: PixelGrid, box: SampleBox) -> Growth {
        let bw = box.width, bh = box.height
        var taken = [Bool](repeating: false, count: bw * bh)
        guard !seeds.isEmpty else { return Growth(taken: taken, extent: nil) }
        let limit = Int(maxAreaFraction * Double(bw * bh))
        let slack = Int((edgeSlack * grid.scale).rounded())
        let gw = grid.width, ox = box.minX, oy = box.minY
        let sr = Int(seed.r), sg = Int(seed.g), sb = Int(seed.b)
        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        var count = 0
        var overflow = false
        var stack: [Int] = []
        stack.reserveCapacity(4096)
        grid.bytes.withUnsafeBufferPointer { px in
            grid.edges.withUnsafeBufferPointer { edge in
                taken.withUnsafeMutableBufferPointer { took in
                    func take(_ local: Int) {
                        took[local] = true
                        count += 1
                        let x = local % bw, y = local / bw
                        minX = min(minX, x); maxX = max(maxX, x)
                        minY = min(minY, y); maxY = max(maxY, y)
                        stack.append(local)
                    }
                    for s in seeds {
                        let local = (s.y - oy) * bw + (s.x - ox)
                        if !took[local] { take(local) }
                    }
                    while let current = stack.popLast() {
                        // The background: past the area limit, or across the bound from side to side.
                        if count > limit || (minX <= slack && maxX >= bw - 1 - slack) || (minY <= slack && maxY >= bh - 1 - slack) {
                            overflow = true
                            return
                        }
                        let x = current % bw, y = current / bw
                        for (dx, dy) in steps {
                            let nx = x + dx, ny = y + dy
                            guard nx >= 0, ny >= 0, nx < bw, ny < bh else { continue }
                            let next = ny * bw + nx
                            let at = (oy + ny) * gw + ox + nx
                            guard !took[next], !edge[at] else { continue }
                            let r = Int(px[at * 4]), g = Int(px[at * 4 + 1]), b = Int(px[at * 4 + 2])
                            guard max(abs(r - sr), abs(g - sg), abs(b - sb)) <= seedTolerance else { continue }
                            take(next)
                        }
                    }
                }
            }
        }
        guard !overflow, count > 0 else { return Growth(taken: taken, extent: nil) }
        return Growth(taken: taken, extent: SampleBox(minX: ox + minX, minY: oy + minY, maxX: ox + maxX, maxY: oy + maxY))
    }

    /// R119's tests: not the background (within `edgeSlack` of two opposite sides of the bound), under
    /// `maxAreaFraction` of it, at least `minSide` either way.
    private static func accept(_ extent: SampleBox, in box: SampleBox, grid: PixelGrid) -> CGRect? {
        let slack = Int((edgeSlack * grid.scale).rounded())
        let left = extent.minX - box.minX <= slack, right = box.maxX - extent.maxX <= slack
        let top = extent.minY - box.minY <= slack, bottom = box.maxY - extent.maxY <= slack
        guard !(left && right), !(top && bottom) else { return nil }
        let shape = grid.rect(of: extent), bound = grid.rect(of: box)
        guard shape.width * shape.height < maxAreaFraction * bound.width * bound.height,
              shape.width >= minSide, shape.height >= minSide else { return nil }
        return shape
    }

    /// The samples on the outline of `rect` that lie inside `box`.
    private static func ringSamples(around rect: CGRect, in grid: PixelGrid, box: SampleBox) -> [(x: Int, y: Int)] {
        let r = grid.span(of: rect)
        var ring: [(x: Int, y: Int)] = []
        for x in stride(from: r.minX, through: r.maxX, by: 1) {
            ring.append((x, r.minY))
            ring.append((x, r.maxY))
        }
        for y in stride(from: r.minY + 1, to: r.maxY, by: 1) {
            ring.append((r.minX, y))
            ring.append((r.maxX, y))
        }
        return ring.filter { box.contains(x: $0.x, y: $0.y) }
    }
}
```

- [ ] **Step 4: Run the tests to see them pass.** `xcodebuild … test -quiet -only-testing:LocantTests/ShapeFinderTests`. Expected: exit 0. If one fails, fix `ShapeFinder.swift`, not the test's expectation. The synthetic expectations are exact by construction.

- [ ] **Step 5: Build, run every test, commit.**

```bash
xcodebuild -project Locant.xcodeproj -scheme Locant -configuration Debug -destination 'platform=macOS' -derivedDataPath "$DD" build -quiet
xcodebuild -project Locant.xcodeproj -scheme Locant -destination 'platform=macOS' -derivedDataPath "$DD" test -quiet
git add Locant/Resolve/ShapeFinder.swift LocantTests/ShapeFinderTests.swift
git commit -m "shapes: find the shape around a point or a rectangle in a screen sample"
```

---

### Task 3: Real-screen fixtures, tolerances, and speed (§3)

**Files:**
- Create: `scripts/blur-fixture-text.swift`
- Create:
  - `LocantTests/Fixtures/shape-segments.png`
  - `LocantTests/Fixtures/shape-toolbar.png`
  - `LocantTests/Fixtures/shape-pill.png`
  - `LocantTests/Fixtures/shape-sheet.png`
  - `LocantTests/Fixtures/shape-claude-card.png`
  - `LocantTests/Fixtures/shape-web-list.png`
  - `LocantTests/Fixtures/shapes.json`
- Modify: `LocantTests/ShapeFinderTests.swift` (one test)
- Modify, only if Step 6 has to change them: `Locant/Resolve/ShapeFinder.swift` (the two tolerances) and `specs/capture-shapes.md` (R119's numbers)

**Interfaces:**
- Consumes: `PixelGrid(image:frame:scale:generation:)`, `ShapeFinder.fill(at:in:bound:)`, `ShapeFinder.shape(around:in:bound:)`, `ShapeFinder.enclosing(_:in:bound:)`.
- Produces: the fixture files, and a check of `ShapeFinder.edgeTolerance` (4) and `ShapeFinder.seedTolerance` (24) on them.

- [ ] **Step 1: Write the blur script.** Create `scripts/blur-fixture-text.swift`:

```swift
#!/usr/bin/env swift
// Blurs the text in a @2x screenshot so a real-screen fixture can be public, then reads it back and
// lists any text still legible (specs/capture-shapes.md, section 3).
// Usage: swift scripts/blur-fixture-text.swift <in.png> <out.png>
import AppKit
import CoreImage
import Vision

let args = CommandLine.arguments
guard args.count == 3 else { print("usage: blur-fixture-text <in.png> <out.png>"); exit(2) }
let input = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[2])
guard let rep = NSBitmapImageRep(data: try Data(contentsOf: input)), let image = rep.cgImage else {
    print("cannot read \(input.path)"); exit(1)
}
let width = image.width, height = image.height
let detect = VNDetectTextRectanglesRequest()
try VNImageRequestHandler(cgImage: image).perform([detect])
let original = CIImage(cgImage: image)
var result = original
for observation in detect.results ?? [] {
    // Vision's boxes are normalized with the origin at the bottom left, as Core Image's are.
    let box = VNImageRectForNormalizedRect(observation.boundingBox, width, height).insetBy(dx: -4, dy: -4).integral
    result = original.clampedToExtent().applyingGaussianBlur(sigma: 8).cropped(to: box).composited(over: result)
}
guard let blurred = CIContext().createCGImage(result, from: original.extent) else { print("cannot render"); exit(1) }
let out = NSBitmapImageRep(cgImage: blurred)
out.size = NSSize(width: CGFloat(width) / 2, height: CGFloat(height) / 2) // @2x, as the capture was
guard let png = out.representation(using: .png, properties: [:]) else { print("cannot encode"); exit(1) }
try png.write(to: output)
let read = VNRecognizeTextRequest()
read.recognitionLevel = .accurate
read.recognitionLanguages = ["en-US", "zh-Hans"]
try VNImageRequestHandler(cgImage: blurred).perform([read])
let legible = (read.results ?? []).compactMap { $0.topCandidates(1).first?.string }.filter { $0.count >= 3 }
print("\(output.lastPathComponent): blurred \(detect.results?.count ?? 0) text boxes; still legible: \(legible.isEmpty ? "none" : legible.joined(separator: " | "))")
```

- [ ] **Step 2: Make the six fixtures.** These are Malik's captures of the failing cases, plus two cards outside SwiftUI, as the spec names them.

```bash
P=/Users/malik/Pictures/Locant; F=LocantTests/Fixtures
swift scripts/blur-fixture-text.swift $P/locant-devicehub-20261023-022759-bkzx.png $F/shape-segments.png
swift scripts/blur-fixture-text.swift $P/locant-devicehub-20261018-231612-95js.png $F/shape-toolbar.png
swift scripts/blur-fixture-text.swift $P/locant-devicehub-20261023-023725-uoyv.png $F/shape-pill.png
swift scripts/blur-fixture-text.swift $P/locant-devicehub-20261023-023021-yu3f.png $F/shape-sheet.png
swift scripts/blur-fixture-text.swift $P/locant-claude-20261019-000746-vtbd.png $F/shape-claude-card.png
swift scripts/blur-fixture-text.swift $P/locant-dia-20261003-182251-7706.png $F/shape-web-list.png
```

- **Expected:** six lines, each ending `still legible: none`. A line listing words means text survived: rerun that file with `insetBy(dx: -8, dy: -8)` in the script. If words still survive, stop and show Malik the file.
- **Then:** open each PNG with the Read tool and look. You should see shapes and edges with no readable text.

- [ ] **Step 3: Write the expected rectangles.** These were measured on Oct 23 on the originals with a scanline tool independent of `ShapeFinder`, at the native 2x. Blurring moves no edges. Create `LocantTests/Fixtures/shapes.json`:

```json
[
  {
    "file": "shape-segments",
    "source": "20261023-022759-bkzx",
    "cases": [
      { "name": "capsule from its rim", "at": [38.5, 55], "expect": [37, 37.5, 162.5, 36.5] },
      { "name": "capsule around Recent", "around": [40.12, 40.85, 77.82, 29.92], "expect": [37, 37.5, 162.5, 36.5] },
      { "name": "capsule around Currents", "around": [117.94, 40.85, 77.82, 29.92], "expect": [37, 37.5, 162.5, 36.5] },
      { "name": "background", "at": [220, 95], "expect": null }
    ]
  },
  {
    "file": "shape-toolbar",
    "source": "20261018-231612-95js",
    "cases": [
      { "name": "capsule between share and pencil", "at": [290, 60], "expect": [246.5, 41, 139, 39.5] },
      { "name": "background", "at": [420, 20], "expect": null }
    ]
  },
  {
    "file": "shape-pill",
    "source": "20261023-023725-uoyv",
    "cases": [
      { "name": "pill from its padding: no edge drawn along its top", "at": [34, 48], "expect": null },
      { "name": "pill around its text: no edge drawn along its top", "around": [40.57, 40.1, 96.66, 14.96], "expect": null },
      { "name": "background", "at": [100, 10], "expect": null }
    ]
  },
  {
    "file": "shape-sheet",
    "source": "20261023-023021-yu3f",
    "bound": [40.5, 40, 334, 726.5],
    "cases": [
      { "name": "sheet from its margin: its bottom fades without a step", "at": [55, 500], "expect": null },
      { "name": "sheet around Add a thought: its bottom fades without a step", "around": [60, 447.5, 122.5, 34], "expect": null },
      { "name": "Library page behind it", "at": [200, 150], "expect": null }
    ]
  },
  {
    "file": "shape-claude-card",
    "source": "20261019-000746-vtbd",
    "cases": [
      { "name": "card from its padding", "at": [50, 100], "expect": [43.5, 39.5, 481, 147] },
      { "name": "background", "at": [600, 100], "expect": null }
    ]
  },
  {
    "file": "shape-web-list",
    "source": "20261003-182251-7706",
    "cases": [
      { "name": "row from its padding", "at": [300, 60], "expect": [40, 41, 401, 40] },
      { "name": "gap between cards", "at": [300, 90], "expect": null }
    ]
  }
]
```

Notes on these:
- **Points are local to the capture,** in points from its top-left.
- **`shape-sheet`'s `bound`** is the simulated screen inside that capture (the hit element's frame), which is what the live bound is. The capture also holds the device's bezel and the desktop around it.
- **Shapes cut by a capture's edge** (the file row) touch one side only, so they are still shapes. Their expected right edge is the capture's.
- **The pill and the sheet expect no shape.** They have no edge on screen to find (spec R119, measured Oct 23), so hover falls back to the cluster there (R120). Their measured rectangles, for the record: the pill 27.5, 32.5, 150.5 × 45 to the capture's right edge; the sheet 47, 385, 321 × 375. A change that makes either pass is a spec change: tell Malik rather than loosening a rule to get it.
- **The toolbar capsule** ends at 385.5 pt (771 px). A first reading took the trash icon's right edge, 733 px, for the capsule's.

- [ ] **Step 4: Write the failing test.** Add to `ShapeFinderTests`:

```swift
    // MARK: Real screens (section 3)

    private struct FixtureFile: Decodable {
        struct Case: Decodable {
            let name: String
            let at: [CGFloat]?
            let around: [CGFloat]?
            let expect: [CGFloat]?
        }
        let file: String
        let source: String
        let bound: [CGFloat]?
        let cases: [Case]
    }

    private func rect(_ v: [CGFloat]) -> CGRect { CGRect(x: v[0], y: v[1], width: v[2], height: v[3]) }

    /// Malik's captures of the failing cases and two cards outside SwiftUI, text blurred, at their 2x
    /// scale through the conversion the live sample uses. Expected rectangles were measured apart from
    /// `ShapeFinder`; a nil one is a background point that must give no shape.
    func testRealScreens() throws {
        let bundle = Bundle(for: Self.self)
        let index = try XCTUnwrap(bundle.url(forResource: "shapes", withExtension: "json"))
        let files = try JSONDecoder().decode([FixtureFile].self, from: Data(contentsOf: index))
        XCTAssertEqual(files.count, 6)
        for fixture in files {
            let url = try XCTUnwrap(bundle.url(forResource: fixture.file, withExtension: "png"), fixture.file)
            let image = try XCTUnwrap(NSBitmapImageRep(data: try Data(contentsOf: url))?.cgImage, fixture.file)
            let frame = CGRect(x: 0, y: 0, width: CGFloat(image.width) / 2, height: CGFloat(image.height) / 2)
            let grid = try XCTUnwrap(PixelGrid(image: image, frame: frame, scale: 2, generation: 1))
            let bound = fixture.bound.map(rect) ?? frame
            for c in fixture.cases {
                let label = "\(fixture.file): \(c.name)"
                let found: CGRect?
                if let at = c.at {
                    found = ShapeFinder.fill(at: CGPoint(x: at[0], y: at[1]), in: grid, bound: bound)?.shape
                } else {
                    found = ShapeFinder.shape(around: rect(try XCTUnwrap(c.around, label)), in: grid, bound: bound)
                }
                if let expect = c.expect {
                    assertRect(found, rect(expect), within: 2, label)
                } else {
                    XCTAssertNil(found, label)
                }
            }
        }
    }
```

- [ ] **Step 5: Run it.** `xcodebuild … test -quiet -only-testing:LocantTests/ShapeFinderTests/testRealScreens`. Expected: it passes. On Oct 23, this plan's own `ShapeFinder` code, run at (4, 24) on the unblurred captures, passed every case. If a case fails on the blurred files, the blur reached an edge. Run Step 6's tool on the original capture for that fixture before touching a tolerance, and widen the script's text box less, not the rules.

- [ ] **Step 6 (only if Step 5 still fails): sweep the two tolerances outside the app.** The edge map is built with the grid, so the tool rebuilds the grids for each edge tolerance.

```bash
mkdir -p $SP/sweep
sed -e 's/static let edgeTolerance = /nonisolated(unsafe) static var edgeTolerance = /' \
    -e 's/static let seedTolerance = /nonisolated(unsafe) static var seedTolerance = /' \
    Locant/Resolve/ShapeFinder.swift > $SP/sweep/ShapeFinder.swift
cat > $SP/sweep/main.swift <<'EOF'
import AppKit
// Sweeps R119's two tolerances over the real-screen fixtures, then times 100 lookups on shape-sheet's
// iPhone screen, cropped to it as the live sample is. Usage: sweep <LocantTests/Fixtures> [edge] [seed]
let dir = URL(fileURLWithPath: CommandLine.arguments[1])
struct FixtureFile: Decodable {
    struct Case: Decodable { let name: String; let at: [CGFloat]?; let around: [CGFloat]?; let expect: [CGFloat]? }
    let file: String; let source: String; let bound: [CGFloat]?; let cases: [Case]
}
func rect(_ v: [CGFloat]) -> CGRect { CGRect(x: v[0], y: v[1], width: v[2], height: v[3]) }
func image(_ name: String) -> CGImage { NSBitmapImageRep(data: try! Data(contentsOf: dir.appending(path: name + ".png")))!.cgImage! }
func grid(_ name: String) -> PixelGrid {
    let i = image(name)
    return PixelGrid(image: i, frame: CGRect(x: 0, y: 0, width: CGFloat(i.width) / 2, height: CGFloat(i.height) / 2), scale: 2, generation: 1)!
}
func close(_ a: CGRect?, _ b: [CGFloat]?) -> Bool {
    guard let b else { return a == nil }
    guard let a else { return false }
    let e = rect(b)
    return abs(a.minX - e.minX) <= 2 && abs(a.minY - e.minY) <= 2 && abs(a.maxX - e.maxX) <= 2 && abs(a.maxY - e.maxY) <= 2
}
let files = try! JSONDecoder().decode([FixtureFile].self, from: Data(contentsOf: dir.appending(path: "shapes.json")))
for edge in [3, 4, 5, 6] {
    ShapeFinder.edgeTolerance = edge
    let grids = Dictionary(uniqueKeysWithValues: files.map { ($0.file, grid($0.file)) })
    for seed in [16, 24, 40] {
        ShapeFinder.seedTolerance = seed
        var failed: [String] = []
        for f in files {
            let g = grids[f.file]!, bound = f.bound.map(rect) ?? g.frame
            for c in f.cases {
                let found = c.at.map { ShapeFinder.fill(at: CGPoint(x: $0[0], y: $0[1]), in: g, bound: bound)?.shape }
                    ?? ShapeFinder.shape(around: rect(c.around!), in: g, bound: bound)
                if !close(found, c.expect) { failed.append("\(f.file): \(c.name) → \(found.map { "\($0)" } ?? "nil")") }
            }
        }
        print("edge \(edge) seed \(seed): \(failed.isEmpty ? "all pass" : "\(failed.count) fail")")
        for line in failed { print("   ", line) }
    }
}
ShapeFinder.edgeTolerance = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2])! : 4
ShapeFinder.seedTolerance = CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[3])! : 24
let bound = rect(files.first { $0.file == "shape-sheet" }!.bound!)
let screen = image("shape-sheet").cropping(to: CGRect(x: bound.minX * 2, y: bound.minY * 2, width: bound.width * 2, height: bound.height * 2))!
var start = ContinuousClock.now
let sheet = PixelGrid(image: screen, frame: bound, scale: 2, generation: 1)!
let built = (ContinuousClock.now - start) / .milliseconds(1)
var times: [Double] = []
for i in 0..<100 {
    let p = CGPoint(x: bound.minX + bound.width * (0.05 + 0.9 * Double(i % 10) / 9),
                    y: bound.minY + bound.height * (0.05 + 0.9 * Double(i / 10) / 9))
    start = ContinuousClock.now
    if let shape = ShapeFinder.fill(at: p, in: sheet, bound: bound)?.shape { _ = ShapeFinder.enclosing(shape, in: sheet, bound: bound) }
    times.append((ContinuousClock.now - start) / .milliseconds(1))
}
times.sort()
print(String(format: "iPhone screen at edge %d seed %d: grid and edge map %.1f ms once; lookups p50 %.2f ms, p95 %.2f ms, max %.2f ms",
             ShapeFinder.edgeTolerance, ShapeFinder.seedTolerance, built, times[49], times[94], times[99]))
EOF
xcrun swiftc -O -o $SP/sweep/sweep $SP/sweep/main.swift $SP/sweep/ShapeFinder.swift 2>&1 | grep error; $SP/sweep/sweep $W/LocantTests/Fixtures
```

Expected: twelve `edge … seed …` lines, each followed by its failures, then one timing line. On Oct 23 the unblurred captures passed at edge 3 and 4 with seed 24 or 40, and failed at 5 and 6 (the Recent/Currents capsule leaks).

**Pick a pair.** Of the pairs that pass every fixture, take the one nearest (4, 24). Then:
1. Set `edgeTolerance` and `seedTolerance` in `Locant/Resolve/ShapeFinder.swift` to the pair.
2. Run all of `ShapeFinderTests`. The synthetic tests must still pass; if one fails, take the next-nearest pair.
3. In `specs/capture-shapes.md` R119, change every tolerance number to the chosen pair: "by more than 4" (edge samples), "within 4 of the seed color" (both seed rules), "within 24 of the seed color" (the growth rule), and the sentence "The 4 and 24 were set by the real-screen fixtures…".

**If no pair passes every fixture: stop.** Write the sweep's output to `$SP/sweep/result.txt` and ask Malik. A change to the fill is a spec change, so don't make it on your own.

- [ ] **Step 7: Check speed.** If Step 6 didn't run, do its `sed`, `cat` and `swiftc` lines. Then run `$SP/sweep/sweep $W/LocantTests/Fixtures <edge> <seed>` with the tolerances in the code.
  - **Expected:** the last line shows p50 under 5 ms and p95 under 15 ms (spec §3). On Oct 23: grid and edge map 27 ms once, p50 4.6 ms, p95 13.4 ms.
  - **If not:** don't optimize past the spec here. Report the numbers to Malik and go on. The live path also reuses a fill while the pointer stays on it.

- [ ] **Step 8: Run every test, build, commit.**

```bash
xcodebuild -project Locant.xcodeproj -scheme Locant -configuration Debug -destination 'platform=macOS' -derivedDataPath "$DD" build -quiet
xcodebuild -project Locant.xcodeproj -scheme Locant -destination 'platform=macOS' -derivedDataPath "$DD" test -quiet
git add scripts/blur-fixture-text.swift LocantTests/Fixtures/shape-*.png LocantTests/Fixtures/shapes.json LocantTests/ShapeFinderTests.swift
git add Locant/Resolve/ShapeFinder.swift specs/capture-shapes.md   # only if Step 6 changed them
git commit -m "shapes: real-screen fixtures, text blurred, with edges measured apart from the finder"
```

---

### Task 4: The screen sample (R118)

**Files:**
- Modify: `Locant/Capture/Geometry.swift` (add `sampleScale`)
- Modify: `Locant/Capture/ScreenCapture.swift` (add `regionImage`)
- Create: `Locant/Capture/ScreenSampler.swift`
- Modify: `LocantTests/GeometryTests.swift`
- Create: `LocantTests/ScreenSamplerTests.swift`

**Interfaces:**
- Consumes: `PixelGrid(image:frame:scale:generation:)`, `HitRefiner.matches(_:_:)` (`Frame`, 1 pt), `Frame(_ rect: CGRect)`.
- Produces:
  - `static func Geometry.sampleScale(native: CGFloat, size: CGSize, maxSamples: Int) -> CGFloat`
  - `static func ScreenCapture.regionImage(_ rect: CGRect, maxSamples: Int) async throws -> (image: CGImage, frame: CGRect, scale: CGFloat)`
  - `@MainActor final class ScreenSampler`, with:
    - `typealias Capture`
    - `static let maxSamples`
    - `init(hasPermission:capture:refresh:)`
    - `var onUpdate: (() -> Void)?`
    - `func start()`, `func stop()`, `func want(_ area: CGRect)`, `func image(for area: CGRect) -> PixelGrid?`

- [ ] **Step 1: Write the failing tests.** Add to `LocantTests/GeometryTests.swift`, inside the class:

```swift
    // specs/capture-shapes.md R118: the display's own scale, lowered only above 4,000,000 samples.
    func testSampleScaleKeepsTheDisplaysScaleUpToTheCap() {
        XCTAssertEqual(Geometry.sampleScale(native: 2, size: CGSize(width: 341, height: 741), maxSamples: 4_000_000), 2)
        XCTAssertEqual(Geometry.sampleScale(native: 2, size: CGSize(width: 1720, height: 1000), maxSamples: 4_000_000),
                       (4_000_000 / 1_720_000.0).squareRoot(), accuracy: 0.0001)
        XCTAssertEqual(Geometry.sampleScale(native: 2, size: .zero, maxSamples: 4_000_000), 2)
    }
```

Create `LocantTests/ScreenSamplerTests.swift`:

```swift
import CoreGraphics
import XCTest
@testable import Locant

/// specs/capture-shapes.md R118: one image of the area hover wants, taken once per area, never without
/// permission, and dropped on stop.
@MainActor
final class ScreenSamplerTests: XCTestCase {
    private actor Calls {
        var areas: [CGRect] = []
        func add(_ area: CGRect) { areas.append(area) }
        var count: Int { areas.count }
    }

    private nonisolated static func image(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(gray: 0.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// A sampler whose capture records the area and returns a plain image at 2x; refresh far off, so
    /// only `want` captures.
    private func makeSampler(permitted: Bool, calls: Calls) -> ScreenSampler {
        ScreenSampler(hasPermission: { permitted }, capture: { area in
            await calls.add(area)
            return (Self.image(width: Int(area.width) * 2, height: Int(area.height) * 2), area, 2)
        }, refresh: .seconds(600))
    }

    private let first = CGRect(x: 0, y: 0, width: 100, height: 200)
    private let second = CGRect(x: 100, y: 0, width: 100, height: 200)

    func testWithoutPermissionNothingIsCaptured() async throws {
        let calls = Calls()
        let sampler = makeSampler(permitted: false, calls: calls)
        sampler.start()
        sampler.want(first)
        try await Task.sleep(for: .milliseconds(200))
        let count = await calls.count
        XCTAssertEqual(count, 0)
        XCTAssertNil(sampler.image(for: first))
        sampler.stop()
    }

    func testOneCapturePerAreaAndAnotherForANewArea() async {
        let calls = Calls()
        let sampler = makeSampler(permitted: true, calls: calls)
        sampler.start()
        let landed = expectation(description: "first image")
        sampler.onUpdate = { landed.fulfill() }
        sampler.want(first)
        sampler.want(first) // one in flight: not asked twice
        await fulfillment(of: [landed], timeout: 2)
        XCTAssertEqual(sampler.image(for: first)?.width, 200)
        XCTAssertEqual(sampler.image(for: first)?.generation, 1)
        sampler.want(first) // the newest image already shows it
        var count = await calls.count
        XCTAssertEqual(count, 1)

        let moved = expectation(description: "second image")
        sampler.onUpdate = { moved.fulfill() }
        sampler.want(second)
        await fulfillment(of: [moved], timeout: 2)
        count = await calls.count
        XCTAssertEqual(count, 2)
        XCTAssertNil(sampler.image(for: first))
        XCTAssertEqual(sampler.image(for: second)?.generation, 2)
        sampler.stop()
    }

    func testStopDropsTheImageAndTakesNoMore() async throws {
        let calls = Calls()
        let sampler = makeSampler(permitted: true, calls: calls)
        sampler.start()
        let landed = expectation(description: "image")
        sampler.onUpdate = { landed.fulfill() }
        sampler.want(first)
        await fulfillment(of: [landed], timeout: 2)
        sampler.stop()
        XCTAssertNil(sampler.image(for: first))
        sampler.want(second)
        try await Task.sleep(for: .milliseconds(200))
        let count = await calls.count
        XCTAssertEqual(count, 1)
    }
}
```

- [ ] **Step 2: Run them to see them fail.** `xcodebuild … test -quiet -only-testing:LocantTests/ScreenSamplerTests -only-testing:LocantTests/GeometryTests`. Expected: compile failure, `sampleScale` and `ScreenSampler` not found.

- [ ] **Step 3: Write the implementation.**

In `Locant/Capture/Geometry.swift`, after `pixelRect(_:inDisplay:scale:)`, add:

```swift
    // MARK: Screen sample (specs/capture-shapes.md R118)

    /// The display's own scale, lowered so `size` (points) holds at most `maxSamples` samples.
    static func sampleScale(native: CGFloat, size: CGSize, maxSamples: Int) -> CGFloat {
        let area = size.width * size.height
        guard area > 0 else { return native }
        return min(native, (CGFloat(maxSamples) / area).squareRoot())
    }
```

In `Locant/Capture/ScreenCapture.swift`, after `displayImage(containing:)`, add:

```swift
    /// specs/capture-shapes.md R118: `rect` (global points) from the display holding its center, own
    /// windows excluded, at the display's scale unless that would exceed `maxSamples` samples. `frame`
    /// is the part of `rect` on that display.
    static func regionImage(_ rect: CGRect, maxSamples: Int) async throws -> (image: CGImage, frame: CGRect, scale: CGFloat) {
        let content = try await shareableContent()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        guard let display = content.displays.first(where: { $0.frame.contains(center) }) ?? content.displays.first else {
            throw ScreenCaptureFailure.noDisplay
        }
        let visible = rect.intersection(display.frame).integral
        guard !visible.isEmpty else { throw ScreenCaptureFailure.cropOutsideImage }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == ownPID }
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
        let scale = Geometry.sampleScale(native: CGFloat(filter.pointPixelScale), size: visible.size, maxSamples: maxSamples)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = Geometry.displayLocalRect(visible, inDisplay: display.frame)
        configuration.width = Int((visible.width * scale).rounded())
        configuration.height = Int((visible.height * scale).rounded())
        configuration.showsCursor = false
        configuration.captureResolution = .best
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return (image, visible, scale)
    }
```

Create `Locant/Capture/ScreenSampler.swift`:

```swift
import CoreGraphics
import Foundation

/// specs/capture-shapes.md R118: one recent image of the area hover reads shapes in, while the overlay
/// is up. Hover never waits for it: without an image of the area it wants, hover runs without shapes,
/// and when one lands `onUpdate` has the spot read again. Memory only, dropped on `stop()`.
@MainActor
final class ScreenSampler {
    typealias Capture = @Sendable (CGRect) async throws -> (image: CGImage, frame: CGRect, scale: CGFloat)

    /// Larger areas are taken at a lower scale. Nonisolated: the default capture reads it off the main actor.
    nonisolated static let maxSamples = 4_000_000

    /// A new image landed.
    var onUpdate: (() -> Void)?

    private let hasPermission: @MainActor () -> Bool
    private let capture: Capture
    private let refresh: Duration
    private var latest: PixelGrid?
    private var latestArea: CGRect?
    private var wanted: CGRect?
    private var inFlight = false
    private var generation = 0
    private var loop: Task<Void, Never>?

    init(hasPermission: @escaping @MainActor () -> Bool = { ScreenCapture.hasPermission() },
         capture: @escaping Capture = { try await ScreenCapture.regionImage($0, maxSamples: ScreenSampler.maxSamples) },
         refresh: Duration = .seconds(1)) {
        self.hasPermission = hasPermission
        self.capture = capture
        self.refresh = refresh
    }

    /// The overlay is up: the area hover wants is taken again every `refresh`.
    func start() {
        guard loop == nil else { return }
        let refresh = refresh
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: refresh)
                guard !Task.isCancelled, let self else { return }
                self.take()
            }
        }
    }

    /// The overlay is gone: no more captures, and the image is dropped.
    func stop() {
        loop?.cancel()
        loop = nil
        latest = nil
        latestArea = nil
        wanted = nil
    }

    /// The area hover reads shapes in now. Taken at once unless the newest image already shows it.
    func want(_ area: CGRect) {
        guard loop != nil, area.width > 0, area.height > 0 else { return }
        wanted = area
        if let latestArea, HitRefiner.matches(Frame(latestArea), Frame(area)) { return }
        take()
    }

    /// The newest image, when it shows `area`.
    func image(for area: CGRect) -> PixelGrid? {
        guard let latest, let latestArea, HitRefiner.matches(Frame(latestArea), Frame(area)) else { return nil }
        return latest
    }

    /// One capture at a time, never without Screen Recording permission, so it can never prompt.
    /// A failure leaves the previous image, or none, and says nothing.
    private func take() {
        guard !inFlight, let area = wanted, hasPermission() else { return }
        inFlight = true
        generation += 1
        let generation = generation
        let capture = capture
        Task { [weak self] in
            let grid = await Task.detached { () -> PixelGrid? in
                guard let taken = try? await capture(area), taken.frame.width > 0 else { return nil }
                return PixelGrid(image: taken.image, frame: taken.frame,
                                 scale: CGFloat(taken.image.width) / taken.frame.width, generation: generation)
            }.value
            guard let self else { return }
            self.inFlight = false
            guard self.loop != nil, let grid else { return }
            self.latest = grid
            self.latestArea = area
            self.onUpdate?()
        }
    }
}
```

- [ ] **Step 4: Run the tests to see them pass.** Same command as Step 2. Expected: exit 0.

- [ ] **Step 5: Build, run every test, commit.**

```bash
xcodebuild -project Locant.xcodeproj -scheme Locant -configuration Debug -destination 'platform=macOS' -derivedDataPath "$DD" build -quiet
xcodebuild -project Locant.xcodeproj -scheme Locant -destination 'platform=macOS' -derivedDataPath "$DD" test -quiet
git add Locant/Capture/Geometry.swift Locant/Capture/ScreenCapture.swift Locant/Capture/ScreenSampler.swift LocantTests/GeometryTests.swift LocantTests/ScreenSamplerTests.swift
git commit -m "shapes: sample the area hover reads, at the display's scale, once per area"
```

---

### Task 5: The cluster under any parent (R120)

**Files:**
- Modify: `Locant/Resolve/ElementResolver.swift` (`HitRefiner.ladder`)
- Modify: `Locant/Resolve/AccessibilityReader.swift` (`snapshot(of:)`)
- Modify: `LocantTests/ElementResolverTests.swift`

**Interfaces:**
- Consumes: `HitRefiner.selectionLevels(for:at:)`, `ElementResolver.clusterElement(members:ancestors:within:)`.
- Produces: no new names. `selectionLevels(for:at:)` now forms clusters under any parent, and the reader fills `children` and `siblings` under any container.

- [ ] **Step 1: Write the failing tests.** Add to `ElementResolverTests`, after `testSelectionLevelsOnSpanningContainerPickClusterUnderPointOrNothing`:

```swift
    // MARK: Clusters under any parent (specs/capture-shapes.md R120)

    /// Oryne's thought-detail toolbar: share and pencil, 40×40 each, in a 360×48 hosting group that is
    /// far from spanning the 400×870 screen.
    private func toolbarNodes() -> (share: AttributeSet, pencil: AttributeSet, hosting: AttributeSet, screen: AttributeSet) {
        (AttributeSet(role: "AXButton", identifier: "share", frame: Frame(x: 256, y: 330, w: 40, h: 40)),
         AttributeSet(role: "AXButton", identifier: "pencil", frame: Frame(x: 300, y: 330, w: 40, h: 40)),
         AttributeSet(role: "AXGroup", identifier: "_TtGC7SwiftUI32NavigationStackHosting", frame: Frame(x: 118, y: 324, w: 360, h: 48)),
         AttributeSet(role: "AXGroup", frame: Frame(x: 100, y: 100, w: 400, h: 870)))
    }

    func testClusterFormsUnderAParentThatDoesNotSpanTheWindow() {
        let n = toolbarNodes()
        let snapshot = ElementSnapshot(element: n.pencil, ancestors: [n.hosting, n.screen], siblings: [n.share, n.pencil])
        let levels = HitRefiner.selectionLevels(for: snapshot, at: CGPoint(x: 320, y: 350))
        XCTAssertEqual(levels.map { $0?.role }, ["button", "cluster", "group", "group"])
        XCTAssertEqual(levels[1]?.members?.compactMap(\.identifier), ["share", "pencil"])
    }

    func testAContainerThatDoesNotSpanTheWindowIsRungZeroWithoutACluster() {
        let n = toolbarNodes()
        let hit = ElementSnapshot(element: n.hosting, ancestors: [n.screen], children: [n.share, n.pencil])
        XCTAssertEqual(HitRefiner.selectionLevels(for: hit, at: CGPoint(x: 200, y: 350)).map { $0?.role }, ["group", "group"],
                       "away from the buttons: the container itself, not the fallback square")
        XCTAssertEqual(HitRefiner.selectionLevels(for: hit, at: CGPoint(x: 298, y: 350)).map { $0?.role }, ["cluster", "group", "group"],
                       "between the buttons: their cluster")
    }
```

- [ ] **Step 2: Run them to see them fail.** `xcodebuild … test -quiet -only-testing:LocantTests/ElementResolverTests`. Expected: `testClusterFormsUnderAParentThatDoesNotSpanTheWindow` fails with `["button", "group", "group"]`, and the second test's second assertion fails with `["group", "group"]`.

- [ ] **Step 3: Write the implementation.** In `Locant/Resolve/ElementResolver.swift`, in `HitRefiner.ladder(for:at:)`, replace:

```swift
        if let base, ElementResolver.containerRoles.contains(base.role), spans(snapshot.element.frame, window: window) {
            // Window-sized container under the cursor: the cluster around the point, else nothing.
            let nodes = content(of: snapshot.children ?? [], within: snapshot.element.frame)
            if let members = cluster(containing: point, among: nodes),
               let cluster = ElementResolver.clusterElement(members: members, ancestors: [snapshot.element] + snapshot.ancestors, within: snapshot.element.frame) {
                levels.append(cluster)
            } else {
                levels.append(nil)
            }
            levels.append(base)
        } else if let base {
            levels.append(base)
            if let siblings = snapshot.siblings, let parent = snapshot.ancestors.first, spans(parent.frame, window: window) {
```

with:

```swift
        if let base, ElementResolver.containerRoles.contains(base.role) {
            // A container under the cursor: the cluster around the point, whatever the container's size
            // (specs/capture-shapes.md R120); else nothing when it spans the window, else the container.
            let spanning = spans(snapshot.element.frame, window: window)
            let containerArea = snapshot.element.frame.map { $0.w * $0.h } ?? .infinity
            let nodes = content(of: snapshot.children ?? [], within: snapshot.element.frame)
            if let members = cluster(containing: point, among: nodes),
               let cluster = ElementResolver.clusterElement(members: members, ancestors: [snapshot.element] + snapshot.ancestors, within: snapshot.element.frame),
               spanning || cluster.frame.w * cluster.frame.h < 0.9 * containerArea {
                levels.append(cluster)
            } else if spanning {
                levels.append(nil)
            }
            levels.append(base)
        } else if let base {
            levels.append(base)
            // R120: the cluster around the element under any parent.
            if let siblings = snapshot.siblings, let parent = snapshot.ancestors.first {
```

The rest of that branch is unchanged.

In `Locant/Resolve/AccessibilityReader.swift`, in `snapshot(of:)`, replace:

```swift
        // Flat trees (SwiftUI): read the neighbourhood so HitRefiner can form visual clusters.
        let window = HitRefiner.windowFrame(in: snapshot)
        if ElementResolver.isContainer(elementAttributes), HitRefiner.spans(elementAttributes.frame, window: window) {
            snapshot.children = neighbors(of: element, attributes: elementAttributes)
        } else if let parent = parents.first, let parentAttributes = ancestors.first,
                  HitRefiner.spans(parentAttributes.frame, window: window) {
            snapshot.siblings = neighbors(of: parent, attributes: parentAttributes)
        }
```

with:

```swift
        // Flat trees (SwiftUI): read the neighbourhood so HitRefiner can form visual clusters, under any
        // container (specs/capture-shapes.md R120), not only one that spans the window.
        if ElementResolver.isContainer(elementAttributes) {
            snapshot.children = neighbors(of: element, attributes: elementAttributes)
        } else if let parent = parents.first, let parentAttributes = ancestors.first, ElementResolver.isContainer(parentAttributes) {
            snapshot.siblings = neighbors(of: parent, attributes: parentAttributes)
        }
```

- [ ] **Step 4: Run the tests to see them pass.** Same command as Step 2. Expected: exit 0, with every older `ElementResolverTests`, `SnapLadderTests`, and `DOMIdentifierTests` still green. Of the recorded fixtures only `card-siblings` has siblings, and its parent spans the window, so no older expectation changes.

- [ ] **Step 5: Build, run every test, commit.**

```bash
xcodebuild -project Locant.xcodeproj -scheme Locant -configuration Debug -destination 'platform=macOS' -derivedDataPath "$DD" build -quiet
xcodebuild -project Locant.xcodeproj -scheme Locant -destination 'platform=macOS' -derivedDataPath "$DD" test -quiet
git add Locant/Resolve/ElementResolver.swift Locant/Resolve/AccessibilityReader.swift LocantTests/ElementResolverTests.swift
git commit -m "hover: clusters form under any parent, and a small container under the pointer stays itself"
```

---

### Task 6: Shapes on the ladder (R116, R117, R121 readout)

**Files:**
- Modify: `Locant/Resolve/ShapeFinder.swift` (add `ShapeSource`, `ShapeLookup`)
- Modify: `Locant/Resolve/ElementResolver.swift` (`shapeRawRole`; `HitRefiner` shape ladder, `shapeElement`, `members`)
- Modify: `Locant/Capture/SelectionOverlay.swift` (`Readout.describing`, cluster branch)
- Modify: `LocantTests/ElementResolverTests.swift`, `LocantTests/ShapeFinderTests.swift`

**Interfaces:**
- Consumes:
  - `ShapeFinder.fill(at:in:bound:)`, `ShapeFinder.enclosing(_:in:bound:)`, `ShapeFinder.Fill.covers(_:in:)`
  - `HitRefiner.selectionLevels(for:at:)`, `HitRefiner.collapsingSameFrames(_:)`
  - `RegionResolver.minimumInside`
- Produces:
  - `protocol ShapeSource`, with `mutating func shape(at: CGPoint) -> CGRect?` and `mutating func shapes(around: CGRect) -> [CGRect]`
  - `struct ShapeLookup: ShapeSource, Sendable`, with `struct Memo: Sendable { generation, bound, lastFill, around }`, `init(grid:bound:memo:)`, and `private(set) var memo`
  - `ElementResolver.shapeRawRole = "LocantShape"`
  - `HitRefiner`:
    - `shapeHold = 3`, `shapeMerge = 2`
    - `static func selectionLevels(for: ElementSnapshot?, at: CGPoint, shapes: inout some ShapeSource, holding: ResolvedElement?) -> [ResolvedElement?]`
    - `static func shapeElement(frame: CGRect, snapshot: ElementSnapshot) -> ResolvedElement`
    - `static func members(inside: CGRect, of: ElementSnapshot) -> [ElementMember]`
    - `static func holds(_ outer: CGRect, _ inner: CGRect) -> Bool`
    - `static func matches(_ a: Frame, _ b: Frame, within: Double) -> Bool`
  - `Readout.describing` of a cluster: suffix = member names joined by `, `, nil without names.

- [ ] **Step 1: Write the failing tests.** Add to `ElementResolverTests`, after Task 5's tests:

```swift
    // MARK: Shapes on the ladder (specs/capture-shapes.md R117, R121)

    /// Shapes at fixed rectangles: at a point, the smallest that holds it; around a rectangle, the ones
    /// holding it, innermost first. `asked` tells whether the ladder asked at all.
    private struct FixedShapes: ShapeSource {
        var rects: [CGRect]
        var asked = false

        mutating func shape(at point: CGPoint) -> CGRect? {
            asked = true
            return rects.filter { $0.contains(point) }.min { $0.width * $0.height < $1.width * $1.height }
        }

        mutating func shapes(around rect: CGRect) -> [CGRect] {
            asked = true
            return rects.filter { $0.insetBy(dx: -1, dy: -1).contains(rect) && !HitRefiner.matches(Frame($0), Frame(rect)) }
                .sorted { $0.width * $0.height < $1.width * $1.height }
        }
    }

    /// The glass capsule around share, pencil, and trash.
    private let capsule = CGRect(x: 250, y: 326, width: 140, height: 44)

    func testOnAButtonTheCapsuleIsTheNextRung() throws {
        let n = toolbarNodes()
        let snapshot = ElementSnapshot(element: n.pencil, ancestors: [n.hosting, n.screen], siblings: [n.share, n.pencil])
        var shapes = FixedShapes(rects: [capsule])
        let levels = HitRefiner.selectionLevels(for: snapshot, at: CGPoint(x: 320, y: 350), shapes: &shapes, holding: nil)
        XCTAssertEqual(levels.map { $0?.role }, ["button", "cluster", "group", "group"])
        let shape = try XCTUnwrap(levels[1])
        XCTAssertEqual(shape.rawRole, "LocantShape")
        XCTAssertEqual(shape.frame, Frame(capsule))
        XCTAssertEqual(shape.members?.compactMap(\.identifier), ["share", "pencil"])
        XCTAssertEqual(shape.path.map(\.role), ["group", "group", "cluster"])
        XCTAssertEqual(shape.path[1].identifier, "_TtGC7SwiftUI32NavigationStackHosting", "the innermost node holding it")
        XCTAssertEqual(levels[2]?.identifier, "_TtGC7SwiftUI32NavigationStackHosting", "the sibling cluster gave way to the shape")
    }

    func testInsideAShapeTheElementHoldsForThreePoints() throws {
        let n = toolbarNodes()
        let gap = ElementSnapshot(element: n.hosting, ancestors: [n.screen], children: [n.share, n.pencil])
        let pencil = try XCTUnwrap(ElementResolver.resolve(ElementSnapshot(element: n.pencil, ancestors: [n.hosting, n.screen])))
        var shapes = FixedShapes(rects: [capsule])
        let held = HitRefiner.selectionLevels(for: gap, at: CGPoint(x: 342, y: 350), shapes: &shapes, holding: pencil)
        XCTAssertEqual(held.first??.identifier, "pencil", "2 pt past its edge: still the pencil")
        let left = HitRefiner.selectionLevels(for: gap, at: CGPoint(x: 345, y: 350), shapes: &shapes, holding: pencil)
        XCTAssertEqual(left.first??.rawRole, "LocantShape", "5 pt past it: the capsule")
        let fresh = HitRefiner.selectionLevels(for: gap, at: CGPoint(x: 342, y: 350), shapes: &shapes, holding: nil)
        XCTAssertEqual(fresh.first??.rawRole, "LocantShape", "arriving in the gap: the capsule, not the pencil")
    }

    func testAShapeBeatsAnElementReachedOnlyByTolerance() {
        let n = toolbarNodes()
        // The reader refined the gap to the pencil, 3 pt away: within its 8 pt tolerance, not under the pointer.
        let refined = ElementSnapshot(element: n.pencil, ancestors: [n.hosting, n.screen], siblings: [n.share, n.pencil])
        var shapes = FixedShapes(rects: [capsule])
        let levels = HitRefiner.selectionLevels(for: refined, at: CGPoint(x: 343, y: 350), shapes: &shapes, holding: nil)
        XCTAssertEqual(levels.map { $0?.rawRole }, ["LocantShape", "AXGroup", "AXGroup"],
                       "the pencil, which does not hold the capsule, is dropped, and so is the sibling cluster")
    }

    func testAShapeThatOverhangsItsParentIsDroppedAndOneThatMatchesItMerges() {
        let n = toolbarNodes()
        let snapshot = ElementSnapshot(element: n.pencil, ancestors: [n.hosting, n.screen])
        let point = CGPoint(x: 320, y: 350)
        var overhang = FixedShapes(rects: [CGRect(x: 250, y: 326, width: 140, height: 60)])
        XCTAssertEqual(HitRefiner.selectionLevels(for: snapshot, at: point, shapes: &overhang, holding: nil).map { $0?.rawRole },
                       ["AXButton", "AXGroup", "AXGroup"])
        var matching = FixedShapes(rects: [CGRect(x: 119, y: 325, width: 359, height: 46)])
        let merged = HitRefiner.selectionLevels(for: snapshot, at: point, shapes: &matching, holding: nil)
        XCTAssertEqual(merged.map { $0?.rawRole }, ["AXButton", "AXGroup", "AXGroup"])
        XCTAssertEqual(merged[1]?.identifier, "_TtGC7SwiftUI32NavigationStackHosting", "the accessibility rung is kept")
    }

    func testNoAnswerAsksForNoShape() {
        var shapes = FixedShapes(rects: [capsule])
        XCTAssertEqual(HitRefiner.selectionLevels(for: nil, at: CGPoint(x: 320, y: 350), shapes: &shapes, holding: nil).count, 0)
        XCTAssertFalse(shapes.asked)
    }

    func testWithoutAShapeTodaysLadderStands() {
        let n = toolbarNodes()
        let gap = ElementSnapshot(element: n.hosting, ancestors: [n.screen], children: [n.share, n.pencil])
        var none = FixedShapes(rects: [])
        let point = CGPoint(x: 298, y: 350)
        XCTAssertEqual(HitRefiner.selectionLevels(for: gap, at: point, shapes: &none, holding: nil),
                       HitRefiner.selectionLevels(for: gap, at: point))
    }

    func testAShapeReadsTheNamesOfWhatItHolds() {
        let recent = AttributeSet(role: "AXButton", description: "Recent", frame: Frame(x: 40, y: 40, w: 78, h: 30))
        let currents = AttributeSet(role: "AXButton", description: "Currents", frame: Frame(x: 118, y: 40, w: 78, h: 30))
        let nameless = AttributeSet(role: "AXImage", frame: Frame(x: 60, y: 45, w: 10, h: 10))
        let screen = AttributeSet(role: "AXGroup", frame: Frame(x: 0, y: 0, w: 400, h: 870))
        let snapshot = ElementSnapshot(element: recent, ancestors: [screen], siblings: [recent, currents, nameless])
        let shape = HitRefiner.shapeElement(frame: CGRect(x: 37, y: 37.5, width: 162.5, height: 36.5), snapshot: snapshot)
        XCTAssertEqual(shape.members?.count, 3)
        XCTAssertEqual(Readout.describing(shape), Readout(role: "cluster", identifier: nil, suffix: "Recent, Currents", isFallback: false))
        var empty = shape
        empty.members = []
        XCTAssertNil(Readout.describing(empty).suffix)
    }
```

Add to `ShapeFinderTests`, before `// MARK: Real screens`:

```swift
    // R119: the live source keeps its memo while the sample and the bound stay the same, and drops it otherwise.
    func testShapeLookupKeepsItsMemoForOneSampleAndBound() {
        var canvas = Canvas(400, 300, background: dark)
        let card = CGRect(x: 100, y: 80, width: 160, height: 90)
        canvas.paint(card, RGB(r: 50, g: 50, b: 54))
        var lookup = ShapeLookup(grid: canvas.grid(generation: 1), bound: canvas.bounds, memo: .init())
        assertRect(lookup.shape(at: CGPoint(x: 106, y: 125)), card)
        XCTAssertNotNil(lookup.memo.lastFill)
        XCTAssertEqual(lookup.shapes(around: CGRect(x: 120, y: 100, width: 20, height: 20)).count, 1)
        XCTAssertEqual(lookup.memo.around.count, 1)
        XCTAssertNotNil(ShapeLookup(grid: canvas.grid(generation: 1), bound: canvas.bounds, memo: lookup.memo).memo.lastFill)
        let newer = ShapeLookup(grid: canvas.grid(generation: 2), bound: canvas.bounds, memo: lookup.memo)
        XCTAssertNil(newer.memo.lastFill)
        XCTAssertTrue(newer.memo.around.isEmpty)
    }
```

- [ ] **Step 2: Run them to see them fail.** `xcodebuild … test -quiet -only-testing:LocantTests/ElementResolverTests -only-testing:LocantTests/ShapeFinderTests`. Expected: compile failure, `ShapeSource`, `ShapeLookup`, and `shapeElement` not found.

- [ ] **Step 3: Write the implementation.**

At the end of `Locant/Resolve/ShapeFinder.swift`, add:

```swift
/// specs/capture-shapes.md R117: what the ladder asks of the pixels. `ShapeLookup` answers from a screen
/// sample; tests answer from fixed rectangles.
protocol ShapeSource {
    /// R119: the shape at a point; nil when there is none.
    mutating func shape(at point: CGPoint) -> CGRect?
    /// R119: the shapes around a rectangle, innermost first, at most three.
    mutating func shapes(around rect: CGRect) -> [CGRect]
}

/// The live `ShapeSource` over one screen sample. `memo` carries the last fill and the shapes found around
/// rectangles from one hover step to the next while the sample and the bound stay the same (R119).
struct ShapeLookup: ShapeSource, Sendable {
    struct Memo: Sendable {
        var generation = -1
        var bound = CGRect.null
        var lastFill: ShapeFinder.Fill?
        var around: [Frame: [CGRect]] = [:]
    }

    let grid: PixelGrid
    let bound: CGRect
    private(set) var memo: Memo

    init(grid: PixelGrid, bound: CGRect, memo: Memo) {
        self.grid = grid
        self.bound = bound
        self.memo = memo.generation == grid.generation && memo.bound == bound ? memo : Memo(generation: grid.generation, bound: bound)
    }

    mutating func shape(at point: CGPoint) -> CGRect? {
        if let fill = memo.lastFill, fill.covers(point, in: grid) { return fill.shape }
        let fill = ShapeFinder.fill(at: point, in: grid, bound: bound)
        memo.lastFill = fill
        return fill?.shape
    }

    mutating func shapes(around rect: CGRect) -> [CGRect] {
        let key = Frame(rect)
        if let known = memo.around[key] { return known }
        let found = ShapeFinder.enclosing(rect, in: grid, bound: bound)
        if memo.around.count >= 64 { memo.around.removeAll() }
        memo.around[key] = found
        return found
    }
}
```

In `Locant/Resolve/ElementResolver.swift`, after `static let clusterRawRole = "LocantCluster"`, add:

```swift
    /// specs/capture-shapes.md R116: a shape found on screen; a cluster too, but its frame is the edges seen.
    static let shapeRawRole = "LocantShape"
```

At the end of `Locant/Resolve/ElementResolver.swift`, add:

```swift
// MARK: - Shapes (specs/capture-shapes.md)

extension HitRefiner {
    /// R117: inside a shape, the element under the pointer keeps the outline this far past its frame.
    static let shapeHold: Double = 3
    /// R117: a shape and an accessibility rung within this on every edge are one rung, since pixel edges
    /// are read a sample at a time. Two accessibility rungs still merge within 1 pt (`collapsingSameFrames`).
    static let shapeMerge: Double = 2

    /// R117: the ladder with the shapes under the pointer.
    /// - Rung 0 is the element the pointer is on; else the element still held inside a shape; else the
    ///   shape at the point; else today's ladder, unchanged.
    /// - After rung 0 come the shapes around it, then today's rungs that hold it, ordered by containment.
    /// - With no accessibility answer: nothing, and no shape is asked for.
    static func selectionLevels(for snapshot: ElementSnapshot?, at point: CGPoint,
                                shapes: inout some ShapeSource, holding previous: ResolvedElement?) -> [ResolvedElement?] {
        guard let snapshot else { return [] }
        let today = selectionLevels(for: snapshot, at: point)
        let rung0: ResolvedElement
        var shapeAtPoint: CGRect?
        if let hit = ElementResolver.resolve(snapshot), isElement(hit), hit.frame.cgRect.contains(point) {
            rung0 = hit
        } else if let shape = shapes.shape(at: point) {
            shapeAtPoint = shape
            if let previous, isElement(previous),
               previous.frame.cgRect.insetBy(dx: -shapeHold, dy: -shapeHold).contains(point),
               holds(shape, previous.frame.cgRect) {
                rung0 = previous
            } else {
                rung0 = shapeElement(frame: shape, snapshot: snapshot)
            }
        } else {
            return today
        }
        let around = shapes.shapes(around: rung0.frame.cgRect)
        // R120: the cluster stands in for a shape, so it is offered only where there is none.
        let offersCluster = shapeAtPoint == nil && around.isEmpty
        let accessibility = today.compactMap { $0 }.filter { rung in
            !(rung.frame == rung0.frame && rung.rawRole == rung0.rawRole)
                && holds(rung.frame.cgRect, rung0.frame.cgRect)
                && (offersCluster || rung.rawRole != ElementResolver.clusterRawRole)
        }
        let candidates = (around.map { shapeElement(frame: $0, snapshot: snapshot) } + accessibility)
            .enumerated()
            .sorted { a, b in
                let (x, y) = (rungArea(a.element), rungArea(b.element))
                if x != y { return x < y }
                if isShape(a.element) != isShape(b.element) { return !isShape(a.element) }
                return a.offset < b.offset
            }
            .map(\.element)
        var ladder: [ResolvedElement] = [rung0]
        for candidate in candidates {
            let last = ladder[ladder.count - 1]
            if matches(last.frame, candidate.frame, within: shapeMerge) {
                // The accessibility rung is kept: it carries a handle to grep.
                if isShape(last), !isShape(candidate) { ladder[ladder.count - 1] = candidate }
                continue
            }
            if holds(candidate.frame.cgRect, last.frame.cgRect) {
                ladder.append(candidate)
                continue
            }
            // A shape that does not hold the rung below it is dropped; so is one below an accessibility
            // rung that does not hold it.
            guard !isShape(candidate) else { continue }
            while ladder.count > 1, let top = ladder.last, isShape(top), !holds(candidate.frame.cgRect, top.frame.cgRect) {
                ladder.removeLast()
            }
            ladder.append(candidate)
        }
        return collapsingSameFrames(ladder)
    }

    /// R116: a shape as an element. Its path is that of the innermost node, among the hovered element and
    /// its ancestors, whose frame holds it; its members are what the snapshot holds inside it (R121).
    static func shapeElement(frame: CGRect, snapshot: ElementSnapshot) -> ResolvedElement {
        let chain = [snapshot.element] + snapshot.ancestors
        let holder = chain.firstIndex { node in node.frame.map { holds($0.cgRect, frame) } ?? false } ?? chain.count
        var path: [PathEntry] = chain[holder...].prefix(ElementResolver.maxAncestors).reversed().map { node in
            PathEntry(role: ElementResolver.mapRole(node.role ?? "", subrole: node.subrole), identifier: ElementResolver.nonEmpty(node.identifier))
        }
        path.append(PathEntry(role: ElementResolver.clusterRole, identifier: nil))
        return ResolvedElement(
            role: ElementResolver.clusterRole, rawRole: ElementResolver.shapeRawRole, label: nil, identifier: nil,
            identifierSource: .unknown, value: nil, frame: Frame(frame), path: path,
            members: members(inside: frame, of: snapshot)
        )
    }

    /// R121: the non-container nodes the snapshot holds (the element, its siblings, its children) at least
    /// half inside `frame`, one per rectangle, in reading order.
    static func members(inside frame: CGRect, of snapshot: ElementSnapshot) -> [ElementMember] {
        var seen = Set<String>()
        let inside = ([snapshot.element] + (snapshot.siblings ?? []) + (snapshot.children ?? [])).filter { node in
            guard !ElementResolver.isContainer(node), let f = node.frame, f.w > 0, f.h > 0 else { return false }
            let overlap = f.cgRect.intersection(frame)
            guard !overlap.isNull, overlap.width * overlap.height >= RegionResolver.minimumInside * f.w * f.h else { return false }
            return seen.insert("\(node.role ?? "")|\(f.x)|\(f.y)|\(f.w)|\(f.h)").inserted
        }
        let ordered = inside.sorted { a, b in
            let fa = a.frame!, fb = b.frame!
            return abs(fa.y - fb.y) > 4 ? fa.y < fb.y : fa.x < fb.x
        }
        return ordered.map { node in
            ElementMember(role: ElementResolver.mapRole(node.role ?? "", subrole: node.subrole),
                          label: ElementResolver.nonEmpty(node.title) ?? ElementResolver.nonEmpty(node.description),
                          identifier: ElementResolver.nonEmpty(node.identifier))
        }
    }

    /// `outer` holds `inner`, give or take `shapeMerge`.
    static func holds(_ outer: CGRect, _ inner: CGRect) -> Bool {
        outer.insetBy(dx: -shapeMerge, dy: -shapeMerge).contains(inner)
    }

    /// The same rectangle, within `slack` on every edge.
    static func matches(_ a: Frame, _ b: Frame, within slack: Double) -> Bool {
        abs(a.x - b.x) <= slack && abs(a.y - b.y) <= slack
            && abs((a.x + a.w) - (b.x + b.w)) <= slack && abs((a.y + a.h) - (b.y + b.h)) <= slack
    }

    private static func isElement(_ rung: ResolvedElement) -> Bool {
        !ElementResolver.containerRoles.contains(rung.role) && rung.role != ElementResolver.clusterRole
    }

    private static func isShape(_ rung: ResolvedElement) -> Bool { rung.rawRole == ElementResolver.shapeRawRole }

    private static func rungArea(_ rung: ResolvedElement) -> Double { rung.frame.w * rung.frame.h }
}
```

In `Locant/Capture/SelectionOverlay.swift`, in `Readout.describing`, replace:

```swift
        if element.role == ElementResolver.clusterRole {
            return Readout(role: "cluster", identifier: nil, suffix: "\(element.members?.count ?? 0) elements", isFallback: false)
        }
```

with:

```swift
        if element.role == ElementResolver.clusterRole {
            // specs/capture-shapes.md R121: what the shape or cluster holds, by name.
            let names = (element.members ?? []).compactMap { $0.label ?? $0.identifier }
            return Readout(role: "cluster", identifier: nil, suffix: names.isEmpty ? nil : names.joined(separator: ", "), isFallback: false)
        }
```

- [ ] **Step 4: Run the tests to see them pass.** Same command as Step 2. Expected: exit 0.

- [ ] **Step 5: Build, run every test, commit.**

```bash
xcodebuild -project Locant.xcodeproj -scheme Locant -configuration Debug -destination 'platform=macOS' -derivedDataPath "$DD" build -quiet
xcodebuild -project Locant.xcodeproj -scheme Locant -destination 'platform=macOS' -derivedDataPath "$DD" test -quiet
git add Locant/Resolve/ShapeFinder.swift Locant/Resolve/ElementResolver.swift Locant/Capture/SelectionOverlay.swift LocantTests/ElementResolverTests.swift LocantTests/ShapeFinderTests.swift
git commit -m "hover: shapes join the ladder, in containment order, and read what they hold"
```

---

### Task 7: Hover reads shapes (R117, R118 in the app)

UI wiring in `AppState`: no unit tests (`docs/CLAUDE.md`). The pure parts are tested in Tasks 2–6, and Task 9 checks the whole in the app.

**Files:**
- Modify: `Locant/App/AppState.swift`

**Interfaces:**
- Consumes:
  - `ScreenSampler` (`start`, `stop`, `want`, `image(for:)`, `onUpdate`)
  - `ShapeLookup(grid:bound:memo:)`, `.memo`
  - `HitRefiner.selectionLevels(for:at:shapes:holding:)`, `HitRefiner.simulatedScreen(in:)`
  - `Geometry.windowOwner(at:windows:excludingPID:)`, `SelectionOverlay.displayFrameCG(containing:)`
- Produces: private `AppState.shapeLevels(for:at:)`, `shapeBound(at:in:)`, `rehover()`.

- [ ] **Step 1: Add the sampler and the memo.** After `@ObservationIgnored private var outlineMoves = OutlineMoves()`, add:

```swift
    /// specs/capture-shapes.md R118: the screen under the pointer, read for the shapes hover lands on.
    @ObservationIgnored private let sampler = ScreenSampler()
    /// R119: the last fill and the shapes found around rectangles, while the sample stays the same.
    @ObservationIgnored private var shapeMemo = ShapeLookup.Memo()
```

- [ ] **Step 2: Wire its life.**
  - In `start()`, after `overlay.onRegion = { [weak self] rect, start in self?.region(rect, start: start) }`, add `sampler.onUpdate = { [weak self] in self?.rehover() }`.
  - In `beginAction(_:)`, replace `            overlay.show()` with:

```swift
            overlay.show()
            sampler.start()
```

  - In `reset()`, after `outlineMoves = OutlineMoves()`, add:

```swift
        sampler.stop()
        shapeMemo = ShapeLookup.Memo()
```

- [ ] **Step 3: Read shapes in the hover loop.** In `drainHover()`, replace:

```swift
            var freshLevels = fresh.map { HitRefiner.selectionLevels(for: $0, at: point) } ?? []
```

with:

```swift
            var freshLevels = await shapeLevels(for: fresh, at: point)
            guard phase == .hovering, !Task.isCancelled else { return }
```

After `drainHover()`, before `selectedElement()`, add:

```swift
    /// specs/capture-shapes.md R117: the ladder at `point`, with the shapes under the pointer once the screen
    /// sample of their area has landed (R118). Until then, today's ladder; with no answer at the point, nothing.
    private func shapeLevels(for snapshot: ElementSnapshot?, at point: CGPoint) async -> [ResolvedElement?] {
        guard let snapshot else { return [] }
        let bound = shapeBound(at: point, in: snapshot)
        sampler.want(bound)
        guard let grid = sampler.image(for: bound) else { return HitRefiner.selectionLevels(for: snapshot, at: point) }
        let holding = lastHoverElement
        let memo = shapeMemo
        let started = ContinuousClock.now
        let (levels, kept) = await Task.detached(priority: .userInitiated) {
            var lookup = ShapeLookup(grid: grid, bound: bound, memo: memo)
            let levels = HitRefiner.selectionLevels(for: snapshot, at: point, shapes: &lookup, holding: holding)
            return (levels, lookup.memo)
        }.value
        shapeMemo = kept
        #if DEBUG
        NSLog("Locant shapes: %.2f ms", (ContinuousClock.now - started) / .milliseconds(1))
        #endif
        return levels
    }

    /// R119's bound: the simulated screen in Device Hub, else the window under the point, else its display.
    private func shapeBound(at point: CGPoint, in snapshot: ElementSnapshot) -> CGRect {
        HitRefiner.simulatedScreen(in: snapshot)
            ?? Geometry.windowOwner(at: point, windows: windows, excludingPID: ownPID)?.bounds
            ?? SelectionOverlay.displayFrameCG(containing: point)
    }

    /// R118: a new screen sample landed; the spot under the pointer is read again with it.
    private func rehover() {
        guard phase == .hovering, lastHoverSnapshot != nil else { return }
        hover(lastHoverPoint)
    }
```

- [ ] **Step 4: Build and run every test.**

```bash
xcodebuild -project Locant.xcodeproj -scheme Locant -configuration Debug -destination 'platform=macOS' -derivedDataPath "$DD" build -quiet
xcodebuild -project Locant.xcodeproj -scheme Locant -destination 'platform=macOS' -derivedDataPath "$DD" test -quiet
```

Expected: both exit 0. A strict-concurrency error about the detached closure means a captured value isn't `Sendable`. Check that only `grid`, `bound`, `memo`, `snapshot`, `point`, and `holding` are captured, and don't capture `self`.

- [ ] **Step 5: Commit.**

```bash
git add Locant/App/AppState.swift
git commit -m "hover: read the shape under the pointer from the screen sample, and again when a new one lands"
```

---

### Task 8: What a committed shape says (R121, R123)

**Files:**
- Modify: `Locant/App/AppState.swift` (`click`, `pin`, a new `withWalkedMembers`)
- Modify: `Locant/Payload/MarkdownBuilder.swift` (cluster head line)
- Modify: `schema/capture.schema.json` (the `role` description only)
- Modify: `CHANGELOG.md`
- Modify: `LocantTests/MarkdownBuilderTests.swift`

**Interfaces:**
- Consumes: `ElementResolver.shapeRawRole`, `AccessibilityReader.elements(in:pid:)`, `RegionResolver.elements(in:among:)`, and, only if Task 1 Step 4b applied, `AccessibilityReader.hitElements(in:pid:)`.
- Produces: private `AppState.withWalkedMembers(_:pid:) async -> ResolvedElement?`.

- [ ] **Step 1: Write the failing test.** Add to `MarkdownBuilderTests`, after `testClusterRendersMembers`:

```swift
    // specs/capture-shapes.md R121: a shape's frame is its visible edges; a cluster's stays approximate.
    func testShapeHeadLineSaysItsFrameIsTheVisibleEdges() {
        let shape = ResolvedElement(
            role: "cluster", rawRole: "LocantShape", label: nil, identifier: nil, identifierSource: .unknown, value: nil,
            frame: Frame(x: 2036, y: -1147, w: 163, h: 37),
            path: [PathEntry(role: "group", identifier: nil), PathEntry(role: "cluster", identifier: nil)],
            members: [ElementMember(role: "button", label: "Recent", identifier: nil),
                      ElementMember(role: "button", label: "Currents", identifier: nil)]
        )
        let md = MarkdownBuilder.build(capture(element: shape))
        XCTAssertTrue(md.contains("cluster · 2 elements (shape found on screen by Locant, not an accessibility element; frame from its visible edges)\nMembers: button \"Recent\" · button \"Currents\"\n"), md)
        XCTAssertFalse(md.contains("frame approximate"))
    }
```

- [ ] **Step 2: Run it to see it fail.** `xcodebuild … test -quiet -only-testing:LocantTests/MarkdownBuilderTests`. Expected: `testShapeHeadLineSaysItsFrameIsTheVisibleEdges` fails; the Markdown printed in the message reads `frame approximate`.

- [ ] **Step 3: Write the Markdown change.** In `Locant/Payload/MarkdownBuilder.swift`, in `elementLines(_:)`, replace:

```swift
            var lines = [
                "cluster · \(members.count) elements (visual grouping computed by Locant, not an accessibility element; frame approximate)",
```

with:

```swift
            // specs/capture-shapes.md R121: a shape's frame is the edges seen on screen; a cluster's, an estimate.
            let kind = element.rawRole == ElementResolver.shapeRawRole
                ? "shape found on screen by Locant, not an accessibility element; frame from its visible edges"
                : "visual grouping computed by Locant, not an accessibility element; frame approximate"
            var lines = [
                "cluster · \(members.count) elements (\(kind))",
```

Run Step 2's command again. Expected: exit 0, with `testClusterRendersMembers` still green.

- [ ] **Step 4: The schema's words.** In `schema/capture.schema.json`, in `$defs.role.description`, replace:

```
`cluster` is a visual grouping computed by Locant from neighboring elements when the platform exposes no container (rawRole LocantCluster); it is not an accessibility element and carries `members`.
```

with:

```
`cluster` is computed by Locant where the platform exposes no container; it is not an accessibility element and carries `members`. rawRole LocantShape: a shape found on screen from its visible edges (a pill, capsule, card, or sheet), its frame those edges. rawRole LocantCluster: a grouping of neighboring elements, its frame approximate.
```

Check that it still parses: `python3 -I -c "import json; json.load(open('schema/capture.schema.json'))"`. Expected: no output.

- [ ] **Step 5: Members on commit.** In `Locant/App/AppState.swift`, after `describeTarget(_:snapshot:window:)`, add:

```swift
    /// specs/capture-shapes.md R121: a shape Point commits lists every element the drawn-frame walk finds
    /// inside it; the members known at hover stay when the walk finds none.
    private func withWalkedMembers(_ element: ResolvedElement?, pid: pid_t) async -> ResolvedElement? {
        guard var shape = element, shape.rawRole == ElementResolver.shapeRawRole, pid > 0 else { return element }
        let rect = shape.frame.cgRect
        let found = RegionResolver.elements(in: rect, among: await reader.elements(in: rect, pid: pid))
        if !found.isEmpty {
            shape.members = found.map { ElementMember(role: $0.role, label: $0.label, identifier: $0.identifier) }
        }
        return shape
    }
```

If Task 1 Step 4b applied, change its `found` line to the same fallback the region uses:

```swift
        var found = RegionResolver.elements(in: rect, among: await reader.elements(in: rect, pid: pid))
        if found.isEmpty { found = RegionResolver.elements(in: rect, among: await reader.hitElements(in: rect, pid: pid)) } // R122
```

In `click(_:shift:)`, inside the Point `Task`, replace:

```swift
            let (element, snapshot) = await resolveClicked(at: point)
            guard phase == .resolving else { return }
            // The window that answered the hit test, else the normal window under the point.
            let window = snapshot?.window ?? Geometry.windowOwner(at: point, windows: windows, excludingPID: ownPID)
```

with:

```swift
            let (clicked, snapshot) = await resolveClicked(at: point)
            guard phase == .resolving else { return }
            // The window that answered the hit test, else the normal window under the point.
            let window = snapshot?.window ?? Geometry.windowOwner(at: point, windows: windows, excludingPID: ownPID)
            let element = await withWalkedMembers(clicked, pid: window?.ownerPID ?? context?.frontPID ?? 0)
            guard phase == .resolving else { return }
```

In `pin(at:)`, replace:

```swift
            } else {
                let target = await describeTarget(element, snapshot: snapshot, window: window)
```

with:

```swift
            } else {
                let walked = await withWalkedMembers(element, pid: window?.ownerPID ?? context?.frontPID ?? 0) ?? element
                guard phase == .hovering else { return }
                let target = await describeTarget(walked, snapshot: snapshot, window: window)
```

- [ ] **Step 6: The changelog.** In `CHANGELOG.md`, between the intro paragraph and `## 1.0.1 (2026-10-21)`, add:

```markdown
## Unreleased

- **Point lands on the shape you see.** A capsule, card, or panel whose edges are drawn on screen is now found there, even when the app does not expose it to accessibility, as SwiftUI often does not. Point into its padding and the outline takes the whole shape; ⌥ from a button inside steps to it; the payload lists what it holds. Where a shape shows no clear edge, nearby elements still group as before, now inside small containers too.

```

- [ ] **Step 7: Build, run every test, commit.**

```bash
xcodebuild -project Locant.xcodeproj -scheme Locant -configuration Debug -destination 'platform=macOS' -derivedDataPath "$DD" build -quiet
xcodebuild -project Locant.xcodeproj -scheme Locant -destination 'platform=macOS' -derivedDataPath "$DD" test -quiet
git add Locant/App/AppState.swift Locant/Payload/MarkdownBuilder.swift schema/capture.schema.json CHANGELOG.md LocantTests/MarkdownBuilderTests.swift
git commit -m "capture: a committed shape lists what it holds and says its frame is its visible edges"
```

---

### Task 9: Check it in the app (§3)

This task needs Malik. Ask him first. Don't send synthetic input while he is at the Mac. A step that fails goes back to its task with what you saw; don't patch here.

**Files:** none. Commit only if a fix was needed, in its own commit, in the task it belongs to.

- [ ] **Step 1: The ladder probe.** It prints what hover would show at a point, shapes included, from the live screen.

```bash
mkdir -p $SP/ladder && cat > $SP/ladder/main.swift <<'EOF'
import AppKit
// Prints the ladder Locant would show at a point in Device Hub, shapes included (specs/capture-shapes.md §3).
// Usage: ladder <x> <y>   (global CG points)
let point = CGPoint(x: Double(CommandLine.arguments[1])!, y: Double(CommandLine.arguments[2])!)
guard let hub = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dt.Devices").first else { print("Device Hub is not running"); exit(1) }
let reader = AccessibilityReader()
guard let snapshot = await reader.snapshot(at: point, candidates: [], fallbackPID: hub.processIdentifier) else { print("no answer"); exit(0) }
guard let bound = HitRefiner.simulatedScreen(in: snapshot) else { print("not on the simulated screen"); exit(0) }
let taken = try await ScreenCapture.regionImage(bound, maxSamples: 4_000_000)
guard let grid = PixelGrid(image: taken.image, frame: taken.frame, scale: CGFloat(taken.image.width) / taken.frame.width, generation: 1) else { exit(1) }
var lookup = ShapeLookup(grid: grid, bound: bound, memo: .init())
func show(_ title: String, _ levels: [ResolvedElement?]) {
    print(title)
    for (i, rung) in levels.enumerated() {
        guard let rung else { print(" ", i, "nothing (fallback square)"); continue }
        let names = (rung.members ?? []).compactMap { $0.label ?? $0.identifier }.joined(separator: ", ")
        print(" ", i, rung.role, rung.rawRole, rung.identifier ?? rung.label ?? "", rung.frame, names.isEmpty ? "" : "· \(names)")
    }
}
show("with shapes:", HitRefiner.selectionLevels(for: snapshot, at: point, shapes: &lookup, holding: nil))
show("without shapes:", HitRefiner.selectionLevels(for: snapshot, at: point))
EOF
eval xcrun swiftc -O -o $SP/ladder/ladder $SP/ladder/main.swift $READER $W/Locant/Resolve/ShapeFinder.swift $W/Locant/Capture/ScreenCapture.swift 2>&1 | grep error
```

If `regionImage` throws for permission when the probe runs, skip the probe's runs and do Step 3's checks in the app alone. Note it in the report.

- [ ] **Step 2: Probe the five cases.** Ask Malik to put each screen up in Oryne in Device Hub, then pointer off.
  - **Recent/Currents** (Library):
    1. Find the buttons' frames with Task 1's probe, its band moved to cover them, or with `$SP/ladder/ladder` at the button's center.
    2. Run the ladder 1.5 pt left of Recent's `minX`, at its `midY`. Expected: rung 0 `cluster LocantShape` with `· Recent, Currents`.
    3. Run it at Recent's center. Expected: rung 0 the button, rung 1 the capsule.
  - **Toolbar** (thought detail): at the midpoint between two adjacent toolbar buttons. Expected: rung 0 the capsule. At the pencil's center: expected rung 0 `button … pencil`, rung 1 the capsule.
  - **Sheet** (Library with the Notification sheet up). Its bottom has no edge, so no shape is expected (spec R119).
    - Between its heading and "Add a thought": expected rung 0 `cluster LocantCluster` with the sheet's contents (R120).
    - 8 pt inside its left edge, away from its contents: expected the 334×726 screen group, as today.
    - On "Add a thought": expected the button.
  - **Background:** a point on the screen's plain background. Expected: `with shapes:` and `without shapes:` print the same rungs. On a spanning background, R120 changes nothing, so `without shapes:` is today's ladder.
  - **The pill:** it shows only after a thought is deleted. Ask Malik whether he wants to do that; skip it if not. No shape is expected (no edge along its top). In its padding, `with shapes:` and `without shapes:` match; the second rung is `cluster LocantCluster · Thought deleted, Undo` (R120).

- [ ] **Step 3: By hand, in the Debug app.** Setup:

```bash
defaults export com.malikzhang.deixis "$SP/defaults-before.plist"
osascript -e 'tell application id "com.malikzhang.deixis" to quit'
for i in $(seq 1 30); do pgrep -f "MacOS/Locant$" >/dev/null || break; perl -e 'sleep 0.5'; done
pgrep -f "MacOS/Locant$" && echo "still running: stop and ask Malik"
mkdir -p "$SP/captures"
APP="$DD/Build/Products/Debug/Locant.app"
open -n "$APP" --args -pastesIntoAgent '<false/>' -checksForUpdates '<false/>' -collectsIterations '<false/>' -ballEnabled '<false/>' -captureFolder "$SP/captures"
```

Ask Malik to Point (double-tap ⌃) over Oryne in Device Hub and try each case:
- **The pill** (if shown): the fallback. In its padding, the outline is as before. ⌥ from "Thought deleted" outlines `cluster · Thought deleted, Undo`, and committed at that level, the PNG holds the whole pill.
- **The toolbar:** the capsule's rim outlines the capsule; on the pencil, `button · pencil`; ⌥ from the pencil goes to the capsule, then up.
- **Recent/Currents:** ⌥ from Recent outlines the capsule in one press.
- **The sheet:** the fallback, and not solved. Between its contents, the outline is their cluster; in its empty margin, the 334×726 group as before; on "Add a thought", the button.
- **The background:** outlines what it did before.
- **A drawn frame** around the three toolbar icons lists the buttons hover reads there (R122, as Task 1 found).
- **The taps:** every outline move taps once on the trackpad.

For each committed capture, check the sidecar:

```bash
for f in "$SP"/captures/**/*.json(N); do plutil -extract element.rawRole raw "$f" 2>/dev/null; plutil -extract element.members json -o - "$f" 2>/dev/null | head -c 300; echo; done
```

Expected for a shape: `LocantShape` and the members the walk found. The Markdown on the clipboard (`pbpaste | head -5`) shows the `frame from its visible edges` head line.

Also watch Xcode's console or `/usr/bin/log stream --predicate 'process == "Locant"' --level debug | grep "Locant shapes"`. The per-lookup times should mostly be a few milliseconds.

- [ ] **Step 4: Restore.**

```bash
pkill -f "Debug/Locant.app/Contents/MacOS/Locant"; perl -e 'sleep 2'
defaults export com.malikzhang.deixis "$SP/defaults-after.plist"
diff <(plutil -p "$SP/defaults-before.plist") <(plutil -p "$SP/defaults-after.plist")
open -a /Applications/Locant.app
```

For each key the diff shows as changed, write Malik's old value back (`defaults write com.malikzhang.deixis <key> …`, or `defaults delete` for an added key). Confirm `pgrep -f "MacOS/Locant$"` shows one PID from `/Applications`.

- [ ] **Step 5: Report** in three lines (`docs/CLAUDE.md`):
  - what passed;
  - what was skipped (the pill, if Malik didn't delete a thought; the no-permission case, which the `ScreenSamplerTests` cover instead);
  - what is unsure: tolerances near their limit on `shape-sheet`, and any lookup times over 5 ms.
