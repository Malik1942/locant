import XCTest
@testable import Locant

/// specs/ball-edges.md R85, on Malik's built-in display: 2056×1329, the Dock at the bottom with its
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
