import AppKit
import XCTest
@testable import Locant

/// specs/capture-shapes.md R127: lines of text read in the background, once per rectangle and its pixels, one
/// read at a time, dropped on stop. Every test but the last answers with a stand-in for Vision.
@MainActor
final class TextLineReaderTests: XCTestCase {
    private actor Calls {
        var frames: [CGRect] = []
        var readings: [TextLineReader.Reading] = []
        /// Records a read; its number, from 1.
        func add(_ frame: CGRect, reading: TextLineReader.Reading) -> Int {
            frames.append(frame)
            readings.append(reading)
            return frames.count
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

    /// Two lines in the top and bottom halves of `frame`, as a card's title and date.
    private nonisolated static func two(in frame: CGRect) -> [TextLine] {
        let (top, bottom) = frame.divided(atDistance: frame.height / 2, from: .minYEdge)
        return [TextLine(text: "title", frame: Frame(top)), TextLine(text: "date", frame: Frame(bottom))]
    }

    /// A reader whose recognizer records the rectangle it was shown, runs `before` (which can hold it or
    /// throw), and reads what `lines` gives for the read's number (from 1): by default two lines in it.
    private func makeReader(calls: Calls, before: @escaping @Sendable (CGRect) async throws -> Void = { _ in },
                            lines: @escaping @Sendable (Int, CGRect) -> [TextLine] = { _, frame in two(in: frame) }) -> TextLineReader {
        TextLineReader(recognize: { _, frame, reading in
            let number = await calls.add(frame, reading: reading)
            try await before(frame)
            return lines(number, frame)
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
        let read = Self.two(in: a)
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
        XCTAssertEqual(reader.lines(in: a, of: changed), read, "asked again; the lines last read stand meanwhile")
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

    func testARequestForTheRectangleInFlightOrWaitingIsNotAskedTwice() async throws {
        let calls = Calls()
        let gate = Gate()
        let held = a
        let reader = makeReader(calls: calls, before: { frame in
            if frame == held { await gate.wait() }
        })
        reader.start()
        let landed = expectation(description: "two reads")
        landed.expectedFulfillmentCount = 2
        reader.onUpdate = { landed.fulfill() }
        let grid = sample(generation: 1)
        for area in [a, a, b, b] {
            XCTAssertNil(reader.lines(in: area, of: grid)) // a in flight, then b waiting, each asked twice
        }
        await gate.release()
        await fulfillment(of: [landed], timeout: 2)
        try await Task.sleep(for: .milliseconds(100)) // settle: nothing more is read
        let frames = await calls.frames
        XCTAssertEqual(frames, [a, b])
        reader.stop()
    }

    func testAReadOfOneLineOrNoneIsNoUpdate() async throws {
        let calls = Calls()
        let reader = makeReader(calls: calls, lines: { number, frame in
            number == 1 ? [TextLine(text: "Library", frame: Frame(frame))] : []
        })
        reader.start()
        reader.onUpdate = { XCTFail("one line or none makes no rung, so it is no update") }
        let grid = sample(generation: 1)
        XCTAssertNil(reader.lines(in: a, of: grid))
        XCTAssertNil(reader.lines(in: b, of: grid)) // waits
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(reader.lines(in: a, of: grid)?.map(\.text), ["Library"])
        XCTAssertEqual(reader.lines(in: b, of: grid), [])
        let count = await calls.count
        XCTAssertEqual(count, 2)
        reader.stop()
    }

    /// A card whose date ticks: its pixels and its label (the texts it merges) change in the same step. The lines
    /// last read in its frame stand while the new ones are read, since the new label shares a part with the old,
    /// so its line does not drop to the card and back; never for an element whose label shares no part.
    func testWhileChangedPixelsAreReadTheElementsLastLinesStand() async throws {
        let calls = Calls()
        let gate = Gate()
        let reader = makeReader(calls: calls, before: { _ in
            if await calls.count == 2 { await gate.wait() } // the second read is held
        }, lines: { number, frame in
            number == 2 ? [TextLine(text: "title", frame: Frame(frame))] : Self.two(in: frame)
        })
        reader.start()
        var updates = 0
        let first = expectation(description: "the first read")
        reader.onUpdate = {
            updates += 1
            first.fulfill()
        }
        let card = "Random, 4 seconds ago"
        XCTAssertNil(reader.lines(in: a, of: sample(generation: 1), label: card))
        await fulfillment(of: [first], timeout: 2)

        let ticked = sample(generation: 2, marks: [CGRect(x: 320, y: 125, width: 10, height: 4)])
        let later = "Random, 5 seconds ago"
        XCTAssertEqual(reader.lines(in: a, of: ticked, label: later), Self.two(in: a),
                       "the label ticked with the pixels: the lines last read stand while the new pixels are read")
        XCTAssertEqual(reader.lines(in: a, of: ticked, label: card), Self.two(in: a))
        XCTAssertNil(reader.lines(in: a, of: ticked, label: "Weeknight noodles, yesterday"), "never for a label that shares no part")
        XCTAssertNil(reader.lines(in: a, of: ticked, label: nil), "nor for no label")

        let second = expectation(description: "the second read, of one line")
        reader.onUpdate = {
            updates += 1
            second.fulfill()
        }
        await gate.release()
        await fulfillment(of: [second], timeout: 2)
        XCTAssertEqual(updates, 2, "one line where two stood is an update, so the line's rung goes")
        XCTAssertEqual(reader.lines(in: a, of: ticked, label: later)?.count, 1)
        let count = await calls.count
        XCTAssertEqual(count, 2)

        reader.onUpdate = nil
        reader.stop()
        reader.start()
        XCTAssertNil(reader.lines(in: a, of: sample(generation: 3), label: card), "stopped: nothing last read stands")
        reader.stop()
    }

    func testTheReadingIsDecidedFromTheLabel() {
        XCTAssertEqual(TextLineReader.reading(for: "Weeknight noodles, yesterday"), .latin)
        XCTAssertEqual(TextLineReader.reading(for: "Café, 4 seconds ago"), .latin)
        XCTAssertEqual(TextLineReader.reading(for: nil), .latin)
        XCTAssertEqual(TextLineReader.reading(for: "周末面条, 昨天"), .han)
        XCTAssertEqual(TextLineReader.reading(for: "Product 想法, 4 秒前"), .han, "Han with Latin")
        XCTAssertEqual(TextLineReader.reading(for: "约翰・史密斯, 昨天"), .han, "a transliterated name's middle dot is no kana")
        XCTAssertEqual(TextLineReader.reading(for: "卡拉OK・派对ー"), .han, "nor is the long vowel mark")
        XCTAssertNil(TextLineReader.reading(for: "コーヒー"), "katakana with long vowel marks")
        XCTAssertNil(TextLineReader.reading(for: "カード"), "katakana")
        XCTAssertNil(TextLineReader.reading(for: "週末のうどん"), "kana with Han")
        XCTAssertNil(TextLineReader.reading(for: "Noodles ｶｰﾄﾞ"), "halfwidth katakana")
        XCTAssertNil(TextLineReader.reading(for: "주말 국수, 어제"), "Hangul")
    }

    func testTheReadingReachesTheRecognizerAndAnUncalibratedOneReadsNothing() async throws {
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

        reader.onUpdate = { XCTFail("nothing is read for a label in Korean") }
        XCTAssertNil(reader.lines(in: c, of: grid, label: "주말 국수, 어제"))
        XCTAssertNil(reader.lines(in: a, of: grid, label: "주말 국수, 어제"), "not even where lines were read for another label")
        try await Task.sleep(for: .milliseconds(100))
        let readings = await calls.readings
        XCTAssertEqual(readings, [.han, .latin])
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

    /// A sample of `area` at 2x, white, with `lines` drawn in black at AppKit's bottom-left origins (the first
    /// line higher), and where each was drawn: the bounds, in global points, of the dark samples in its band of
    /// rows (the top half, then the bottom half).
    private func drawnSample(_ area: CGRect, lines: [(text: String, size: CGFloat, weight: NSFont.Weight, at: NSPoint)]) throws
        -> (grid: PixelGrid, drawn: [CGRect]) {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(area.width) * 2, pixelsHigh: Int(area.height) * 2,
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = area.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: area.size).fill()
        for line in lines {
            NSAttributedString(string: line.text, attributes: [
                .font: NSFont.systemFont(ofSize: line.size, weight: line.weight), .foregroundColor: NSColor.black,
            ]).draw(at: line.at)
        }
        NSGraphicsContext.restoreGraphicsState()
        let grid = try XCTUnwrap(PixelGrid(image: try XCTUnwrap(rep.cgImage), frame: area, scale: 2, generation: 1))
        func drawn(_ band: ClosedRange<Int>) -> CGRect {
            var box = SampleBox(minX: .max, minY: .max, maxX: .min, maxY: .min)
            for y in band {
                for x in 0..<grid.width where grid.color(x: x, y: y).r < 160 {
                    box = SampleBox(minX: min(box.minX, x), minY: min(box.minY, y), maxX: max(box.maxX, x), maxY: max(box.maxY, y))
                }
            }
            return grid.rect(of: box)
        }
        let half = grid.height / 2
        return (grid, [drawn(0...(half - 1)), drawn(half...(grid.height - 1))])
    }

    /// Reads the element `element` cut from `grid` as hover cuts it, twice, logging the time of each.
    private func read(_ element: CGRect, of grid: PixelGrid, reading: TextLineReader.Reading) throws -> [TextLine] {
        let cut = try XCTUnwrap(grid.image(of: element))
        let clock = ContinuousClock()
        var lines: [TextLine] = []
        let first = try clock.measure { lines = try TextLineReader.read(cut.image, showing: cut.frame, reading: reading) }
        let again = try clock.measure { _ = try TextLineReader.read(cut.image, showing: cut.frame, reading: reading) }
        NSLog("Locant text lines (test, %@): first %.1f ms, again %.1f ms; read %@",
              "\(reading)", first / .milliseconds(1), again / .milliseconds(1), "\(lines)")
        return lines
    }

    private func assertWhereDrawn(_ lines: [TextLine], _ drawn: [CGRect], file: StaticString = #filePath, line: UInt = #line) {
        for (read, box) in zip(lines, drawn) {
            let found = read.frame.cgRect
            for (a, b) in [(found.minX, box.minX), (found.minY, box.minY), (found.maxX, box.maxX), (found.maxY, box.maxY)] {
                XCTAssertEqual(a, b, accuracy: 3, "\(read.text): \(found) vs drawn \(box)", file: file, line: line)
            }
        }
    }

    /// Runs Vision: two lines drawn with AppKit at 2x, cut from the sample as hover cuts an element and read the
    /// Latin way, come back as two lines with their text, where they were drawn, within 3 pt.
    func testVisionReadsTwoDrawnLinesWhereTheyAre() throws {
        let (grid, drawn) = try drawnSample(CGRect(x: 1000, y: 500, width: 320, height: 100), lines: [
            ("Weeknight noodles", 17, .semibold, NSPoint(x: 30, y: 58)), ("Seven minutes ahead", 15, .regular, NSPoint(x: 30, y: 24)),
        ])
        let lines = try read(CGRect(x: 1010, y: 505, width: 300, height: 90), of: grid, reading: .latin)
        XCTAssertEqual(lines.map { $0.text.lowercased() }, ["weeknight noodles", "seven minutes ahead"])
        assertWhereDrawn(lines, drawn)
    }

    /// Runs Vision: a card in Chinese, read the Han way, gives both its lines, where they were drawn, within 3 pt.
    /// Calibrated on this synthetic render only, not yet on a real sample.
    func testVisionReadsTwoDrawnLinesInChineseTheHanWay() throws {
        let (grid, drawn) = try drawnSample(CGRect(x: 1000, y: 500, width: 320, height: 100), lines: [
            ("周末面条", 17, .semibold, NSPoint(x: 30, y: 58)), ("昨天", 15, .regular, NSPoint(x: 30, y: 24)),
        ])
        let lines = try read(CGRect(x: 1010, y: 505, width: 300, height: 90), of: grid, reading: .han)
        XCTAssertEqual(lines.map(\.text), ["周末面条", "昨天"])
        assertWhereDrawn(lines, drawn)
    }
}
