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

    func testAGapOrAMisalignmentBreaksTheRow() {
        func rungs(_ second: AttributeSet) -> [ResolvedElement] {
            let first = node("AXButton", id: "a", x: 100, y: 50, w: 40, h: 40)
            let screen = node("AXGroup", x: 0, y: 0, w: 400, h: 600)
            let snapshot = ElementSnapshot(element: first, ancestors: [screen], siblings: [first, second])
            return groups(in: HitRefiner.selectionLevels(for: snapshot, at: center(first)))
        }
        XCTAssertEqual(rungs(node("AXButton", id: "b", x: 142, y: 50, w: 40, h: 40)).count, 1, "a 2 pt gap still touches")
        XCTAssertEqual(rungs(node("AXButton", id: "b", x: 138, y: 50, w: 40, h: 40)).count, 1, "a 2 pt overlap still touches")
        XCTAssertEqual(rungs(node("AXButton", id: "b", x: 143, y: 50, w: 40, h: 40)).count, 0, "a 3 pt gap does not")
        XCTAssertEqual(rungs(node("AXButton", id: "b", x: 137, y: 50, w: 40, h: 40)).count, 0, "a 3 pt overlap does not")
        XCTAssertEqual(rungs(node("AXButton", id: "b", x: 140, y: 50, w: 40, h: 42)).count, 0, "a height 2 pt off does not")
        XCTAssertEqual(rungs(node("AXButton", id: "b", x: 140, y: 52, w: 40, h: 40)).count, 0, "a top edge 2 pt off does not")
        XCTAssertEqual(rungs(node("AXButton", id: "b", x: 140, y: 51, w: 40, h: 41)).count, 1, "1 pt off on both still lines up")
        XCTAssertEqual(rungs(node("AXGroup", id: "b", x: 140, y: 50, w: 40, h: 40)).count, 0, "a container is not a control")
        XCTAssertEqual(rungs(node("AXButton", id: "b", x: 140, y: 50, w: 0, h: 40)).count, 0, "a member needs a frame")
    }

    func testTheChainStopsAtTheFirstGap() throws {
        var n = capsuleRow()
        n.buttons.append(node("AXButton", id: "far", x: 683.3, y: 398.2, w: 39.4, h: 39.3)) // 5 pt past trash
        let snapshot = ElementSnapshot(element: n.buttons[1], ancestors: [n.screen], siblings: n.buttons + [n.meta])
        let group = try XCTUnwrap(groups(in: HitRefiner.selectionLevels(for: snapshot, at: center(n.buttons[1]))).first)
        XCTAssertEqual(group.members?.compactMap(\.identifier), ["folder", "square.and.arrow.up", "trash"])
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

    /// Currents as the repaired reader reads it: the inner group, which lists it, heads its ancestors ahead
    /// of the screen that Device Hub reports as its parent, and its siblings are the inner group's children.
    func testTheRepairedSnapshotOfCurrentsFeedsTheRowOfButtons() throws {
        let inner = AttributeSet(role: "AXGroup", frame: hubScreen)
        let screen = AttributeSet(role: "AXGroup", subrole: HitRefiner.simulatedScreenSubrole, frame: hubScreen)
        let recent = AttributeSet(role: "AXButton", description: "Recent", identifier: "square.grid.2x2", frame: Frame(x: 567.1, y: 220.0, w: 39.4, h: 39.3))
        let currents = AttributeSet(role: "AXButton", description: "Currents", identifier: "water.waves", frame: Frame(x: 606.5, y: 220.0, w: 39.4, h: 39.3))
        let library = [
            AttributeSet(role: "AXHeading", description: "Library", frame: Frame(x: 362.2, y: 218.2, w: 113.6, h: 42.9)),
            recent,
            currents,
            AttributeSet(role: "AXPopUpButton", description: "Filter", identifier: "library.filter", frame: Frame(x: 653.9, y: 220.0, w: 39.4, h: 39.3)),
            AttributeSet(role: "AXImage", description: "Search", frame: Frame(x: 378.3, y: 284.1, w: 14.6, h: 14.9)),
            AttributeSet(role: "AXTextField", frame: Frame(x: 401.9, y: 281.7, w: 277.1, h: 19.7)),
            AttributeSet(role: "AXButton", description: "Product Ideas", frame: Frame(x: 362.2, y: 318.3, w: 331.1, h: 61.7)),
            AttributeSet(role: "AXButton", frame: Frame(x: 362.2, y: 380.0, w: 331.1, h: 75.9)),
            AttributeSet(role: "AXButton", description: "Cooking", frame: Frame(x: 362.2, y: 455.9, w: 331.1, h: 67.9)),
            AttributeSet(role: "AXButton", frame: Frame(x: 362.2, y: 523.8, w: 331.1, h: 75.9)),
        ]
        let point = center(currents)
        let repaired = ElementSnapshot(element: currents, ancestors: [inner, screen], siblings: library)
        let levels = HitRefiner.selectionLevels(for: repaired, at: point)
        XCTAssertEqual(levels.map { $0?.rawRole }, ["AXButton", "LocantGroup", "LocantCluster", "AXGroup"])
        XCTAssertEqual(levels.first??.identifier, "water.waves")
        let group = try XCTUnwrap(levels[1])
        XCTAssertEqual(group.members?.compactMap(\.identifier), ["square.grid.2x2", "water.waves"], "Filter, 8 pt on, is not in the row")
        XCTAssertEqual(group.frame.x, 567.1, accuracy: 0.1)
        XCTAssertEqual(group.frame.w, 78.8, accuracy: 0.1)
        XCTAssertEqual(group.path.map(\.role), ["group", "group", "cluster"], "the inner group joins the path")
        XCTAssertEqual(HitRefiner.simulatedScreen(in: repaired), hubScreen.cgRect)

        // As read before the repair: the screen as the parent, its own children as the siblings.
        let unrepaired = ElementSnapshot(element: currents, ancestors: [screen], siblings: hubChildren())
        XCTAssertEqual(HitRefiner.selectionLevels(for: unrepaired, at: point).map { $0?.rawRole }, ["AXButton", "AXGroup"],
                       "from the button straight to the screen")
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
