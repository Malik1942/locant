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

    // 3: a top rung that is the window itself is not doubled; a content group that only covers
    // most of it is not the window (no title bar, no toolbar), so the window is still appended.
    func testOnlyTheWindowItselfStandsInForTheWindow() {
        let button = element("button", Frame(x: 120, y: 120, w: 80, h: 30))
        let axWindow = element("window", Frame(x: 100, y: 100, w: 800, h: 600))
        XCTAssertEqual(HitRefiner.addingWindow([button, axWindow], window: window, appName: "Mail").map { $0?.role }, ["button", "window"])
        let offByOne = element("window", Frame(x: 100.5, y: 100, w: 800, h: 599.5))
        XCTAssertEqual(HitRefiner.addingWindow([button, offByOne], window: window, appName: "Mail").map { $0?.role }, ["button", "window"])
        let content = element("group", Frame(x: 100, y: 152, w: 800, h: 548))
        XCTAssertEqual(HitRefiner.addingWindow([button, content], window: window, appName: "Mail").map { $0?.role }, ["button", "group", "window"])
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

    // MARK: Device Hub (Xcode 27)

    private func fixture(_ name: String) throws -> ElementSnapshot {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"), "fixture \(name)")
        return try JSONDecoder().decode(ElementSnapshot.self, from: Data(contentsOf: url))
    }

    private let hubWindow = CGRect(x: 519, y: 182, width: 1100, height: 800)
    private let hubScreen = CGRect(x: 1043.81, y: 261.55, width: 298.89, height: 648.9)

    /// Device Hub draws the simulated device beside a sidebar and under a toolbar, where Simulator.app's
    /// window was the device; on the device, the ladder ends in its screen, as the window rung.
    func testDeviceHubLadderEndsInTheSimulatedScreen() throws {
        let snapshot = try fixture("devicehub-screen")
        let point = CGPoint(x: 1097.83, y: 460.28)
        XCTAssertEqual(HitRefiner.simulatedScreen(in: snapshot), hubScreen)
        let levels = HitRefiner.endingInScreen(HitRefiner.selectionLevels(for: snapshot, at: point), screen: hubScreen, appName: "Device Hub")
        XCTAssertEqual(levels.map { $0?.role }, ["button", "window"])
        XCTAssertEqual(levels[0]?.identifier, "oceanCurrent.product ideas")
        XCTAssertEqual(levels[1]?.frame, Frame(hubScreen))
        XCTAssertEqual(levels[1]?.label, "Device Hub")
        let whole = HitRefiner.addingWindow(HitRefiner.selectionLevels(for: snapshot, at: point), window: hubWindow, appName: "Device Hub")
        XCTAssertEqual(whole.last??.frame, Frame(hubWindow), "the window rung alone is Device Hub's 1100×800 window")
    }

    /// A blank spot of the screen hits the screen itself, which is then the whole ladder.
    func testBlankDeviceScreenIsTheScreen() throws {
        let snapshot = try fixture("devicehub-blank")
        XCTAssertEqual(HitRefiner.simulatedScreen(in: snapshot), hubScreen)
        let levels = HitRefiner.endingInScreen(HitRefiner.selectionLevels(for: snapshot, at: CGPoint(x: 1063.81, y: 291.55)),
                                               screen: hubScreen, appName: "Device Hub")
        XCTAssertEqual(levels.map { $0?.role }, ["window"])
        XCTAssertEqual(levels[0]?.frame, Frame(hubScreen))
    }

    /// The sidebar and the toolbar are Device Hub's own: no screen, so the window as everywhere else.
    func testDeviceHubSidebarHasNoSimulatedScreen() throws {
        XCTAssertNil(HitRefiner.simulatedScreen(in: try fixture("devicehub-sidebar")))
    }
}
