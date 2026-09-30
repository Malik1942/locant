import XCTest
@testable import Locant

/// v0.9 R77: Snap and Cut end their ladder in the window.
final class SnapLadderTests: XCTestCase {
    private func element(_ role: String, _ frame: Frame) -> ResolvedElement {
        ResolvedElement(role: role, rawRole: "AX" + role.capitalized, label: nil, identifier: nil, identifierSource: .unknown, value: nil, frame: frame, path: [])
    }

    private let window = CGRect(x: 100, y: 100, width: 800, height: 600)

    // 1: the window comes after the elements, named after the app, with the window's bounds.
    func testWindowIsAppended() {
        let button = element("button", Frame(x: 120, y: 120, w: 80, h: 30))
        let toolbar = element("toolbar", Frame(x: 100, y: 100, w: 800, h: 52))
        let levels = HitRefiner.addingWindow([button, toolbar], window: window, appName: "Safari")
        XCTAssertEqual(levels.count, 3)
        XCTAssertEqual(levels[0]?.role, "button")
        XCTAssertEqual(levels[1]?.role, "toolbar")
        XCTAssertEqual(levels[2]?.role, "window")
        XCTAssertEqual(levels[2]?.label, "Safari")
        XCTAssertEqual(levels[2]?.frame, Frame(window))
        XCTAssertEqual(levels[2]?.path.map(\.role), ["window"])
    }

    // 2: no elements (a canvas): the window alone.
    func testEmptyLadderIsTheWindow() {
        let levels = HitRefiner.addingWindow([], window: window, appName: "Figma")
        XCTAssertEqual(levels.map { $0?.role }, ["window"])
    }

    // 3: a top rung that already spans the window is not doubled.
    func testSpanningTopRungIsNotDoubled() {
        let group = element("group", Frame(x: 101, y: 101, w: 798, h: 598))
        let levels = HitRefiner.addingWindow([element("button", Frame(x: 120, y: 120, w: 80, h: 30)), group], window: window, appName: "Mail")
        XCTAssertEqual(levels.map { $0?.role }, ["button", "group"])
    }

    // 4: no window (the desktop, the menu bar): the elements alone, empty rungs dropped.
    func testNoWindowLeavesTheElements() {
        let icon = element("image", Frame(x: 10, y: 10, w: 64, h: 64))
        XCTAssertEqual(HitRefiner.addingWindow([nil, icon], window: nil, appName: nil).map { $0?.role }, ["image"])
        XCTAssertEqual(HitRefiner.addingWindow([nil], window: nil, appName: nil).count, 0)
        XCTAssertEqual(HitRefiner.addingWindow([icon], window: .zero, appName: "Finder").map { $0?.role }, ["image"])
    }

    // 5: empty rungs go even when the window is appended.
    func testNilRungsAreDropped() {
        let levels = HitRefiner.addingWindow([nil, element("button", Frame(x: 120, y: 120, w: 80, h: 30))], window: window, appName: "Notes")
        XCTAssertEqual(levels.map { $0?.role }, ["button", "window"])
    }
}
