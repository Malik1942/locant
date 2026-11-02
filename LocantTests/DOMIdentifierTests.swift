import XCTest
@testable import Locant

/// v0.8: web nodes carry the DOM's handles; the payload, the hover label, and the path use them.
final class DOMIdentifierTests: XCTestCase {
    private func fixture(_ name: String) throws -> ElementSnapshot {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"), "fixture \(name)")
        return try JSONDecoder().decode(ElementSnapshot.self, from: Data(contentsOf: url))
    }

    private func capture(_ element: ResolvedElement, url: String? = nil, mode: CaptureMode = .reference) -> Capture {
        Capture(
            id: "20260916-120000-ab12", createdAt: "2026-09-16T12:00:00-07:00", mode: mode,
            image: ImageInfo(path: "/tmp/x.png", widthPt: 300, heightPt: 124, scale: 2, crop: nil),
            source: SourceInfo(app: AppInfo(bundleId: "company.thebrowser.dia", name: "Dia"), window: WindowInfo(title: "Cart"), url: url, simulator: nil),
            element: element, note: "make this rounded"
        )
    }

    func testChromiumButtonCarriesDOMIdAndClasses() throws {
        let e = try XCTUnwrap(ElementResolver.resolve(try fixture("chromium-button")))
        XCTAssertNil(e.identifier, "no accessibility identifier on a plain web button")
        XCTAssertEqual(e.dom?.id, "checkout-button")
        XCTAssertEqual(e.dom?.classes, ["btn", "btn-primary", "w-full"])
        XCTAssertEqual(e.label, "Checkout")
    }

    func testPathSegmentsShowDOMHandles() throws {
        let e = try XCTUnwrap(ElementResolver.resolve(try fixture("chromium-button")))
        XCTAssertEqual(e.path.map(\.dom), [nil, nil, "#root", ".relative", "#checkout", ".actions", "#checkout-button"])
        XCTAssertEqual(e.path.map(\.identifier), [nil, nil, nil, nil, nil, nil, nil])
    }

    func testSnapshotDecodesPageURL() throws {
        XCTAssertEqual(try fixture("chromium-button").url, "http://localhost:5173/cart")
    }

    func testMarkdownHeadAndPathForWebNode() throws {
        let e = try XCTUnwrap(ElementResolver.resolve(try fixture("chromium-button")))
        let md = MarkdownBuilder.build(capture(e, url: "http://localhost:5173/cart"))
        XCTAssertTrue(md.contains("button \"Checkout\" · #checkout-button · .btn.btn-primary.w-full\n"), md)
        XCTAssertTrue(md.contains("Path: window > webArea > group#root > group.relative > group#checkout > group.actions > button#checkout-button"), md)
        XCTAssertTrue(md.contains("URL: http://localhost:5173/cart"), md)
        XCTAssertFalse(md.contains("No identifier"), "a DOM id is a handle; no advice line")
        XCTAssertFalse(md.contains("no identifier"))
    }

    func testClassesOnlyIsCappedAndAdvisesAnId() throws {
        let e = try XCTUnwrap(ElementResolver.resolve(try fixture("chromium-classes-only")))
        XCTAssertNil(e.dom?.id)
        let md = MarkdownBuilder.build(capture(e, url: "http://localhost:5173/cart", mode: .fix))
        XCTAssertTrue(md.contains("staticText · .text-sm.font-medium.text-muted.tracking-tight.uppercase.mt-2 (+2 more)\n"), md)
        XCTAssertTrue(md.contains("No id attribute. Grep the class names"), md)
        XCTAssertFalse(md.contains("accessibilityIdentifier"), "web advice, not SwiftUI advice")
        // Someone else's page: the fact, not an id to add.
        let reference = MarkdownBuilder.build(capture(e))
        XCTAssertTrue(reference.contains("(+2 more)\nNo id attribute.\nValue: \"Total\"\n"), reference)
        XCTAssertFalse(reference.contains("give the element an id"))
    }

    func testHoverReadoutShowsDOMHandle() throws {
        let button = try XCTUnwrap(ElementResolver.resolve(try fixture("chromium-button")))
        let r = Readout.describing(button)
        XCTAssertEqual(r.identifier, "#checkout-button")
        XCTAssertNil(r.suffix)
        let text = try XCTUnwrap(ElementResolver.resolve(try fixture("chromium-classes-only")))
        let r2 = Readout.describing(text)
        XCTAssertEqual(r2.identifier, ".text-sm.font-medium")
        XCTAssertEqual(r2.role, "staticText")
    }

    func testNativeElementHasNoDOM() throws {
        let e = try XCTUnwrap(ElementResolver.resolve(try fixture("swiftui-button")))
        XCTAssertNil(e.dom)
        XCTAssertEqual(e.path.map(\.dom), [nil, nil, nil, nil])
        let md = MarkdownBuilder.build(capture(e))
        XCTAssertTrue(md.contains("· id=captureButton\n"), md)
    }

    func testLocalhostURLPutsCaptureInFixMode() {
        var source = SourceInfo(app: AppInfo(bundleId: "company.thebrowser.dia", name: "Dia"), window: nil, url: "http://localhost:5173/cart", simulator: nil)
        XCTAssertEqual(ModeClassifier.classify(source), .fix)
        source.url = "https://www.example.com/cart"
        XCTAssertEqual(ModeClassifier.classify(source), .reference)
    }

    func testSidecarRoundTripsDOM() throws {
        let e = try XCTUnwrap(ElementResolver.resolve(try fixture("chromium-button")))
        let data = try JSONEncoder().encode(capture(e, url: "http://localhost:5173/cart"))
        let back = try JSONDecoder().decode(Capture.self, from: data)
        XCTAssertEqual(back.element?.dom, e.dom)
        XCTAssertEqual(back.element?.path, e.path)
        XCTAssertEqual(back.source.url, "http://localhost:5173/cart")
    }
}
