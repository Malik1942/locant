import AudioToolbox
import CoreGraphics
import XCTest
@testable import Locant

@MainActor
final class FeedbackTests: XCTestCase {
    /// The clock `Feedback.now` reads. Held here, not in a local: the closure is sendable, and a
    /// local it captures must not change afterwards.
    private var clock: TimeInterval = 100

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

    // R61: Trackpad taps is read at the moment of each tap. R59: the gate spaces them 80 ms.
    func testTapsFollowTheSwitchAndTheGate() {
        let preferences = Preferences(defaults: isolatedDefaults())
        let feedback = Feedback(preferences: preferences, bundle: Bundle(for: FeedbackTests.self))
        var tapped: [NSHapticFeedbackManager.FeedbackPattern] = []
        feedback.now = { self.clock }
        feedback.perform = { tapped.append($0) }
        feedback.tap(.alignment)
        clock += 0.050
        feedback.tap(.alignment) // inside 80 ms: dropped
        clock += 0.040
        feedback.tap(.levelChange) // 90 ms after the first
        preferences.trackpadTaps = false
        clock += 0.090
        feedback.tap(.generic) // switched off, and it leaves the gate alone: it never reached it
        preferences.trackpadTaps = true
        clock += 0.010
        feedback.tap(.generic) // 100 ms after the last tap that played, 10 after the switched-off one
        XCTAssertEqual(tapped, [.alignment, .levelChange, .generic])
    }

    // R59: a click is felt already, so the gate stays shut for 80 ms after it.
    func testAClickHoldsTheGate() {
        let feedback = Feedback(preferences: Preferences(defaults: isolatedDefaults()), bundle: Bundle(for: FeedbackTests.self))
        var taps = 0
        feedback.now = { self.clock }
        feedback.perform = { _ in taps += 1 }
        feedback.clicked()
        clock += 0.050
        feedback.tap(.alignment)
        XCTAssertEqual(taps, 0)
        clock += 0.040
        feedback.tap(.alignment)
        XCTAssertEqual(taps, 1)
    }

    // R59: only an outline actually drawn counts. An overlay that is not showing has no panel to
    // draw in, so it says false and nothing taps.
    func testAnOverlayWithNoPanelsDrawsNoOutline() {
        let overlay = SelectionOverlay()
        XCTAssertFalse(overlay.setHighlight(nil, readout: .describing(nil), around: .zero))
    }

    // R59: the same rule one layer down, where a drag or an adjustment also stops the drawing:
    // a content view with no window draws nothing, and says so.
    func testAContentViewWithNoWindowDrawsNoOutline() {
        let view = OverlayContentView(frame: .zero)
        XCTAssertFalse(view.showHighlight(screenRect: .zero, readout: .describing(nil)))
    }

    // R60: with no sound files (the test bundle has none) nothing loads and nothing plays.
    func testMissingSoundsPlayNothing() {
        let bundle = Bundle(for: FeedbackTests.self)
        for sound in Feedback.Sound.allCases {
            XCTAssertNil(Feedback.url(for: sound, in: bundle))
        }
        let feedback = Feedback(preferences: Preferences(defaults: isolatedDefaults()), bundle: bundle)
        var played = 0, tapped = 0
        feedback.playSound = { _ in played += 1 }
        feedback.perform = { _ in tapped += 1 }
        feedback.play(.landed)
        feedback.play(.missed)
        XCTAssertEqual(played, 0)
        XCTAssertEqual(tapped, 2, "the tap is the other channel: it plays even when the file is missing")
    }

    // R60: both sounds ship: mono, 48 kHz, 24-bit, no longer than 700 ms, and they load as system sounds.
    func testSoundsShipAndLoadAsSystemSounds() throws {
        for sound in Feedback.Sound.allCases {
            let url = try XCTUnwrap(Feedback.url(for: sound, in: .main), "\(sound).caf is not in the app bundle")
            var fileID: AudioFileID?
            XCTAssertEqual(AudioFileOpenURL(url as CFURL, .readPermission, kAudioFileCAFType, &fileID), 0)
            let file = try XCTUnwrap(fileID)
            defer { AudioFileClose(file) }
            var duration: Float64 = 0
            var size = UInt32(MemoryLayout<Float64>.size)
            XCTAssertEqual(AudioFileGetProperty(file, kAudioFilePropertyEstimatedDuration, &size, &duration), 0)
            XCTAssertLessThanOrEqual(duration, 0.700, "\(sound) runs \(duration) s")
            var format = AudioStreamBasicDescription()
            size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            XCTAssertEqual(AudioFileGetProperty(file, kAudioFilePropertyDataFormat, &size, &format), 0)
            XCTAssertEqual(format.mSampleRate, 48_000)
            XCTAssertEqual(format.mChannelsPerFrame, 1)
            XCTAssertEqual(format.mBitsPerChannel, 24)
            var id: SystemSoundID = 0
            XCTAssertEqual(AudioServicesCreateSystemSoundID(url as CFURL, &id), kAudioServicesNoError)
            AudioServicesDisposeSystemSoundID(id)
        }
    }

    // R59, R60: a capture is one event in two channels. Each channel follows its own switch; the
    // capture's tap ignores the 80 ms ratchet gate and then holds it, so no outline tap crowds it.
    func testACaptureMarksItselfInBothChannels() {
        let preferences = Preferences(defaults: isolatedDefaults())
        let feedback = Feedback(preferences: preferences)
        var tapped: [NSHapticFeedbackManager.FeedbackPattern] = []
        var played: [SystemSoundID] = []
        feedback.now = { self.clock }
        feedback.perform = { tapped.append($0) }
        feedback.playSound = { played.append($0) }

        feedback.tap(.alignment)
        clock += 0.010
        feedback.play(.landed)
        XCTAssertEqual(tapped, [.alignment, .generic], "the capture's mark does not wait for the gate")
        XCTAssertEqual(played.count, 1)

        clock += 0.075 // 85 ms after the outline tap, which the gate alone would let through; 75 after the mark
        feedback.tap(.alignment)
        XCTAssertEqual(tapped.count, 2, "the mark holds the gate, so the next outline tap is dropped")

        clock += 0.200
        preferences.sounds = false
        feedback.play(.missed)
        XCTAssertEqual(tapped.last, .levelChange, "with Sounds off the capture still marks itself")
        XCTAssertEqual(played.count, 1)

        clock += 0.200
        preferences.sounds = true
        preferences.trackpadTaps = false
        feedback.play(.missed)
        XCTAssertEqual(tapped.count, 3, "with Trackpad taps off the capture only sounds")
        XCTAssertEqual(played.count, 2)
        XCTAssertNotEqual(played.first, played.last, "landed and missed are two sounds")

        clock += 0.200
        preferences.sounds = false
        feedback.play(.landed)
        XCTAssertEqual(tapped.count, 3, "with both switches off the capture marks itself in neither channel")
        XCTAssertEqual(played.count, 2)
    }
}
