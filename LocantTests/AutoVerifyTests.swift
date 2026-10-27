import AppKit
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
        // specs/capture-shapes.md R135: a line of text read from the screen has no accessibility element to find again.
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

    // 9: specs/capture-shapes.md R134: in Device Hub a capture commits the card as drawn, inside the padded frame
    // accessibility reports; the element found again is tightened by the same rule, so the two images show one outline.
    func testAnIterationOfATightenedCaptureTightensTheElementFoundAgain() {
        let screen = CGRect(x: 347.9, y: 137.5, width: 359.7, height: 780.9)
        let padded = CGRect(x: 362.2, y: 543.2, width: 331.1, height: 75.9)
        let drawn = CGRect(x: 363.4, y: 549.0, width: 329.5, height: 64.0)
        let tight = drawn.intersection(padded)
        func card(_ frame: CGRect) -> ResolvedElement {
            ResolvedElement(role: "button", rawRole: "AXButton", label: "Weeknight noodles, yesterday", identifier: nil,
                            identifierSource: .unknown, value: nil, frame: Frame(frame), path: [])
        }
        func inHub(_ element: ResolvedElement) -> Capture {
            var c = capture(element: element)
            c.source.simulator = SimulatorInfo(device: "iPhone 17", appBundleId: "com.inspireocean.app")
            return c
        }
        var asked: [CGRect] = []
        func ink(_ rect: CGRect) -> CGRect? {
            asked.append(rect)
            return drawn.offsetBy(dx: 0, dy: rect.minY - padded.minY)
        }
        XCTAssertEqual(AutoVerify.afterFrame(of: inHub(card(tight)), found: padded, screen: screen, ink: ink), tight)
        XCTAssertEqual(asked, [padded], "what is drawn is read inside the frame found again")
        let moved = padded.offsetBy(dx: 0, dy: 100)
        XCTAssertEqual(AutoVerify.afterFrame(of: inHub(card(tight)), found: moved, screen: screen, ink: ink), tight.offsetBy(dx: 0, dy: 100),
                       "moved: tightened where it is now")

        asked = []
        XCTAssertEqual(AutoVerify.afterFrame(of: inHub(card(padded)), found: padded, screen: screen, ink: ink), padded,
                       "a capture that committed the padded frame (clicked before the sample landed) is cropped around it")
        XCTAssertEqual(AutoVerify.afterFrame(of: inHub(card(tight)), found: padded, screen: nil, ink: ink), padded, "no simulated screen in the tree")
        XCTAssertEqual(AutoVerify.afterFrame(of: capture(element: card(tight)), found: padded, screen: screen, ink: ink), padded, "not a simulator")
        let small = CGRect(x: 606.5, y: 220.0, width: 39.4, height: 39.3)
        XCTAssertEqual(AutoVerify.afterFrame(of: inHub(card(small.insetBy(dx: 10, dy: 10))), found: small, screen: screen, ink: ink), small, "under 44 pt")
        var set = inHub(card(tight))
        let other = CaptureTarget(element: card(padded.offsetBy(dx: 0, dy: 80)), app: AppInfo(bundleId: "com.inspireocean.app", name: "Oryne"),
                                  window: nil, url: nil, imagePath: nil)
        set.targets = [CaptureTarget(element: card(tight), app: other.app, window: nil, url: nil, imagePath: nil), other]
        XCTAssertEqual(AutoVerify.afterFrame(of: set, found: padded, screen: screen, ink: ink), padded, "a set's shared image")
        XCTAssertEqual(asked, [], "none of these reads a pixel")
    }

    // 10: the after-image is cut from the crop just taken, pixel for pixel, and what is drawn is read from that crop.
    func testTheAfterImageIsCutFromTheCropJustTaken() throws {
        // 100×60 pt at 2x, at (500, 300) on screen: dark gray, with a light mark at 530,320 10×5 pt.
        let (width, height) = (200, 120)
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let level: UInt8 = (60..<80).contains(x) && (40..<50).contains(y) ? 220 : 30
                bytes[(y * width + x) * 4] = level
                bytes[(y * width + x) * 4 + 1] = level
                bytes[(y * width + x) * 4 + 2] = level
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                          space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                          provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: 100, height: 60)
        let taken = CroppedImage(png: try XCTUnwrap(rep.representation(using: .png, properties: [:])), widthPt: 100, heightPt: 60, scale: 2,
                                 crop: CGRect(x: 500, y: 300, width: 100, height: 60))

        let grid = try XCTUnwrap(taken.grid())
        XCTAssertEqual(grid.frame, taken.crop)
        XCTAssertEqual(grid.scale, 2)
        XCTAssertEqual(grid.edgeBounds(inside: taken.crop), CGRect(x: 529.5, y: 319.5, width: 11, height: 6), "the mark, one sample past it")

        let cut = try XCTUnwrap(taken.cut(to: CGRect(x: 520, y: 310, width: 40, height: 30)))
        XCTAssertEqual(cut.crop, CGRect(x: 520, y: 310, width: 40, height: 30))
        XCTAssertEqual(cut.widthPt, 40)
        XCTAssertEqual(cut.heightPt, 30)
        XCTAssertEqual(cut.scale, 2)
        let back = try XCTUnwrap(PixelGrid(image: try XCTUnwrap(ImageDiff.image(fromPNG: cut.png)), frame: cut.crop, scale: 2, generation: 0))
        XCTAssertEqual(back.width, 80)
        XCTAssertEqual(back.height, 60)
        for (x, y) in [(0, 0), (20, 20), (39, 29), (40, 30), (79, 59)] {
            XCTAssertEqual(back.color(x: x, y: y), grid.color(x: x + 40, y: y + 20), "sample \(x), \(y)")
        }
        XCTAssertEqual(back.color(x: 20, y: 20).r, 220, "inside the mark")

        XCTAssertEqual(taken.cut(to: CGRect(x: 580, y: 340, width: 50, height: 50))?.crop, CGRect(x: 580, y: 340, width: 20, height: 20), "cut to the crop")
        XCTAssertNil(taken.cut(to: CGRect(x: 0, y: 0, width: 10, height: 10)), "outside it")
    }

    // 11: specs/capture-shapes.md R135: a line read from the screen has no accessibility element, so a set that has to
    // refind one with its first element would find another element in its place.
    func testASetWithALineToRefindIsIgnored() {
        func target(_ element: ResolvedElement, imagePath: String? = nil) -> CaptureTarget {
            CaptureTarget(element: element, app: AppInfo(bundleId: "com.inspireocean.app", name: "Oryne"), window: nil, url: nil, imagePath: imagePath)
        }
        let first = ResolvedElement(role: "button", rawRole: "AXButton", label: "Save", identifier: "save", identifierSource: .declared, value: nil,
                                    frame: Frame(x: 1, y: 2, w: 3, h: 4), path: [])
        let line = ResolvedElement(role: "staticText", rawRole: ElementResolver.textRawRole, label: "Weeknight noodles", identifier: nil,
                                   identifierSource: .unknown, value: nil, frame: Frame(x: 375, y: 558, w: 124, h: 16), path: [])
        var set = capture(element: first)
        set.targets = [target(first), target(line)]
        XCTAssertFalse(AutoVerify.wants(set, activated: "com.inspireocean.app", now: now), "the line shares the image: it would be refound")

        var text = line
        text.rawRole = "AXStaticText"
        set.targets = [target(first), target(text)]
        XCTAssertTrue(AutoVerify.wants(set, activated: "com.inspireocean.app", now: now), "an accessibility staticText is refound")

        set.targets = [target(first), target(line, imagePath: "/tmp/x-2.png")]
        XCTAssertTrue(AutoVerify.wants(set, activated: "com.inspireocean.app", now: now),
                      "with an image of its own, only the first element is refound")
    }
}
