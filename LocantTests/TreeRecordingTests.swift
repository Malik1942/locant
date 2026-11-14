import XCTest
@testable import Locant

/// specs/frozen-screen.md R174: the tree recorded before the overlay opened answers for what the app has
/// dropped since. The reader says which nodes are gone; everything here is the pure part.
final class TreeRecordingTests: XCTestCase {
    private func node(_ role: String, _ frame: CGRect?, title: String? = nil, classes: [String]? = nil, value: String? = nil,
                      childCount: Int = 0) -> AttributeSet {
        AttributeSet(role: role, subrole: nil, title: title, description: nil, value: value.map { .string($0) }, identifier: nil,
                     frame: frame.map { Frame($0) }, childCount: childCount, domId: nil, domClasses: classes)
    }

    /// A page with a nav item and the menu that hangs under it on hover, outside the item's own frame, and a
    /// list whose last row is scrolled out but still reports a frame.
    ///
    /// 0 application
    /// └ 1 window (0, 0, 800, 600)
    ///   └ 2 web area (0, 50, 800, 550), with the page address
    ///     ├ 3 group nav item (100, 60, 120, 30)
    ///     │ ├ 4 link "Products" (100, 60, 120, 30)
    ///     │ └ 5 group menu (100, 90, 240, 120)
    ///     │   ├ 6 link "Pricing" (110, 100, 100, 24)
    ///     │   └ 7 link "Docs" (110, 130, 100, 24)
    ///     ├ 8 text "Body copy" (100, 100, 600, 40), behind the menu
    ///     └ 9 scroll area (500, 300, 200, 100)
    ///       └ 10 text "Row scrolled out" (500, 420, 200, 30)
    private var page: TreeRecording {
        var tree = TreeRecording(pid: 42)
        func add(_ attributes: AttributeSet, parent: Int?, url: String? = nil) {
            let index = tree.nodes.count
            tree.nodes.append(.init(attributes: attributes, parent: parent, depth: parent.map { tree.nodes[$0].depth + 1 } ?? 0, url: url))
            if let parent { tree.nodes[parent].children.append(index) }
        }
        add(node("AXApplication", nil, title: "Browser", childCount: 1), parent: nil)
        add(node("AXWindow", CGRect(x: 0, y: 0, width: 800, height: 600), title: "Shop", childCount: 1), parent: 0)
        add(node("AXWebArea", CGRect(x: 0, y: 50, width: 800, height: 550), classes: [], childCount: 3), parent: 1, url: "http://localhost:3000/")
        add(node("AXGroup", CGRect(x: 100, y: 60, width: 120, height: 30), classes: ["nav-item"], childCount: 2), parent: 2)
        add(node("AXLink", CGRect(x: 100, y: 60, width: 120, height: 30), title: "Products", classes: ["nav-link"]), parent: 3)
        add(node("AXGroup", CGRect(x: 100, y: 90, width: 240, height: 120), classes: ["menu"], childCount: 2), parent: 3)
        add(node("AXLink", CGRect(x: 110, y: 100, width: 100, height: 24), title: "Pricing", classes: ["menu-link"], value: "/pricing"), parent: 5)
        add(node("AXLink", CGRect(x: 110, y: 130, width: 100, height: 24), title: "Docs", classes: ["menu-link"]), parent: 5)
        add(node("AXStaticText", CGRect(x: 100, y: 100, width: 600, height: 40), classes: [], value: "Body copy"), parent: 2)
        add(node("AXScrollArea", CGRect(x: 500, y: 300, width: 200, height: 100), childCount: 1), parent: 2)
        add(node("AXStaticText", CGRect(x: 500, y: 420, width: 200, height: 30), value: "Row scrolled out"), parent: 9)
        return tree
    }

    func testHitsAreDeepestFirst() {
        // On "Pricing": the link, its menu, then the text behind (same depth as the nav item, which does not
        // hold the point), the web area and the window.
        XCTAssertEqual(page.hits(at: CGPoint(x: 150, y: 110)), [6, 5, 8, 2, 1])
    }

    func testAMenuOutsideItsItemIsStillHit() {
        // The menu hangs below the nav item's frame; a plain parent does not clip.
        XCTAssertEqual(page.hits(at: CGPoint(x: 300, y: 200)).first, 5)
    }

    func testAScrollAreaClipsWhatItHolds() {
        // The row's frame holds the point, the scroll area's does not: the row is not on screen there.
        XCTAssertEqual(page.hits(at: CGPoint(x: 600, y: 430)), [2, 1])
    }

    func testAContainerGivesWayToAControlNearThePoint() {
        // In the menu's padding, 6 pt left of "Docs": within the 8 pt tolerance.
        XCTAssertEqual(page.refined(5, at: CGPoint(x: 104, y: 140)), 7)
        // Far from both links, the menu stands.
        XCTAssertEqual(page.refined(5, at: CGPoint(x: 320, y: 200)), 5)
        // A control stands as it is.
        XCTAssertEqual(page.refined(6, at: CGPoint(x: 150, y: 110)), 6)
    }

    func testSnapshotHasTheShapeOfALiveRead() {
        let snapshot = page.snapshot(of: 6)
        XCTAssertEqual(snapshot.fromRecording, true)
        XCTAssertEqual(snapshot.element.title, "Pricing")
        XCTAssertEqual(snapshot.element.value, .string("/pricing"), "the element keeps its value")
        XCTAssertEqual(snapshot.url, "http://localhost:3000/", "from the web area above")
        XCTAssertEqual(snapshot.ancestors.map(\.role), ["AXGroup", "AXGroup", "AXWebArea", "AXWindow", "AXApplication"])
        XCTAssertEqual(snapshot.ancestors.first?.domClasses, ["menu"], "a web node's ancestors keep their DOM handles")
        XCTAssertNil(snapshot.ancestors.first?.childCount)
        XCTAssertEqual(snapshot.siblings?.map(\.title), ["Pricing", "Docs"])
        XCTAssertNil(snapshot.siblings?.first?.domClasses, "neighbors are read light, as live")
        XCTAssertNil(snapshot.siblings?.first?.value)
        XCTAssertNil(snapshot.children)
        XCTAssertEqual(ElementResolver.resolve(snapshot)?.label, "Pricing")
    }

    func testANeighborThatIsATextWithNoOtherNameKeepsItsWords() {
        // The web area's children: the nav item, the text behind the menu, the scroll area.
        let around = page.snapshot(of: 2).children
        XCTAssertEqual(around?.map(\.value), [nil, .string("Body copy"), nil])
    }

    func testSnapshotOfAContainerListsItsChildren() {
        let snapshot = page.snapshot(of: 5)
        XCTAssertEqual(snapshot.children?.map(\.title), ["Pricing", "Docs"])
        XCTAssertNil(snapshot.siblings)
    }

    func testANodeBehindAnotherNormalWindowDidNotShow() {
        let own = Geometry.WindowRecord(ownerPID: 42, layer: 0, bounds: CGRect(x: 0, y: 0, width: 800, height: 600))
        let panel = Geometry.WindowRecord(ownerPID: 7, layer: 1000, bounds: CGRect(x: 0, y: 0, width: 400, height: 900))
        let foreign = Geometry.WindowRecord(ownerPID: 7, layer: 0, bounds: CGRect(x: 50, y: 50, width: 300, height: 300))
        let ownInFront = Geometry.WindowRecord(ownerPID: 42, layer: 0, bounds: CGRect(x: 60, y: 60, width: 200, height: 200))
        XCTAssertTrue(page.showed(6, among: [own]))
        XCTAssertTrue(page.showed(6, among: [panel, own]), "a transparent panel at the screen saver level hides nothing")
        XCTAssertFalse(page.showed(6, among: [foreign, own]), "another app's window lay in front")
        XCTAssertFalse(page.showed(6, among: [ownInFront, own]), "so did the app's own other window")
        XCTAssertTrue(page.showed(6, among: []), "a window the list does not have stands")
        XCTAssertTrue(page.showed(0, among: [foreign]), "a node outside any window stands")
    }

    func testPathRunsFromTheRoot() {
        XCTAssertEqual(page.path(to: 7), [0, 1, 2, 3, 5, 7])
    }

    func testDistance() {
        let frame = Frame(CGRect(x: 100, y: 100, width: 50, height: 50))
        XCTAssertEqual(TreeRecording.distance(from: CGPoint(x: 120, y: 120), to: frame), 0)
        XCTAssertEqual(TreeRecording.distance(from: CGPoint(x: 90, y: 120), to: frame), 10)
        XCTAssertEqual(TreeRecording.distance(from: CGPoint(x: 153, y: 154), to: frame), 5)
        XCTAssertEqual(TreeRecording.distance(from: CGPoint(x: 0, y: 0), to: nil), 0, "the application has no frame and is walked into")
    }

    func testADrawnFrameKeepsWhatLeftAndDropsWhatIsBehindIt() {
        let tree = page
        let live = [ElementSnapshot(element: tree.nodes[8].attributes, ancestors: []),  // behind the menu, partly outside it
                    ElementSnapshot(element: node("AXButton", CGRect(x: 120, y: 150, width: 60, height: 20), title: "Behind"), ancestors: []),
                    ElementSnapshot(element: tree.nodes[4].attributes, ancestors: [])]
        let recorded = [tree.regionSnapshot(of: 6), tree.regionSnapshot(of: 7)]
        let merged = TreeRecording.merged(live: live, recorded: recorded, under: [tree.nodes[5].attributes.frame!.cgRect])
        XCTAssertEqual(merged.map { $0.element.title ?? "text" }, ["text", "Products", "Pricing", "Docs"])
        XCTAssertEqual(TreeRecording.merged(live: live, recorded: [], under: []), live, "nothing recorded, nothing changes")
        XCTAssertEqual(recorded[0].ancestors.first?.title, nil)
        XCTAssertNil(recorded[0].element.value, "a drawn frame's elements are read light")
    }
}
