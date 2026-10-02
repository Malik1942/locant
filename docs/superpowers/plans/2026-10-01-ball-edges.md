# Ball edges Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The ball tucks into the bottom edge beside the Dock as well as the sides, wakes where it rests, shows a ghost of where a drop will tuck, and can be thrown at an edge (`specs/ball-edges.md`, R80–R85).

**Architecture:** Two new pure units carry the geometry and the release rules (`BallEdges`, `Throw`); `Spring`/`Glide` gain an initial velocity; `AccessibilityReader` reads the Dock's tile frame; `FloatingBall` swaps its `visibleFrame` docking for `BallEdges`, keeps its home at the tuck, and passes drag velocity through; a small `BallGhost` panel previews the tuck.

**Tech Stack:** Swift 6 (strict concurrency complete), AppKit, ApplicationServices (AX), XCTest. No packages.

## Global Constraints

- Swift 6, strict concurrency `complete`; `async/await` only.
- No third-party packages; no private API.
- Accessibility calls run on a background actor (`AccessibilityReader`); the main actor touches AppKit only.
- Pure functions get tests; UI does not.
- Commits: small, one intent each, `area: what changed`, never without a green build.
- No new settings, permissions, or targets. Tests live in `LocantTests/` (file-system-synchronized group: new files need no pbxproj edit).

**Test command** (from the worktree root; `SCRATCH` is the session scratchpad):

```bash
xcodebuild -project Locant.xcodeproj -scheme Locant -destination 'platform=macOS' test \
  -only-testing:LocantTests/<Class> CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
  -derivedDataPath "$SCRATCH/DerivedData" -quiet
```

Drop `-only-testing` for the full suite. Expected tail on success: `** TEST SUCCEEDED **`.

---

### Task 1: A spring that starts with a velocity

**Files:**
- Modify: `Locant/Launcher/Motion.swift`
- Test: `LocantTests/SpringTests.swift`

**Interfaces:**
- Produces: `Spring.offset(at:displacement:velocity:) -> Double`, `Spring.settleTime(displacement:velocity:tolerance:) -> Double`, `Glide.move(to:spring:velocity:)` (velocity defaults to `.zero`). Removes the `Spring.settleTime` property.

- [ ] **Step 1: Write the failing tests.** In `SpringTests.swift`, change test 1's settle line to the new API and add tests 4 and 5:

```swift
    // 1
    func testStartsAtZeroAndSettlesAtOne() {
        for spring in [Spring.wake, .settle, .tuck] {
            let settle = spring.settleTime(displacement: 1, velocity: 0, tolerance: 0.005)
            XCTAssertEqual(spring.value(at: 0), 0)
            XCTAssertEqual(spring.value(at: settle), 1, accuracy: 0.01)
            XCTAssertEqual(spring.value(at: settle * 2), 1, accuracy: 0.001)
        }
    }
```

```swift
    // 4
    func testWithoutVelocityTheOffsetIsTodaysCurve() {
        for spring in [Spring.wake, .settle, .tuck] {
            for t in stride(from: 0.0, through: 1.0, by: 0.05) {
                XCTAssertEqual(spring.offset(at: t, displacement: -300, velocity: 0), -300 * (1 - spring.value(at: t)), accuracy: 0.0001)
            }
        }
    }

    // 5
    func testAThrownSpringStartsAtItsVelocityAndStillSettles() {
        let spring = Spring.tuck
        let h = 0.0001
        let start = (spring.offset(at: h, displacement: -300, velocity: 2000) - spring.offset(at: 0, displacement: -300, velocity: 2000)) / h
        XCTAssertEqual(start, 2000, accuracy: 5)
        let settle = spring.settleTime(displacement: -300, velocity: 2000)
        for t in stride(from: settle, through: settle + 1, by: 0.01) {
            XCTAssertLessThanOrEqual(abs(spring.offset(at: t, displacement: -300, velocity: 2000)), 0.25)
        }
    }
```

- [ ] **Step 2: Run `-only-testing:LocantTests/SpringTests`.** Expected: build failure, `value of type 'Spring' has no member 'offset'`.

- [ ] **Step 3: Implement.** In `Motion.swift`, replace the `settleTime` property with:

```swift
    /// The offset from rest after `t` seconds, in the caller's units, of a spring let go
    /// `displacement` from rest while moving at `velocity` per second. With no velocity it is
    /// `displacement · (1 − value(at: t))`; a velocity is how a thrown ball keeps the hand's speed.
    func offset(at t: Double, displacement: Double, velocity: Double) -> Double {
        guard t > 0 else { return displacement }
        let omega = 2 * Double.pi / response
        let zeta = min(damping, 0.999)
        let omegaD = omega * (1 - zeta * zeta).squareRoot()
        let decay = exp(-zeta * omega * t)
        return decay * (displacement * cos(omegaD * t) + (zeta * omega * displacement + velocity) / omegaD * sin(omegaD * t))
    }

    /// When `offset` stays within `tolerance` of rest: the swing's envelope has decayed that far.
    func settleTime(displacement: Double, velocity: Double, tolerance: Double = 0.25) -> Double {
        let omega = 2 * Double.pi / response
        let zeta = min(damping, 0.999)
        let omegaD = omega * (1 - zeta * zeta).squareRoot()
        let amplitude = hypot(displacement, (zeta * omega * displacement + velocity) / omegaD)
        guard amplitude > tolerance else { return 0 }
        return log(amplitude / tolerance) / (zeta * omega)
    }
```

In `Glide`, add `private var velocity = CGPoint.zero`, and replace `move(to:spring:)` and `tick(_:)`:

```swift
    /// `velocity`, in points per second, is the window's speed as it is let go; a thrown ball keeps it.
    func move(to target: CGPoint, spring: Spring, velocity: CGPoint = .zero) {
        cancel()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            window.setFrameOrigin(target)
            return
        }
        from = window.frame.origin
        to = target
        self.velocity = velocity
        self.spring = spring
        start = CACurrentMediaTime()
        duration = max(spring.settleTime(displacement: from.x - to.x, velocity: velocity.x),
                       spring.settleTime(displacement: from.y - to.y, velocity: velocity.y))
        let link = window.displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }
```

```swift
    @objc private func tick(_ link: CADisplayLink) {
        let t = CACurrentMediaTime() - start
        guard t < duration else {
            window.setFrameOrigin(to)
            cancel()
            return
        }
        window.setFrameOrigin(CGPoint(
            x: to.x + spring.offset(at: t, displacement: from.x - to.x, velocity: velocity.x),
            y: to.y + spring.offset(at: t, displacement: from.y - to.y, velocity: velocity.y)
        ))
    }
```

Update the `value(at:)` doc's neighbour comment that mentioned `settleTime` if any; leave `value(at:)` as is.

- [ ] **Step 4: Run `-only-testing:LocantTests/SpringTests`.** Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit.**

```bash
git add Locant/Launcher/Motion.swift LocantTests/SpringTests.swift
git commit -m "motion: a spring can start with a velocity, and a glide settles to a quarter point"
```

### Task 2: Free edges (`BallEdges`)

**Files:**
- Create: `Locant/Launcher/BallEdges.swift`
- Test: `LocantTests/BallEdgesTests.swift`

**Interfaces:**
- Consumes: `FloatingBall.Tokens.diameter`, `.dockedVisible`, `.approach`, `.edgeSnap`, `.ringMargin` (nested types are not main-actor isolated, so a pure struct may read them).
- Produces: `struct BallEdges` with `init(frame:visible:dock:others:)`, `free: [Edge: [Span]]`, `tuck(nearest:) -> Tuck?`, `home(for:) -> CGPoint`, `isNearEdge(_:) -> Bool`, `ringSafe(_:) -> CGPoint`, `inside(_:) -> CGPoint`; `BallEdges.Edge` (`.left`, `.right`, `.bottom`), `BallEdges.Tuck { edge, center }`.

- [ ] **Step 1: Write the failing tests** in `LocantTests/BallEdgesTests.swift`:

```swift
import XCTest
@testable import Locant

/// specs/ball-edges.md R80, on Malik's built-in display: 2056×1329, the Dock at the bottom with its
/// tiles from x 330 to 1726, the menu bar 39 pt.
final class BallEdgesTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 2056, height: 1329)
    let visible = CGRect(x: 0, y: 52, width: 2056, height: 1238)
    let dock = CGRect(x: 330, y: 10, width: 1396, height: 46)
    var edges: BallEdges { BallEdges(frame: screen, visible: visible, dock: dock, others: []) }

    func testABottomDockSplitsTheBottomEdgeClearOfItsEnds() {
        XCTAssertEqual(edges.free[.bottom], [48...250, 1806...2008])
    }

    func testWithoutADockTheWholeBottomIsFree() {
        let noDock = BallEdges(frame: screen, visible: CGRect(x: 0, y: 0, width: 2056, height: 1290), dock: nil, others: [])
        XCTAssertEqual(noDock.free[.bottom], [48...2008])
    }

    func testAnUnreadDockClosesTheEdgeTheVisibleFrameShowsItOn() {
        let unread = BallEdges(frame: screen, visible: visible, dock: nil, others: [])
        XCTAssertEqual(unread.free[.bottom], [])
        XCTAssertEqual(unread.free[.left], [48...1242])
    }

    func testALeftDockSplitsTheLeftEdge() {
        let left = BallEdges(frame: screen, visible: CGRect(x: 60, y: 0, width: 1996, height: 1290),
                             dock: CGRect(x: 4, y: 300, width: 56, height: 700), others: [])
        XCTAssertEqual(left.free[.left], [48...220, 1080...1242])
        XCTAssertEqual(left.free[.bottom], [48...2008])
    }

    func testTheSidesRunUpToTheMenuBarAndKeepClearOfTheCorners() {
        XCTAssertEqual(edges.free[.left], [48...1242])
        XCTAssertEqual(edges.free[.right], [48...1242])
    }

    func testADisplayTouchingAnEdgeClosesThatSpan() {
        let beside = CGRect(x: 2056, y: 200, width: 1920, height: 1080)
        let shared = BallEdges(frame: screen, visible: visible, dock: dock, others: [beside])
        XCTAssertEqual(shared.free[.right], [48...176])
        XCTAssertEqual(shared.free[.left], [48...1242])
    }

    func testADockOnAnotherDisplayDoesNotCount() {
        let upper = CGRect(x: -1038, y: 1329, width: 3360, height: 1890)
        let elsewhere = BallEdges(frame: screen, visible: CGRect(x: 0, y: 0, width: 2056, height: 1290),
                                  dock: CGRect(x: 200, y: 1339, width: 1200, height: 46), others: [upper])
        XCTAssertEqual(elsewhere.free[.bottom], [48...2008])
    }

    func testAHiddenDockStillCountsByItsSpan() {
        // A full-screen Space slides the Dock off the bottom; its tiles keep their x.
        let hidden = BallEdges(frame: screen, visible: visible, dock: CGRect(x: 330, y: -46, width: 1396, height: 46), others: [])
        XCTAssertEqual(hidden.free[.bottom], [48...250, 1806...2008])
    }

    func testOverTheDockTheNearestTuckIsItsEnd() {
        let tuck = edges.tuck(nearest: CGPoint(x: 400, y: 30))
        XCTAssertEqual(tuck?.edge, .bottom)
        XCTAssertEqual(tuck?.center.x, 250)
    }

    func testASideEdgeWinsWhenItIsNearer() {
        XCTAssertEqual(edges.tuck(nearest: CGPoint(x: 300, y: 400))?.edge, .left)
        XCTAssertEqual(edges.tuck(nearest: CGPoint(x: 2000, y: 700))?.edge, .right)
    }

    func testATuckShowsSixtyPercentAndHomeTouchesTheEdge() throws {
        let bottom = try XCTUnwrap(edges.tuck(nearest: CGPoint(x: 1900, y: 20)))
        XCTAssertEqual(bottom.center.y, 4.8, accuracy: 0.001)
        XCTAssertEqual(edges.home(for: bottom), CGPoint(x: 1900, y: 24))
        let right = try XCTUnwrap(edges.tuck(nearest: CGPoint(x: 2050, y: 600)))
        XCTAssertEqual(right.center.x, 2056 - 4.8, accuracy: 0.001)
        XCTAssertEqual(edges.home(for: right), CGPoint(x: 2032, y: 600))
    }

    func testARingBesideTheDockMeasuresFromTheRealBottom() {
        XCTAssertEqual(edges.ringSafe(CGPoint(x: 1900, y: 24)), CGPoint(x: 1900, y: 100))
        XCTAssertEqual(edges.ringSafe(CGPoint(x: 1000, y: 24)), CGPoint(x: 1000, y: 152))
        XCTAssertEqual(edges.ringSafe(CGPoint(x: 2032, y: 1280)), CGPoint(x: 1956, y: 1190))
    }

    func testADropNearTheVisibleFrameTucks() {
        XCTAssertTrue(edges.isNearEdge(CGPoint(x: 1000, y: 100)))
        XCTAssertFalse(edges.isNearEdge(CGPoint(x: 1000, y: 101)))
        XCTAssertTrue(edges.isNearEdge(CGPoint(x: 2010, y: 600)))
        XCTAssertFalse(edges.isNearEdge(CGPoint(x: 1000, y: 1280)), "the top is not a tuck edge")
    }

    func testInsideKeepsTheWholeDiscInTheVisibleFrame() {
        XCTAssertEqual(edges.inside(CGPoint(x: 2100, y: 1400)), CGPoint(x: 2032, y: 1266))
        XCTAssertEqual(edges.inside(CGPoint(x: 900, y: 600)), CGPoint(x: 900, y: 600))
    }

    func testNoRoomAnywhereMeansNoTuck() {
        let tiny = CGRect(x: 0, y: 0, width: 80, height: 80)
        XCTAssertNil(BallEdges(frame: tiny, visible: tiny, dock: nil, others: []).tuck(nearest: CGPoint(x: 40, y: 40)))
    }
}
```

- [ ] **Step 2: Run `-only-testing:LocantTests/BallEdgesTests`.** Expected: build failure, `cannot find 'BallEdges' in scope`.

- [ ] **Step 3: Implement** `Locant/Launcher/BallEdges.swift`:

```swift
import CoreGraphics

/// specs/ball-edges.md R80: where the ball may tuck on one screen, and how far in it must come for
/// the ring. Pure. Everything is in AppKit coordinates (bottom-left origin, y up), and every
/// position is the disc's center. Tucks use the screen's real edges, not `visibleFrame`: beside a
/// Dock at the bottom the bottom of the screen is free, over the Dock it is not.
struct BallEdges: Equatable, Sendable {
    enum Edge: CaseIterable, Sendable { case left, right, bottom }

    struct Tuck: Equatable, Sendable {
        var edge: Edge
        /// The disc's center, `dockedVisible` of the disc on screen.
        var center: CGPoint
    }

    typealias Span = ClosedRange<CGFloat>

    let frame: CGRect
    let visible: CGRect
    /// Along each edge, the stretches the center may tuck into: y on the sides, x on the bottom.
    let free: [Edge: [Span]]
    /// Along each edge, what the Dock covers widened by `dockGap`, or the whole edge when its span is unknown.
    let dockSpans: [Edge: [Span]]

    static var radius: CGFloat { FloatingBall.Tokens.diameter / 2 }
    /// How far inside its edge a tucked center sits: 4.8 pt, so 60 percent of the disc shows.
    static var tuckInset: CGFloat { FloatingBall.Tokens.diameter * FloatingBall.Tokens.dockedVisible - radius }
    /// The wake radius: tucked this far from the Dock's ends, the ball sleeps while the cursor reaches for them.
    static var dockGap: CGFloat { FloatingBall.Tokens.approach }
    static var cornerMargin: CGFloat { FloatingBall.Tokens.diameter }
    /// With no Dock frame, `visibleFrame` inset more than this from an edge means the Dock is on it.
    static let dockInset: CGFloat = 8

    /// `dock`: the Dock's tiles, wherever they are; they count when this screen is the one nearest them.
    /// `others`: the other screens' frames.
    init(frame: CGRect, visible: CGRect, dock: CGRect?, others: [CGRect]) {
        self.frame = frame
        self.visible = visible
        var dockSpans: [Edge: [Span]] = [:]
        if let dock {
            if Self.isNearest(frame, to: dock, among: others) {
                let (edge, span) = Self.dockEdge(dock, in: frame)
                dockSpans[edge] = [(span.lowerBound - Self.dockGap)...(span.upperBound + Self.dockGap)]
            }
        } else {
            if visible.minY - frame.minY > Self.dockInset { dockSpans[.bottom] = [Self.length(of: .bottom, frame: frame, visible: visible)] }
            if visible.minX - frame.minX > Self.dockInset { dockSpans[.left] = [Self.length(of: .left, frame: frame, visible: visible)] }
            if frame.maxX - visible.maxX > Self.dockInset { dockSpans[.right] = [Self.length(of: .right, frame: frame, visible: visible)] }
        }
        var free: [Edge: [Span]] = [:]
        for edge in Edge.allCases {
            let whole = Self.length(of: edge, frame: frame, visible: visible)
            guard let usable = Self.span(whole.lowerBound + Self.cornerMargin, whole.upperBound - Self.cornerMargin) else {
                free[edge] = []
                continue
            }
            let cuts = (dockSpans[edge] ?? []) + others.compactMap { Self.shared(edge, with: $0, frame: frame) }
            free[edge] = Self.subtract(cuts, from: usable)
        }
        self.free = free
        self.dockSpans = dockSpans
    }

    // MARK: Questions

    /// The free tuck nearest `point`, or nil when no edge has room.
    func tuck(nearest point: CGPoint) -> Tuck? {
        var best: (tuck: Tuck, distance: CGFloat)?
        for edge in Edge.allCases {
            for span in free[edge] ?? [] {
                let along = edge == .bottom ? point.x : point.y
                let candidate = tuck(on: edge, at: min(max(along, span.lowerBound), span.upperBound))
                let distance = hypot(candidate.center.x - point.x, candidate.center.y - point.y)
                if distance < best?.distance ?? .infinity { best = (candidate, distance) }
            }
        }
        return best?.tuck
    }

    /// The tuck's spot with the whole disc on screen, touching the edge: the ball's home while it rests there.
    func home(for tuck: Tuck) -> CGPoint {
        switch tuck.edge {
        case .left: CGPoint(x: frame.minX + Self.radius, y: tuck.center.y)
        case .right: CGPoint(x: frame.maxX - Self.radius, y: tuck.center.y)
        case .bottom: CGPoint(x: tuck.center.x, y: frame.minY + Self.radius)
        }
    }

    /// A drop here tucks: within `edgeSnap` of the left, right, or bottom of `visibleFrame`, or past it.
    func isNearEdge(_ point: CGPoint) -> Bool {
        let snap = FloatingBall.Tokens.edgeSnap
        return point.x - visible.minX <= snap || visible.maxX - point.x <= snap || point.y - visible.minY <= snap
    }

    /// `center` pulled in until the ring (`ringMargin`) fits. Toward the menu bar it measures from
    /// `visibleFrame`; toward the other sides from the real edge, except across the Dock.
    func ringSafe(_ center: CGPoint) -> CGPoint {
        let margin = FloatingBall.Tokens.ringMargin
        let left = (covered(.left, at: center.y) ? visible.minX : frame.minX) + margin
        let right = (covered(.right, at: center.y) ? visible.maxX : frame.maxX) - margin
        let bottom = (covered(.bottom, at: center.x) ? visible.minY : frame.minY) + margin
        let top = visible.maxY - margin
        guard left <= right, bottom <= top else { return center }
        return CGPoint(x: min(max(center.x, left), right), y: min(max(center.y, bottom), top))
    }

    /// `point` kept inside `visibleFrame` with the whole disc showing: where a throw into open space rests.
    func inside(_ point: CGPoint) -> CGPoint {
        let area = visible.insetBy(dx: Self.radius, dy: Self.radius)
        guard !area.isNull else { return point }
        return CGPoint(x: min(max(point.x, area.minX), area.maxX), y: min(max(point.y, area.minY), area.maxY))
    }

    // MARK: Pieces

    private func tuck(on edge: Edge, at along: CGFloat) -> Tuck {
        switch edge {
        case .left: Tuck(edge: edge, center: CGPoint(x: frame.minX + Self.tuckInset, y: along))
        case .right: Tuck(edge: edge, center: CGPoint(x: frame.maxX - Self.tuckInset, y: along))
        case .bottom: Tuck(edge: edge, center: CGPoint(x: along, y: frame.minY + Self.tuckInset))
        }
    }

    private func covered(_ edge: Edge, at along: CGFloat) -> Bool {
        (dockSpans[edge] ?? []).contains { $0.contains(along) }
    }

    /// The whole stretch of an edge the center could use; the sides run up to the menu bar.
    private static func length(of edge: Edge, frame: CGRect, visible: CGRect) -> Span {
        switch edge {
        case .left, .right: frame.minY...max(frame.minY, visible.maxY)
        case .bottom: frame.minX...frame.maxX
        }
    }

    /// A Dock wider than tall is on the bottom; otherwise on the side its middle is nearer. Its span runs along that edge.
    private static func dockEdge(_ dock: CGRect, in frame: CGRect) -> (Edge, Span) {
        if dock.width > dock.height { return (.bottom, dock.minX...dock.maxX) }
        return (dock.midX < frame.midX ? .left : .right, dock.minY...dock.maxY)
    }

    private static func isNearest(_ frame: CGRect, to dock: CGRect, among others: [CGRect]) -> Bool {
        let middle = CGPoint(x: dock.midX, y: dock.midY)
        let mine = distance(from: middle, to: frame)
        return others.allSatisfy { mine <= distance(from: middle, to: $0) }
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        hypot(max(rect.minX - point.x, 0, point.x - rect.maxX), max(rect.minY - point.y, 0, point.y - rect.maxY))
    }

    /// Where `other` touches this screen along `edge`, widened by a radius so no part of a tucked disc
    /// shows on the other display; nil when it does not touch.
    private static func shared(_ edge: Edge, with other: CGRect, frame: CGRect) -> Span? {
        let touching: Bool
        let overlap: (low: CGFloat, high: CGFloat)
        switch edge {
        case .left:
            touching = abs(other.maxX - frame.minX) <= 1
            overlap = (max(frame.minY, other.minY), min(frame.maxY, other.maxY))
        case .right:
            touching = abs(other.minX - frame.maxX) <= 1
            overlap = (max(frame.minY, other.minY), min(frame.maxY, other.maxY))
        case .bottom:
            touching = abs(other.maxY - frame.minY) <= 1
            overlap = (max(frame.minX, other.minX), min(frame.maxX, other.maxX))
        }
        guard touching, overlap.low < overlap.high else { return nil }
        return (overlap.low - radius)...(overlap.high + radius)
    }

    /// `range` with every one of `cuts` taken out; what is left, low to high.
    private static func subtract(_ cuts: [Span], from range: Span) -> [Span] {
        var pieces: [Span] = []
        var low = range.lowerBound
        for cut in cuts.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let piece = span(low, min(cut.lowerBound, range.upperBound)) { pieces.append(piece) }
            low = max(low, cut.upperBound)
        }
        if let piece = span(low, range.upperBound) { pieces.append(piece) }
        return pieces
    }

    private static func span(_ low: CGFloat, _ high: CGFloat) -> Span? {
        low < high ? low...high : nil
    }
}
```

- [ ] **Step 4: Run `-only-testing:LocantTests/BallEdgesTests`.** Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit.**

```bash
git add Locant/Launcher/BallEdges.swift LocantTests/BallEdgesTests.swift
git commit -m "ball: the free stretches of a screen's edges, beside the Dock and clear of its ends, the corners, and other displays"
```

### Task 3: The release (`Throw`)

**Files:**
- Create: `Locant/Launcher/Throw.swift`
- Test: `LocantTests/ThrowTests.swift`

**Interfaces:**
- Consumes: `BallEdges` (Task 2): `frame`, `isNearEdge(_:)`, `tuck(nearest:)`, `inside(_:)`, `BallEdges.Tuck`.
- Produces: `enum Throw` with `Sample { time, point }`, `Release { landing, thrown, tuck }`, `window`, `minimumSpeed`, `maximumSpeed`, `velocity(_:) -> CGPoint`, `isThrow(_:) -> Bool`, `projection(_:) -> CGPoint`, `landing(from:by:in:) -> CGPoint`, `release(center:velocity:edges:autoHide:) -> Release`.

- [ ] **Step 1: Write the failing tests** in `LocantTests/ThrowTests.swift`:

```swift
import XCTest
@testable import Locant

/// specs/ball-edges.md R83, on the same display as `BallEdgesTests`.
final class ThrowTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 2056, height: 1329)
    let visible = CGRect(x: 0, y: 52, width: 2056, height: 1238)
    let dock = CGRect(x: 330, y: 10, width: 1396, height: 46)
    var edges: BallEdges { BallEdges(frame: screen, visible: visible, dock: dock, others: []) }

    private func sample(_ time: TimeInterval, _ x: CGFloat, _ y: CGFloat = 0) -> Throw.Sample {
        Throw.Sample(time: time, point: CGPoint(x: x, y: y))
    }

    func testVelocityReadsOnlyTheLastEightyMilliseconds() {
        let samples = [sample(0, 0), sample(0.05, 50), sample(0.10, 100), sample(0.15, 200)]
        XCTAssertEqual(Throw.velocity(samples).x, 2000, accuracy: 0.001)
        XCTAssertEqual(Throw.velocity(samples).y, 0)
    }

    func testAPauseBeforeLettingGoIsStill() {
        XCTAssertEqual(Throw.velocity([sample(0, 0), sample(0.05, 100), sample(0.30, 100)]), .zero)
    }

    func testOneSampleIsStill() {
        XCTAssertEqual(Throw.velocity([sample(0, 10)]), .zero)
        XCTAssertEqual(Throw.velocity([]), .zero)
    }

    func testAWildFlickIsCapped() {
        let velocity = Throw.velocity([sample(0, 0), sample(0.01, 500)])
        XCTAssertEqual(hypot(velocity.x, velocity.y), Throw.maximumSpeed, accuracy: 0.001)
    }

    func testOnlyAFastReleaseIsAThrow() {
        XCTAssertFalse(Throw.isThrow(CGPoint(x: 699, y: 0)))
        XCTAssertTrue(Throw.isThrow(CGPoint(x: 0, y: -700)))
    }

    func testTheProjectionIsAboutHalfASecondOfTheVelocity() {
        let projection = Throw.projection(CGPoint(x: 1000, y: -2000))
        XCTAssertEqual(projection.x, 499, accuracy: 0.01)
        XCTAssertEqual(projection.y, -998, accuracy: 0.01)
    }

    func testThePathStopsAtTheScreen() {
        let down = Throw.landing(from: CGPoint(x: 1000, y: 600), by: CGPoint(x: 0, y: -2000), in: screen)
        XCTAssertEqual(down.x, 1000, accuracy: 0.001)
        XCTAssertEqual(down.y, 0, accuracy: 0.001)
        let corner = Throw.landing(from: CGPoint(x: 1900, y: 200), by: CGPoint(x: 500, y: -500), in: screen)
        XCTAssertEqual(corner.x, 2056, accuracy: 0.001)
        XCTAssertEqual(corner.y, 44, accuracy: 0.001)
        XCTAssertEqual(Throw.landing(from: CGPoint(x: 500, y: 500), by: CGPoint(x: 100, y: 0), in: screen), CGPoint(x: 600, y: 500))
    }

    func testASlowDropNearAnEdgeTucksAndInTheOpenStays() {
        let near = Throw.release(center: CGPoint(x: 1900, y: 40), velocity: CGPoint(x: 100, y: 0), edges: edges, autoHide: true)
        XCTAssertFalse(near.thrown)
        XCTAssertEqual(near.tuck?.edge, .bottom)
        let open = Throw.release(center: CGPoint(x: 1000, y: 600), velocity: .zero, edges: edges, autoHide: true)
        XCTAssertNil(open.tuck)
        XCTAssertEqual(open.landing, CGPoint(x: 1000, y: 600))
    }

    func testAFlickAtTheBottomLeftTucksBesideTheDock() {
        let release = Throw.release(center: CGPoint(x: 600, y: 500), velocity: CGPoint(x: -1000, y: -1500), edges: edges, autoHide: true)
        XCTAssertTrue(release.thrown)
        XCTAssertEqual(release.tuck?.edge, .bottom)
        XCTAssertEqual(release.tuck?.center.x, 250)
    }

    func testAFlickIntoTheOpenRestsInsideTheVisibleFrame() {
        let release = Throw.release(center: CGPoint(x: 1000, y: 600), velocity: CGPoint(x: 0, y: 1500), edges: edges, autoHide: true)
        XCTAssertTrue(release.thrown)
        XCTAssertNil(release.tuck)
        XCTAssertEqual(release.landing, CGPoint(x: 1000, y: 1266))
    }

    func testWithAutoHideOffNothingTucks() {
        XCTAssertNil(Throw.release(center: CGPoint(x: 2040, y: 600), velocity: .zero, edges: edges, autoHide: false).tuck)
        let flick = Throw.release(center: CGPoint(x: 1000, y: 600), velocity: CGPoint(x: 3000, y: 0), edges: edges, autoHide: false)
        XCTAssertNil(flick.tuck)
        XCTAssertEqual(flick.landing, CGPoint(x: 2032, y: 600))
    }
}
```

- [ ] **Step 2: Run `-only-testing:LocantTests/ThrowTests`.** Expected: build failure, `cannot find 'Throw' in scope`.

- [ ] **Step 3: Implement** `Locant/Launcher/Throw.swift`:

```swift
import CoreGraphics
import Foundation

/// specs/ball-edges.md R83: what letting go of the ball does. A release faster than `minimumSpeed`
/// is a throw, carried on the way iOS carries Picture in Picture; anything slower is a drop. Pure.
enum Throw {
    struct Sample: Equatable, Sendable {
        var time: TimeInterval
        var point: CGPoint
    }

    struct Release: Equatable, Sendable {
        /// Where the disc's center comes to rest, or the point its tuck was chosen from.
        var landing: CGPoint
        var thrown: Bool
        /// Set when the release tucks the ball.
        var tuck: BallEdges.Tuck?
    }

    /// The speed is read over this much of the drag before the release.
    static let window: TimeInterval = 0.08
    static let minimumSpeed: CGFloat = 700
    /// A wilder flick counts as this fast.
    static let maximumSpeed: CGFloat = 4000
    /// UIScrollView's normal deceleration rate, per millisecond.
    static let deceleration: CGFloat = 0.998

    /// Points per second from the oldest sample within `window` of the last one to the last one.
    /// The release itself is the last sample, so a pause before letting go reads as still.
    static func velocity(_ samples: [Sample]) -> CGPoint {
        guard let last = samples.last,
              let first = samples.first(where: { last.time - $0.time <= window }),
              last.time > first.time else { return .zero }
        let elapsed = CGFloat(last.time - first.time)
        let velocity = CGPoint(x: (last.point.x - first.point.x) / elapsed, y: (last.point.y - first.point.y) / elapsed)
        let speed = hypot(velocity.x, velocity.y)
        guard speed > maximumSpeed else { return velocity }
        return CGPoint(x: velocity.x * maximumSpeed / speed, y: velocity.y * maximumSpeed / speed)
    }

    static func isThrow(_ velocity: CGPoint) -> Bool {
        hypot(velocity.x, velocity.y) >= minimumSpeed
    }

    /// How far the deceleration carries a release: `v · d / (1 − d)` with `d` per millisecond,
    /// about half a second of the velocity.
    static func projection(_ velocity: CGPoint) -> CGPoint {
        let seconds = deceleration / (1 - deceleration) / 1000
        return CGPoint(x: velocity.x * seconds, y: velocity.y * seconds)
    }

    /// `start` carried by `offset`, stopped where the path leaves `bounds`.
    static func landing(from start: CGPoint, by offset: CGPoint, in bounds: CGRect) -> CGPoint {
        let origin = CGPoint(x: min(max(start.x, bounds.minX), bounds.maxX), y: min(max(start.y, bounds.minY), bounds.maxY))
        var t: CGFloat = 1
        if offset.x > 0 { t = min(t, (bounds.maxX - origin.x) / offset.x) }
        if offset.x < 0 { t = min(t, (bounds.minX - origin.x) / offset.x) }
        if offset.y > 0 { t = min(t, (bounds.maxY - origin.y) / offset.y) }
        if offset.y < 0 { t = min(t, (bounds.minY - origin.y) / offset.y) }
        t = max(t, 0)
        return CGPoint(x: origin.x + offset.x * t, y: origin.y + offset.y * t)
    }

    /// Letting go of a disc centered at `center` and moving at `velocity`: where it lands, and the
    /// tuck when the landing is at an edge and Auto-hide is on. A throw into open space rests inside
    /// the visible frame; a drop stays exactly where it is.
    static func release(center: CGPoint, velocity: CGPoint, edges: BallEdges, autoHide: Bool) -> Release {
        guard isThrow(velocity) else {
            let tuck = autoHide && edges.isNearEdge(center) ? edges.tuck(nearest: center) : nil
            return Release(landing: center, thrown: false, tuck: tuck)
        }
        let point = landing(from: center, by: projection(velocity), in: edges.frame)
        if autoHide, edges.isNearEdge(point), let tuck = edges.tuck(nearest: point) {
            return Release(landing: point, thrown: true, tuck: tuck)
        }
        return Release(landing: edges.inside(point), thrown: true, tuck: nil)
    }
}
```

- [ ] **Step 4: Run `-only-testing:LocantTests/ThrowTests`.** Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit.**

```bash
git add Locant/Launcher/Throw.swift LocantTests/ThrowTests.swift
git commit -m "ball: a release reads the drag's speed, and a throw lands where iOS would carry it, at an edge or in the open"
```

### Task 4: The Dock's frame and the saved spot below the visible frame

**Files:**
- Modify: `Locant/Resolve/AccessibilityReader.swift` (add `dockFrame()` after `raise(pid:)`)
- Modify: `Locant/Launcher/FloatingBall.swift` (`onScreenOrigin`)
- Test: `LocantTests/FloatingBallTests.swift`

**Interfaces:**
- Produces: `AccessibilityReader.dockFrame() -> CGRect?` (CG coordinates); `FloatingBall.onScreenOrigin(_:screens:visible:)` with `visible: [CGRect]? = nil`.

- [ ] **Step 1: Write the failing tests** at the end of `FloatingBallTests`:

```swift
    func testAHomeOnTheBottomEdgeBesideTheDockIsKept() {
        // specs/ball-edges.md R82: the disc touching the real bottom, below the Dock's top.
        let screen = CGRect(x: 0, y: 0, width: 2056, height: 1329)
        let visible = CGRect(x: 0, y: 52, width: 2056, height: 1238)
        let home = CGPoint(x: 1806 - offset, y: 24 - offset)
        XCTAssertEqual(FloatingBall.onScreenOrigin(home, screens: [screen], visible: [visible]), home)
    }

    func testOffEveryScreenItStillComesInsideTheVisibleFrame() {
        let screen = CGRect(x: 0, y: 0, width: 2056, height: 1329)
        let visible = CGRect(x: 0, y: 52, width: 2056, height: 1238)
        let safe = FloatingBall.onScreenOrigin(CGPoint(x: 900, y: -400), screens: [screen], visible: [visible])
        XCTAssertEqual(safe.y + offset, 52 + FloatingBall.Tokens.diameter / 2)
    }
```

- [ ] **Step 2: Run `-only-testing:LocantTests/FloatingBallTests`.** Expected: build failure, `extra argument 'visible' in call`.

- [ ] **Step 3: Implement.** Replace `onScreenOrigin` in `FloatingBall.swift`:

```swift
    /// A saved origin is trusted only while the disc's center falls on a connected display: after
    /// a display goes away the disc would otherwise sit where nothing shows it. A tuck or a home on
    /// the bottom edge beside the Dock lies below `visibleFrame` but on the screen, so it passes.
    /// Off every screen, the whole disc is brought inside the visible frame it lies nearest
    /// (`visible`, which defaults to `screens`).
    static func onScreenOrigin(_ origin: CGPoint, screens: [CGRect], visible: [CGRect]? = nil) -> CGPoint {
        let targets = visible ?? screens
        guard !screens.isEmpty, !targets.isEmpty else { return origin }
        let offset = Tokens.pad + Tokens.diameter / 2
        let center = CGPoint(x: origin.x + offset, y: origin.y + offset)
        if screens.contains(where: { $0.contains(center) }) { return origin }
        func distance(to frame: CGRect) -> CGFloat {
            hypot(max(frame.minX - center.x, 0, center.x - frame.maxX), max(frame.minY - center.y, 0, center.y - frame.maxY))
        }
        guard let nearest = targets.min(by: { distance(to: $0) < distance(to: $1) }) else { return origin }
        let radius = Tokens.diameter / 2
        let safe = CGPoint(
            x: min(max(center.x, nearest.minX + radius), nearest.maxX - radius),
            y: min(max(center.y, nearest.minY + radius), nearest.maxY - radius)
        )
        return CGPoint(x: safe.x - offset, y: safe.y - offset)
    }
```

In `AccessibilityReader`, after `raise(pid:)`:

```swift
    /// specs/ball-edges.md R81: the Dock's tiles (its `AXList`), in CG coordinates. Nil without the
    /// Dock, without trust, or without a list. A hidden Dock (a full-screen Space, auto-hide) reports
    /// a frame off the bottom of the screen; its span along the edge is still right.
    func dockFrame() -> CGRect? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        let list = children(of: app).first { string(copy($0, kAXRoleAttribute)) == kAXListRole }
        return list.flatMap { frame(copy($0, Self.frameAttribute))?.cgRect }
    }
```

- [ ] **Step 4: Run `-only-testing:LocantTests/FloatingBallTests`.** Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit.**

```bash
git add Locant/Resolve/AccessibilityReader.swift Locant/Launcher/FloatingBall.swift LocantTests/FloatingBallTests.swift
git commit -m "ball: the reader finds the Dock's tiles, and a saved spot below the visible frame but on the screen is kept"
```

### Task 5: The ball tucks beside the Dock, wakes where it rests, and can be thrown

**Files:**
- Modify: `Locant/Launcher/FloatingBall.swift` (the `FloatingBall` class and `BallView`)
- Modify: `Locant/App/AppState.swift:163` (pass a reader)

**Interfaces:**
- Consumes: `BallEdges` (Task 2), `Throw` (Task 3), `Glide.move(to:spring:velocity:)` (Task 1), `AccessibilityReader.dockFrame()` and `onScreenOrigin(_:screens:visible:)` (Task 4), `Geometry.appKitRect(fromCG:primaryHeight:)`.
- Produces: `FloatingBall.init(origin:reader:)`, `FloatingBall.dragEnded(velocity:)`, `Tokens.dockSettle`. Task 6 adds the ghost call inside `dragged(to:)` and `dragEnded(velocity:)`.

- [ ] **Step 1: Wire the reader and the Dock cache.** In `FloatingBall`:
  - class doc: replace "tucks into a screen edge when left near one" with "tucks into the nearest free stretch of a screen edge (left, right, or the bottom beside the Dock; specs/ball-edges.md), which becomes its home,".
  - `Tokens`: add `/// After an app launches or quits, the Dock is read again once it has grown or shrunk.` `static let dockSettle: Duration = .milliseconds(600)`.
  - stored properties: add `private let reader: AccessibilityReader`, `private var workspaceObservers: [NSObjectProtocol] = []`, `/// The spot the ball is tucked into while docked.` `private var tucked: BallEdges.Tuck?`, `/// R81: the Dock's tiles in AppKit coordinates, as last read; nil when unknown.` `private var dockFrame: CGRect?`, `private var dockRead: Task<Void, Never>?`. Change `freeOrigin`'s doc to `/// Home: where the ball rests and wakes from. A tuck moves it to the tucked spot (R82).`
  - `init(origin:)` becomes `init(origin: CGPoint?, reader: AccessibilityReader)`; its first line uses `Self.onScreenOrigin($0, screens: Self.screenFrames, visible: Self.visibleFrames)`; assign `self.reader = reader` before `panel`.
  - add `private static var screenFrames: [CGRect] { NSScreen.screens.map(\.frame) }` beside `visibleFrames`, and the two conversions:

```swift
    private static var centerOffset: CGFloat { Tokens.pad + Tokens.diameter / 2 }

    private static func origin(forCenter center: CGPoint) -> CGPoint {
        CGPoint(x: center.x - centerOffset, y: center.y - centerOffset)
    }

    private static func center(forOrigin origin: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + centerOffset, y: origin.y + centerOffset)
    }
```

  - `show(firstLaunch:)`: call `refreshDock()` before `startMonitors()`.
  - `hide()`: add `dockRead?.cancel()` after `dockTask = nil`.
  - `startMonitors()`: after the screen observer,

```swift
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification].map { name in
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshDock(after: Tokens.dockSettle) }
            }
        }
```

  - `stopMonitors()`: `for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }` and `workspaceObservers = []`.
  - `screensChanged()`: first line `refreshDock()`; use `Self.onScreenOrigin(freeOrigin, screens: Self.screenFrames, visible: Self.visibleFrames)` and `Self.screenFrames.contains { $0.contains(discCenter) }`.
  - `set(_:)`: after `state = newState`, add `if newState != .docked { tucked = nil }`.

- [ ] **Step 2: Replace the docking section** (`scheduleDock`, `dock(ifWithin:)`, `ringSafeOrigin`, `move`) with:

```swift
    // MARK: Docking

    private func scheduleDock() {
        dockTask?.cancel()
        refreshDock()
        dockTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Tokens.dockDelay))
            guard !Task.isCancelled, self.autoHide, self.state == .rest, !self.view.isDragging else { return }
            self.tuck(nearest: self.discCenter)
        }
    }

    /// R80: the tucks and the ring's room on the screen the ball is on.
    private func edges() -> BallEdges? {
        guard let screen = panel.screen ?? NSScreen.main else { return nil }
        let others = NSScreen.screens.filter { $0 != screen }.map(\.frame)
        return BallEdges(frame: screen.frame, visible: screen.visibleFrame, dock: dockFrame, others: others)
    }

    /// R82: tuck into the free spot nearest `point`. False when no edge has room; the ball stays put.
    @discardableResult
    private func tuck(nearest point: CGPoint) -> Bool {
        guard let edges = edges(), let spot = edges.tuck(nearest: point) else { return false }
        tuck(into: spot, edges: edges)
        return true
    }

    /// Tucks into `spot`, which becomes home and is saved; a throw passes the hand's speed on.
    private func tuck(into spot: BallEdges.Tuck, edges: BallEdges, velocity: CGPoint = .zero) {
        let home = Self.origin(forCenter: edges.home(for: spot))
        if home != freeOrigin {
            freeOrigin = home
            onMoved?(home)
        }
        set(.docked)
        tucked = spot
        move(to: Self.origin(forCenter: spot.center), spring: .tuck, velocity: velocity)
    }

    /// R81: read the Dock again, after `delay`. Decisions use the last answer and never wait on this one.
    private func refreshDock(after delay: Duration = .zero) {
        dockRead?.cancel()
        dockRead = Task { @MainActor in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            let frame = await self.reader.dockFrame()
            guard !Task.isCancelled else { return }
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            self.dockFrame = frame.map { Geometry.appKitRect(fromCG: $0, primaryHeight: primaryHeight) }
            self.retuckIfCovered()
        }
    }

    /// R82: a tucked ball whose spot is no longer free (the Dock grew over it, a display came)
    /// moves to the nearest free one.
    private func retuckIfCovered() {
        guard state == .docked, !view.isDragging, let tucked, let edges = edges(),
              let spot = edges.tuck(nearest: tucked.center), spot != tucked else { return }
        tuck(into: spot, edges: edges)
    }

    /// `origin` (window origin) pulled in far enough for the ring to open fully (R80): from the real
    /// edge beside the Dock, from the visible frame across it and toward the menu bar.
    private func ringSafeOrigin(_ origin: CGPoint) -> CGPoint {
        guard let edges = edges() else { return origin }
        return Self.origin(forCenter: edges.ringSafe(Self.center(forOrigin: origin)))
    }

    /// The disc glides on a spring; the window animator cannot, so `Glide` steps it per frame.
    private func move(to origin: CGPoint, spring: Spring, velocity: CGPoint = .zero) {
        shownOrigin = origin
        glide.move(to: origin, spring: spring, velocity: velocity)
    }
```

- [ ] **Step 3: The press, the drag, and the release.** `pressBegan()`: first line `refreshDock()`. `dragged(to:)`: change `if state == .docked { state = .rest }` to `if state == .docked { state = .rest; tucked = nil }`. Replace `dragEnded()`:

```swift
    /// R83: a drop near an edge tucks into the nearest free spot at once and stays until the cursor
    /// has left; a throw carries on and tucks where it was heading, or comes to rest in open space.
    /// A drop in the open stays ready under the cursor; leaving rests it.
    func dragEnded(velocity: CGPoint) {
        guard let edges = edges() else {
            onMoved?(freeOrigin)
            set(.ready)
            return
        }
        let release = Throw.release(center: discCenter, velocity: velocity, edges: edges, autoHide: autoHide)
        if let spot = release.tuck {
            tuck(into: spot, edges: edges, velocity: release.thrown ? velocity : .zero)
            holdDock = true
        } else if release.thrown {
            freeOrigin = Self.origin(forCenter: release.landing)
            onMoved?(freeOrigin)
            move(to: freeOrigin, spring: .settle, velocity: velocity)
            if state == .rest { scheduleDock() } else { set(.rest) }
        } else {
            onMoved?(freeOrigin)
            set(.ready)
        }
    }
```

  In `BallView`: add `private var samples: [Throw.Sample] = []`. In `mouseDown`, after `dragStart = location`: `samples = [Throw.Sample(time: event.timestamp, point: location)]`. In `mouseDragged`, right after the `ringOpen` early return:

```swift
        samples.append(Throw.Sample(time: event.timestamp, point: now))
        samples.removeAll { event.timestamp - $0.time > 2 * Throw.window }
```

  In `mouseUp`, extend the `defer` with `samples = []`, and replace `ball?.dragEnded()` with:

```swift
            samples.append(Throw.Sample(time: event.timestamp, point: NSEvent.mouseLocation))
            ball?.dragEnded(velocity: Throw.velocity(samples))
```

- [ ] **Step 4: AppState.** In `updateBall()`, `FloatingBall(origin: preferences.ballPosition)` becomes `FloatingBall(origin: preferences.ballPosition, reader: AccessibilityReader())` with the comment `// specs/ball-edges.md R81: a reader of its own for the Dock, as the agent label has.` above it.

- [ ] **Step 5: Build and run the full suite.** Expected: `** TEST SUCCEEDED **`, no new warnings in `FloatingBall.swift` (`grep -c warning` over the log for that file is 0).

- [ ] **Step 6: Commit.**

```bash
git add Locant/Launcher/FloatingBall.swift Locant/App/AppState.swift
git commit -m "ball: it tucks into the nearest free edge spot, beside the Dock too, wakes from there, and keeps a throw's speed"
```

### Task 6: The ghost

**Files:**
- Create: `Locant/Launcher/BallGhost.swift`
- Modify: `Locant/Launcher/FloatingBall.swift` (`DiscView.hideGlow()`, the ghost in `FloatingBall`)

**Interfaces:**
- Consumes: `DiscView`, `FloatingBall.Tokens.panelSide`, `.pad`, `DesignTokens.reveal`, `.dismiss`, `BallEdges.isNearEdge(_:)`, `tuck(nearest:)`.
- Produces: `BallGhost.show(at:below:)`, `BallGhost.hide()`.

- [ ] **Step 1: `DiscView.hideGlow()`.** After `startGlow()` in `DiscView`:

```swift
    /// The ghost (specs/ball-edges.md R84) is the glass alone, without the drifting light.
    func hideGlow() {
        glow.removeAnimation(forKey: "glow")
        glow.opacity = 0
    }
```

- [ ] **Step 2: Create** `Locant/Launcher/BallGhost.swift`:

```swift
import AppKit

/// specs/ball-edges.md R84: where a release will tuck the ball. The disc's glass, faint, with no
/// hand and no glow, in a panel of its own just under the ball; it never takes the mouse.
@MainActor
final class BallGhost {
    static let alpha: CGFloat = 0.35

    private let panel: NSPanel
    private var shown = false

    init() {
        let side = FloatingBall.Tokens.panelSide
        let bounds = NSRect(x: 0, y: 0, width: side, height: side)
        panel = NSPanel(contentRect: bounds, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let content = NSView(frame: bounds)
        let disc = DiscView(frame: bounds.insetBy(dx: FloatingBall.Tokens.pad, dy: FloatingBall.Tokens.pad))
        disc.hideGlow()
        content.addSubview(disc)
        panel.contentView = content
    }

    /// `origin`: the window origin the ball will have once tucked there. Moves without a glide.
    func show(at origin: CGPoint, below ball: NSWindow) {
        panel.setFrameOrigin(origin)
        guard !shown else { return }
        shown = true
        panel.alphaValue = 0
        panel.order(.below, relativeTo: ball.windowNumber)
        fade(to: Self.alpha, over: DesignTokens.reveal)
    }

    func hide() {
        guard shown else { return }
        shown = false
        fade(to: 0, over: DesignTokens.dismiss)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(DesignTokens.dismiss * 1000) + 20))
            if !self.shown { self.panel.orderOut(nil) }
        }
    }

    private func fade(to alpha: CGFloat, over duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = alpha
        }
    }
}
```

- [ ] **Step 3: Use it in `FloatingBall`.** Add `private let ghost = BallGhost()` beside `ring`. In `hide()`, add `ghost.hide()`. At the end of `dragged(to:)`, call `showGhost()`. First line of `dragEnded(velocity:)`: `ghost.hide()`. Add:

```swift
    /// R84: while a drop would tuck, the ghost shows where.
    private func showGhost() {
        guard autoHide, let edges = edges(), edges.isNearEdge(discCenter),
              let spot = edges.tuck(nearest: discCenter) else {
            ghost.hide()
            return
        }
        ghost.show(at: Self.origin(forCenter: spot.center), below: panel)
    }
```

- [ ] **Step 4: Build and run the full suite.** Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit.**

```bash
git add Locant/Launcher/BallGhost.swift Locant/Launcher/FloatingBall.swift
git commit -m "ball: while a drag would tuck it, a faint ghost shows where"
```

### Task 7: Copy

**Files:**
- Modify: `README.md:204`, `site/index.html:519`, `CHANGELOG.md` (Unreleased)

- [ ] **Step 1: README ball row** becomes:

```markdown
| **The ball** | A 48 pt glass disc. Rests translucent, tucks into the nearest edge after two seconds without use (left, right, or the bottom beside the Dock), wakes where it rests as the cursor approaches, starts Point on click. Hold half a second for the ring: Snap ↑, Text →, Color ↓, Cut ←; release at center cancels. Drag it anywhere, or flick it at an edge and it tucks where it was heading. |
```

- [ ] **Step 2: Site Awake card:** `<h3>Awake</h3><p>Move toward it and it comes back out. Drag it anywhere, or flick it at an edge.</p>`

- [ ] **Step 3: CHANGELOG**, first bullet under `## Unreleased`:

```markdown
- **The ball rests at the bottom too.** Besides the left and right edges, it tucks into the bottom of the screen beside the Dock, never on or behind it, and far enough from the Dock's ends that reaching for them does not wake it. Where it tucks is its home: coming near brings it out right there, instead of back to wherever it was before. While you drag it toward an edge, a faint ghost shows where it will tuck; flick it at an edge and it flies there and tucks.
```

- [ ] **Step 4: Commit.**

```bash
git add README.md site/index.html CHANGELOG.md
git commit -m "docs: the ball tucks beside the Dock, wakes where it rests, shows a ghost, and can be flicked"
```

### Task 8: Verify on the real Mac

- [ ] **Step 1:** Save `defaults read com.malikzhang.deixis ballPosition`, build a Debug copy signed with the team (`DEVELOPMENT_TEAM=MVAUZXPK9M`) into a scratch DerivedData (it inherits the grants), quit `/Applications/Locant.app` (the same bundle id; `terminate()` can take over 5 s, poll `pgrep -f "MacOS/Locant$"`), and open the scratch build. Tucks save the ball's home, so the saved value is restored at the end.
- [ ] **Step 2:** Only when `HIDIdleTime` ≥ 40 s: drive the ball with CGEvents (move, down, drag, up) and read its window with `CGWindowListCopyWindowInfo` (owner Locant, layer 3, 68×68) after each step: (a) slow drag to x 1900, y 30 (AppKit) → ghost window present (second 68×68 layer-3 window) during the drag, ball tucked with center y ≈ 4.8 after; (b) drop at x 1000, y 40 → ball glides to center x 250 or 1806; (c) flick from (600, 500) toward the lower left at about 1800 pt/s → tucked at center x 250; (d) drop at (1000, 700), wait 3 s → tucked at an edge; move the cursor within 60 pt → ball center within 100 pt of that edge, not at (1000, 700); (e) relaunch → ball at the same spot.
- [ ] **Step 3:** `screencapture -x -R` of the bottom right strip to see the tucked ball beside the Dock; restore `/Applications/Locant.app` and the saved `ballPosition`.
