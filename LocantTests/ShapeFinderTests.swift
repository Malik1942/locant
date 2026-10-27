import AppKit
import XCTest
@testable import Locant

/// specs/capture-shapes.md R127: shapes found in the pixels.
final class ShapeFinderTests: XCTestCase {
    /// A screen in points, `scale` samples per point, painted with rectangles, read as a grid at the origin.
    private struct Canvas {
        let widthPt: Int, heightPt: Int, scale: Int
        var bytes: [UInt8]

        init(_ widthPt: Int, _ heightPt: Int, scale: Int = 2, background: RGB) {
            self.widthPt = widthPt
            self.heightPt = heightPt
            self.scale = scale
            let samples = widthPt * scale * heightPt * scale
            bytes = [UInt8](repeating: 255, count: samples * 4)
            for i in 0..<samples {
                bytes[i * 4] = background.r
                bytes[i * 4 + 1] = background.g
                bytes[i * 4 + 2] = background.b
            }
        }

        var bounds: CGRect { CGRect(x: 0, y: 0, width: widthPt, height: heightPt) }

        /// Every sample whose center lies in `rect`, inside its corners of `radius`, takes `color(y)`.
        mutating func paint(_ rect: CGRect, radius: CGFloat = 0, _ color: (CGFloat) -> RGB) {
            let s = CGFloat(scale), width = widthPt * scale
            let x0 = max(0, Int((rect.minX * s).rounded(.down))), x1 = min(width, Int((rect.maxX * s).rounded(.up)))
            let y0 = max(0, Int((rect.minY * s).rounded(.down))), y1 = min(heightPt * scale, Int((rect.maxY * s).rounded(.up)))
            guard x0 < x1, y0 < y1 else { return }
            for y in y0..<y1 {
                for x in x0..<x1 {
                    let p = CGPoint(x: (CGFloat(x) + 0.5) / s, y: (CGFloat(y) + 0.5) / s)
                    guard rect.contains(p), Self.insideCorners(p, rect, radius) else { continue }
                    let c = color(p.y), i = (y * width + x) * 4
                    bytes[i] = c.r
                    bytes[i + 1] = c.g
                    bytes[i + 2] = c.b
                }
            }
        }

        mutating func paint(_ rect: CGRect, radius: CGFloat = 0, _ color: RGB) {
            paint(rect, radius: radius) { _ in color }
        }

        /// A `width` pt line along the inside of each edge of `rect`.
        mutating func outline(_ rect: CGRect, width: CGFloat = 1, _ color: RGB) {
            paint(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: width), color)
            paint(CGRect(x: rect.minX, y: rect.maxY - width, width: rect.width, height: width), color)
            paint(CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height), color)
            paint(CGRect(x: rect.maxX - width, y: rect.minY, width: width, height: rect.height), color)
        }

        func grid(generation: Int = 1) -> PixelGrid {
            PixelGrid(frame: bounds, scale: CGFloat(scale), width: widthPt * scale, height: heightPt * scale,
                      bytes: bytes, generation: generation)
        }

        private static func insideCorners(_ p: CGPoint, _ r: CGRect, _ radius: CGFloat) -> Bool {
            guard radius > 0 else { return true }
            let cx = min(max(p.x, r.minX + radius), r.maxX - radius)
            let cy = min(max(p.y, r.minY + radius), r.maxY - radius)
            return hypot(p.x - cx, p.y - cy) <= radius
        }
    }

    private let dark = RGB(r: 20, g: 20, b: 22)

    private func assertRect(_ found: CGRect?, _ expected: CGRect, within slack: CGFloat = 1, _ message: String = "",
                            file: StaticString = #filePath, line: UInt = #line) {
        guard let found else { return XCTFail("no shape; expected \(expected) \(message)", file: file, line: line) }
        for (a, b) in [(found.minX, expected.minX), (found.minY, expected.minY), (found.maxX, expected.maxX), (found.maxY, expected.maxY)] {
            XCTAssertEqual(a, b, accuracy: slack, "\(found) vs \(expected) \(message)", file: file, line: line)
        }
    }

    // A card on a flat background: from a point in its padding, and from the ring around a label in it.
    func testRoundedCardFromItsPaddingAndAroundALabel() {
        var canvas = Canvas(400, 300, background: dark)
        let card = CGRect(x: 100, y: 80, width: 160, height: 90)
        let label = CGRect(x: 120, y: 100, width: 60, height: 14)
        canvas.paint(card, radius: 12, RGB(r: 50, g: 50, b: 54))
        canvas.paint(label, RGB(r: 200, g: 200, b: 200))
        let grid = canvas.grid()
        assertRect(ShapeFinder.fill(at: CGPoint(x: 106, y: 125), in: grid, bound: canvas.bounds)?.shape, card)
        assertRect(ShapeFinder.shape(around: label, in: grid, bound: canvas.bounds), card)
    }

    // Oryne's Recent/Currents switch: two buttons fill a glass capsule but for a 3 pt rim, the selected
    // one lighter than the fill. The ring around either button finds the capsule, and so does its rim.
    func testCapsuleWhoseButtonsTouchFromEitherButton() {
        var canvas = Canvas(240, 120, background: RGB(r: 26, g: 27, b: 29))
        let capsule = CGRect(x: 37, y: 37.5, width: 162.5, height: 36.5)
        let recent = CGRect(x: 40, y: 40.5, width: 78, height: 30)
        let currents = CGRect(x: 118, y: 40.5, width: 78, height: 30)
        canvas.paint(capsule, radius: 18.25, RGB(r: 42, g: 42, b: 45))
        canvas.paint(currents, radius: 15, RGB(r: 80, g: 80, b: 84))
        canvas.paint(CGRect(x: 60, y: 50, width: 36, height: 10), RGB(r: 150, g: 150, b: 150)) // "Recent"
        let grid = canvas.grid()
        assertRect(ShapeFinder.shape(around: recent, in: grid, bound: canvas.bounds), capsule)
        assertRect(ShapeFinder.shape(around: currents, in: grid, bound: canvas.bounds), capsule)
        assertRect(ShapeFinder.fill(at: CGPoint(x: 38.5, y: 55), in: grid, bound: canvas.bounds)?.shape, capsule)
    }

    // A card whose fill runs through 20 levels top to bottom is one shape.
    func testGradientFillIsOneShape() {
        var canvas = Canvas(300, 300, background: RGB(r: 10, g: 10, b: 10))
        let card = CGRect(x: 50, y: 50, width: 200, height: 150)
        canvas.paint(card) { y in
            let level = UInt8(40 + Int((y - 50) / 150 * 20))
            return RGB(r: level, g: level, b: level)
        }
        assertRect(ShapeFinder.fill(at: CGPoint(x: 150, y: 125), in: canvas.grid(), bound: canvas.bounds)?.shape, card)
    }

    // The "Thought deleted" pill: its fill is the background's within 2 levels; only a 1 pt rim tells
    // them apart, and the fill stops at it.
    func testGlassRimStopsTheFill() {
        var canvas = Canvas(200, 120, background: RGB(r: 12, g: 14, b: 17))
        let pill = CGRect(x: 30, y: 30, width: 150, height: 44)
        canvas.paint(pill, radius: 22, RGB(r: 14, g: 14, b: 17))
        canvas.outline(pill, RGB(r: 30, g: 30, b: 34))
        let found = ShapeFinder.fill(at: CGPoint(x: 40, y: 52), in: canvas.grid(), bound: canvas.bounds)?.shape
        assertRect(found, pill.insetBy(dx: 1, dy: 1))
    }

    // The background touches two opposite sides of the bound: no shape. Nor is a strip that runs the
    // bound's full width, like a toolbar.
    func testBackgroundAndFullWidthStripGiveNoShape() {
        var canvas = Canvas(400, 300, background: dark)
        canvas.paint(CGRect(x: 100, y: 80, width: 160, height: 90), radius: 12, RGB(r: 50, g: 50, b: 54))
        canvas.paint(CGRect(x: 0, y: 260, width: 400, height: 40), RGB(r: 60, g: 60, b: 64))
        let grid = canvas.grid()
        XCTAssertNil(ShapeFinder.fill(at: CGPoint(x: 20, y: 20), in: grid, bound: canvas.bounds)?.shape)
        XCTAssertNil(ShapeFinder.fill(at: CGPoint(x: 200, y: 280), in: grid, bound: canvas.bounds)?.shape)
    }

    // 60% of the bound or more is not a shape, nor is anything under 12 pt either way.
    func testTooBigOrTooSmallGivesNoShape() {
        var canvas = Canvas(400, 300, background: dark)
        canvas.paint(CGRect(x: 10, y: 10, width: 370, height: 260), RGB(r: 50, g: 50, b: 54))
        canvas.paint(CGRect(x: 100, y: 100, width: 10, height: 30), RGB(r: 90, g: 90, b: 94))
        let grid = canvas.grid()
        XCTAssertNil(ShapeFinder.fill(at: CGPoint(x: 300, y: 200), in: grid, bound: canvas.bounds)?.shape)
        XCTAssertNil(ShapeFinder.fill(at: CGPoint(x: 105, y: 115), in: grid, bound: canvas.bounds)?.shape)
    }

    // A pill on a sheet that meets the bottom of the bound: the pill from its padding, the sheet around
    // it, and nothing beyond, since the background runs the bound's width.
    func testPillInsideASheet() {
        var canvas = Canvas(300, 600, background: RGB(r: 4, g: 4, b: 5))
        let sheet = CGRect(x: 10, y: 300, width: 280, height: 300)
        let pill = CGRect(x: 40, y: 340, width: 120, height: 36)
        canvas.paint(sheet, radius: 30, RGB(r: 30, g: 30, b: 34))
        canvas.paint(pill, radius: 18, RGB(r: 60, g: 60, b: 64))
        let grid = canvas.grid()
        assertRect(ShapeFinder.fill(at: CGPoint(x: 50, y: 358), in: grid, bound: canvas.bounds)?.shape, pill)
        let around = ShapeFinder.enclosing(pill, in: grid, bound: canvas.bounds)
        XCTAssertEqual(around.count, 1)
        assertRect(around.first, sheet)
        assertRect(ShapeFinder.fill(at: CGPoint(x: 20, y: 500), in: grid, bound: canvas.bounds)?.shape, sheet)
    }

    // A pointer on an icon's stroke seeds from the fill around it.
    func testPointerOnAnIconStrokeFindsThePill() {
        var canvas = Canvas(220, 120, background: RGB(r: 10, g: 10, b: 12))
        let pill = CGRect(x: 50, y: 40, width: 120, height: 40)
        canvas.paint(pill, radius: 20, RGB(r: 40, g: 40, b: 44))
        canvas.paint(CGRect(x: 100, y: 48, width: 1.5, height: 24), RGB(r: 220, g: 220, b: 220))
        assertRect(ShapeFinder.fill(at: CGPoint(x: 100.75, y: 60), in: canvas.grid(), bound: canvas.bounds)?.shape, pill)
    }

    // An accessibility frame from another app reaches the finder as the app reported it: infinite, NaN,
    // or far taller than the screen. Nothing traps, and the ring is built only where the sample is.
    func testFramesFromOtherAppsNeverTrap() {
        var canvas = Canvas(400, 300, background: dark)
        canvas.paint(CGRect(x: 100, y: 80, width: 160, height: 90), RGB(r: 50, g: 50, b: 54))
        let grid = canvas.grid()
        let nan = CGFloat.nan
        XCTAssertNil(ShapeFinder.shape(around: .infinite, in: grid, bound: canvas.bounds))
        XCTAssertNil(ShapeFinder.shape(around: CGRect(x: nan, y: nan, width: 20, height: 20), in: grid, bound: canvas.bounds))
        XCTAssertNil(ShapeFinder.shape(around: CGRect(x: 120, y: -15_000, width: 20, height: 30_000), in: grid, bound: canvas.bounds))
        XCTAssertNil(ShapeFinder.fill(at: CGPoint(x: nan, y: 125), in: grid, bound: canvas.bounds))
        XCTAssertNil(ShapeFinder.fill(at: CGPoint(x: 1e300, y: 125), in: grid, bound: canvas.bounds))
        XCTAssertNil(grid.sample(at: CGPoint(x: 106, y: nan)))
        XCTAssertNil(grid.box(of: .infinite))
        XCTAssertNil(grid.box(of: CGRect(x: 0, y: 0, width: nan, height: 10)))
        // A bound that is not finite, or empty, finds nothing.
        for bound in [CGRect.infinite, .null, CGRect(x: nan, y: 0, width: 400, height: 300), CGRect(x: 100, y: 100, width: 0, height: 50)] {
            XCTAssertNil(ShapeFinder.fill(at: CGPoint(x: 106, y: 125), in: grid, bound: bound), "\(bound)")
            XCTAssertNil(ShapeFinder.shape(around: CGRect(x: 120, y: 100, width: 20, height: 20), in: grid, bound: bound), "\(bound)")
        }
        // A frame inside the sample still finds the card.
        assertRect(ShapeFinder.shape(around: CGRect(x: 120, y: 100, width: 20, height: 20), in: grid, bound: canvas.bounds),
                   CGRect(x: 100, y: 80, width: 160, height: 90))
    }

    func testSeedColorIsTheMeanOfTheLargestBucket() {
        let colors = [RGB(r: 16, g: 16, b: 16), RGB(r: 17, g: 17, b: 17), RGB(r: 23, g: 23, b: 23),
                      RGB(r: 200, g: 0, b: 0), RGB(r: 201, g: 0, b: 0)]
        XCTAssertEqual(ShapeFinder.seedColor(of: colors), RGB(r: 18, g: 18, b: 18))
        XCTAssertNil(ShapeFinder.seedColor(of: []))
    }

    // The conversion the live sample and the fixtures share keeps the top row first.
    func testGridFromAnImageIsTopRowFirst() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 2, width: 4, height: 2)) // Core Graphics' y runs up: the top half
        let image = try XCTUnwrap(context.makeImage())
        let grid = try XCTUnwrap(PixelGrid(image: image, frame: CGRect(x: 10, y: 20, width: 2, height: 2), scale: 2, generation: 1))
        XCTAssertEqual(grid.color(x: 0, y: 0), RGB(r: 255, g: 0, b: 0))
        XCTAssertEqual(grid.color(x: 0, y: 3), RGB(r: 0, g: 0, b: 255))
        XCTAssertEqual(grid.sample(at: CGPoint(x: 11.9, y: 21.9))?.x, 3)
        XCTAssertNil(grid.sample(at: CGPoint(x: 12, y: 20)))
    }

    // R127: while the pointer stays on the samples a fill took, its answer stands.
    func testAFillCoversTheSamplesItTook() throws {
        var canvas = Canvas(400, 300, background: dark)
        canvas.paint(CGRect(x: 100, y: 80, width: 160, height: 90), RGB(r: 50, g: 50, b: 54))
        let grid = canvas.grid()
        let fill = try XCTUnwrap(ShapeFinder.fill(at: CGPoint(x: 106, y: 125), in: grid, bound: canvas.bounds))
        XCTAssertTrue(fill.covers(CGPoint(x: 250, y: 160), in: grid))
        XCTAssertFalse(fill.covers(CGPoint(x: 20, y: 20), in: grid))
        XCTAssertFalse(fill.covers(CGPoint(x: 250, y: 160), in: canvas.grid(generation: 2)), "a newer sample")
    }

    // R127: the live source keeps its memo while the sample and the bound stay the same, and drops it otherwise.
    func testShapeLookupKeepsItsMemoForOneSampleAndBound() {
        var canvas = Canvas(400, 300, background: dark)
        let card = CGRect(x: 100, y: 80, width: 160, height: 90)
        canvas.paint(card, RGB(r: 50, g: 50, b: 54))
        var lookup = ShapeLookup(grid: canvas.grid(generation: 1), bound: canvas.bounds, memo: .init())
        assertRect(lookup.shape(at: CGPoint(x: 106, y: 125)), card)
        XCTAssertNotNil(lookup.memo.lastFill)
        XCTAssertEqual(lookup.shapes(around: CGRect(x: 120, y: 100, width: 20, height: 20)).count, 1)
        XCTAssertEqual(lookup.memo.around.count, 1)
        XCTAssertNotNil(ShapeLookup(grid: canvas.grid(generation: 1), bound: canvas.bounds, memo: lookup.memo).memo.lastFill)
        let newer = ShapeLookup(grid: canvas.grid(generation: 2), bound: canvas.bounds, memo: lookup.memo)
        XCTAssertNil(newer.memo.lastFill)
        XCTAssertTrue(newer.memo.around.isEmpty)
    }

    // R134: what is drawn inside a rectangle is the bounds of the edge samples it covers. A step marks the
    // sample on each side of it, so the bounds reach one sample (half a point here) past what is painted.
    func testEdgeBoundsAreWhatIsDrawnInsideARectangle() {
        var canvas = Canvas(400, 300, background: dark)
        let button = CGRect(x: 50, y: 50, width: 300, height: 76)
        canvas.paint(CGRect(x: 50, y: 56, width: 300, height: 64), RGB(r: 50, g: 50, b: 54)) // a card inset 6 pt top and bottom
        canvas.paint(CGRect(x: 70, y: 200, width: 120, height: 16), RGB(r: 200, g: 200, b: 200))
        let grid = canvas.grid()
        assertRect(grid.edgeBounds(inside: button), CGRect(x: 50, y: 55.5, width: 300, height: 65), within: 0.01,
                   "the frame's own sides cut the card's left and right edges")
        assertRect(grid.edgeBounds(inside: CGRect(x: 40, y: 180, width: 300, height: 60)), CGRect(x: 69.5, y: 199.5, width: 121, height: 17), within: 0.01)
        XCTAssertNil(grid.edgeBounds(inside: CGRect(x: 20, y: 150, width: 300, height: 20)), "a flat background")
        // Frames from other apps: not finite, off the grid, or far taller than the screen.
        for rect in [CGRect.infinite, .null, CGRect(x: CGFloat.nan, y: 50, width: 300, height: 76), CGRect(x: 500, y: 50, width: 40, height: 40)] {
            XCTAssertNil(grid.edgeBounds(inside: rect), "\(rect)")
        }
        assertRect(grid.edgeBounds(inside: CGRect(x: 50, y: -15_000, width: 300, height: 30_000)),
                   CGRect(x: 50, y: 55.5, width: 300, height: 161), within: 0.01, "the card and the block, the part the sample shows")
    }

    // R134: the live source keeps what it found inside each rectangle, nothing found included.
    func testShapeLookupKeepsWhatIsDrawnInsideEachRectangle() {
        var canvas = Canvas(400, 300, background: dark)
        canvas.paint(CGRect(x: 100, y: 80, width: 160, height: 90), RGB(r: 50, g: 50, b: 54))
        var lookup = ShapeLookup(grid: canvas.grid(generation: 1), bound: canvas.bounds, memo: .init())
        XCTAssertNotNil(lookup.ink(inside: CGRect(x: 90, y: 70, width: 180, height: 110)))
        XCTAssertNil(lookup.ink(inside: CGRect(x: 10, y: 10, width: 40, height: 40)))
        XCTAssertEqual(lookup.memo.ink.count, 2)
        XCTAssertNil(lookup.ink(inside: CGRect(x: 10, y: 10, width: 40, height: 40)))
        XCTAssertEqual(lookup.memo.ink.count, 2)
        XCTAssertTrue(ShapeLookup(grid: canvas.grid(generation: 2), bound: canvas.bounds, memo: lookup.memo).memo.ink.isEmpty, "a newer sample")
    }

    // MARK: Padded frames tighten, in the phone (R134)

    /// The tightened frame of `frame` on this canvas, as the ladder takes it from the live source.
    private func tightened(_ frame: CGRect, on canvas: Canvas) -> CGRect {
        var lookup = ShapeLookup(grid: canvas.grid(), bound: canvas.bounds, memo: .init())
        return HitRefiner.tightFrame(frame, ink: lookup.ink(inside: frame))
    }

    // A button's frame around a card drawn 6 pt inside it top and bottom, 2 pt at the sides: the card. A drawn
    // step marks the sample on each side, so the frame ends one sample (half a point here) outside the card.
    func testAButtonFrameTightensToTheCardDrawnInIt() {
        var canvas = Canvas(400, 300, background: dark)
        let button = CGRect(x: 50, y: 50, width: 300, height: 76)
        let card = CGRect(x: 52, y: 56, width: 296, height: 64)
        canvas.paint(card, RGB(r: 50, g: 50, b: 54))
        canvas.paint(CGRect(x: 66, y: 72, width: 140, height: 14), RGB(r: 220, g: 220, b: 220)) // its title
        assertRect(tightened(button, on: canvas), card.insetBy(dx: -0.5, dy: -0.5), within: 0.01)
    }

    // The Product Ideas header: a frame around a line of text and a "1 >" at its right: their edges.
    func testAFrameAroundTextTightensToTheText() {
        var canvas = Canvas(400, 300, background: dark)
        let header = CGRect(x: 20, y: 100, width: 331, height: 62)
        let light = RGB(r: 230, g: 230, b: 230)
        for x in stride(from: 36, through: 136, by: 8) {
            canvas.paint(CGRect(x: CGFloat(x), y: 122, width: 5, height: 18), light) // glyphs
        }
        canvas.paint(CGRect(x: 316, y: 125, width: 7, height: 12), light) // "1 >"
        // The glyphs and the sample on each side of them.
        assertRect(tightened(header, on: canvas), CGRect(x: 35.5, y: 121.5, width: 288, height: 19), within: 0.01)
    }

    // Nothing drawn inside a frame, or nothing more than 2 pt inside it: the frame stays.
    func testAFrameWithNothingDrawnWellInsideItStays() {
        var canvas = Canvas(400, 300, background: dark)
        let empty = CGRect(x: 20, y: 20, width: 120, height: 50)
        let near = CGRect(x: 200, y: 20, width: 120, height: 50)
        let farther = CGRect(x: 200, y: 120, width: 120, height: 50)
        canvas.paint(near.insetBy(dx: 2.5, dy: 2.5), RGB(r: 60, g: 60, b: 64))  // edges from 2 pt in
        canvas.paint(farther.insetBy(dx: 3, dy: 3), RGB(r: 60, g: 60, b: 64))   // edges from 2.5 pt in
        XCTAssertEqual(tightened(empty, on: canvas), empty)
        XCTAssertEqual(tightened(near, on: canvas), near)
        assertRect(tightened(farther, on: canvas), farther.insetBy(dx: 2.5, dy: 2.5), within: 0.01)
    }

    // A control under 44 pt either way keeps its frame around its icon: iOS pads it to the tap target on purpose.
    func testAControlUnder44PointsKeepsItsFrame() {
        var canvas = Canvas(400, 300, background: dark)
        let small = CGRect(x: 20, y: 200, width: 40, height: 40)
        let large = CGRect(x: 100, y: 200, width: 44, height: 44)
        canvas.paint(CGRect(x: 32, y: 212, width: 16, height: 16), RGB(r: 220, g: 220, b: 220))
        canvas.paint(CGRect(x: 114, y: 214, width: 16, height: 16), RGB(r: 220, g: 220, b: 220))
        XCTAssertEqual(tightened(small, on: canvas), small)
        assertRect(tightened(large, on: canvas), CGRect(x: 113.5, y: 213.5, width: 17, height: 17), within: 0.01)
    }

    // The ladder tightens only on Device Hub's simulated screen, with the live source.
    func testOnlyTheSimulatedScreenTightens() {
        var canvas = Canvas(400, 300, background: dark)
        let button = AttributeSet(role: "AXButton", description: "Weeknight noodles", frame: Frame(x: 50, y: 50, w: 300, h: 76))
        canvas.paint(CGRect(x: 50, y: 56, width: 300, height: 64), RGB(r: 50, g: 50, b: 54))
        let phone = AttributeSet(role: "AXGroup", subrole: HitRefiner.simulatedScreenSubrole, frame: Frame(canvas.bounds))
        let window = AttributeSet(role: "AXGroup", frame: Frame(canvas.bounds))
        let point = CGPoint(x: 200, y: 52) // in the button's padding, above the card
        func rung0(under screen: AttributeSet) -> Frame? {
            var lookup = ShapeLookup(grid: canvas.grid(), bound: canvas.bounds, memo: .init())
            let snapshot = ElementSnapshot(element: button, ancestors: [screen])
            return HitRefiner.selectionLevels(for: snapshot, at: point, shapes: &lookup, holding: nil).first??.frame
        }
        XCTAssertEqual(rung0(under: phone), Frame(x: 50, y: 55.5, w: 300, h: 65))
        XCTAssertEqual(rung0(under: window), button.frame, "off the simulated screen")
    }

    // MARK: Real screens (section 3)

    private struct FixtureFile: Decodable {
        struct Case: Decodable {
            let name: String
            let at: [CGFloat]?
            let around: [CGFloat]?
            let expect: [CGFloat]?
        }
        let file: String
        let source: String
        let bound: [CGFloat]?
        let cases: [Case]
    }

    private func rect(_ v: [CGFloat]) -> CGRect { CGRect(x: v[0], y: v[1], width: v[2], height: v[3]) }

    /// Malik's captures of the failing cases and two cards outside SwiftUI, text blurred, at their 2x
    /// scale through the conversion the live sample uses. Expected rectangles were measured apart from
    /// `ShapeFinder`; a nil one is a background point that must give no shape.
    func testRealScreens() throws {
        let bundle = Bundle(for: Self.self)
        let index = try XCTUnwrap(bundle.url(forResource: "shapes", withExtension: "json"))
        let files = try JSONDecoder().decode([FixtureFile].self, from: Data(contentsOf: index))
        XCTAssertEqual(files.count, 6)
        for fixture in files {
            let url = try XCTUnwrap(bundle.url(forResource: fixture.file, withExtension: "png"), fixture.file)
            let image = try XCTUnwrap(NSBitmapImageRep(data: try Data(contentsOf: url))?.cgImage, fixture.file)
            let frame = CGRect(x: 0, y: 0, width: CGFloat(image.width) / 2, height: CGFloat(image.height) / 2)
            let grid = try XCTUnwrap(PixelGrid(image: image, frame: frame, scale: 2, generation: 1))
            let bound = fixture.bound.map(rect) ?? frame
            for c in fixture.cases {
                let label = "\(fixture.file): \(c.name)"
                let found: CGRect?
                if let at = c.at {
                    found = ShapeFinder.fill(at: CGPoint(x: at[0], y: at[1]), in: grid, bound: bound)?.shape
                } else {
                    found = ShapeFinder.shape(around: rect(try XCTUnwrap(c.around, label)), in: grid, bound: bound)
                }
                if let expect = c.expect {
                    assertRect(found, rect(expect), within: 2, label)
                } else {
                    XCTAssertNil(found, label)
                }
            }
        }
    }
}
