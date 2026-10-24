import CoreGraphics
import XCTest
@testable import Locant

/// specs/capture-shapes.md R118: one image of the area hover wants, taken once per area, never without
/// permission, and dropped on stop.
@MainActor
final class ScreenSamplerTests: XCTestCase {
    private actor Calls {
        var areas: [CGRect] = []
        func add(_ area: CGRect) { areas.append(area) }
        var count: Int { areas.count }
    }

    private nonisolated static func image(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(gray: 0.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// A sampler whose capture records the area and returns a plain image at 2x; refresh far off, so
    /// only `want` captures.
    private func makeSampler(permitted: Bool, calls: Calls) -> ScreenSampler {
        ScreenSampler(hasPermission: { permitted }, capture: { area in
            await calls.add(area)
            return (Self.image(width: Int(area.width) * 2, height: Int(area.height) * 2), area, 2)
        }, refresh: .seconds(600))
    }

    private let first = CGRect(x: 0, y: 0, width: 100, height: 200)
    private let second = CGRect(x: 100, y: 0, width: 100, height: 200)

    func testWithoutPermissionNothingIsCaptured() async throws {
        let calls = Calls()
        let sampler = makeSampler(permitted: false, calls: calls)
        sampler.start()
        sampler.want(first)
        try await Task.sleep(for: .milliseconds(200))
        let count = await calls.count
        XCTAssertEqual(count, 0)
        XCTAssertNil(sampler.image(for: first))
        sampler.stop()
    }

    func testOneCapturePerAreaAndAnotherForANewArea() async {
        let calls = Calls()
        let sampler = makeSampler(permitted: true, calls: calls)
        sampler.start()
        let landed = expectation(description: "first image")
        sampler.onUpdate = { landed.fulfill() }
        sampler.want(first)
        sampler.want(first) // one in flight: not asked twice
        await fulfillment(of: [landed], timeout: 2)
        XCTAssertEqual(sampler.image(for: first)?.width, 200)
        XCTAssertEqual(sampler.image(for: first)?.generation, 1)
        sampler.want(first) // the newest image already shows it
        var count = await calls.count
        XCTAssertEqual(count, 1)

        let moved = expectation(description: "second image")
        sampler.onUpdate = { moved.fulfill() }
        sampler.want(second)
        await fulfillment(of: [moved], timeout: 2)
        count = await calls.count
        XCTAssertEqual(count, 2)
        XCTAssertNil(sampler.image(for: first))
        XCTAssertEqual(sampler.image(for: second)?.generation, 2)
        sampler.stop()
    }

    func testStopDropsTheImageAndTakesNoMore() async throws {
        let calls = Calls()
        let sampler = makeSampler(permitted: true, calls: calls)
        sampler.start()
        let landed = expectation(description: "image")
        sampler.onUpdate = { landed.fulfill() }
        sampler.want(first)
        await fulfillment(of: [landed], timeout: 2)
        sampler.stop()
        XCTAssertNil(sampler.image(for: first))
        sampler.want(second)
        try await Task.sleep(for: .milliseconds(200))
        let count = await calls.count
        XCTAssertEqual(count, 1)
    }
}
