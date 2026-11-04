import JavaScriptCore
import XCTest
@testable import Locant

/// Prototype: the component and source lines a page gives for a web node (WebSourceLocator).
final class WebSourceLocatorTests: XCTestCase {
    /// Chrome's reply for the caption of a Library card on bricks-build (Nov 4 2026), verbatim.
    static let chromeReply = #"{"v":1,"node":{"tag":"p","id":"caption-g2","classes":["card-caption"]},"framework":"react","source":{"file":"/src/Library.tsx","line":150,"column":7,"via":"sourcemap"},"components":["Card","Grid","Library","Routes","Page","App"],"props":[{"name":"brick","value":"{id, photo, saved_at, title, measurements, …}"},{"name":"onOpen","value":"[function]"}],"renderedAt":{"file":"/src/Library.tsx","line":93,"column":24,"via":"sourcemap"}}"#

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"), "fixture \(name)")
        return try Data(contentsOf: url)
    }

    private func element(id: String? = "caption-g2", classes: [String] = ["card-caption"], component: ComponentInfo? = nil) -> ResolvedElement {
        ResolvedElement(role: "group", rawRole: "AXGroup", label: nil, identifier: nil, identifierSource: .unknown, value: nil,
                        frame: Frame(x: 620, y: 520, w: 279, h: 20), path: [], dom: DOMInfo(id: id, classes: classes), component: component)
    }

    private func capture(_ element: ResolvedElement) -> Capture {
        Capture(id: "20261104-101500-c9wk", createdAt: "2026-11-04T10:15:00-08:00", mode: .fix,
                image: ImageInfo(path: "/tmp/x.png", widthPt: 340, heightPt: 100, scale: 2, crop: nil),
                source: SourceInfo(app: AppInfo(bundleId: "com.google.Chrome", name: "Google Chrome"), window: WindowInfo(title: "Tearsheet"),
                                   url: "http://localhost:5176/", simulator: nil),
                element: element, note: "why only saved and a date?")
    }

    func testParsesChromesReply() throws {
        let info = try XCTUnwrap(WebSourceLocator.parse(Self.chromeReply))
        XCTAssertEqual(info.framework, "react")
        XCTAssertEqual(info.name, "Card")
        XCTAssertEqual(info.ancestors, ["Grid", "Library", "Routes", "Page", "App"])
        XCTAssertEqual(info.props.map(\.name), ["brick", "onOpen"])
        XCTAssertEqual(info.source, SourceLocation(file: "/src/Library.tsx", line: 150, column: 7))
        XCTAssertEqual(info.renderedAt, SourceLocation(file: "/src/Library.tsx", line: 93, column: 24))
    }

    func testErrorsAndNonReactPagesGiveNothing() {
        XCTAssertNil(WebSourceLocator.parse(#"{"v":1,"node":{"tag":"p"},"error":"no React fiber on the node or its ancestors"}"#))
        XCTAssertNil(WebSourceLocator.parse(#"{"v":1,"error":"no window shows the captured page"}"#))
        XCTAssertNil(WebSourceLocator.parse("execution error: Executing JavaScript through AppleScript is turned off."))
        XCTAssertNil(WebSourceLocator.parse(#"{"v":1,"framework":"react","components":[]}"#), "a fiber with nothing to name")
    }

    func testProductionBuildKeepsNamesWithoutLines() throws {
        let info = try XCTUnwrap(WebSourceLocator.parse(#"{"v":1,"framework":"react","production":true,"components":["Card","Grid"]}"#))
        XCTAssertEqual(info.name, "Card")
        XCTAssertNil(info.source)
        let md = MarkdownBuilder.build(capture(element(component: info)))
        XCTAssertTrue(md.contains("Component: Card in Grid (React, read from the page)\n"), md)
        XCTAssertFalse(md.contains("Source:"))
        XCTAssertFalse(md.contains("Rendered at:"))
    }

    func testMarkdownShowsComponentLinesUnderTheElement() throws {
        var info = try XCTUnwrap(WebSourceLocator.parse(Self.chromeReply))
        let root = "/Users/malik/Documents/mhackathon/bricks-build"
        info.source = WebSourceLocator.absolutize(info.source!, root: root) { $0 == root + "/src/Library.tsx" }
        info.renderedAt = WebSourceLocator.absolutize(info.renderedAt!, root: root) { $0 == root + "/src/Library.tsx" }
        let md = MarkdownBuilder.build(capture(element(classes: [], component: info)))
        XCTAssertTrue(md.contains("""
        group · #caption-g2
        Component: Card in Grid › Library › Routes › Page › … (React, read from the page)
        Props: brick {id, photo, saved_at, title, measurements, …} · onOpen [function]
        Source: \(root)/src/Library.tsx:150:7 (this element's JSX)
        Rendered at: \(root)/src/Library.tsx:93:24 (where <Card> is used)
        Frame:
        """), md)
    }

    func testSourceLineReplacesTheGrepAdvice() throws {
        let classesOnly = element(id: nil, classes: ["grid", "grid-cols-2"])
        XCTAssertTrue(MarkdownBuilder.build(capture(classesOnly)).contains("No id attribute. Grep the class names"))
        var located = classesOnly
        located.component = try XCTUnwrap(WebSourceLocator.parse(Self.chromeReply))
        XCTAssertFalse(MarkdownBuilder.build(capture(located)).contains("No id attribute"))
    }

    func testAbsolutizeOnlyWhenTheFileIsThere() {
        let served = SourceLocation(file: "/src/App.tsx", line: 3, column: 1)
        XCTAssertEqual(WebSourceLocator.absolutize(served, root: "/p") { $0 == "/p/src/App.tsx" }.file, "/p/src/App.tsx")
        XCTAssertEqual(WebSourceLocator.absolutize(served, root: "/p") { _ in false }.file, "/src/App.tsx")
        let absolute = SourceLocation(file: "/Users/me/app/src/App.tsx", line: 3, column: nil)
        XCTAssertEqual(WebSourceLocator.absolutize(absolute, root: "/p") { $0 == absolute.file }, absolute, "React 18 gives real paths")
        XCTAssertEqual(absolute.text, "/Users/me/app/src/App.tsx:3")
    }

    func testOnlyChromeForNow() {
        XCTAssertTrue(WebSourceLocator.supports(bundleId: "com.google.Chrome"))
        XCTAssertTrue(WebSourceLocator.supports(bundleId: "com.google.Chrome.canary"))
        XCTAssertFalse(WebSourceLocator.supports(bundleId: "company.thebrowser.dia"))
        XCTAssertFalse(WebSourceLocator.supports(bundleId: "com.apple.Safari"))
        XCTAssertFalse(WebSourceLocator.supports(bundleId: nil))
    }

    func testMatchURLDropsTheFragment() {
        XCTAssertEqual(WebSourceLocator.matchURL("http://localhost:5176/#/brick/g2"), "http://localhost:5176/")
        XCTAssertEqual(WebSourceLocator.matchURL("http://localhost:5176/brick/g2?x=1"), "http://localhost:5176/brick/g2?x=1")
    }

    func testPageScriptFillsTheHandles() throws {
        let script = try XCTUnwrap(WebSourceLocator.pageScript(for: element()), "web-source.js is in the app bundle")
        XCTAssertFalse(script.contains("__LOCANT_ARGS__"))
        XCTAssertTrue(script.contains(#""id":"caption-g2""#), String(script.suffix(200)))
        // It parses as JavaScript.
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("var f = function () { return " + script + " }")
        XCTAssertNil(context.exception, context.exception?.toString() ?? "")
    }

    /// The wrapper runs the main script through a script element and returns what it dispatched. A fake
    /// DOM in JavaScriptCore stands in for the page: appendChild runs the element's text, as a browser does.
    func testPageWorldWrapperReturnsTheDispatchedAnswer() throws {
        let fakeDOM = """
        var listeners = {};
        function CustomEvent(type, init) { this.type = type; this.detail = init.detail; }
        var document = {
          addEventListener: function (t, f) { (listeners[t] = listeners[t] || []).push(f); },
          removeEventListener: function (t, f) { listeners[t] = (listeners[t] || []).filter(function (g) { return g !== f; }); },
          dispatchEvent: function (e) { (listeners[e.type] || []).forEach(function (f) { f(e); }); },
          createElement: function () { return { textContent: '', remove: function () {} }; },
          documentElement: { appendChild: function (s) { eval(s.textContent); } },
          head: null
        };
        """
        let wrapped = WebSourceLocator.pageWorldScript(#"JSON.stringify({v:1,framework:"react",components:["Card"]})"#, event: "locant-web-source-test")
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript(fakeDOM)
        let result = context.evaluateScript(wrapped)?.toString()
        XCTAssertNil(context.exception, context.exception?.toString() ?? "")
        XCTAssertEqual(WebSourceLocator.parse(result ?? "")?.name, "Card")

        // A page that never runs the script (Content-Security-Policy) says so.
        context.evaluateScript("document.documentElement.appendChild = function () {}")
        XCTAssertTrue(context.evaluateScript(wrapped)?.toString().contains("did not run the script") ?? false)
    }

    func testAnswerGivesUpAtTheLimitWithoutStoppingTheTask() async {
        let slow = Task<Int?, Never> { try? await Task.sleep(for: .milliseconds(400)); return 7 }
        let start = ContinuousClock.now
        let early = await WebSourceLocator.answer(of: slow, within: .milliseconds(50))
        XCTAssertNil(early)
        XCTAssertLessThan(ContinuousClock.now - start, .milliseconds(300))
        let later = await slow.value
        XCTAssertEqual(later, 7)
        let fast = Task<Int?, Never> { 3 }
        let quick = await WebSourceLocator.answer(of: fast, within: .seconds(2))
        XCTAssertEqual(quick, 3)
    }

    func testSidecarWithComponentDecodesAndRoundTrips() throws {
        let capture = try JSONDecoder().decode(Capture.self, from: try fixture("sidecar-web-component"))
        XCTAssertEqual(capture.element?.component?.name, "Card")
        XCTAssertEqual(capture.element?.component?.renderedAt?.line, 93)
        let again = try JSONDecoder().decode(Capture.self, from: try JSONEncoder().encode(capture))
        XCTAssertEqual(again, capture)
    }
}
