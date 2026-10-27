import AppKit
import XCTest
@testable import Locant

/// specs/capture-shapes.md R127: lines of text read in the background, once per rectangle and its pixels, one
/// read at a time, dropped on stop. Every test but the last answers with a stand-in for Vision.
@MainActor
final class TextLineReaderTests: XCTestCase {
    private actor Calls {
        var frames: [CGRect] = []
        var cjk: [Bool] = []
        func add(_ frame: CGRect, cjk flag: Bool) {
            frames.append(frame)
            cjk.append(flag)
        }
        var count: Int { frames.count }
    }

    /// Holds a read until the test opens it.
    private actor Gate {
        private var open = false
        private var waiting: [CheckedContinuation<Void, Never>] = []
        func wait() async {
            if open { return }
            await withCheckedContinuation { waiting.append($0) }
        }
        func release() {
            open = true
            for continuation in waiting { continuation.resume() }
            waiting = []
        }
    }

    private struct Refused: Error {}

    /// A reader whose recognizer records the rectangle it was shown, runs `before` (which can hold it or
    /// throw), and reads one line filling that rectangle.
    private func makeReader(calls: Calls, before: @escaping @Sendable (CGRect) async throws -> Void = { _ in }) -> TextLineReader {
        TextLineReader(recognize: { _, frame, cjk in
            await calls.add(frame, cjk: cjk)
            try await before(frame)
            return [TextLine(text: "line", frame: Frame(frame))]
        })
    }

    /// The simulated screen's sample at 2x: one dark gray, with `marks` painted light.
    private let screen = CGRect(x: 300, y: 100, width: 120, height: 80)

    private func sample(generation: Int, marks: [CGRect] = []) -> PixelGrid {
        let width = Int(screen.width) * 2, height = Int(screen.height) * 2
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let p = CGPoint(x: screen.minX + (CGFloat(x) + 0.5) / 2, y: screen.minY + (CGFloat(y) + 0.5) / 2)
                let level: UInt8 = marks.contains { $0.contains(p) } ? 220 : 30
                let i = (y * width + x) * 4
                bytes[i] = level
                bytes[i + 1] = level
                bytes[i + 2] = level
            }
        }
        return PixelGrid(frame: screen, scale: 2, width: width, height: height, bytes: bytes, generation: generation)
    }

    private let a = CGRect(x: 310, y: 110, width: 40, height: 20)
    private let b = CGRect(x: 360, y: 110, width: 40, height: 20)
    private let c = CGRect(x: 310, y: 140, width: 40, height: 20)

    func testBeforeStartNothingIsRead() async throws {
        let calls = Calls()
        let reader = makeReader(calls: calls)
        XCTAssertNil(reader.lines(in: a, of: sample(generation: 1)))
        try await Task.sleep(for: .milliseconds(100))
        let count = await calls.count
        XCTAssertEqual(count, 0)
    }

    func testLinesAreReadOncePerRectangleAndItsPixels() async throws {
        let calls = Calls()
        let reader = makeReader(calls: calls)
        reader.start()
        var updates = 0
        let landed = expectation(description: "lines")
        reader.onUpdate = {
            updates += 1
            landed.fulfill()
        }
        let first = sample(generation: 1)
        XCTAssertNil(reader.lines(in: a, of: first))
        XCTAssertNil(reader.lines(in: a, of: first), "asked once")
        await fulfillment(of: [landed], timeout: 2)
        let read = [TextLine(text: "line", frame: Frame(a))]
        XCTAssertEqual(reader.lines(in: a, of: first), read)

        // The sample's refresh: a new sample, with the same pixels inside the rectangle (a change outside it).
        XCTAssertEqual(reader.lines(in: a, of: sample(generation: 2, marks: [b])), read)
        try await Task.sleep(for: .milliseconds(100)) // settle: nothing more is read
        var count = await calls.count
        XCTAssertEqual(count, 1)
        XCTAssertEqual(updates, 1)

        // Changed pixels inside it: read again.
        let again = expectation(description: "lines again")
        reader.onUpdate = {
            updates += 1
            again.fulfill()
        }
        let changed = sample(generation: 3, marks: [CGRect(x: 320, y: 115, width: 10, height: 5)])
        XCTAssertNil(reader.lines(in: a, of: changed))
        await fulfillment(of: [again], timeout: 2)
        XCTAssertEqual(reader.lines(in: a, of: changed), read)
        count = await calls.count
        XCTAssertEqual(count, 2)
        XCTAssertEqual(updates, 2, "once per landing")
        reader.stop()
    }

    func testOfTheRequestsThatComeDuringAReadOnlyTheNewestWaits() async throws {
        let calls = Calls()
        let gate = Gate()
        let held = a
        let reader = makeReader(calls: calls, before: { frame in
            if frame == held { await gate.wait() }
        })
        reader.start()
        var updates = 0
        let landed = expectation(description: "two reads")
        landed.expectedFulfillmentCount = 2
        reader.onUpdate = {
            updates += 1
            landed.fulfill()
        }
        let grid = sample(generation: 1)
        XCTAssertNil(reader.lines(in: a, of: grid)) // read, and held
        XCTAssertNil(reader.lines(in: b, of: grid)) // waits
        XCTAssertNil(reader.lines(in: c, of: grid)) // waits instead
        await gate.release()
        await fulfillment(of: [landed], timeout: 2)
        try await Task.sleep(for: .milliseconds(100)) // settle: b is never read
        let frames = await calls.frames
        XCTAssertEqual(frames, [a, c])
        XCTAssertEqual(updates, 2)
        XCTAssertNotNil(reader.lines(in: a, of: grid))
        XCTAssertNotNil(reader.lines(in: c, of: grid))
        reader.stop()
    }

    func testStopDropsAReadStillRunning() async throws {
        let calls = Calls()
        let gate = Gate()
        let reached = expectation(description: "the read reached the gate")
        reached.assertForOverFulfill = false
        let reader = makeReader(calls: calls, before: { _ in
            reached.fulfill()
            await gate.wait()
        })
        reader.start()
        var updates = 0
        reader.onUpdate = { updates += 1 }
        let grid = sample(generation: 1)
        XCTAssertNil(reader.lines(in: a, of: grid))
        await fulfillment(of: [reached], timeout: 2)
        reader.stop()
        XCTAssertNil(reader.lines(in: a, of: grid), "stopped: nothing is asked")
        reader.start()
        await gate.release() // the read finishes now, into a session that is over
        try await Task.sleep(for: .milliseconds(200)) // settle: it lands nowhere
        XCTAssertEqual(updates, 0)

        let landed = expectation(description: "the new session's read")
        reader.onUpdate = {
            updates += 1
            landed.fulfill()
        }
        XCTAssertNil(reader.lines(in: a, of: grid), "its lines were dropped, so they are asked for again")
        await fulfillment(of: [landed], timeout: 2)
        XCTAssertEqual(updates, 1)
        let count = await calls.count
        XCTAssertEqual(count, 2)
        XCTAssertNotNil(reader.lines(in: a, of: grid))
        reader.stop()
    }

    func testAFailedReadIsNotAnUpdateNorTriedAgainOnTheSamePixels() async throws {
        let calls = Calls()
        let reader = makeReader(calls: calls, before: { _ in throw Refused() })
        reader.start()
        reader.onUpdate = { XCTFail("a failed read is not an update") }
        let grid = sample(generation: 1)
        XCTAssertNil(reader.lines(in: a, of: grid))
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(reader.lines(in: a, of: grid), [], "no lines there")
        let count = await calls.count
        XCTAssertEqual(count, 1)
        reader.stop()
    }

    func testALabelWithCJKCharactersAsksForTheirRead() async {
        XCTAssertTrue(TextLineReader.holdsCJK("周末面条, 昨天"))
        XCTAssertTrue(TextLineReader.holdsCJK("カード"))
        XCTAssertFalse(TextLineReader.holdsCJK("Weeknight noodles, yesterday"))
        XCTAssertFalse(TextLineReader.holdsCJK(nil))
        let calls = Calls()
        let reader = makeReader(calls: calls)
        reader.start()
        let grid = sample(generation: 1)
        let chinese = expectation(description: "the read for a label in Chinese")
        reader.onUpdate = { chinese.fulfill() }
        XCTAssertNil(reader.lines(in: a, of: grid, label: "周末面条, 昨天"))
        await fulfillment(of: [chinese], timeout: 2)
        let english = expectation(description: "the read for a label in English")
        reader.onUpdate = { english.fulfill() }
        XCTAssertNil(reader.lines(in: b, of: grid, label: "Weeknight noodles, yesterday"))
        await fulfillment(of: [english], timeout: 2)
        let flags = await calls.cjk
        XCTAssertEqual(flags, [true, false])
        reader.stop()
    }

    func testVisionsBoxIsPlacedInGlobalPoints() {
        // Vision's box has its origin at the bottom left of the image, which shows (100, 200) 300×80.
        let frame = TextLineReader.globalFrame(of: CGRect(x: 0.1, y: 0.5, width: 0.5, height: 0.25), in: CGRect(x: 100, y: 200, width: 300, height: 80))
        XCTAssertEqual(frame.x, 130, accuracy: 1e-9)
        XCTAssertEqual(frame.y, 220, accuracy: 1e-9)
        XCTAssertEqual(frame.w, 150, accuracy: 1e-9)
        XCTAssertEqual(frame.h, 20, accuracy: 1e-9)
    }

    func testACutIsTheSamplesTheRectangleCoversWithTheirOwnBytes() throws {
        let mark = CGRect(x: 320, y: 115, width: 10, height: 5)
        let grid = sample(generation: 1, marks: [mark])
        let cut = try XCTUnwrap(grid.image(of: CGRect(x: 310.2, y: 110, width: 40, height: 20)))
        XCTAssertEqual(cut.frame, CGRect(x: 310, y: 110, width: 40.5, height: 20), "out to whole samples")
        XCTAssertEqual(cut.image.width, 81)
        XCTAssertEqual(cut.image.height, 40)
        let back = try XCTUnwrap(PixelGrid(image: cut.image, frame: cut.frame, scale: 2, generation: 0))
        for (x, y) in [(0, 0), (20, 10), (25, 12), (80, 39)] {
            XCTAssertEqual(back.color(x: x, y: y), grid.color(x: x + 20, y: y + 20), "sample \(x), \(y)")
        }
        XCTAssertEqual(back.color(x: 20, y: 10).r, 220, "inside the mark")
        XCTAssertEqual(back.color(x: 0, y: 0).r, 30)

        XCTAssertEqual(grid.image(of: CGRect(x: 400, y: 170, width: 50, height: 50))?.frame, CGRect(x: 400, y: 170, width: 20, height: 10),
                       "cut to the sample")
        XCTAssertNil(grid.image(of: CGRect(x: 0, y: 0, width: 10, height: 10)), "off the sample")
        XCTAssertNil(grid.image(of: .infinite))
        XCTAssertNil(grid.image(of: CGRect(x: CGFloat.nan, y: 110, width: 40, height: 20)))
    }

    /// The one test that runs Vision: two lines drawn with AppKit at 2x, cut from the sample as hover cuts
    /// an element, come back as two lines where they were drawn, within 3 pt.
    func testVisionReadsTwoDrawnLinesWhereTheyAre() throws {
        let area = CGRect(x: 1000, y: 500, width: 320, height: 100) // the sample, in global points
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 200, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = NSSize(width: 320, height: 100)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 320, height: 100).fill()
        // AppKit's origin is at the bottom left, so the first line is drawn higher.
        NSAttributedString(string: "Weeknight noodles", attributes: [
            .font: NSFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: NSColor.black,
        ]).draw(at: NSPoint(x: 30, y: 58))
        NSAttributedString(string: "Seven minutes ahead", attributes: [
            .font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.darkGray,
        ]).draw(at: NSPoint(x: 30, y: 24))
        NSGraphicsContext.restoreGraphicsState()
        let grid = try XCTUnwrap(PixelGrid(image: try XCTUnwrap(rep.cgImage), frame: area, scale: 2, generation: 1))

        /// Where a line was drawn: the bounds, in global points, of the dark samples in rows `band`.
        func drawn(_ band: ClosedRange<Int>) -> CGRect {
            var box = SampleBox(minX: .max, minY: .max, maxX: .min, maxY: .min)
            for y in band {
                for x in 0..<grid.width where grid.color(x: x, y: y).r < 160 {
                    box = SampleBox(minX: min(box.minX, x), minY: min(box.minY, y), maxX: max(box.maxX, x), maxY: max(box.maxY, y))
                }
            }
            return grid.rect(of: box)
        }
        let expected = [drawn(0...95), drawn(96...199)]

        let element = CGRect(x: 1010, y: 505, width: 300, height: 90) // the answer, inside the sample
        let cut = try XCTUnwrap(grid.image(of: element))
        let clock = ContinuousClock()
        var lines: [TextLine] = []
        let cold = try clock.measure { lines = try TextLineReader.read(cut.image, showing: cut.frame, cjk: false) }
        let warm = try clock.measure { _ = try TextLineReader.read(cut.image, showing: cut.frame, cjk: false) }
        NSLog("Locant text lines (test, .fast): cold %.1f ms, warm %.1f ms; read %@; drawn %@",
              cold / .milliseconds(1), warm / .milliseconds(1), "\(lines)", "\(expected)")

        XCTAssertEqual(lines.count, 2, "\(lines)")
        XCTAssertEqual(lines.map { $0.text.lowercased() }, ["weeknight noodles", "seven minutes ahead"])
        for (line, box) in zip(lines, expected) {
            let found = line.frame.cgRect
            for (a, b) in [(found.minX, box.minX), (found.minY, box.minY), (found.maxX, box.maxX), (found.maxY, box.maxY)] {
                XCTAssertEqual(a, b, accuracy: 3, "\(line.text): \(found) vs drawn \(box)")
            }
        }
    }
}
