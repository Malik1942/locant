import XCTest
@testable import Locant

/// specs/ball-edges.md R88, on the same display as `BallEdgesTests`.
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
