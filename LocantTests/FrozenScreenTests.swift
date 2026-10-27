import AppKit
import XCTest
@testable import Locant

/// specs/frozen-screen.md R120: crops cut from the frozen image of a display, with the same pixel
/// math as a live crop.
final class FrozenScreenTests: XCTestCase {
    /// The upper display on Malik's Mac, above and left of the built-in one: CG points.
    let upper = CGRect(x: 0, y: -1692, width: 3008, height: 1692)
    let builtIn = CGRect(x: 0, y: 0, width: 2056, height: 1329)

    /// A display image at `scale`: red, with a blue square of `blue` (CG points) painted in.
    private func image(of display: CGRect, scale: CGFloat, blue: CGRect) -> CGImage {
        let width = Int(display.width * scale), height = Int(display.height * scale)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // CGContext draws from the bottom left; the image's first row is the display's top.
        let local = Geometry.pixelRect(blue, inDisplay: display, scale: scale)
        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        context.fill(CGRect(x: local.minX, y: CGFloat(height) - local.maxY, width: local.width, height: local.height))
        return context.makeImage()!
    }

    /// The color at pixel (x, y) from the top left of a PNG.
    private func pixel(_ png: Data, x: Int, y: Int) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let rep = NSBitmapImageRep(data: png)!
        let color = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
        return (color.redComponent, color.greenComponent, color.blueComponent)
    }

    func testCropFromImageOfDisplayWithNegativeOrigin() throws {
        let blue = CGRect(x: 2208, y: -1660, width: 360, height: 468) // Monister's window
        let full = image(of: upper, scale: 2, blue: blue)
        let crop = try ScreenCapture.crop(blue.insetBy(dx: -40, dy: -40), from: full, display: upper, scale: 2)
        XCTAssertEqual(crop.crop, CGRect(x: 2168, y: -1692, width: 440, height: 540), "clamped to the display's top edge")
        XCTAssertEqual(crop.widthPt, 440)
        XCTAssertEqual(crop.heightPt, 540)
        XCTAssertEqual(crop.scale, 2)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: crop.png))
        XCTAssertEqual(rep.pixelsWide, 880)
        XCTAssertEqual(rep.pixelsHigh, 1080)
        XCTAssertEqual(pixel(crop.png, x: 10, y: 500).r, 1, accuracy: 0.05, "the padding left of the window")
        let inside = pixel(crop.png, x: 80 + 360, y: 64 + 468)
        XCTAssertEqual(inside.b, 1, accuracy: 0.05, "the window itself")
        XCTAssertEqual(inside.r, 0, accuracy: 0.05)
    }

    func testCropOutsideTheImageThrows() {
        let full = image(of: builtIn, scale: 2, blue: .zero)
        XCTAssertThrowsError(try ScreenCapture.crop(CGRect(x: 5000, y: 5000, width: 10, height: 10), from: full, display: builtIn, scale: 2))
    }

    func testFrozenScreenCropsFromTheDisplayHoldingTheCenter() throws {
        let blue = CGRect(x: 100, y: -1000, width: 50, height: 50)
        let frozen = FrozenScreen(shots: [
            .init(display: builtIn, scale: 2, image: image(of: builtIn, scale: 2, blue: .zero)),
            .init(display: upper, scale: 2, image: image(of: upper, scale: 2, blue: blue)),
        ])
        let crop = try XCTUnwrap(try frozen.crop(blue))
        XCTAssertEqual(crop.crop, blue)
        XCTAssertEqual(pixel(crop.png, x: 50, y: 50).b, 1, accuracy: 0.05, "from the upper display's image")
        XCTAssertEqual(frozen.shot(containing: CGPoint(x: 10, y: 10))?.display, builtIn)
        XCTAssertNil(try frozen.crop(CGRect(x: 4000, y: 100, width: 20, height: 20)), "no display there: crop live")
    }

    // specs/capture-shapes.md R126: while the screen is frozen, hover's sample is cut from the frozen image.

    private let red = RGB(r: 255, g: 0, b: 0)
    private let blue = RGB(r: 0, g: 0, b: 255)

    /// The sample's color at a global point, read the way hover reads it (`ScreenSampler` makes the grid).
    private func color(of sample: (image: CGImage, frame: CGRect, scale: CGFloat), at point: CGPoint) throws -> RGB {
        let grid = try XCTUnwrap(PixelGrid(image: sample.image, frame: sample.frame,
                                           scale: CGFloat(sample.image.width) / sample.frame.width, generation: 0))
        let at = try XCTUnwrap(grid.sample(at: point))
        return grid.color(x: at.x, y: at.y)
    }

    func testSampleFromTheFrozenImageOfADisplayWithNegativeOrigin() throws {
        let window = CGRect(x: 2208, y: -1660, width: 360, height: 468) // Monister's window
        let frozen = FrozenScreen(shots: [
            .init(display: builtIn, scale: 2, image: image(of: builtIn, scale: 2, blue: .zero)),
            .init(display: upper, scale: 2, image: image(of: upper, scale: 2, blue: window)),
        ])
        let sample = try XCTUnwrap(frozen.sample(window.insetBy(dx: -40, dy: -40), maxSamples: ScreenSampler.maxSamples))
        XCTAssertEqual(sample.frame, CGRect(x: 2168, y: -1692, width: 440, height: 540), "the part on the display")
        XCTAssertEqual(sample.scale, 2, "the shot's own scale")
        XCTAssertEqual(sample.image.width, 880)
        XCTAssertEqual(sample.image.height, 1080)
        XCTAssertLessThanOrEqual(try color(of: sample, at: CGPoint(x: 2400, y: -1400)).difference(blue), 2, "the window")
        XCTAssertLessThanOrEqual(try color(of: sample, at: CGPoint(x: 2180, y: -1400)).difference(red), 2, "left of it")
        XCTAssertLessThanOrEqual(try color(of: sample, at: CGPoint(x: 2400, y: -1180)).difference(red), 2, "below it")
    }

    func testALargeSampleIsCutAtALowerScale() throws {
        let card = CGRect(x: 600, y: 400, width: 200, height: 150)
        let frozen = FrozenScreen(shots: [.init(display: builtIn, scale: 2, image: image(of: builtIn, scale: 2, blue: card))])
        let area = CGRect(x: 500, y: 300, width: 400, height: 300) // 480,000 samples at 2x
        let sample = try XCTUnwrap(frozen.sample(area, maxSamples: 120_000))
        XCTAssertEqual(sample.frame, area)
        XCTAssertEqual(sample.scale, Geometry.sampleScale(native: 2, size: area.size, maxSamples: 120_000))
        XCTAssertEqual(sample.scale, 1)
        XCTAssertEqual(sample.image.width, 400)
        XCTAssertEqual(sample.image.height, 300)
        XCTAssertLessThanOrEqual(try color(of: sample, at: CGPoint(x: 700, y: 475)).difference(blue), 2, "the card")
        XCTAssertLessThanOrEqual(try color(of: sample, at: CGPoint(x: 550, y: 350)).difference(red), 2, "around it")
    }

    func testNoSampleOffEveryShot() {
        let frozen = FrozenScreen(shots: [.init(display: builtIn, scale: 2, image: image(of: builtIn, scale: 2, blue: .zero))])
        XCTAssertNil(frozen.sample(CGRect(x: 4000, y: 100, width: 20, height: 20), maxSamples: ScreenSampler.maxSamples),
                     "no display there: the sample is taken live")
    }
}
