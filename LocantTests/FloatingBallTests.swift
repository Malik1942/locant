import XCTest
@testable import Locant

@MainActor
final class FloatingBallTests: XCTestCase {
    /// The built-in display's visible frame: the menu bar takes the top 37 pt.
    let builtIn = CGRect(x: 0, y: 0, width: 2056, height: 1292)
    /// The external display stacked above it (its own menu bar too).
    let upper = CGRect(x: -1038, y: 1329, width: 3360, height: 1853)
    let offset = FloatingBall.Tokens.pad + FloatingBall.Tokens.diameter / 2

    func testOriginOnAConnectedScreenIsKept() {
        let origin = CGPoint(x: 1500, y: 40)
        XCTAssertEqual(FloatingBall.onScreenOrigin(origin, screens: [builtIn]), origin)
        XCTAssertEqual(FloatingBall.onScreenOrigin(origin, screens: [builtIn, upper]), origin)
    }

    func testOriginOnTheSecondScreenIsKeptWhileItIsConnected() {
        let origin = CGPoint(x: 2207, y: 2102)
        XCTAssertEqual(FloatingBall.onScreenOrigin(origin, screens: [builtIn, upper]), origin)
    }

    func testOriginLeftOnADisconnectedScreenComesBackOntoTheNearestOne() {
        // Sep 14 2026: the disc sat at the right edge of the upper display after it was unplugged.
        let stale = CGPoint(x: 2207, y: 2102)
        let safe = FloatingBall.onScreenOrigin(stale, screens: [builtIn])
        let center = CGPoint(x: safe.x + offset, y: safe.y + offset)
        let radius = FloatingBall.Tokens.diameter / 2
        XCTAssertEqual(center.x, builtIn.maxX - radius, "pulled in from the right, the whole disc visible")
        XCTAssertEqual(center.y, builtIn.maxY - radius, "pulled down from above, the whole disc visible")
    }

    func testOffScreenOriginPicksTheNearestOfSeveralScreens() {
        // Above the upper display's top edge, roughly its middle: it belongs to that display.
        let stale = CGPoint(x: 500, y: 3400)
        let safe = FloatingBall.onScreenOrigin(stale, screens: [builtIn, upper])
        let center = CGPoint(x: safe.x + offset, y: safe.y + offset)
        XCTAssertEqual(center.x, 500 + offset)
        XCTAssertEqual(center.y, upper.maxY - FloatingBall.Tokens.diameter / 2)
    }

    func testDockedOriginPartlyOffTheEdgeStillCountsAsOnScreen() {
        let hidden = FloatingBall.Tokens.diameter * (1 - FloatingBall.Tokens.dockedVisible)
        let dockedLeft = CGPoint(x: builtIn.minX - FloatingBall.Tokens.pad - hidden, y: 600)
        let dockedBottom = CGPoint(x: 900, y: builtIn.minY - FloatingBall.Tokens.pad - hidden)
        XCTAssertEqual(FloatingBall.onScreenOrigin(dockedLeft, screens: [builtIn]), dockedLeft)
        XCTAssertEqual(FloatingBall.onScreenOrigin(dockedBottom, screens: [builtIn]), dockedBottom)
    }

    func testNoScreensLeavesTheOriginAlone() {
        let origin = CGPoint(x: -5000, y: -5000)
        XCTAssertEqual(FloatingBall.onScreenOrigin(origin, screens: []), origin)
    }

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
}
