import CoreGraphics
import XCTest
@testable import Locant

final class GeometryTests: XCTestCase {
    let primaryHeight: CGFloat = 1329

    // 1
    func testPointFlipRoundTrips() {
        let appKit = CGPoint(x: 228, y: 402)
        let cg = Geometry.cgPoint(fromAppKit: appKit, primaryHeight: primaryHeight)
        XCTAssertEqual(cg, CGPoint(x: 228, y: 927))
        XCTAssertEqual(Geometry.appKitPoint(fromCG: cg, primaryHeight: primaryHeight), appKit)
    }

    // 2
    func testRectFlip() {
        let cg = CGRect(x: 43, y: 893, width: 370, height: 50)
        let appKit = Geometry.appKitRect(fromCG: cg, primaryHeight: primaryHeight)
        XCTAssertEqual(appKit, CGRect(x: 43, y: 1329 - 943, width: 370, height: 50))
        XCTAssertEqual(Geometry.cgRect(fromAppKit: appKit, primaryHeight: primaryHeight), cg)
    }

    // 3
    func testCropPadsAndClampsToWindowThenDisplay() {
        let display = CGRect(x: 0, y: 0, width: 2056, height: 1329)
        let window = CGRect(x: 0, y: 101, width: 456, height: 972)
        let element = CGRect(x: 43, y: 893, width: 370, height: 50)
        let crop = Geometry.cropRect(element: element, clickPoint: .zero, window: window, display: display)
        // x clamps at the window's left edge (43 - 40 = 3 stays inside), right edge 413 + 40 = 453 stays inside
        XCTAssertEqual(crop, CGRect(x: 3, y: 853, width: 450, height: 130))

        let nearEdge = CGRect(x: 10, y: 110, width: 100, height: 20)
        let clamped = Geometry.cropRect(element: nearEdge, clickPoint: .zero, window: window, display: display)
        XCTAssertEqual(clamped, CGRect(x: 0, y: 101, width: 150, height: 69))

        let noElement = Geometry.cropRect(element: nil, clickPoint: CGPoint(x: 228, y: 927), window: window, display: display)
        XCTAssertEqual(noElement, CGRect(x: 128, y: 827, width: 200, height: 200))

        let topOfDisplay = Geometry.cropRect(element: CGRect(x: 100, y: 0, width: 50, height: 10), clickPoint: .zero, window: nil, display: display)
        XCTAssertEqual(topOfDisplay, CGRect(x: 60, y: 0, width: 130, height: 50))
    }

    // 4
    func testPixelRectOnSecondaryDisplayWithNegativeOrigin() {
        let secondary = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let rect = CGRect(x: -1000, y: 300, width: 200, height: 100)
        XCTAssertEqual(Geometry.displayLocalRect(rect, inDisplay: secondary), CGRect(x: 920, y: 500, width: 200, height: 100))
        XCTAssertEqual(Geometry.pixelRect(rect, inDisplay: secondary, scale: 2), CGRect(x: 1840, y: 1000, width: 400, height: 200))
    }

    // 5
    func testWindowHitTestSkipsOwnWindowsAndNonZeroLayers() {
        let point = CGPoint(x: 228, y: 927)
        let windows: [Geometry.WindowRecord] = [
            .init(ownerPID: 999, layer: 1000, bounds: CGRect(x: 0, y: 0, width: 2056, height: 1329)), // Locant overlay
            .init(ownerPID: 500, layer: 25, bounds: CGRect(x: 0, y: 0, width: 2056, height: 24)),     // menu bar
            .init(ownerPID: 45450, layer: 0, bounds: CGRect(x: 0, y: 101, width: 456, height: 972)),  // Simulator
            .init(ownerPID: 777, layer: 0, bounds: CGRect(x: 0, y: 0, width: 2056, height: 1329)),   // app behind
        ]
        XCTAssertEqual(Geometry.windowOwner(at: point, windows: windows, excludingPID: 999)?.ownerPID, 45450)
        XCTAssertEqual(Geometry.windowOwner(at: CGPoint(x: 1500, y: 700), windows: windows, excludingPID: 999)?.ownerPID, 777)
        XCTAssertNil(Geometry.windowOwner(at: point, windows: [windows[0], windows[1]], excludingPID: 999))
    }

    // 6: desktop icons, widgets, and status items live in other layers. Candidates keep every layer,
    // front to back, so the reader can ask the Dock, then the app, then Finder, in that order.
    func testWindowCandidatesKeepEveryLayerFrontToBackExceptOwn() {
        let screen = CGRect(x: 0, y: 0, width: 2056, height: 1329)
        let windows: [Geometry.WindowRecord] = [
            .init(ownerPID: 999, layer: 1000, bounds: screen),                                          // Locant overlay
            .init(ownerPID: 1109, layer: 25, bounds: CGRect(x: 1783, y: 0, width: 38, height: 39)),     // Wi-Fi status item
            .init(ownerPID: 4242, layer: 24, bounds: CGRect(x: 0, y: 0, width: 2056, height: 39)),      // menu bar, credited to its owner
            .init(ownerPID: 1282, layer: 20, bounds: screen),                                           // Dock (screen-wide)
            .init(ownerPID: 45450, layer: 0, bounds: CGRect(x: 0, y: 101, width: 456, height: 972)),    // Simulator
            .init(ownerPID: 1112, layer: -2147483601, bounds: CGRect(x: 8, y: 47, width: 180, height: 180)), // widget
            .init(ownerPID: 1284, layer: -2147483603, bounds: screen),                                  // Finder desktop
        ]
        let inSimulator = Geometry.windowCandidates(at: CGPoint(x: 100, y: 150), windows: windows, excludingPID: 999)
        XCTAssertEqual(inSimulator.map(\.ownerPID), [1282, 45450, 1112, 1284], "the widget is behind the Simulator window")
        let onDesktop = Geometry.windowCandidates(at: CGPoint(x: 1500, y: 700), windows: windows, excludingPID: 999)
        XCTAssertEqual(onDesktop.map(\.ownerPID), [1282, 1284])
        let onWiFi = Geometry.windowCandidates(at: CGPoint(x: 1800, y: 20), windows: windows, excludingPID: 999)
        XCTAssertEqual(onWiFi.map(\.ownerPID), [1109, 4242, 1282, 1284])
        let onMenuTitle = Geometry.windowCandidates(at: CGPoint(x: 80, y: 20), windows: windows, excludingPID: 999)
        XCTAssertEqual(onMenuTitle.map(\.ownerPID), [4242, 1282, 1284])
        XCTAssertEqual(Geometry.windowOwner(at: CGPoint(x: 1500, y: 700), windows: windows, excludingPID: 999), nil, "Snap and Cut still take normal windows only")
    }

    // 7: an owner's answer counts only when it shows at the point. Wispr Flow keeps a transparent
    // 490×1144 panel at layer 1000 over the left of the screen, so it is asked first over the Device
    // Hub window; it answers with its menu bar, or with a button of its own window behind Device Hub.
    func testAnswerCountsOnlyWhenItShowsAtThePoint() {
        let wispr: pid_t = 65585, deviceHub: pid_t = 63568
        let wisprWindow = CGRect(x: 353, y: 136, width: 1350, height: 850)
        let deviceHubWindow = CGRect(x: 168, y: 235, width: 470, height: 1000)
        let candidates: [Geometry.WindowRecord] = [
            .init(ownerPID: wispr, layer: 1000, bounds: CGRect(x: 0, y: 86, width: 490, height: 1144)), // transparent panel
            .init(ownerPID: 1282, layer: 20, bounds: CGRect(x: 0, y: 0, width: 2056, height: 1329)),    // Dock (screen-wide)
            .init(ownerPID: deviceHub, layer: 0, bounds: deviceHubWindow),
            .init(ownerPID: 64769, layer: 0, bounds: CGRect(x: 12, y: 65, width: 1795, height: 1199)),  // an app behind
            .init(ownerPID: wispr, layer: 0, bounds: wisprWindow),
        ]
        let orb = CGPoint(x: 280, y: 555), card = CGPoint(x: 402, y: 461)
        let menuBar = CGRect(x: 0, y: 0, width: 2056, height: 39)
        XCTAssertFalse(Geometry.answerIsVisible(frame: menuBar, window: nil, owner: wispr, at: orb, candidates: candidates),
                       "the menu bar is not at the point")
        XCTAssertFalse(Geometry.answerIsVisible(frame: CGRect(x: 365, y: 459, width: 192, height: 36), window: wisprWindow, owner: wispr, at: card, candidates: candidates),
                       "Device Hub's window covers Wispr Flow's there")
        XCTAssertTrue(Geometry.answerIsVisible(frame: CGRect(x: 252, y: 527, width: 56, height: 99), window: deviceHubWindow, owner: deviceHub, at: orb, candidates: candidates))
        XCTAssertTrue(Geometry.answerIsVisible(frame: CGRect(x: 405, y: 465, width: 50, height: 10), window: nil, owner: deviceHub, at: card, candidates: candidates),
                      "within the hover tolerance of its frame")
        // A sheet or popover is a window of its own app in front of the app's window: its own.
        let sheet = CGRect(x: 200, y: 400, width: 400, height: 200)
        let withSheet = [Geometry.WindowRecord(ownerPID: deviceHub, layer: 0, bounds: sheet)] + candidates
        XCTAssertTrue(Geometry.answerIsVisible(frame: CGRect(x: 380, y: 450, width: 60, height: 30), window: sheet, owner: deviceHub, at: card, candidates: withSheet))
        // What cannot be read stands, as before: no frame, no window, a window not under the point.
        XCTAssertTrue(Geometry.answerIsVisible(frame: nil, window: nil, owner: wispr, at: card, candidates: candidates))
        XCTAssertTrue(Geometry.answerIsVisible(frame: CGRect(x: 380, y: 450, width: 40, height: 20), window: CGRect(x: 900, y: 900, width: 200, height: 100), owner: deviceHub, at: card, candidates: candidates))
    }
}
