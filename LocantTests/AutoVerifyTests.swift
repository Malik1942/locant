import XCTest
@testable import Locant

final class AutoVerifyTests: XCTestCase {
    private func capture(mode: CaptureMode = .fix, bundleId: String = "com.inspireocean.app", createdAt: String = "2026-09-14T18:00:00+08:00",
                         element: ResolvedElement? = ResolvedElement(role: "button", rawRole: "AXButton", label: "Save", identifier: "save", identifierSource: .declared, value: nil, frame: Frame(x: 1, y: 2, w: 3, h: 4), path: []),
                         iterations: [Iteration] = []) -> Capture {
        var c = Capture(
            id: "20260914-180000-ab12", createdAt: createdAt, mode: mode,
            image: ImageInfo(path: "/tmp/locant-oryne-20260914-180000-ab12.png", widthPt: 10, heightPt: 10, scale: 2, crop: nil),
            source: SourceInfo(app: AppInfo(bundleId: bundleId, name: "Oryne"), window: nil, url: nil, simulator: nil, projectRoot: "/tmp/x", gitCommit: "abc123"),
            element: element, note: "round it"
        )
        c.iterations = iterations
        return c
    }

    private let now = ISO8601DateFormatter().date(from: "2026-09-14T20:00:00+08:00")!

    // 1
    func testOwnAppWithinADay() {
        XCTAssertTrue(AutoVerify.wants(capture(), activated: "com.inspireocean.app", now: now))
    }

    // 2
    func testOtherAppsAreIgnored() {
        XCTAssertFalse(AutoVerify.wants(capture(), activated: "com.apple.Safari", now: now))
        XCTAssertFalse(AutoVerify.wants(capture(mode: .reference), activated: "com.inspireocean.app", now: now))
    }

    // 3
    func testDrawnFrameAndNoElementAreIgnored() {
        XCTAssertFalse(AutoVerify.wants(capture(element: nil), activated: "com.inspireocean.app", now: now))
        let cluster = ResolvedElement(role: ElementResolver.clusterRole, rawRole: "", label: nil, identifier: nil, identifierSource: .unknown, value: nil, frame: Frame(x: 0, y: 0, w: 9, h: 9), path: [])
        XCTAssertFalse(AutoVerify.wants(capture(element: cluster), activated: "com.inspireocean.app", now: now))
        // specs/capture-shapes.md R127: a line of text read from the screen has no accessibility element to find again.
        let line = ResolvedElement(role: "staticText", rawRole: ElementResolver.textRawRole, label: "Weeknight noodles", identifier: nil,
                                   identifierSource: .unknown, value: nil, frame: Frame(x: 375, y: 558, w: 124, h: 16), path: [])
        XCTAssertFalse(AutoVerify.wants(capture(element: line), activated: "com.inspireocean.app", now: now))
        var text = line
        text.rawRole = "AXStaticText"
        XCTAssertTrue(AutoVerify.wants(capture(element: text), activated: "com.inspireocean.app", now: now))
    }

    // 4
    func testWatchEndsAfterADay() {
        XCTAssertTrue(AutoVerify.wants(capture(createdAt: "2026-09-13T20:00:01+08:00"), activated: "com.inspireocean.app", now: now))
        XCTAssertFalse(AutoVerify.wants(capture(createdAt: "2026-09-13T19:59:59+08:00"), activated: "com.inspireocean.app", now: now))
        XCTAssertFalse(AutoVerify.wants(capture(createdAt: "not a date"), activated: "com.inspireocean.app", now: now))
    }

    // 5
    func testComparesWithTheNewestImage() {
        XCTAssertEqual(AutoVerify.previousImagePath(of: capture()), "/tmp/locant-oryne-20260914-180000-ab12.png")
        let iteration = Iteration(capturedAt: "2026-09-14T18:05:00+08:00", imagePath: "/tmp/after-1.png", gitBefore: "abc123", gitAfter: nil, diffStat: nil, files: [])
        XCTAssertEqual(AutoVerify.previousImagePath(of: capture(iterations: [iteration])), "/tmp/after-1.png")
    }

    // MARK: The newest Point capture (v0.8 R58)

    private func entry(_ names: [String], minutesOld: Double) -> LifecycleEntry {
        LifecycleEntry(urls: names.map { URL(filePath: "/tmp/\($0)") }, modified: now.addingTimeInterval(-minutesOld * 60), pinned: false, resolved: false)
    }

    // 6: a set's extra crops ride in its entry, so counting files hid it from before & after.
    func testTheNewestSetIsPickedDespiteItsExtraCrops() {
        let single = entry(["locant-oryne-20260914-180000-ab12.png", "locant-oryne-20260914-180000-ab12.json"], minutesOld: 30)
        let set = entry([
            "locant-oryne-20260914-183000-cd34.png",
            "locant-oryne-20260914-183000-cd34.json",
            "locant-oryne-20260914-183000-cd34-2.png",
            "locant-oryne-20260914-183000-cd34-3.png",
        ], minutesOld: 10)
        XCTAssertEqual(AutoVerify.newestSidecar(among: [single, set])?.lastPathComponent, "locant-oryne-20260914-183000-cd34.json")
        XCTAssertEqual(AutoVerify.newestSidecar(among: [set, single])?.lastPathComponent, "locant-oryne-20260914-183000-cd34.json")
    }

    // 7: an image with no sidecar is a Snap, a Cut, or an after-image — never a Point capture.
    func testImagesWithoutASidecarAreNotCaptures() {
        let snap = entry(["locant-snap-figma-20260914-190000-ef56.png"], minutesOld: 1)
        let after = entry(["locant-oryne-20260914-180000-ab12-after-1.png"], minutesOld: 2)
        let point = entry(["locant-oryne-20260914-180000-ab12.png", "locant-oryne-20260914-180000-ab12.json"], minutesOld: 30)
        XCTAssertEqual(AutoVerify.newestSidecar(among: [snap, after, point])?.lastPathComponent, "locant-oryne-20260914-180000-ab12.json")
        XCTAssertNil(AutoVerify.newestSidecar(among: [snap, after]))
        XCTAssertNil(AutoVerify.newestSidecar(among: []))
    }

    // 8: what `capture.image` holds decides how many elements have to be refound.
    func testASharedImageNeedsEveryElementRefound() {
        func target(_ id: String, imagePath: String? = nil) -> CaptureTarget {
            CaptureTarget(
                element: ResolvedElement(role: "button", rawRole: "AXButton", label: nil, identifier: id, identifierSource: .declared, value: nil, frame: Frame(x: 0, y: 0, w: 10, h: 10), path: []),
                app: AppInfo(bundleId: "com.inspireocean.app", name: "Oryne"), window: nil, url: nil, imagePath: imagePath
            )
        }
        var alone = capture()
        XCTAssertFalse(AutoVerify.sharesOneImage(alone), "a single element owns its image")
        XCTAssertEqual(AutoVerify.companions(of: alone), [])

        alone.targets = [target("a"), target("b")]
        XCTAssertTrue(AutoVerify.sharesOneImage(alone), "no extra crops means one image covers the union")
        XCTAssertEqual(AutoVerify.companions(of: alone).map(\.identifier), ["b"])

        alone.targets = [target("a"), target("b", imagePath: "/tmp/x-2.png")]
        XCTAssertFalse(AutoVerify.sharesOneImage(alone), "extra crops mean the image is element 1's own")
        XCTAssertEqual(AutoVerify.companions(of: alone), [])
    }
}
