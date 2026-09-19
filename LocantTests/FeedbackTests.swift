import CoreGraphics
import XCTest
@testable import Locant

@MainActor
final class FeedbackTests: XCTestCase {
    // v0.8.1 R59: one tap per 80 ms, measured from the last tap let through; either side of the edge.
    func testTapGateSpacesTapsEightyMillisecondsApart() {
        var gate = TapGate(spacing: 0.080)
        XCTAssertTrue(gate.admit(at: 10.0))
        XCTAssertFalse(gate.admit(at: 10.0799))
        XCTAssertTrue(gate.admit(at: 10.0801))
        XCTAssertFalse(gate.admit(at: 10.1))
    }

    // R59: a dropped tap does not restart the interval, so a steady sweep keeps its rhythm.
    func testTapGateDroppedTapsDoNotRestartTheInterval() {
        var gate = TapGate(spacing: 0.080)
        XCTAssertTrue(gate.admit(at: 1.00))
        XCTAssertFalse(gate.admit(at: 1.05))
        XCTAssertTrue(gate.admit(at: 1.10), "100 ms after the last tap played, 50 ms after the dropped one")
    }

    // R59: hover redraws about every 33 ms; a sweep across small elements taps every third
    // redraw, evenly: a ratchet, not a buzz, not silence.
    func testTapGateAtHoverRateIsAnEvenRatchet() {
        var gate = TapGate(spacing: 0.080)
        let played = (0..<30).map { Double($0) * 0.033 }.filter { gate.admit(at: $0) }
        XCTAssertEqual(played.count, 10)
        for (a, b) in zip(played, played.dropFirst()) {
            XCTAssertEqual(b - a, 0.099, accuracy: 0.0001)
        }
    }

    // R59: a hold shuts the gate for 80 ms from the hold, as a tap would, without one.
    func testTapGateHoldShutsItFromTheHold() {
        var gate = TapGate(spacing: 0.080)
        XCTAssertTrue(gate.admit(at: 1.000))
        gate.hold(at: 1.030)
        XCTAssertFalse(gate.admit(at: 1.090), "90 ms after the tap, but 60 after the hold")
        XCTAssertTrue(gate.admit(at: 1.111))
    }

    // R59: the first outline is not a move; another frame is; the same frame again is not.
    func testOutlineMovesBetweenFrames() {
        var outline = OutlineMoves()
        let a = CGRect(x: 10, y: 10, width: 40, height: 20)
        let b = CGRect(x: 60, y: 10, width: 40, height: 20)
        XCTAssertFalse(outline.moved(to: a), "the first outline after the overlay opens")
        XCTAssertFalse(outline.moved(to: a))
        XCTAssertTrue(outline.moved(to: b))
        XCTAssertTrue(outline.moved(to: a))
    }

    // R59: onto the no-element square (nil) is not a move; off it onto an element is, even
    // when the square was the first outline or the element is the one before the square.
    func testOutlineMovesAroundTheNoElementSquare() {
        var outline = OutlineMoves()
        let a = CGRect(x: 10, y: 10, width: 40, height: 20)
        XCTAssertFalse(outline.moved(to: nil))
        XCTAssertTrue(outline.moved(to: a))
        XCTAssertFalse(outline.moved(to: nil))
        XCTAssertTrue(outline.moved(to: a))
        XCTAssertFalse(outline.moved(to: a))
    }

    // R59: an edge that shifts 2 pt or less, as a web card lifting under the pointer, is the
    // same outline; 3 pt is a move.
    func testOutlineMovesIgnoresADriftOfTwoPoints() {
        var outline = OutlineMoves()
        let card = CGRect(x: 100, y: 100, width: 200, height: 120)
        XCTAssertFalse(outline.moved(to: card))
        XCTAssertFalse(outline.moved(to: card.offsetBy(dx: 0, dy: -2)), "lifted 2 pt")
        XCTAssertFalse(outline.moved(to: card), "settled back")
        XCTAssertTrue(outline.moved(to: card.offsetBy(dx: 3, dy: 0)), "3 pt is a move")
    }
}
