import CoreGraphics
import XCTest
@testable import Locant

/// specs/capture-shapes.md R126: one image of the area hover wants, taken once per area, never without
/// permission, and dropped on stop.
@MainActor
final class ScreenSamplerTests: XCTestCase {
    private actor Calls {
        var areas: [CGRect] = []
        func add(_ area: CGRect) { areas.append(area) }
        var count: Int { areas.count }
    }

    /// Holds a capture until the test opens it.
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

    private nonisolated static func image(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(gray: 0.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// A sampler whose capture records the area, runs `before` (which can hold it or throw), and returns
    /// a plain image at 2x; refresh far off unless asked, so only `want` captures.
    private func makeSampler(permitted: Bool, calls: Calls, refresh: Duration = .seconds(600),
                             before: @escaping @Sendable (CGRect) async throws -> Void = { _ in }) -> ScreenSampler {
        ScreenSampler(hasPermission: { permitted }, capture: { area in
            await calls.add(area)
            try await before(area)
            return (Self.image(width: Int(area.width) * 2, height: Int(area.height) * 2), area, 2)
        }, refresh: refresh)
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

    func testOneCapturePerAreaAndAnotherForANewArea() async throws {
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
        try await Task.sleep(for: .milliseconds(200))
        var count = await calls.count
        XCTAssertEqual(count, 1)
        let asked = await calls.areas
        XCTAssertEqual(asked, [first])

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

    func testACaptureStartedBeforeStopNeverLandsAfterIt() async throws {
        let calls = Calls()
        let gate = Gate()
        let held = first
        let reached = expectation(description: "the held capture reached the gate")
        let sampler = makeSampler(permitted: true, calls: calls, before: { area in
            guard area == held else { return }
            reached.fulfill()
            await gate.wait()
        })
        sampler.start()
        var updates = 0
        let landed = expectation(description: "the new session's image")
        landed.assertForOverFulfill = false // `updates` counts a stray landing
        sampler.onUpdate = {
            updates += 1
            landed.fulfill()
        }
        sampler.want(first) // held at the gate
        await fulfillment(of: [reached], timeout: 2)
        sampler.stop()
        sampler.start()
        sampler.want(second) // the held capture does not block the new session
        await fulfillment(of: [landed], timeout: 2)
        var count = await calls.count
        XCTAssertEqual(count, 2)
        XCTAssertEqual(sampler.image(for: second)?.generation, 2)
        XCTAssertEqual(updates, 1)

        await gate.release() // the old capture finishes now, into a session that is over
        try await Task.sleep(for: .milliseconds(200)) // settle: nothing lands
        XCTAssertNil(sampler.image(for: first)?.generation)
        XCTAssertEqual(sampler.image(for: second)?.generation, 2)
        XCTAssertEqual(updates, 1)
        count = await calls.count
        XCTAssertEqual(count, 2)
        sampler.stop()
    }

    func testAFailedCaptureLeavesThePreviousImageAndSaysNothing() async throws {
        let calls = Calls()
        let refused = second
        let failed = expectation(description: "the refused area was asked for")
        let sampler = makeSampler(permitted: true, calls: calls, before: { area in
            guard area == refused else { return }
            failed.fulfill()
            throw Refused()
        })
        sampler.start()
        let landed = expectation(description: "first image")
        sampler.onUpdate = { landed.fulfill() }
        sampler.want(first)
        await fulfillment(of: [landed], timeout: 2)

        sampler.onUpdate = { XCTFail("a failed capture is not an update") }
        sampler.want(second)
        await fulfillment(of: [failed], timeout: 2)
        try await Task.sleep(for: .milliseconds(100)) // settle: no update follows
        let count = await calls.count
        XCTAssertEqual(count, 2)
        XCTAssertEqual(sampler.image(for: first)?.generation, 1)
        XCTAssertNil(sampler.image(for: second))
        sampler.stop()
    }

    func testAnAreaWantedDuringAFailedCaptureIsTakenRightAfterIt() async {
        let calls = Calls()
        let gate = Gate()
        let held = first
        let sampler = makeSampler(permitted: true, calls: calls, before: { area in
            if area == held {
                await gate.wait()
                throw Refused()
            }
        })
        sampler.start()
        let landed = expectation(description: "second image")
        sampler.onUpdate = { landed.fulfill() }
        sampler.want(first) // in flight, and about to fail
        sampler.want(second) // wanted meanwhile, parked
        await gate.release()
        await fulfillment(of: [landed], timeout: 2) // well inside the 600 s refresh
        let asked = await calls.areas
        XCTAssertEqual(asked, [first, second])
        XCTAssertEqual(sampler.image(for: second)?.generation, 2)
        sampler.stop()
    }

    // A wedged capture service throws at once. Hover wants the same area about 30 times a second; the
    // failed area is asked again only at the next refresh, not at hover's rate.
    func testAFailedAreaWaitsForTheNextRefresh() async throws {
        let calls = Calls()
        let refused = first
        let failed = expectation(description: "the area was asked for and failed")
        failed.assertForOverFulfill = false
        let sampler = makeSampler(permitted: true, calls: calls, before: { area in
            guard area == refused else { return }
            failed.fulfill()
            throw Refused()
        })
        sampler.start()
        sampler.want(first)
        await fulfillment(of: [failed], timeout: 2)
        for _ in 0..<6 {
            try await Task.sleep(for: .milliseconds(33))
            sampler.want(first)
        }
        try await Task.sleep(for: .milliseconds(100)) // settle: nothing more is asked
        let count = await calls.count
        XCTAssertEqual(count, 1)
        sampler.stop()
    }

    // R126, amended Oct 27: while the screen is frozen (specs/frozen-screen.md R119), the sample is cut from the
    // frozen image, the pixels the user sees. A freeze still being taken is waited for; ScreenCaptureKit is not asked.

    private nonisolated static func blueImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// A sampler that reads `freeze` first; its live capture records the area and returns a plain gray image.
    private func frozenFirstSampler(calls: Calls, freeze: @escaping @Sendable () async -> FrozenScreen?) -> ScreenSampler {
        ScreenSampler(hasPermission: { true }, capture: ScreenSampler.frozenFirst(freeze, live: { area in
            await calls.add(area)
            return (Self.image(width: Int(area.width) * 2, height: Int(area.height) * 2), area, 2)
        }), refresh: .seconds(600))
    }

    func testWhileFrozenTheSampleIsCutFromTheFrozenImage() async throws {
        let calls = Calls()
        let gate = Gate()
        let display = CGRect(x: 0, y: 0, width: 400, height: 300)
        let frozen = FrozenScreen(shots: [.init(display: display, scale: 2, image: Self.blueImage(width: 800, height: 600))])
        let sampler = frozenFirstSampler(calls: calls, freeze: {
            await gate.wait() // the freeze has not answered yet
            return frozen
        })
        sampler.start()
        let landed = expectation(description: "the frozen image")
        sampler.onUpdate = { landed.fulfill() }
        sampler.want(first)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(sampler.image(for: first), "waits for the freeze")
        await gate.release()
        await fulfillment(of: [landed], timeout: 2)
        let grid = try XCTUnwrap(sampler.image(for: first))
        XCTAssertEqual(grid.width, 200)
        XCTAssertEqual(grid.height, 400)
        XCTAssertEqual(grid.scale, 2)
        XCTAssertLessThanOrEqual(grid.color(x: 100, y: 200).difference(RGB(r: 0, g: 0, b: 255)), 2, "the frozen pixels")
        let count = await calls.count
        XCTAssertEqual(count, 0, "nothing captured live")
        sampler.stop()
    }

    func testWithoutAFreezeTheSampleIsLive() async throws {
        let calls = Calls()
        let sampler = frozenFirstSampler(calls: calls, freeze: { nil }) // no permission, failed, or timed out
        sampler.start()
        let landed = expectation(description: "the live image")
        sampler.onUpdate = { landed.fulfill() }
        sampler.want(first)
        await fulfillment(of: [landed], timeout: 2)
        let asked = await calls.areas
        XCTAssertEqual(asked, [first])
        XCTAssertEqual(sampler.image(for: first)?.width, 200)
        sampler.stop()
    }

    func testAnAreaOffEveryFrozenDisplayIsSampledLive() async throws {
        let calls = Calls()
        let elsewhere = CGRect(x: 0, y: -1000, width: 400, height: 300)
        let frozen = FrozenScreen(shots: [.init(display: elsewhere, scale: 2, image: Self.blueImage(width: 800, height: 600))])
        let sampler = frozenFirstSampler(calls: calls, freeze: { frozen })
        sampler.start()
        let landed = expectation(description: "the live image")
        sampler.onUpdate = { landed.fulfill() }
        sampler.want(first)
        await fulfillment(of: [landed], timeout: 2)
        let asked = await calls.areas
        XCTAssertEqual(asked, [first])
        let grid = try XCTUnwrap(sampler.image(for: first))
        XCTAssertGreaterThan(grid.color(x: 100, y: 200).difference(RGB(r: 0, g: 0, b: 255)), 100, "not the frozen pixels")
        sampler.stop()
    }

    // The refresh still takes a failed area again.
    func testTheRefreshTakesAFailedAreaAgain() async {
        let calls = Calls()
        let asked = expectation(description: "asked at want, then again at the refresh")
        asked.expectedFulfillmentCount = 2
        asked.assertForOverFulfill = false
        let sampler = makeSampler(permitted: true, calls: calls, refresh: .milliseconds(300), before: { _ in
            asked.fulfill()
            throw Refused()
        })
        sampler.start()
        sampler.want(first)
        await fulfillment(of: [asked], timeout: 3)
        let areas = await calls.areas
        XCTAssertEqual(Array(areas.prefix(2)), [first, first])
        sampler.stop()
    }
}
