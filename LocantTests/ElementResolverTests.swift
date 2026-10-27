import CoreGraphics
import XCTest
@testable import Locant

final class ElementResolverTests: XCTestCase {
    private func fixture(_ name: String) throws -> ElementSnapshot {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"), "fixture \(name)")
        return try JSONDecoder().decode(ElementSnapshot.self, from: Data(contentsOf: url))
    }

    // 1
    func testSwiftUIButtonWithIdentifier() throws {
        let e = try XCTUnwrap(ElementResolver.resolve(try fixture("swiftui-button")))
        XCTAssertEqual(e.role, "button")
        XCTAssertEqual(e.rawRole, "AXButton")
        XCTAssertEqual(e.identifier, "captureButton")
        XCTAssertEqual(e.label, "Capture")
        XCTAssertEqual(e.frame, Frame(x: 43, y: 893.6667, w: 370, h: 50.3333))
    }

    // 2
    func testAppKitTextFieldWithoutIdentifier() throws {
        let e = try XCTUnwrap(ElementResolver.resolve(try fixture("appkit-textfield")))
        XCTAssertEqual(e.role, "textField")
        XCTAssertNil(e.identifier)
        XCTAssertEqual(e.identifierSource, .unknown)
        XCTAssertEqual(e.label, "Name")
        XCTAssertEqual(e.value, .string("Malik"))
    }

    // 3
    func testUnknownRoleKeepsRawRole() throws {
        let e = try XCTUnwrap(ElementResolver.resolve(try fixture("unknown-role")))
        XCTAssertEqual(e.role, "unknown")
        XCTAssertEqual(e.rawRole, "AXCustomThing")
    }

    // 4
    func testPathTruncatesAtSixAncestorsRootFirst() throws {
        let e = try XCTUnwrap(ElementResolver.resolve(try fixture("deep-path")))
        XCTAssertEqual(e.path.count, 7)
        XCTAssertEqual(e.path.map(\.identifier), ["a6", "a5", "a4", "a3", "a2", "a1", "leaf"])
        XCTAssertEqual(e.path[2].role, "toolbar")
        XCTAssertEqual(e.path.last?.role, "button")
    }

    // 5
    func testMissingFrameReturnsNil() throws {
        XCTAssertNil(ElementResolver.resolve(try fixture("missing-frame")))
    }

    // 6
    func testSimulatorPathIncludesWindowAndResolvesIdentifier() throws {
        let e = try XCTUnwrap(ElementResolver.resolve(try fixture("simulator-path")))
        XCTAssertEqual(e.identifier, "captureButton")
        XCTAssertEqual(e.identifierSource, .declared)
        XCTAssertTrue(e.path.contains { $0.role == "window" })
        XCTAssertEqual(e.path.first?.role, "application", "five ancestors fit, so the root is the Simulator app")
        XCTAssertEqual(e.path[1].role, "window")
        XCTAssertEqual(e.path.count, 6)
    }

    // 7
    func testRetryReturnsPopulatedReadAfterEmptyOnes() async throws {
        let provider = ScriptedProvider(script: [nil, try fixture("empty-group"), try fixture("swiftui-button")])
        let e = await ElementResolver.resolve(at: CGPoint(x: 228, y: 927), using: provider, retries: 5, delay: .zero)
        XCTAssertEqual(e?.identifier, "captureButton")
        let calls = await provider.calls
        XCTAssertEqual(calls, 3)
    }

    func testRetryGivesUpAfterRetriesAndReturnsNil() async throws {
        let provider = ScriptedProvider(script: [])
        let e = await ElementResolver.resolve(at: .zero, using: provider, retries: 2, delay: .zero)
        XCTAssertNil(e)
        let calls = await provider.calls
        XCTAssertEqual(calls, 3, "one read plus two retries")
    }

    func testRetryReReadsAFirstContainerHitOnce() async throws {
        let container = ElementSnapshot(element: AttributeSet(role: "AXGroup", frame: Frame(x: 0, y: 0, w: 1448, h: 944), childCount: 40), ancestors: [])
        let refined = ScriptedProvider(script: [container, try fixture("swiftui-button")])
        let e = await ElementResolver.resolve(at: .zero, using: refined, retries: 5, delay: .zero)
        XCTAssertEqual(e?.identifier, "captureButton")
        let calls = await refined.calls
        XCTAssertEqual(calls, 2)

        let stubborn = ScriptedProvider(script: [container, container])
        let f = await ElementResolver.resolve(at: .zero, using: stubborn, retries: 1, delay: .zero)
        XCTAssertEqual(f?.role, "group", "a container that stays a container is still the answer")
    }

    // 8
    func testIdentifierSourceForSymbolImageAndDeclaredButton() throws {
        let image = try XCTUnwrap(ElementResolver.resolve(try fixture("symbol-image")))
        XCTAssertEqual(image.role, "image")
        XCTAssertEqual(image.identifier, "plus")
        XCTAssertEqual(image.identifierSource, .possiblySymbolName)

        let button = try XCTUnwrap(ElementResolver.resolve(try fixture("swiftui-button")))
        XCTAssertEqual(button.identifierSource, .declared)

        XCTAssertEqual(ElementResolver.identifierSource(role: "image", identifier: "person.crop.circle"), .possiblySymbolName)
        XCTAssertEqual(ElementResolver.identifierSource(role: "image", identifier: "avatarImage"), .declared)
        XCTAssertEqual(ElementResolver.identifierSource(role: "button", identifier: "plus"), .declared)
        XCTAssertEqual(ElementResolver.identifierSource(role: "image", identifier: ""), .unknown)
    }

    // R2 hover precision
    private func node(_ role: String, id: String? = nil, x: Double, y: Double, w: Double, h: Double) -> AttributeSet {
        AttributeSet(role: role, identifier: id, frame: Frame(x: x, y: y, w: w, h: h), childCount: 0)
    }

    func testRefinerPicksSmallestControlNearPoint() {
        let window = node("AXGroup", x: 0, y: 0, w: 456, h: 900)
        let candidates = [
            node("AXGroup", id: "content", x: 0, y: 0, w: 456, h: 900),   // same size as base: never
            node("AXToolbar", x: 0, y: 840, w: 456, h: 60),               // container, near
            node("AXButton", id: "capture", x: 43, y: 850, w: 370, h: 40), // control, 5 pt away
            node("AXButton", id: "far", x: 43, y: 700, w: 370, h: 40),     // control, far
        ]
        let point = CGPoint(x: 228, y: 895) // 5 pt below the capture button
        XCTAssertEqual(HitRefiner.choose(from: candidates, replacing: window, at: point)?.identifier, "capture")
    }

    func testRefinerFallsBackToSmallerContainerThenNil() {
        let window = node("AXGroup", x: 0, y: 0, w: 456, h: 900)
        let toolbar = node("AXToolbar", x: 0, y: 840, w: 456, h: 60)
        let button = node("AXButton", id: "capture", x: 43, y: 850, w: 100, h: 40)
        XCTAssertNil(HitRefiner.choose(from: [toolbar, button], replacing: window, at: CGPoint(x: 228, y: 895))?.identifier)
        XCTAssertEqual(HitRefiner.choose(from: [toolbar, button], replacing: window, at: CGPoint(x: 228, y: 895))?.role, "AXToolbar")
        XCTAssertNil(HitRefiner.choose(from: [toolbar, button], replacing: window, at: CGPoint(x: 228, y: 400)), "blank area keeps the container")
    }

    func testStickinessKeepsControlsNotContainers() throws {
        let button = try XCTUnwrap(ElementResolver.resolve(try fixture("swiftui-button"))) // 43,893.67 370×50.33
        XCTAssertTrue(HitRefiner.sticks(button, to: CGPoint(x: 228, y: 950)))   // 6 pt below
        XCTAssertFalse(HitRefiner.sticks(button, to: CGPoint(x: 228, y: 970)))  // 26 pt below
        let group = try XCTUnwrap(ElementResolver.resolve(try fixture("empty-group")))
        XCTAssertFalse(HitRefiner.sticks(group, to: CGPoint(x: 100, y: 300)))
        XCTAssertFalse(HitRefiner.sticks(nil, to: .zero))
    }

    func testAncestorDepthReRootsSnapshot() throws {
        let snapshot = try fixture("swiftui-button")
        let parent = try XCTUnwrap(HitRefiner.ancestor(of: snapshot, depth: 1))
        XCTAssertEqual(ElementResolver.resolve(parent)?.role, "group")
        XCTAssertEqual(parent.ancestors.count, 2)
        XCTAssertEqual(ElementResolver.resolve(try XCTUnwrap(HitRefiner.ancestor(of: snapshot, depth: 3)))?.role, "window")
        XCTAssertNil(HitRefiner.ancestor(of: snapshot, depth: 4))
        XCTAssertEqual(HitRefiner.ancestor(of: snapshot, depth: 0), snapshot)
    }

    // R2a clusters (flat SwiftUI trees expose leaves, not cards)
    func testClustersGroupByProximity() throws {
        let snapshot = try fixture("card-siblings")
        let nodes = HitRefiner.content(of: snapshot.siblings ?? [], within: snapshot.ancestors[0].frame)
        XCTAssertEqual(nodes.count, 7, "the window-sized Background sibling is dropped")
        let groups = HitRefiner.clusters(among: nodes)
        XCTAssertEqual(groups.count, 3, "Ocean title, the card, the tab bar")
        let card = try XCTUnwrap(groups.first { $0.contains { $0.description == "Shortcut" } })
        XCTAssertEqual(card.count, 5)
        XCTAssertEqual(HitRefiner.union(of: card), CGRect(x: 59, y: 590, width: 338, height: 120))
    }

    func testSelectionLevelsFromLeafGoLeafClusterParentWindow() throws {
        let snapshot = try fixture("card-siblings")
        let levels = HitRefiner.selectionLevels(for: snapshot, at: CGPoint(x: 100, y: 600))
        XCTAssertEqual(levels.map { $0?.role }, ["staticText", "cluster", "group", "window"], "the frameless application is skipped")
        let cluster = try XCTUnwrap(levels[1])
        XCTAssertEqual(cluster.rawRole, "LocantCluster")
        XCTAssertEqual(cluster.frame, Frame(x: 43, y: 574, w: 370, h: 152), "members' bounds plus 16 pt, inside the parent")
        XCTAssertEqual(cluster.members?.map(\.role), ["staticText", "image", "staticText", "button", "button"])
        XCTAssertEqual(cluster.members?.compactMap(\.identifier), ["bolt.fill", "shortcutActionButton"])
        XCTAssertEqual(cluster.path.last?.role, "cluster")
        XCTAssertEqual(cluster.path.first?.role, "application")
    }

    func testSelectionLevelsOnSpanningContainerPickClusterUnderPointOrNothing() throws {
        let leaf = try fixture("card-siblings")
        let group = ElementSnapshot(element: leaf.ancestors[0], ancestors: Array(leaf.ancestors[1...]), children: leaf.siblings)
        let onCard = HitRefiner.selectionLevels(for: group, at: CGPoint(x: 300, y: 600)) // blank card area
        XCTAssertEqual(onCard.map { $0?.role }, ["cluster", "group", "window"])
        let onNothing = HitRefiner.selectionLevels(for: group, at: CGPoint(x: 200, y: 450)) // the orb: no elements
        XCTAssertEqual(onNothing.map { $0?.role }, [nil, "group", "window"])
        XCTAssertNil(onNothing[0], "nothing specific here: fallback square, element null on click")
    }

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
        XCTAssertEqual(levels.map { $0?.rawRole }, ["AXButton", "LocantGroup", "LocantCluster", "AXGroup", "AXGroup"],
                       "share and pencil, 4 pt apart, are also a row (R124)")
        XCTAssertEqual(levels[2]?.members?.compactMap(\.identifier), ["share", "pencil"])
    }

    func testAContainerThatDoesNotSpanTheWindowIsRungZeroWithoutACluster() {
        let n = toolbarNodes()
        let hit = ElementSnapshot(element: n.hosting, ancestors: [n.screen], children: [n.share, n.pencil])
        XCTAssertEqual(HitRefiner.selectionLevels(for: hit, at: CGPoint(x: 200, y: 350)).map { $0?.role }, ["group", "group"],
                       "away from the buttons: the container itself, not the fallback square")
        XCTAssertEqual(HitRefiner.selectionLevels(for: hit, at: CGPoint(x: 298, y: 350)).map { $0?.role }, ["cluster", "group", "group"],
                       "between the buttons: their cluster")
    }

    // MARK: Shapes on the ladder (specs/capture-shapes.md R117, R121)

    /// Shapes at fixed rectangles: at a point, the smallest that holds it; around a rectangle, the ones
    /// holding it, innermost first; inside a rectangle, the bounds of the parts of `inks` in it (R126).
    /// `asked` tells whether the ladder asked for a shape at all.
    private struct FixedShapes: ShapeSource {
        var rects: [CGRect]
        var inks: [CGRect] = []
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

        mutating func ink(inside rect: CGRect) -> CGRect? {
            let parts = inks.map { $0.intersection(rect) }.filter { !$0.isNull && !$0.isEmpty }
            return parts.isEmpty ? nil : parts.reduce(CGRect.null) { $0.union($1) }
        }
    }

    /// The glass capsule around share, pencil, and trash.
    private let capsule = CGRect(x: 250, y: 326, width: 140, height: 44)

    func testOnAButtonTheCapsuleIsARungAfterItsRow() throws {
        let n = toolbarNodes()
        let snapshot = ElementSnapshot(element: n.pencil, ancestors: [n.hosting, n.screen], siblings: [n.share, n.pencil])
        var shapes = FixedShapes(rects: [capsule])
        let levels = HitRefiner.selectionLevels(for: snapshot, at: CGPoint(x: 320, y: 350), shapes: &shapes, holding: nil)
        XCTAssertEqual(levels.map { $0?.rawRole }, ["AXButton", "LocantGroup", "LocantShape", "AXGroup", "AXGroup"],
                       "share and pencil, 4 pt apart, are a row (R124) inside the capsule")
        let shape = try XCTUnwrap(levels[2])
        XCTAssertEqual(shape.frame, Frame(capsule))
        XCTAssertEqual(shape.members?.compactMap(\.identifier), ["share", "pencil"])
        XCTAssertEqual(shape.path.map(\.role), ["group", "group", "cluster"])
        XCTAssertEqual(shape.path[1].identifier, "_TtGC7SwiftUI32NavigationStackHosting", "the innermost node holding it")
        XCTAssertEqual(levels[3]?.identifier, "_TtGC7SwiftUI32NavigationStackHosting", "the sibling cluster gave way to the shape")
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

    /// R117: the 2 pt merge is for a shape and an accessibility rung. Two accessibility rungs merge only
    /// within 1 pt (`collapsingSameFrames`), so with no shape in sight the ladder is today's, whatever the pointer is on.
    func testWithNoShapeTwoAccessibilityRungsKeepTheirOwnWeights() {
        // (A) a group 1.5 pt off its parent `card`: two rungs, and the one with the identifier stays.
        let ok = AttributeSet(role: "AXButton", identifier: "ok", frame: Frame(x: 100, y: 70, w: 60, h: 30))
        let inner = AttributeSet(role: "AXGroup", frame: Frame(x: 50, y: 50, w: 200, h: 100))
        let card = AttributeSet(role: "AXGroup", identifier: "card", frame: Frame(x: 48.5, y: 50, w: 201.5, h: 100))
        let screen = AttributeSet(role: "AXGroup", frame: Frame(x: 0, y: 0, w: 400, h: 600))
        let nested = ElementSnapshot(element: ok, ancestors: [inner, card, screen])
        let onOK = CGPoint(x: 120, y: 85)
        var none = FixedShapes(rects: [])
        let today = HitRefiner.selectionLevels(for: nested, at: onOK)
        XCTAssertTrue(today.contains { $0?.identifier == "card" }, "today's ladder has the identified rung")
        XCTAssertEqual(HitRefiner.selectionLevels(for: nested, at: onOK, shapes: &none, holding: nil), today)

        // (B) a button inside a group of the same frame, `saveButton`: the group's identifier wins.
        let button = AttributeSet(role: "AXButton", frame: Frame(x: 100, y: 70, w: 60, h: 30))
        let wrapper = AttributeSet(role: "AXGroup", identifier: "saveButton", frame: Frame(x: 100, y: 70, w: 60, h: 30))
        let wrapped = ElementSnapshot(element: button, ancestors: [wrapper, screen])
        let todayWrapped = HitRefiner.selectionLevels(for: wrapped, at: onOK)
        XCTAssertEqual(todayWrapped.first??.identifier, "saveButton", "today's ladder has the identified rung")
        XCTAssertEqual(HitRefiner.selectionLevels(for: wrapped, at: onOK, shapes: &none, holding: nil), todayWrapped)
    }

    /// Only the shape at the pointer is known (nothing found around the element).
    private struct ShapeAtOnly: ShapeSource {
        var rect: CGRect

        mutating func shape(at point: CGPoint) -> CGRect? { rect.contains(point) ? rect : nil }
        mutating func shapes(around rect: CGRect) -> [CGRect] { [] }
        mutating func ink(inside rect: CGRect) -> CGRect? { nil }
    }

    /// R117: the element held inside a shape is rung 0, and the shape at the pointer is the next rung even
    /// when nothing is found around the element; when something is, the shape is not listed twice.
    func testAHeldElementKeepsTheShapeAtThePointer() throws {
        let n = toolbarNodes()
        let gap = ElementSnapshot(element: n.hosting, ancestors: [n.screen], children: [n.share, n.pencil])
        let pencil = try XCTUnwrap(ElementResolver.resolve(ElementSnapshot(element: n.pencil, ancestors: [n.hosting, n.screen])))
        let point = CGPoint(x: 342, y: 350)
        var atOnly = ShapeAtOnly(rect: capsule)
        let levels = HitRefiner.selectionLevels(for: gap, at: point, shapes: &atOnly, holding: pencil)
        XCTAssertEqual(levels.map { $0?.rawRole }, ["AXButton", "LocantShape", "AXGroup", "AXGroup"])
        XCTAssertEqual(levels.first??.identifier, "pencil")
        XCTAssertEqual(levels[1]?.frame, Frame(capsule))

        var both = FixedShapes(rects: [capsule])
        let once = HitRefiner.selectionLevels(for: gap, at: point, shapes: &both, holding: pencil)
        XCTAssertEqual(once.map { $0?.rawRole }, ["AXButton", "LocantShape", "AXGroup", "AXGroup"], "found both ways: one rung")
    }

    // MARK: A row of touching controls (specs/capture-shapes.md R124)

    /// Oryne's thought-detail toolbar in Device Hub (capture 20261026-190816-8ngf): folder, share, and
    /// trash touch and tile the glass capsule, and the meta line sits 23 pt below it.
    private func capsuleRow() -> (buttons: [AttributeSet], meta: AttributeSet, screen: AttributeSet) {
        ([node("AXButton", id: "folder", x: 559.6, y: 398.2, w: 39.4, h: 39.3),
          node("AXButton", id: "square.and.arrow.up", x: 599, y: 398.2, w: 39.4, h: 39.3),
          node("AXButton", id: "trash", x: 638.3, y: 398.2, w: 39.4, h: 39.3)],
         node("AXStaticText", x: 391.5, y: 460.5, w: 220, h: 16),
         node("AXGroup", x: 330, y: 100, w: 400, h: 870))
    }

    private func center(_ node: AttributeSet) -> CGPoint {
        let f = node.frame!
        return CGPoint(x: f.x + f.w / 2, y: f.y + f.h / 2)
    }

    /// The rungs after rung 0 that are a row or column group.
    private func groups(in levels: [ResolvedElement?]) -> [ResolvedElement] {
        levels.compactMap { $0 }.filter { $0.rawRole == ElementResolver.groupRawRole }
    }

    func testARowOfTouchingButtonsIsTheRungAfterEachButton() throws {
        let n = capsuleRow()
        let ids = ["folder", "square.and.arrow.up", "trash"]
        for (index, button) in n.buttons.enumerated() {
            let snapshot = ElementSnapshot(element: button, ancestors: [n.screen], siblings: n.buttons + [n.meta])
            let levels = HitRefiner.selectionLevels(for: snapshot, at: center(button))
            XCTAssertEqual(levels.first??.identifier, ids[index], "rung 0 stays the button under the pointer")
            XCTAssertEqual(levels.map { $0?.rawRole }, ["AXButton", "LocantGroup", "LocantCluster", "AXGroup"], ids[index])
            let group = try XCTUnwrap(levels[1])
            XCTAssertEqual(group.role, "cluster")
            XCTAssertEqual(group.rawRole, ElementResolver.groupRawRole)
            XCTAssertNil(group.label)
            XCTAssertNil(group.identifier)
            XCTAssertEqual(group.identifierSource, .unknown)
            XCTAssertNil(group.value)
            XCTAssertEqual(group.frame.x, 559.6, accuracy: 0.1)
            XCTAssertEqual(group.frame.y, 398.2, accuracy: 0.1)
            XCTAssertEqual(group.frame.w, 118.1, accuracy: 0.1, "the exact union, no padding")
            XCTAssertEqual(group.frame.h, 39.3, accuracy: 0.1)
            XCTAssertEqual(group.members?.compactMap(\.identifier), ids, "in reading order")
            XCTAssertEqual(group.members?.count, 3, "the meta line is not a member")
            XCTAssertEqual(group.path.map(\.role), ["group", "cluster"])
            XCTAssertEqual(levels[2]?.members?.count, 4, "the sibling cluster that follows still takes the meta line")
            XCTAssertEqual(Readout.describing(group),
                           Readout(role: "cluster", identifier: nil, suffix: "folder, square.and.arrow.up, trash", isFallback: false))
        }
    }

    func testAGapPastAQuarterOfTheSideOrAMisalignmentBreaksTheRow() {
        func rungs(_ second: AttributeSet, after first: AttributeSet? = nil) -> [ResolvedElement] {
            let first = first ?? node("AXButton", id: "a", x: 100, y: 50, w: 40, h: 40)
            let screen = node("AXGroup", x: 0, y: 0, w: 400, h: 600)
            let snapshot = ElementSnapshot(element: first, ancestors: [screen], siblings: [first, second])
            return groups(in: HitRefiner.selectionLevels(for: snapshot, at: center(first)))
        }
        // 40 pt controls reach a quarter of their side, 10 pt.
        XCTAssertEqual(rungs(node("AXButton", id: "b", x: 142, y: 50, w: 40, h: 40)).count, 1, "a 2 pt gap")
        XCTAssertEqual(rungs(node("AXButton", id: "b", x: 150, y: 50, w: 40, h: 40)).count, 1, "a 10 pt gap, a quarter of 40 pt")
        XCTAssertEqual(rungs(node("AXButton", id: "b", x: 151, y: 50, w: 40, h: 40)).count, 0, "an 11 pt gap does not")
        XCTAssertEqual(rungs(node("AXButton", id: "b", x: 138, y: 50, w: 40, h: 40)).count, 1, "a 2 pt overlap still joins")
        XCTAssertEqual(rungs(node("AXButton", id: "b", x: 137, y: 50, w: 40, h: 40)).count, 0, "a 3 pt overlap does not")
        XCTAssertEqual(rungs(node("AXButton", id: "b", x: 50, y: 50, w: 40, h: 40)).count, 1, "a 10 pt gap before it")
        XCTAssertEqual(rungs(node("AXButton", id: "b", x: 49, y: 50, w: 40, h: 40)).count, 0, "an 11 pt gap before it does not")
        // 8 pt tall controls reach max(2, 0.25 × 8) = 2 pt.
        let small = node("AXButton", id: "a", x: 100, y: 50, w: 30, h: 8)
        XCTAssertEqual(rungs(node("AXButton", id: "b", x: 132, y: 50, w: 30, h: 8), after: small).count, 1, "a 2 pt gap between small controls")
        XCTAssertEqual(rungs(node("AXButton", id: "b", x: 133, y: 50, w: 30, h: 8), after: small).count, 0, "a 3 pt gap between small controls does not")
        XCTAssertEqual(rungs(node("AXButton", id: "b", x: 140, y: 50, w: 40, h: 42)).count, 0, "a height 2 pt off does not")
        XCTAssertEqual(rungs(node("AXButton", id: "b", x: 140, y: 52, w: 40, h: 40)).count, 0, "a top edge 2 pt off does not")
        XCTAssertEqual(rungs(node("AXButton", id: "b", x: 140, y: 51, w: 40, h: 41)).count, 1, "1 pt off on both still lines up")
        XCTAssertEqual(rungs(node("AXGroup", id: "b", x: 140, y: 50, w: 40, h: 40)).count, 0, "a container is not a control")
        XCTAssertEqual(rungs(node("AXButton", id: "b", x: 140, y: 50, w: 0, h: 40)).count, 0, "a member needs a frame")
    }

    func testTheChainStopsAtTheFirstGapPastTheLimit() throws {
        var n = capsuleRow()
        n.buttons.append(node("AXButton", id: "far", x: 687.7, y: 398.2, w: 39.4, h: 39.3)) // 10 pt past trash; the limit is 9.8
        let snapshot = ElementSnapshot(element: n.buttons[1], ancestors: [n.screen], siblings: n.buttons + [n.meta])
        let group = try XCTUnwrap(groups(in: HitRefiner.selectionLevels(for: snapshot, at: center(n.buttons[1]))).first)
        XCTAssertEqual(group.members?.compactMap(\.identifier), ["folder", "square.and.arrow.up", "trash"])

        let pair = [node("AXButton", id: "a", x: 100, y: 50, w: 39.4, h: 39.3), node("AXButton", id: "b", x: 149.4, y: 50, w: 39.4, h: 39.3)]
        let apart = ElementSnapshot(element: pair[0], ancestors: [n.screen], siblings: pair)
        XCTAssertTrue(groups(in: HitRefiner.selectionLevels(for: apart, at: center(pair[0]))).isEmpty, "a 10 pt gap between 39.3 pt controls")
    }

    /// R124: when two controls could join at one step, the nearer does, then the first in sibling order.
    func testOfTwoControlsThatCouldJoinTheNearerDoes() throws {
        let a = node("AXButton", id: "a", x: 100, y: 50, w: 40, h: 40)
        let far = node("AXButton", id: "far", x: 146, y: 50, w: 40, h: 40)    // 6 pt on
        let near = node("AXButton", id: "near", x: 143, y: 50, w: 40, h: 40)  // 3 pt on
        let screen = node("AXGroup", x: 0, y: 0, w: 400, h: 600)
        let snapshot = ElementSnapshot(element: a, ancestors: [screen], siblings: [a, far, near])
        let group = try XCTUnwrap(groups(in: HitRefiner.selectionLevels(for: snapshot, at: center(a))).first)
        XCTAssertEqual(group.members?.compactMap(\.identifier), ["a", "near"], "the farther one overlaps the nearer by 37 pt, so it stays out")

        let twin = node("AXButton", id: "twin", x: 143, y: 50, w: 40, h: 40)
        let tied = ElementSnapshot(element: a, ancestors: [screen], siblings: [a, near, twin])
        let first = try XCTUnwrap(groups(in: HitRefiner.selectionLevels(for: tied, at: center(a))).first)
        XCTAssertEqual(first.members?.compactMap(\.identifier), ["a", "near"], "equally near: the first in sibling order")
    }

    func testAColumnOfTouchingButtonsIsAGroupAndALoneButtonIsNot() throws {
        let top = node("AXButton", id: "top", x: 100, y: 50, w: 40, h: 40)
        let bottom = node("AXButton", id: "bottom", x: 100, y: 90, w: 40, h: 40)
        let screen = node("AXGroup", x: 0, y: 0, w: 400, h: 600)
        let column = ElementSnapshot(element: bottom, ancestors: [screen], siblings: [top, bottom])
        let group = try XCTUnwrap(groups(in: HitRefiner.selectionLevels(for: column, at: center(bottom))).first)
        XCTAssertEqual(group.frame, Frame(x: 100, y: 50, w: 40, h: 80))
        XCTAssertEqual(group.members?.compactMap(\.identifier), ["top", "bottom"], "top to bottom")

        let narrower = node("AXButton", id: "bottom", x: 100, y: 90, w: 42, h: 40)
        let ragged = ElementSnapshot(element: narrower, ancestors: [screen], siblings: [top, narrower])
        XCTAssertTrue(groups(in: HitRefiner.selectionLevels(for: ragged, at: center(narrower))).isEmpty, "a width 2 pt off")

        let lone = ElementSnapshot(element: top, ancestors: [screen], siblings: [top])
        XCTAssertTrue(groups(in: HitRefiner.selectionLevels(for: lone, at: center(top))).isEmpty)
        let alone = ElementSnapshot(element: top, ancestors: [screen])
        XCTAssertTrue(groups(in: HitRefiner.selectionLevels(for: alone, at: center(top))).isEmpty, "no siblings read")
    }

    func testAGridOffersItsRowBeforeItsColumn() throws {
        let tl = node("AXButton", id: "tl", x: 100, y: 50, w: 40, h: 40)
        let tr = node("AXButton", id: "tr", x: 140, y: 50, w: 40, h: 40)
        let bl = node("AXButton", id: "bl", x: 100, y: 90, w: 40, h: 40)
        let br = node("AXButton", id: "br", x: 140, y: 90, w: 40, h: 40)
        let screen = node("AXGroup", x: 0, y: 0, w: 400, h: 600)
        let snapshot = ElementSnapshot(element: tl, ancestors: [screen], siblings: [tl, tr, bl, br])
        let found = groups(in: HitRefiner.selectionLevels(for: snapshot, at: center(tl)))
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.members?.compactMap(\.identifier), ["tl", "tr"], "the row, not the column")
        XCTAssertEqual(found.first?.frame, Frame(x: 100, y: 50, w: 80, h: 40))
    }

    func testAGroupStaysAndAShapeWithinTwoPointsMergesIntoIt() throws {
        let n = capsuleRow()
        let snapshot = ElementSnapshot(element: n.buttons[1], ancestors: [n.screen], siblings: n.buttons + [n.meta])
        let point = center(n.buttons[1])
        for capsule in [CGRect(x: 558.1, y: 396.7, width: 121.1, height: 42.3),   // 1.5 pt past the buttons
                        CGRect(x: 559.6, y: 398.2, width: 118.1, height: 39.3),   // exactly the buttons
                        CGRect(x: 560.6, y: 399.2, width: 116.1, height: 37.3)] { // 1 pt inside them
            var shapes = FixedShapes(rects: [capsule])
            let levels = HitRefiner.selectionLevels(for: snapshot, at: point, shapes: &shapes, holding: nil)
            XCTAssertEqual(levels.map { $0?.rawRole }, ["AXButton", "LocantGroup", "AXGroup"], "\(capsule)")
            XCTAssertEqual(levels[1]?.members?.count, 3, "the group is kept, not the shape")
        }
        var larger = FixedShapes(rects: [CGRect(x: 551.6, y: 390.2, width: 134.1, height: 55.3)]) // 8 pt past them
        let around = HitRefiner.selectionLevels(for: snapshot, at: point, shapes: &larger, holding: nil)
        XCTAssertEqual(around.map { $0?.rawRole }, ["AXButton", "LocantGroup", "LocantShape", "AXGroup"], "a bigger shape is its own rung")
        var none = FixedShapes(rects: [])
        let bare = HitRefiner.selectionLevels(for: snapshot, at: point, shapes: &none, holding: nil)
        XCTAssertEqual(bare, HitRefiner.selectionLevels(for: snapshot, at: point), "no shape found: today's ladder, group included")
        XCTAssertEqual(groups(in: bare).count, 1)
    }

    // MARK: Device Hub's tree (specs/capture-shapes.md R125)

    /// Oryne's Library screen in Device Hub (probe of Oct 26). The screen's direct children: the content
    /// group with the screen's frame, a generic element of no size at its origin, and the tab bar, drawn
    /// over the content group's last card.
    private let hubScreen = Frame(x: 347.9, y: 137.5, w: 359.7, h: 780.9)

    private func hubChildren() -> [AttributeSet] {
        [AttributeSet(role: "AXGroup", frame: hubScreen),
         AttributeSet(role: "AXGenericElement", frame: Frame(x: 347.9, y: 137.5, w: 0, h: 0)),
         AttributeSet(role: "AXGroup", description: "Tab Bar", frame: Frame(x: 347.9, y: 844.3, w: 359.7, h: 74.2))]
    }

    func testOnTheSimulatedScreenTheTabBarAnswersOverTheContentGroup() {
        let children = hubChildren()
        let onBar = CGPoint(x: 527, y: 880)
        XCTAssertEqual(HitRefiner.overlayIndex(at: onBar, screen: hubScreen, children: children, holding: 0), 2)
        XCTAssertEqual(HitRefiner.overlayIndex(at: onBar, screen: hubScreen, children: children, holding: nil), 2, "the hit's child not known")
        XCTAssertNil(HitRefiner.overlayIndex(at: CGPoint(x: 527, y: 500), screen: hubScreen, children: children, holding: 0),
                     "only the content group holds it")
        XCTAssertNil(HitRefiner.overlayIndex(at: onBar, screen: hubScreen, children: children, holding: 2), "the hit is on the tab bar already")
    }

    func testNeitherAChildOfNoSizeNorASecondScreenSizedOneAnswers() {
        let children = hubChildren()
        for holding in [0, nil] {
            XCTAssertNil(HitRefiner.overlayIndex(at: CGPoint(x: 347.9, y: 137.5), screen: hubScreen, children: children, holding: holding),
                         "the generic element of no size, at its own origin")
        }
        // A rectangle of no width or height never contains a point; one reported with a negative width does,
        // once standardized, so only the size check keeps it from answering.
        let negative = AttributeSet(role: "AXGenericElement", frame: Frame(x: 600, y: 400, w: -200, h: 200))
        XCTAssertTrue(negative.frame!.cgRect.contains(CGPoint(x: 527, y: 500)))
        for holding in [0, nil] {
            XCTAssertNil(HitRefiner.overlayIndex(at: CGPoint(x: 527, y: 500), screen: hubScreen, children: children + [negative], holding: holding),
                         "a child of negative width")
        }
        let twin = AttributeSet(role: "AXGroup", frame: Frame(x: 348.4, y: 137.5, w: 359.2, h: 780.4)) // the screen within 1 pt
        let doubled = [children[0], twin] + children[1...]
        XCTAssertNil(HitRefiner.overlayIndex(at: CGPoint(x: 527, y: 500), screen: hubScreen, children: doubled, holding: 0))
        XCTAssertNil(HitRefiner.overlayIndex(at: CGPoint(x: 527, y: 500), screen: hubScreen, children: doubled, holding: nil))
        XCTAssertEqual(HitRefiner.overlayIndex(at: CGPoint(x: 527, y: 880), screen: hubScreen, children: doubled, holding: 0), 3)
    }

    /// A detached copy of the screen's group (empty frame, no parent; seen Oct 26 after switching devices)
    /// takes the union of its children's frames. The probe rounds to 0.1 pt, so the tab bar ends 0.1 pt
    /// below the content group.
    func testADetachedScreenGroupTakesTheUnionOfItsChildren() throws {
        let union = try XCTUnwrap(HitRefiner.detachedScreenFrame(children: hubChildren()))
        XCTAssertEqual(union.x, 347.9, accuracy: 0.15, "the generic element of no size at the origin adds nothing")
        XCTAssertEqual(union.y, 137.5, accuracy: 0.15)
        XCTAssertEqual(union.w, 359.7, accuracy: 0.15)
        XCTAssertEqual(union.h, 780.9, accuracy: 0.15)
        XCTAssertTrue(HitRefiner.matches(hubChildren()[0].frame!, union), "the content group still spans the screen")
        let empty = [AttributeSet(role: "AXGenericElement", frame: Frame(x: 0, y: 1329, w: 0, h: 0)), AttributeSet(role: "AXGroup")]
        XCTAssertNil(HitRefiner.detachedScreenFrame(children: empty), "no child with a non-empty frame")
        XCTAssertNil(HitRefiner.detachedScreenFrame(children: []))
    }

    /// Oryne's Library screen as the repaired reader reads it (probe of Oct 26): the inner group, which lists
    /// the elements, and the screen that Device Hub reports as their parent, both of the screen's frame; the
    /// inner group's children. Recent and Currents touch; Filter sits 8 pt past Currents, behind a divider
    /// drawn in the same glass capsule.
    private func library() -> (inner: AttributeSet, screen: AttributeSet, capsule: [AttributeSet], children: [AttributeSet]) {
        let capsule = [
            AttributeSet(role: "AXButton", description: "Recent", identifier: "square.grid.2x2", frame: Frame(x: 567.1, y: 220.0, w: 39.4, h: 39.3)),
            AttributeSet(role: "AXButton", description: "Currents", identifier: "water.waves", frame: Frame(x: 606.5, y: 220.0, w: 39.4, h: 39.3)),
            AttributeSet(role: "AXPopUpButton", description: "Filter", identifier: "library.filter", frame: Frame(x: 653.9, y: 220.0, w: 39.4, h: 39.3)),
        ]
        let children = [AttributeSet(role: "AXHeading", description: "Library", frame: Frame(x: 362.2, y: 218.2, w: 113.6, h: 42.9))]
            + capsule + [
            AttributeSet(role: "AXImage", description: "Search", frame: Frame(x: 378.3, y: 284.1, w: 14.6, h: 14.9)),
            AttributeSet(role: "AXTextField", frame: Frame(x: 401.9, y: 281.7, w: 277.1, h: 19.7)),
            AttributeSet(role: "AXButton", description: "Product Ideas", frame: Frame(x: 362.2, y: 318.3, w: 331.1, h: 61.7)),
            AttributeSet(role: "AXButton", frame: Frame(x: 362.2, y: 380.0, w: 331.1, h: 75.9)),
            AttributeSet(role: "AXButton", description: "Cooking", frame: Frame(x: 362.2, y: 455.9, w: 331.1, h: 67.9)),
            AttributeSet(role: "AXButton", frame: Frame(x: 362.2, y: 523.8, w: 331.1, h: 75.9)),
        ]
        return (AttributeSet(role: "AXGroup", frame: hubScreen),
                AttributeSet(role: "AXGroup", subrole: HitRefiner.simulatedScreenSubrole, frame: hubScreen),
                capsule, children)
    }

    /// R124 amended: Filter, 8 pt past Currents (the limit for 39.3 pt buttons is 9.8 pt), joins the row,
    /// from each of the three.
    func testTheLibraryCapsuleIsOneGroupFromEachOfItsThreeButtons() throws {
        let l = library()
        let ids = ["square.grid.2x2", "water.waves", "library.filter"]
        for (index, button) in l.capsule.enumerated() {
            let snapshot = ElementSnapshot(element: button, ancestors: [l.inner, l.screen], siblings: l.children)
            let levels = HitRefiner.selectionLevels(for: snapshot, at: center(button))
            XCTAssertEqual(levels.first??.identifier, ids[index])
            let group = try XCTUnwrap(levels.dropFirst().first ?? nil, ids[index])
            XCTAssertEqual(group.rawRole, ElementResolver.groupRawRole, ids[index])
            XCTAssertEqual(group.frame.x, 567.1, accuracy: 0.1)
            XCTAssertEqual(group.frame.y, 220.0, accuracy: 0.1)
            XCTAssertEqual(group.frame.w, 126.2, accuracy: 0.1)
            XCTAssertEqual(group.frame.h, 39.3, accuracy: 0.1)
            XCTAssertEqual(group.members?.compactMap(\.identifier), ids, "in reading order")
            XCTAssertEqual(group.members?.compactMap(\.label), ["Recent", "Currents", "Filter"])
        }
    }

    /// Currents as the repaired reader reads it: the inner group, which lists it, heads its ancestors ahead
    /// of the screen that Device Hub reports as its parent, and its siblings are the inner group's children.
    func testTheRepairedSnapshotOfCurrentsFeedsTheRowOfButtons() throws {
        let l = library()
        let currents = l.capsule[1]
        let point = center(currents)
        let repaired = ElementSnapshot(element: currents, ancestors: [l.inner, l.screen], siblings: l.children)
        let levels = HitRefiner.selectionLevels(for: repaired, at: point)
        XCTAssertEqual(levels.map { $0?.rawRole }, ["AXButton", "LocantGroup", "LocantCluster", "AXGroup"])
        XCTAssertEqual(levels.first??.identifier, "water.waves")
        let group = try XCTUnwrap(levels[1])
        XCTAssertEqual(group.members?.compactMap(\.identifier), ["square.grid.2x2", "water.waves", "library.filter"],
                       "Filter, 8 pt on, is in the row (R124 amended)")
        XCTAssertEqual(group.frame.x, 567.1, accuracy: 0.1)
        XCTAssertEqual(group.frame.w, 126.2, accuracy: 0.1)
        XCTAssertEqual(group.path.map(\.role), ["group", "group", "cluster"], "the inner group joins the path")
        XCTAssertEqual(HitRefiner.simulatedScreen(in: repaired), hubScreen.cgRect)

        // As read before the repair: the screen as the parent, its own children as the siblings.
        let unrepaired = ElementSnapshot(element: currents, ancestors: [l.screen], siblings: hubChildren())
        XCTAssertEqual(HitRefiner.selectionLevels(for: unrepaired, at: point).map { $0?.rawRole }, ["AXButton", "AXGroup"],
                       "from the button straight to the screen")
    }

    // MARK: Padded frames tighten, in the phone (specs/capture-shapes.md R126)

    /// The Library screen's card "Weeknight noodles, yesterday" (Oct 26): its button's frame is 6 pt taller
    /// than the card drawn in it, top and bottom, which R119's fill finds.
    private let cardButton = AttributeSet(role: "AXButton", description: "Weeknight noodles, yesterday", frame: Frame(x: 362.2, y: 543.2, w: 331.1, h: 75.9))
    private let drawnCard = CGRect(x: 363.4, y: 549.0, width: 329.5, height: 64.0)

    private func assertFrame(_ found: Frame?, _ expected: CGRect, within slack: Double = 0.01, _ message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        guard let found else { return XCTFail("no frame; expected \(expected) \(message)", file: file, line: line) }
        for (a, b) in [(found.x, expected.minX), (found.y, expected.minY), (found.w, expected.width), (found.h, expected.height)] {
            XCTAssertEqual(a, b, accuracy: slack, "\(found) vs \(expected) \(message)", file: file, line: line)
        }
    }

    func testOnTheSimulatedScreenACardsButtonTakesTheCardDrawnInIt() throws {
        let l = library()
        let tight = drawnCard.intersection(cardButton.frame!.cgRect) // the card, cut to the button
        var shapes = FixedShapes(rects: [drawnCard], inks: [drawnCard])
        let onCard = ElementSnapshot(element: cardButton, ancestors: [l.inner, l.screen])
        let levels = HitRefiner.selectionLevels(for: onCard, at: CGPoint(x: 500, y: 616), shapes: &shapes, holding: nil)
        XCTAssertEqual(levels.map { $0?.rawRole }, ["AXButton", "AXGroup"],
                       "the button, now outlining the card, then the screen's group: the card it outlines is no rung of its own")
        assertFrame(levels.first??.frame, tight, "in the padding below the card, the button is still rung 0, tightened to it")
        XCTAssertEqual(levels.first??.label, "Weeknight noodles, yesterday")
        XCTAssertEqual(levels.first??.path, ElementResolver.resolve(onCard)?.path)

        // Its title as rung 0: the fill found around it merges into the tightened button, which is kept.
        let title = AttributeSet(role: "AXStaticText", description: "Weeknight noodles", frame: Frame(x: 378, y: 560, w: 200, h: 20))
        let inside = ElementSnapshot(element: title, ancestors: [cardButton, l.inner, l.screen])
        let point = CGPoint(x: 400, y: 570)
        let merged = HitRefiner.selectionLevels(for: inside, at: point, shapes: &shapes, holding: nil)
        XCTAssertEqual(merged.map { $0?.rawRole }, ["AXStaticText", "AXButton", "AXGroup"])
        assertFrame(merged[0]?.frame, title.frame!.cgRect, "20 pt tall, under the 44 pt gate: unchanged")
        assertFrame(merged[1]?.frame, tight)
        XCTAssertEqual(merged[1]?.label, "Weeknight noodles, yesterday", "the accessibility rung carries the handle")

        // Off the simulated screen, the fill is its own rung inside the padded button.
        let plain = AttributeSet(role: "AXGroup", frame: hubScreen)
        let elsewhere = ElementSnapshot(element: title, ancestors: [cardButton, l.inner, plain])
        let untouched = HitRefiner.selectionLevels(for: elsewhere, at: point, shapes: &shapes, holding: nil)
        XCTAssertEqual(untouched.map { $0?.rawRole }, ["AXStaticText", "LocantShape", "AXButton", "AXGroup"])
        XCTAssertEqual(untouched[2]?.frame, cardButton.frame)
    }

    func testOnTheSimulatedScreenContainersAndComputedRungsKeepTheirFrames() throws {
        let l = library()
        let header = l.children[6]
        XCTAssertEqual(header.description, "Product Ideas")
        // The header's title and "1 >", the heading, and each capsule button's icon are drawn; so is all of it
        // inside the screen.
        let title = CGRect(x: 378, y: 338, width: 300, height: 21)
        let icons = l.capsule.map { $0.frame!.cgRect.insetBy(dx: 10, dy: 10) }
        var shapes = FixedShapes(rects: [], inks: [title, CGRect(x: 362.2, y: 226, width: 100, height: 28)] + icons)
        let snapshot = ElementSnapshot(element: header, ancestors: [l.inner, l.screen], siblings: l.children)
        let today = HitRefiner.selectionLevels(for: snapshot, at: center(header))
        let levels = HitRefiner.selectionLevels(for: snapshot, at: center(header), shapes: &shapes, holding: nil)
        XCTAssertEqual(levels.map { $0?.rawRole }, ["AXButton", "LocantGroup", "LocantCluster", "AXGroup"])
        assertFrame(levels[0]?.frame, title, "the header (331.1×61.7): what is drawn in it")
        XCTAssertEqual(levels[1]?.frame, today[1]?.frame, "the column of headers and cards is the union of their own frames")
        XCTAssertEqual(levels[1]?.members?.count, 4)
        XCTAssertEqual(levels[2]?.frame, today[2]?.frame, "the cluster too")
        XCTAssertEqual(levels[3]?.frame, hubScreen, "a container keeps its frame")

        // With no shape at the point and no element under it, today's ladder, tightened.
        let left = CGPoint(x: 359.2, y: 349) // 3 pt left of the header: the reader's 8 pt tolerance
        let fromLeft = HitRefiner.selectionLevels(for: snapshot, at: left, shapes: &shapes, holding: nil)
        XCTAssertEqual(fromLeft.map { $0?.rawRole }, ["AXButton", "LocantGroup", "LocantCluster", "AXGroup"])
        assertFrame(fromLeft[0]?.frame, title)

        // Off the simulated screen: today's ladder, frames and all.
        let plain = ElementSnapshot(element: header, ancestors: [l.inner, AttributeSet(role: "AXGroup", frame: hubScreen)], siblings: l.children)
        XCTAssertEqual(HitRefiner.selectionLevels(for: plain, at: center(header), shapes: &shapes, holding: nil),
                       HitRefiner.selectionLevels(for: plain, at: center(header)))
    }

    /// R126: the sample shows the simulated screen only, so a rung that does not lie inside it, such as a
    /// non-container around the screen, keeps its frame.
    func testOnTheSimulatedScreenOnlyRungsInsideItTighten() throws {
        let l = library()
        let header = l.children[6]
        let title = CGRect(x: 378, y: 338, width: 300, height: 21)
        let around = AttributeSet(role: "AXUnknown", frame: Frame(x: 300, y: 60, w: 460, h: 900)) // holds the screen
        var shapes = FixedShapes(rects: [], inks: [title])
        let snapshot = ElementSnapshot(element: header, ancestors: [l.inner, l.screen, around], siblings: l.children)
        let levels = HitRefiner.selectionLevels(for: snapshot, at: center(header), shapes: &shapes, holding: nil)
        XCTAssertEqual(levels.map { $0?.rawRole }, ["AXButton", "LocantGroup", "LocantCluster", "AXGroup", "AXUnknown"])
        assertFrame(levels[0]?.frame, title)
        XCTAssertEqual(levels.last??.frame, around.frame, "around the screen: its own frame")
    }

    /// R126: iOS pads a control smaller than its 44 pt tap target on purpose, so the capsule's 39.4×39.3
    /// buttons keep their frames, icons drawn or not.
    func testOnTheSimulatedScreenAControlUnder44PointsKeepsItsFrame() {
        let l = library()
        let currents = l.capsule[1]
        var shapes = FixedShapes(rects: [], inks: l.capsule.map { $0.frame!.cgRect.insetBy(dx: 10, dy: 10) })
        let snapshot = ElementSnapshot(element: currents, ancestors: [l.inner, l.screen], siblings: l.children)
        let levels = HitRefiner.selectionLevels(for: snapshot, at: center(currents), shapes: &shapes, holding: nil)
        XCTAssertEqual(levels, HitRefiner.selectionLevels(for: snapshot, at: center(currents)))
        XCTAssertEqual(levels.first??.frame, currents.frame)
    }

    func testATightFrameIsWhatIsDrawnInsideAFrameAtLeast44PointsBothWays() {
        let frame = CGRect(x: 100, y: 100, width: 200, height: 60)
        XCTAssertEqual(HitRefiner.tightFrame(frame, ink: nil), frame, "nothing drawn inside it")
        XCTAssertEqual(HitRefiner.tightFrame(frame, ink: CGRect(x: 120, y: 120, width: 80, height: 20)), CGRect(x: 120, y: 120, width: 80, height: 20))
        XCTAssertEqual(HitRefiner.tightFrame(frame, ink: CGRect(x: 90, y: 125, width: 220, height: 10)), CGRect(x: 100, y: 125, width: 200, height: 10),
                       "cut to the frame")
        XCTAssertEqual(HitRefiner.tightFrame(frame, ink: frame.insetBy(dx: 2, dy: 2)), frame, "2 pt in on every side, not more")
        XCTAssertEqual(HitRefiner.tightFrame(frame, ink: CGRect(x: 100, y: 100, width: 200, height: 57.5)),
                       CGRect(x: 100, y: 100, width: 200, height: 57.5), "2.5 pt in at the bottom alone")
        // At least 44 pt both ways.
        let icon = CGRect(x: 110, y: 110, width: 20, height: 20)
        XCTAssertEqual(HitRefiner.tightFrame(CGRect(x: 100, y: 100, width: 200, height: 44), ink: icon), icon, "44 pt tall")
        XCTAssertEqual(HitRefiner.tightFrame(CGRect(x: 100, y: 100, width: 44, height: 200), ink: icon), icon, "44 pt wide")
        for small in [CGRect(x: 100, y: 100, width: 200, height: 43.9), CGRect(x: 100, y: 100, width: 43.9, height: 200),
                      CGRect(x: 100, y: 100, width: 39.4, height: 39.3), CGRect(x: 100, y: 100, width: 74, height: 39.3)] {
            XCTAssertEqual(HitRefiner.tightFrame(small, ink: icon), small, "\(small): under 44 pt one way")
        }
    }

    // MARK: Text lines (specs/capture-shapes.md R127)

    /// The card's two lines as Vision might read them; it reads the list icon before "yesterday" as "=".
    private let cardLines = [TextLine(text: "Weeknight noodles", frame: Frame(x: 377.0, y: 560.0, w: 120.0, h: 12.0)),
                             TextLine(text: "= yesterday", frame: Frame(x: 377.0, y: 582.0, w: 70.0, h: 11.0))]
    /// The floating tab bar Device Hub reports with no children (R125), and its three labels as read.
    private let tabBar = AttributeSet(role: "AXGroup", description: "Tab Bar", frame: Frame(x: 347.9, y: 844.3, w: 359.7, h: 74.2), childCount: 0)
    private let tabLines = [TextLine(text: "Tide", frame: Frame(x: 445.5, y: 844.0, w: 18.0, h: 6.5)),
                            TextLine(text: "Ask", frame: Frame(x: 520.5, y: 844.0, w: 14.5, h: 6.5)),
                            TextLine(text: "Library", frame: Frame(x: 587.0, y: 844.0, w: 28.5, h: 8.0))]

    private func textRung(_ lines: [TextLine], at point: CGPoint, in snapshot: ElementSnapshot) throws -> ResolvedElement? {
        let answer = try XCTUnwrap(ElementResolver.resolve(snapshot))
        return HitRefiner.textRung(lines: lines, at: point, answer: answer, answerFrame: try XCTUnwrap(snapshot.element.frame))
    }

    func testOnACardEachLineIsARungLabeledByThePartOfTheCardsLabelItReads() throws {
        let l = library()
        let card = ElementSnapshot(element: cardButton, ancestors: [l.inner, l.screen])
        let first = try XCTUnwrap(try textRung(cardLines, at: CGPoint(x: 400, y: 566), in: card))
        XCTAssertEqual(first.role, "staticText")
        XCTAssertEqual(first.rawRole, ElementResolver.textRawRole)
        XCTAssertEqual(first.label, "Weeknight noodles")
        assertFrame(first.frame, CGRect(x: 375.0, y: 558.0, width: 124.0, height: 16.0), "the line's box grown by 2 pt")
        XCTAssertNil(first.identifier)
        XCTAssertEqual(first.identifierSource, .unknown)
        XCTAssertNil(first.value)
        XCTAssertNil(first.members)
        XCTAssertEqual(first.path, try XCTUnwrap(ElementResolver.resolve(card)).path + [PathEntry(role: "staticText", identifier: nil)])

        let second = try XCTUnwrap(try textRung(cardLines, at: CGPoint(x: 410, y: 581), in: card), "1 pt above the box: within 2 pt")
        XCTAssertEqual(second.label, "yesterday", "the label's part wins over \"= yesterday\"")
        assertFrame(second.frame, CGRect(x: 375.0, y: 580.0, width: 74.0, height: 15.0))

        XCTAssertNil(try textRung(cardLines, at: CGPoint(x: 400, y: 577), in: card), "between the lines, 5 pt from each")
        XCTAssertNil(try textRung(cardLines, at: CGPoint(x: 400, y: 574.5), in: card), "2.5 pt below the first")
        XCTAssertNil(try textRung(Array(cardLines.prefix(1)), at: CGPoint(x: 400, y: 566), in: card), "one line alone adds nothing")

        var unnamed = cardButton
        unnamed.description = "Dinner"
        let read = try XCTUnwrap(try textRung(cardLines, at: CGPoint(x: 400, y: 588), in: ElementSnapshot(element: unnamed, ancestors: [l.inner, l.screen])))
        XCTAssertEqual(read.label, "= yesterday", "no part of the label matches: the text as read")
    }

    func testOnTheTabBarALineIsARungInsideTheGroup() throws {
        let l = library()
        let bar = ElementSnapshot(element: tabBar, ancestors: [l.screen], children: [])
        let ask = try XCTUnwrap(try textRung(tabLines, at: CGPoint(x: 527, y: 847), in: bar))
        XCTAssertEqual(ask.role, "staticText")
        XCTAssertEqual(ask.label, "Ask", "\"Tab Bar\" names none of them")
        assertFrame(ask.frame, CGRect(x: 518.5, y: 844.3, width: 18.5, height: 8.2), "grown by 2 pt, cut to the tab bar's frame")
        XCTAssertEqual(ask.path.map(\.role), ["group", "group", "staticText"])
        XCTAssertNil(try textRung(tabLines, at: CGPoint(x: 527, y: 880), in: bar), "below the labels: the tab bar")
    }

    func testALineMatchesALabelPartOnLettersAndDigitsAlone() {
        XCTAssertEqual(HitRefiner.textLabel("WEEKNIGHT  noodles!", within: "Weeknight noodles, yesterday"), "Weeknight noodles")
        XCTAssertEqual(HitRefiner.textLabel("Weeknight nood", within: "Weeknight noodles, yesterday"), "Weeknight noodles", "the part holds the line")
        XCTAssertEqual(HitRefiner.textLabel("= 4 seconds ago", within: "Random, 4 seconds ago"), "4 seconds ago")
        XCTAssertEqual(HitRefiner.textLabel("Random 4 seconds ago", within: "Random, 4 seconds ago"), "Random", "the line holds a part")
        XCTAssertEqual(HitRefiner.textLabel("=", within: "Random, 4 seconds ago"), "=", "no letters or digits: as read")
        XCTAssertEqual(HitRefiner.textLabel(" Ask ", within: nil), "Ask")
        // Containment takes three letters or digits on the shorter side; equality takes any.
        XCTAssertEqual(HitRefiner.textLabel("1", within: "Product Ideas, 1 thought"), "1", "a stray digit takes no part")
        XCTAssertEqual(HitRefiner.textLabel("no", within: "Weeknight noodles, yesterday"), "no")
        XCTAssertEqual(HitRefiner.textLabel("noo", within: "Weeknight noodles, yesterday"), "Weeknight noodles")
        XCTAssertEqual(HitRefiner.textLabel("1", within: "Product Ideas, 1"), "1", "equal")
        XCTAssertEqual(HitRefiner.textLabel("= 昨天", within: "周末面条, 昨天"), "昨天", "equal, two characters")
    }

    func testOfTwoLinesInReachTheNearerIsTheRung() throws {
        let l = library()
        let card = ElementSnapshot(element: cardButton, ancestors: [l.inner, l.screen])
        // 3 pt apart, so their grown boxes overlap between 573 and 574.
        let close = [TextLine(text: "Weeknight noodles", frame: Frame(x: 377.0, y: 560.0, w: 120.0, h: 12.0)),
                     TextLine(text: "yesterday", frame: Frame(x: 377.0, y: 575.0, w: 70.0, h: 11.0))]
        XCTAssertEqual(try textRung(close, at: CGPoint(x: 400, y: 573.2), in: card)?.label, "Weeknight noodles", "1.2 pt from the first, 1.8 from the second")
        XCTAssertEqual(try textRung(close, at: CGPoint(x: 400, y: 573.8), in: card)?.label, "yesterday", "1.8 pt from the first, 1.2 from the second")
    }

    func testLinesOutsideTheAnswersFrameDoNotCount() throws {
        let l = library()
        let card = ElementSnapshot(element: cardButton, ancestors: [l.inner, l.screen])
        let below = TextLine(text: "Cooking", frame: Frame(x: 377.0, y: 630.0, w: 60.0, h: 12.0)) // under the card's 619.1
        let lines = [cardLines[0], below]
        XCTAssertNil(try textRung(lines, at: CGPoint(x: 400, y: 566), in: card), "one line inside: nothing")
        XCTAssertNil(try textRung(cardLines + [below], at: CGPoint(x: 400, y: 636), in: card), "the pointer on the line outside")
        XCTAssertEqual(try textRung(cardLines + [below], at: CGPoint(x: 400, y: 566), in: card)?.label, "Weeknight noodles")
    }

    /// R127: a line is not kept by the 12 pt stickiness either, as any other element is when the pointer leaves it.
    func testALineDoesNotStick() throws {
        let l = library()
        let bar = ElementSnapshot(element: tabBar, ancestors: [l.screen], children: [])
        let ask = try XCTUnwrap(try textRung(tabLines, at: CGPoint(x: 527, y: 847), in: bar))
        let near = CGPoint(x: 527, y: 860)
        XCTAssertFalse(HitRefiner.sticks(ask, to: near))
        var element = ask
        element.rawRole = "AXStaticText"
        XCTAssertTrue(HitRefiner.sticks(element, to: near), "an accessibility element would")
    }

    /// R127: a line read again, its box moved a little, is the same rung: the ⌥ level chosen from it stays.
    func testALineReadAgainIsTheSameRung() throws {
        let l = library()
        let card = ElementSnapshot(element: cardButton, ancestors: [l.inner, l.screen])
        let first = try XCTUnwrap(try textRung(cardLines, at: CGPoint(x: 400, y: 566), in: card))
        var moved = cardLines
        moved[0].frame = Frame(x: 377.5, y: 559.5, w: 121.0, h: 12.5)
        let again = try XCTUnwrap(try textRung(moved, at: CGPoint(x: 400, y: 566), in: card))
        XCTAssertNotEqual(first.frame, again.frame)
        XCTAssertTrue(HitRefiner.isRereadLine(first, in: card, again, in: card))

        let second = try XCTUnwrap(try textRung(cardLines, at: CGPoint(x: 400, y: 588), in: card))
        XCTAssertFalse(HitRefiner.isRereadLine(first, in: card, second, in: card), "another line")
        var other = cardButton
        other.description = "Weeknight noodles, last week"
        XCTAssertFalse(HitRefiner.isRereadLine(first, in: card, again, in: ElementSnapshot(element: other, ancestors: [l.inner, l.screen])),
                       "another answer's label")
        var shifted = cardButton
        shifted.frame = Frame(x: 362.2, y: 623.2, w: 331.1, h: 75.9)
        XCTAssertFalse(HitRefiner.isRereadLine(first, in: card, again, in: ElementSnapshot(element: shifted, ancestors: [l.inner, l.screen])),
                       "another answer's frame")
        var element = again
        element.rawRole = "AXStaticText"
        XCTAssertFalse(HitRefiner.isRereadLine(first, in: card, element, in: card), "an accessibility element")
        XCTAssertFalse(HitRefiner.isRereadLine(nil, in: card, again, in: card))
    }

    func testLinesAreReadOnlyInAnAnswerOnTheSimulatedScreenThatHasNoChildren() {
        let l = library()
        let onCard = CGPoint(x: 400, y: 566)
        XCTAssertEqual(HitRefiner.textArea(of: ElementSnapshot(element: cardButton, ancestors: [l.inner, l.screen]), at: onCard),
                       cardButton.frame?.cgRect, "a leaf: its accessibility frame")
        XCTAssertNil(HitRefiner.textArea(of: ElementSnapshot(element: cardButton, ancestors: [l.inner, l.screen]), at: CGPoint(x: 400, y: 630)),
                     "its frame does not hold the point")
        var parent = cardButton
        parent.childCount = 2
        XCTAssertNil(HitRefiner.textArea(of: ElementSnapshot(element: parent, ancestors: [l.inner, l.screen]), at: onCard), "it has children")
        XCTAssertNil(HitRefiner.textArea(of: ElementSnapshot(element: cardButton, ancestors: [l.inner, AttributeSet(role: "AXGroup", frame: hubScreen)]), at: onCard),
                     "off the simulated screen")

        let onBar = CGPoint(x: 527, y: 880)
        XCTAssertEqual(HitRefiner.textArea(of: ElementSnapshot(element: tabBar, ancestors: [l.screen], children: []), at: onBar), tabBar.frame?.cgRect,
                       "a container whose children read empty")
        var group = tabBar
        group.description = nil
        XCTAssertNil(HitRefiner.textArea(of: ElementSnapshot(element: group, ancestors: [l.screen], children: [cardButton]), at: onBar),
                     "a container with children")

        // At least 44 pt both ways, at most half the screen's area (359.7×780.9).
        let currents = l.capsule[1] // 39.4×39.3
        XCTAssertNil(HitRefiner.textArea(of: ElementSnapshot(element: currents, ancestors: [l.inner, l.screen]), at: center(currents)))
        for (w, h, reads) in [(331.1, 43.9, false), (43.9, 100.0, false), (44.0, 44.0, true), (359.7, 390.4, true), (359.7, 390.6, false)] {
            let leaf = AttributeSet(role: "AXButton", frame: Frame(x: 347.9, y: 137.5, w: w, h: h), childCount: 0)
            let found = HitRefiner.textArea(of: ElementSnapshot(element: leaf, ancestors: [l.inner, l.screen]), at: CGPoint(x: 350, y: 140))
            XCTAssertEqual(found != nil, reads, "\(w)×\(h)")
        }
    }

    /// R117 step 2 holds an element inside a shape; a line is read again at each step instead.
    func testALineIsNeverHeldInsideAShape() throws {
        let l = library()
        let bar = ElementSnapshot(element: tabBar, ancestors: [l.screen], children: [])
        let capsule = CGRect(x: 352, y: 844.3, width: 351, height: 70) // the tab bar's glass
        let ask = try XCTUnwrap(try textRung(tabLines, at: CGPoint(x: 527, y: 847), in: bar))
        let near = CGPoint(x: 527, y: 854) // 1.5 pt below the line's rung: inside R117's 3 pt hold
        var shapes = FixedShapes(rects: [capsule])
        let levels = HitRefiner.selectionLevels(for: bar, at: near, shapes: &shapes, holding: ask)
        XCTAssertEqual(levels.first??.rawRole, ElementResolver.shapeRawRole)

        var element = ask
        element.rawRole = "AXStaticText"
        let held = HitRefiner.selectionLevels(for: bar, at: near, shapes: &shapes, holding: element)
        XCTAssertEqual(held.first??.rawRole, "AXStaticText", "an accessibility element there would be held")
    }

    /// R126: a click commits what hover drew. On the simulated screen, near the frame of the element hover
    /// outlined tighter counts; near an element that only neighbors the rung drawn does not; off the screen
    /// the 12 pt rule alone decides.
    func testAClickIsOnTheTightenedRungNearItsElementsOwnFrame() throws {
        let l = library()
        let header = l.children[6] // 362.2,318.3 331.1×61.7
        let title = CGRect(x: 378, y: 338, width: 300, height: 21)
        var shapes = FixedShapes(rects: [], inks: [title])
        // 6 pt left of the header, inside the reader's 8 pt tolerance, with no shape there: the header, tightened.
        let ring = CGPoint(x: 356.2, y: 349)
        let snapshot = ElementSnapshot(element: header, ancestors: [l.inner, l.screen], siblings: l.children)
        let drawn = try XCTUnwrap(HitRefiner.selectionLevels(for: snapshot, at: ring, shapes: &shapes, holding: nil).first ?? nil)
        assertFrame(drawn.frame, title)
        XCTAssertTrue(HitRefiner.clickIsOnHover(ring, shown: drawn, snapshot: snapshot), "21.8 pt from the outline, 6 pt from the header")
        XCTAssertTrue(HitRefiner.clickIsOnHover(CGPoint(x: 365, y: 378), shown: drawn, snapshot: snapshot), "in the header's padding")
        XCTAssertFalse(HitRefiner.clickIsOnHover(CGPoint(x: 500, y: 400), shown: drawn, snapshot: snapshot), "20 pt below the header")

        // Off the simulated screen, only 12 pt around what was drawn.
        let plain = ElementSnapshot(element: header, ancestors: [l.inner, AttributeSet(role: "AXGroup", frame: hubScreen)], siblings: l.children)
        XCTAssertFalse(HitRefiner.clickIsOnHover(ring, shown: drawn, snapshot: plain))
        XCTAssertTrue(HitRefiner.clickIsOnHover(CGPoint(x: 370, y: 349), shown: drawn, snapshot: plain), "8 pt from the outline")
        XCTAssertFalse(HitRefiner.clickIsOnHover(ring, shown: nil, snapshot: snapshot))
    }

    /// R126: rung 0 tightened when the first sample lands is the same element, so ⌥'s level stays.
    func testTheSameElementOutlinedTighterIsNoMove() throws {
        let l = library()
        let header = try XCTUnwrap(ElementResolver.resolve(ElementSnapshot(element: l.children[6], ancestors: [l.inner, l.screen])))
        var tight = header
        tight.frame = Frame(x: 378, y: 338, w: 300, h: 21)
        XCTAssertTrue(HitRefiner.isRetightened(header, tight))
        XCTAssertTrue(HitRefiner.isRetightened(tight, header), "and back, when the sample is gone")
        XCTAssertTrue(HitRefiner.isRetightened(header, header))
        var moved = tight
        moved.frame = Frame(x: 378, y: 390, w: 300, h: 21)
        XCTAssertFalse(HitRefiner.isRetightened(header, moved), "a frame outside the other")
        var other = tight
        other.label = "Cooking"
        XCTAssertFalse(HitRefiner.isRetightened(header, other), "another element")
        XCTAssertFalse(HitRefiner.isRetightened(nil, tight))
        XCTAssertFalse(HitRefiner.isRetightened(header, nil))
    }

    /// R126: when the rung drawn is not the snapshot's element (R117 step 3, a shape over an element reached
    /// through the tolerance; step 2, an element held inside a shape), a click in that element's frame far
    /// from the rung is a click elsewhere.
    func testAClickNearTheElementReadIsNotOnAShapeOrAHeldElement() throws {
        let l = library()
        let pill = CGRect(x: 450, y: 528, width: 100, height: 14)
        var shapes = FixedShapes(rects: [pill])
        let above = CGPoint(x: 500, y: 540.2) // 3 pt above the card, in the pill
        let nearCard = ElementSnapshot(element: cardButton, ancestors: [l.inner, l.screen])
        let shape = try XCTUnwrap(HitRefiner.selectionLevels(for: nearCard, at: above, shapes: &shapes, holding: nil).first ?? nil)
        XCTAssertEqual(shape.rawRole, ElementResolver.shapeRawRole)
        XCTAssertFalse(HitRefiner.clickIsOnHover(CGPoint(x: 680, y: 610), shown: shape, snapshot: nearCard), "in the card, far from the pill")

        // Oryne's toolbar on the simulated screen: the pointer 2 pt past the pencil, which holds it inside the
        // capsule, and 2 pt short of trash, which the reader reached through its tolerance.
        let n = toolbarNodes()
        let phone = AttributeSet(role: "AXGroup", subrole: HitRefiner.simulatedScreenSubrole, frame: n.screen.frame)
        let trash = AttributeSet(role: "AXButton", identifier: "trash", frame: Frame(x: 344, y: 330, w: 40, h: 40))
        let pencil = try XCTUnwrap(ElementResolver.resolve(ElementSnapshot(element: n.pencil, ancestors: [n.hosting, phone])))
        let reached = ElementSnapshot(element: trash, ancestors: [n.hosting, phone], siblings: [n.share, n.pencil, trash])
        var capsuleOnly = FixedShapes(rects: [CGRect(x: 250, y: 326, width: 140, height: 44)])
        let held = try XCTUnwrap(HitRefiner.selectionLevels(for: reached, at: CGPoint(x: 342, y: 350), shapes: &capsuleOnly, holding: pencil).first ?? nil)
        XCTAssertEqual(held.identifier, "pencil")
        XCTAssertFalse(HitRefiner.clickIsOnHover(CGPoint(x: 380, y: 350), shown: held, snapshot: reached), "in trash, 40 pt from the pencil")
        XCTAssertTrue(HitRefiner.clickIsOnHover(CGPoint(x: 350, y: 350), shown: held, snapshot: reached), "10 pt from the pencil")
    }

    /// SwiftUI nests several containers in one frame (three 456×900 groups in the Simulator, five
    /// 470×1000 ones in Device Hub), and so does the web. They outline the same rectangle, so they
    /// are one rung, and Option always moves the outline. Of a run the window stays, else the one
    /// with an identifier, else the innermost.
    func testSelectionLevelsCollapseRungsThatOutlineTheSameRectangle() throws {
        let simulator = HitRefiner.selectionLevels(for: try fixture("simulator-path"), at: CGPoint(x: 228, y: 918))
        XCTAssertEqual(simulator.map { $0?.role }, ["button", "group", "window", "application"])

        let chrome = Frame(x: 168, y: 235, w: 470, h: 1000)
        func filling(_ role: String, id: String? = nil) -> AttributeSet { AttributeSet(role: role, identifier: id, frame: chrome) }
        let orb = ElementSnapshot(
            element: node("AXButton", id: "oceanCurrent.product ideas", x: 252, y: 527, w: 55, h: 97),
            ancestors: [node("AXGroup", x: 210, y: 320, w: 385, h: 837), filling("AXGroup"),
                        filling("AXSplitGroup", id: "SidebarNavigationSplitView"), filling("AXGroup"), filling("AXSplitGroup"), filling("AXGroup")]
        )
        let levels = HitRefiner.selectionLevels(for: orb, at: CGPoint(x: 280, y: 555))
        XCTAssertEqual(levels.map { $0?.role }, ["button", "group", "splitGroup"])
        XCTAssertEqual(levels.last??.identifier, "SidebarNavigationSplitView", "the one with an identifier stays")
        XCTAssertEqual(Set(levels.compactMap { $0?.frame }).count, levels.count, "every step moves the outline")

        let window = ElementSnapshot(element: node("AXButton", x: 200, y: 300, w: 40, h: 20),
                                     ancestors: [filling("AXGroup", id: "content"), AttributeSet(role: "AXWindow", frame: chrome)])
        XCTAssertEqual(HitRefiner.selectionLevels(for: window, at: CGPoint(x: 210, y: 310)).map { $0?.role }, ["button", "window"])
    }

    /// The Finder desktop: a screen-sized group under a scroll area, no window anywhere in the chain.
    /// It counts as spanning its root, so blank desktop is "nothing here" and an icon area is a cluster.
    func testDesktopWithoutWindowAncestorSpansItsRoot() throws {
        let screen = Frame(x: 0, y: 0, w: 2056, h: 1329)
        let desktop = AttributeSet(role: "AXGroup", description: "desktop", frame: screen, childCount: 2)
        let scrollArea = AttributeSet(role: "AXScrollArea", description: "desktop", frame: screen)
        let application = AttributeSet(role: "AXApplication", title: "Finder")
        let icon = node("AXImage", x: 1958, y: 47, w: 64, h: 64)
        let label = node("AXStaticText", x: 1950, y: 115, w: 80, h: 16)
        let snapshot = ElementSnapshot(element: desktop, ancestors: [scrollArea, application], children: [icon, label])
        XCTAssertEqual(HitRefiner.windowFrame(in: snapshot), screen)
        let blank = HitRefiner.selectionLevels(for: snapshot, at: CGPoint(x: 1000, y: 600))
        XCTAssertEqual(blank.map { $0?.role }, [nil, "group"], "the scroll area outlines the same screen as the group")
        let nearIcon = HitRefiner.selectionLevels(for: snapshot, at: CGPoint(x: 1990, y: 100))
        XCTAssertEqual(nearIcon.first??.role, "cluster", "icon and its label form one cluster")
    }

    func testDesktopAndMenuBarRoles() {
        XCTAssertEqual(ElementResolver.mapRole("AXMenuBarItem", subrole: "AXMenuExtra"), "menuExtra")
        XCTAssertEqual(ElementResolver.mapRole("AXMenuBarItem", subrole: nil), "menuBarItem")
        XCTAssertEqual(ElementResolver.mapRole("AXDockItem", subrole: nil), "dockItem")
        XCTAssertEqual(ElementResolver.mapRole("AXUnknown", subrole: nil), "unknown", "a widget's cell")
    }

    func testZeroFrameResolvesToNil() {
        let ghost = ElementSnapshot(element: AttributeSet(role: "AXApplication", frame: Frame(x: 0, y: 0, w: 0, h: 0)), ancestors: [])
        XCTAssertNil(ElementResolver.resolve(ghost))
    }

    func testModeClassifier() {
        func source(app: String, simApp: String? = nil, url: String? = nil) -> SourceInfo {
            SourceInfo(
                app: AppInfo(bundleId: app, name: "x"),
                window: nil,
                url: url,
                simulator: app == ModeClassifier.simulatorBundleId ? SimulatorInfo(device: "iPhone", appBundleId: simApp) : nil
            )
        }
        let mine = ["com.example.mine"]
        XCTAssertEqual(ModeClassifier.classify(source(app: "com.example.mine"), myApps: mine), .fix)
        XCTAssertEqual(ModeClassifier.classify(source(app: "com.figma.Desktop"), myApps: mine), .reference)
        XCTAssertEqual(ModeClassifier.classify(source(app: ModeClassifier.simulatorBundleId, simApp: "com.example.mine"), myApps: mine), .fix)
        XCTAssertEqual(ModeClassifier.classify(source(app: ModeClassifier.simulatorBundleId, simApp: "com.other.app"), myApps: mine), .fix, "v0.3: anything in the Simulator was built by the user")
        XCTAssertEqual(ModeClassifier.classify(source(app: ModeClassifier.simulatorBundleId, simApp: nil), myApps: mine), .fix)
        XCTAssertEqual(ModeClassifier.classify(source(app: "com.apple.Safari", url: "http://localhost:3000/x"), myApps: mine), .fix)
        XCTAssertEqual(ModeClassifier.classify(source(app: "com.apple.Safari", url: "https://example.com"), myApps: mine), .reference)
    }

    /// Xcode 27: Device Hub is the simulator when its window shows one (the context then carries a
    /// simulator block), and an Apple app like any other when it shows a physical device.
    func testModeClassifierTreatsDeviceHubAsTheSimulatorItShows() {
        var source = SourceInfo(
            app: AppInfo(bundleId: "com.apple.dt.Devices", name: "Device Hub"),
            window: WindowInfo(title: "iPhone 17 Pro – iOS 26.5"),
            url: nil,
            simulator: SimulatorInfo(device: "iPhone 17 Pro", appBundleId: "com.other.app")
        )
        let signals = ModeClassifier.signals(for: CaptureContext(source: source, frontPID: 0), myApps: [], userTeamIDs: [])
        XCTAssertTrue(signals.isSimulator)
        XCTAssertEqual(signals.simulatedBundleId, "com.other.app")
        XCTAssertEqual(ModeClassifier.classify(source), .fix)

        source.window = WindowInfo(title: "Malik’s iPhone – iOS 27.0")
        source.simulator = nil
        XCTAssertFalse(ModeClassifier.signals(for: CaptureContext(source: source, frontPID: 0), myApps: [], userTeamIDs: []).isSimulator)
        XCTAssertEqual(ModeClassifier.classify(source), .reference)
    }
}

/// Returns scripted snapshots in order, then nil forever. Counts calls.
actor ScriptedProvider: ElementProvider {
    private var script: [ElementSnapshot?]
    private(set) var calls = 0

    init(script: [ElementSnapshot?]) { self.script = script }

    func snapshot(at point: CGPoint) async -> ElementSnapshot? {
        calls += 1
        return script.isEmpty ? nil : script.removeFirst()
    }
}
