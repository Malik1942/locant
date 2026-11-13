import JavaScriptCore
import XCTest
@testable import Locant

/// The component and source lines a page gives for a web node (specs/web-source.md).
final class WebSourceLocatorTests: XCTestCase {
    private func fixture(_ name: String, _ ext: String = "json") throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: ext), "fixture \(name).\(ext)")
        return try Data(contentsOf: url)
    }

    private func text(_ name: String, _ ext: String = "json") throws -> String {
        try XCTUnwrap(String(data: try fixture(name, ext), encoding: .utf8))
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

    /// The Library card's caption on bricks-build, as the lookup returns it.
    private var card: ComponentInfo {
        ComponentInfo(framework: "react", name: "Card", ancestors: ["Grid", "Library", "Routes", "Page", "App"],
                      props: [ComponentProp(name: "brick", value: "{id, photo, saved_at, title, measurements, …}"), ComponentProp(name: "onOpen", value: "[function]")],
                      source: SourceLocation(file: "/src/Library.tsx", line: 150, column: 7),
                      renderedAt: SourceLocation(file: "/src/Library.tsx", line: 93, column: 24))
    }

    /// A dev server that serves what the test hands it, and counts what it was asked for.
    private final class Server: @unchecked Sendable {
        private let lock = NSLock()
        private var files: [String: String]
        private(set) var asked: [String] = []
        init(_ files: [String: String]) { self.files = files }
        var fetch: WebSourceMaps.Fetch {
            { [self] url in serve(url.absoluteString) }
        }
        private func serve(_ address: String) -> String? {
            lock.withLock {
                asked.append(address)
                return files[address]
            }
        }
    }

    // MARK: Browsers

    func testTheBrowsersLocantCanAsk() {
        for id in ["com.google.Chrome", "com.google.Chrome.canary", "company.thebrowser.dia", "com.microsoft.edgemac", "com.brave.Browser"] {
            XCTAssertNotNil(WebSourceLocator.browser(bundleId: id), id)
        }
        // Safari's and Arc's answers were not read from a working install, and Firefox has no command.
        for id in ["com.apple.Safari", "company.thebrowser.Browser", "org.mozilla.firefox", "com.anthropic.claudefordesktop"] {
            XCTAssertNil(WebSourceLocator.browser(bundleId: id), id)
        }
        XCTAssertNil(WebSourceLocator.browser(bundleId: nil))
        XCTAssertEqual(WebSourceLocator.browser(bundleId: "company.thebrowser.dia")?.door, .launchFlag("--enable-applescript-javascript"))
    }

    func testOnlyLocalPagesAreAsked() {
        XCTAssertTrue(WebSourceLocator.asks(bundleId: "com.google.Chrome", url: "http://localhost:5176/#/brick/g2"))
        XCTAssertTrue(WebSourceLocator.asks(bundleId: "company.thebrowser.dia", url: "http://127.0.0.1:3000/"))
        XCTAssertFalse(WebSourceLocator.asks(bundleId: "com.google.Chrome", url: "https://tearsheet.malikzhang.com/"))
        XCTAssertFalse(WebSourceLocator.asks(bundleId: "com.google.Chrome", url: "file:///Users/me/index.html"))
        XCTAssertFalse(WebSourceLocator.asks(bundleId: "com.apple.Safari", url: "http://localhost:5176/"))
        XCTAssertFalse(WebSourceLocator.asks(bundleId: "com.google.Chrome", url: nil))
    }

    /// Each browser's refusal, verbatim from osascript on Nov 13 2026: Chrome 157, Edge 157, Brave 1.99, Dia 1.57.1.
    func testEachBrowsersRefusalIsRecognised() throws {
        let refusals = [
            "com.google.Chrome": "50:99: execution error: Google Chrome got an error: Executing JavaScript through AppleScript is turned off. To turn it on, from the menu bar, go to View > Developer > Allow JavaScript from Apple Events. For more information: https://support.google.com/chrome/?p=applescript (12)",
            "com.microsoft.edgemac": "54:103: execution error: Microsoft Edge got an error: Executing JavaScript through AppleScript is turned off. To turn it on, from the menu bar, go to View > Developer > Allow JavaScript from Apple Events. For more information: https://permanently-removed.invalid (12)",
            "com.brave.Browser": "50:99: execution error: Brave Browser got an error: Executing JavaScript through AppleScript is turned off. To turn it on, from the menu bar, go to View > Developer > Allow JavaScript from Apple Events. For more information: https://support.google.com/chrome/?p=applescript (12)",
            "company.thebrowser.dia": "55:104: execution error: Dia got an error: JavaScript execution via AppleScript requires the --enable-applescript-javascript launch flag. (-10006)",
        ]
        for (id, complaint) in refusals {
            let browser = try XCTUnwrap(WebSourceLocator.browser(bundleId: id))
            XCTAssertEqual(WebSourceLocator.failure(from: complaint, browser: browser), .doorClosed, id)
            XCTAssertTrue(WebSourceLocator.Failure.doorClosed.needsSetup)
        }
        let chrome = try XCTUnwrap(WebSourceLocator.browser(bundleId: "com.google.Chrome"))
        XCTAssertEqual(WebSourceLocator.failure(from: "33:41: execution error: Not authorized to send Apple events to Google Chrome. (-1743)", browser: chrome), .denied)
        // Safari's words are not Chrome's, and a browser that never answered has none.
        let safari = "49:95: execution error: Safari got an error: You must enable 'Allow JavaScript from Apple Events' in the Developer section of Safari Settings to use 'do JavaScript'. (8)"
        guard case .noAnswer = WebSourceLocator.failure(from: safari, browser: chrome) else { return XCTFail("Safari's refusal read as Chrome's") }
        XCTAssertEqual(WebSourceLocator.failure(from: "", browser: chrome), .noAnswer("no reply in 10 s"))
        XCTAssertFalse(WebSourceLocator.Failure.noWindow.needsSetup)
        XCTAssertEqual(WebSourceLocator.Failure.doorClosed.reason(for: try XCTUnwrap(WebSourceLocator.browser(bundleId: "company.thebrowser.dia"))),
                       "Dia was opened without --enable-applescript-javascript")
    }

    /// Dia returns the script's string as a JSON string (measured Nov 13 2026); the others return it bare.
    func testDiasQuotedReplyIsUnwrapped() {
        let dia = #""{\"sum\":2,\"title\":\"Tearsheet\"}""#
        XCTAssertEqual(WebSourceLocator.unquoted(dia), #"{"sum":2,"title":"Tearsheet"}"#)
        XCTAssertEqual(WebSourceLocator.unquoted(#"{"v":2}"#), #"{"v":2}"#)
    }

    func testThePageCommandPassesOverWindowsWithoutTabsAndNotRefusals() throws {
        let command = WebSourceLocator.pageCommand(bundleId: "com.google.Chrome.beta")
        XCTAssertTrue(command.contains(#"tell application id "com.google.Chrome.beta""#))
        XCTAssertTrue(command.contains("set t to active tab of w"))
        XCTAssertTrue(command.contains("then return execute t javascript js"), "the refusal is outside the try")
        XCTAssertTrue(command.contains(WebSourceLocator.noWindowError))
    }

    // MARK: The reply and its lines

    /// Chrome's reply for a card's caption on bricks-build (Vite 8, React 19.3), and the module's own map.
    func testViteStacksMapToTheLinesAsWritten() async throws {
        let answer = try XCTUnwrap(WebSourceLocator.decode(try text("web-source-reply-vite")))
        XCTAssertEqual(answer.framework, "react")
        XCTAssertEqual(answer.components, ["Card", "Grid", "Library", "Routes", "Page", "App"])
        XCTAssertEqual(answer.props?.map(\.name), ["brick", "onOpen"])
        let map = Data(try text("web-source-map-vite").utf8).base64EncodedString()
        let server = Server(["http://localhost:5176/src/Library.tsx": "export {}\n//# sourceMappingURL=data:application/json;base64,\(map)\n"])
        let maps = WebSourceMaps(page: URL(string: "http://localhost:5176/")!, fetch: server.fetch)
        let source = await maps.location(of: try XCTUnwrap(answer.source?.stack))
        let rendered = await maps.location(of: try XCTUnwrap(answer.renderedAt?.stack))
        XCTAssertEqual(source, SourceLocation(file: "/src/Library.tsx", line: 150, column: 7))
        XCTAssertEqual(rendered, SourceLocation(file: "/src/Library.tsx", line: 93, column: 24))
        XCTAssertEqual(server.asked, ["http://localhost:5176/src/Library.tsx"], "one module, read once, and no library")
    }

    /// Next.js 16.4 with Turbopack: the JSX runtime sits in the app's own chunk, and the chunk's map is in sections.
    func testTurbopackSkipsTheRuntimeFrameAndReadsSections() async throws {
        let answer = try XCTUnwrap(WebSourceLocator.decode(try text("web-source-reply-turbopack")))
        let chunk = "http://localhost:3987/_next/static/chunks/_1733q6qtibemv._.js"
        XCTAssertEqual(answer.source?.stack?.first?.url, chunk, "the runtime's frame is in the app's chunk")
        let server = Server([chunk: "(globalThis.TURBOPACK = []).push([]);\n\n//# sourceMappingURL=_1733q6qtibemv._.js.map",
                             chunk + ".map": try text("web-source-map-turbopack")])
        let maps = WebSourceMaps(page: URL(string: "http://localhost:3987/")!, fetch: server.fetch)
        let source = await maps.location(of: try XCTUnwrap(answer.source?.stack))
        let rendered = await maps.location(of: try XCTUnwrap(answer.renderedAt?.stack))
        XCTAssertEqual(source, SourceLocation(file: "/Users/me/next-probe/app/Rows.tsx", line: 12, column: 7))
        XCTAssertEqual(rendered, SourceLocation(file: "/Users/me/next-probe/app/Rows.tsx", line: 21, column: 26))
    }

    /// Next.js 16.4 with webpack: frames name `webpack-internal:` modules, whose maps sit inline in the page's chunk.
    func testWebpackFindsTheModulesMapInsideTheChunk() async throws {
        let answer = try XCTUnwrap(WebSourceLocator.decode(try text("web-source-reply-webpack")))
        let scripts = try XCTUnwrap(answer.scripts)
        XCTAssertEqual(scripts, ["http://localhost:3987/_next/static/chunks/app/page.js"])
        let server = Server([scripts[0]: try text("web-source-chunk-webpack", "txt")])
        let maps = WebSourceMaps(page: URL(string: "http://localhost:3987/")!, scripts: scripts, fetch: server.fetch)
        let source = await maps.location(of: try XCTUnwrap(answer.source?.stack))
        let rendered = await maps.location(of: try XCTUnwrap(answer.renderedAt?.stack))
        XCTAssertEqual(source, SourceLocation(file: "/Users/me/next-probe/app/Rows.tsx", line: 12, column: 7))
        XCTAssertEqual(rendered, SourceLocation(file: "/Users/me/next-probe/app/Rows.tsx", line: 21, column: 26))
        XCTAssertEqual(server.asked, scripts, "the chunk is read once for both lines")
    }

    func testOnlyTheMacsOwnServersAreFetched() async {
        let server = Server([:])
        let maps = WebSourceMaps(page: URL(string: "http://localhost:3000/")!, scripts: ["https://cdn.example.com/app.js"], fetch: server.fetch)
        let remote = [StackFrame(fn: "Card", url: "https://cdn.example.com/app.js", line: 3, column: 9),
                      StackFrame(fn: "Home", url: "about://React/Prerender/file:///Users/me/.next/dev/server/chunks/ssr/page.js?3", line: 67, column: 264),
                      StackFrame(fn: "Card", url: "webpack-internal:///(app-pages-browser)/./app/Card.tsx", line: 4, column: 2)]
        let location = await maps.location(of: remote)
        XCTAssertNil(location, "a server component's line is deferred, and nothing remote is read")
        XCTAssertEqual(server.asked, [])
    }

    func testAModuleWithoutAMapIsItsOwnSource() async {
        let server = Server(["http://localhost:8000/js/app.js": "function App() {}\n"])
        let maps = WebSourceMaps(page: URL(string: "http://localhost:8000/")!, fetch: server.fetch)
        let location = await maps.location(of: [StackFrame(fn: "exports.jsx", url: "http://localhost:8000/js/app.js", line: 1, column: 1),
                                                StackFrame(fn: "App", url: "http://localhost:8000/js/app.js?v=3", line: 12, column: 5)])
        XCTAssertNil(location, "the copy with a query was not served")
        let plain = await maps.location(of: [StackFrame(fn: "App", url: "http://localhost:8000/js/app.js", line: 12, column: 5)])
        XCTAssertEqual(plain, SourceLocation(file: "/js/app.js", line: 12, column: 5))
    }

    func testRuntimeFramesAreReactsOwn() {
        let chunk = "http://localhost:3987/_next/static/chunks/_1733q6qtibemv._.js"
        XCTAssertTrue(WebSourceMaps.isRuntime(StackFrame(fn: "exports.jsxDEV", url: chunk, line: 291, column: 33)))
        XCTAssertTrue(WebSourceMaps.isRuntime(StackFrame(fn: "fakeJSXCallSite", url: chunk, line: 1, column: 1)))
        XCTAssertTrue(WebSourceMaps.isRuntime(StackFrame(fn: "Object.react_stack_bottom_frame", url: chunk, line: 1, column: 1)))
        XCTAssertTrue(WebSourceMaps.isRuntime(StackFrame(fn: "renderWithHooks", url: "http://localhost:5176/node_modules/.vite/deps/react-dom_client.js?v=4", line: 1, column: 1)))
        XCTAssertFalse(WebSourceMaps.isRuntime(StackFrame(fn: "Row", url: chunk, line: 33, column: 215)))
        XCTAssertFalse(WebSourceMaps.isRuntime(StackFrame(fn: "", url: chunk, line: 61, column: 239)), "an arrow function in the user's code")
    }

    func testMappingNumbersAndReferences() {
        XCTAssertEqual(SourceMap.decode("AAAA"), [0, 0, 0, 0])
        XCTAssertEqual(SourceMap.decode("D"), [-1])
        XCTAssertEqual(SourceMap.decode("gBAAU"), [16, 0, 0, 10])
        XCTAssertEqual(SourceMap.decode("A?A"), [0], "stops at what is not a digit")
        XCTAssertEqual(WebSourceMaps.mapReference(in: "x()\n//# sourceMappingURL=app.js.map\n"), "app.js.map")
        XCTAssertNil(WebSourceMaps.mapReference(in: #"eval("//# sourceMappingURL=data:application/json;base64,e30=\n");\nmore()"#), "inside a string, not the file's own")
        XCTAssertNil(WebSourceMaps.mapReference(in: "plain()"))
        XCTAssertNil(SourceMap(json: Data(#"{"version":3}"#.utf8)))
        // Another module's map before this module's name is not this module's.
        let chunk = #"eval("a\n//# sourceMappingURL=data:application/json;charset=utf-8;base64,e30=\n//# sourceURL=webpack-internal:///./a.js\n");eval("b\n//# sourceURL=webpack-internal:///./b.js\n");"#
        XCTAssertNotNil(WebSourceMaps.evaluatedMap(for: "webpack-internal:///./a.js", in: chunk))
        XCTAssertNil(WebSourceMaps.evaluatedMap(for: "webpack-internal:///./b.js", in: chunk))
    }

    func testSourceNamesBecomePaths() {
        let page = URL(string: "http://localhost:5176/")!
        let module = URL(string: "http://localhost:5176/src/Library.tsx?t=1794")!
        XCTAssertEqual(WebSourceMaps.file(named: "Library.tsx", base: module, page: page), "/src/Library.tsx")
        XCTAssertEqual(WebSourceMaps.file(named: "file:///Users/me/my%20app/app/Rows.tsx", base: nil, page: page), "/Users/me/my app/app/Rows.tsx")
        XCTAssertEqual(WebSourceMaps.file(named: "/Users/me/app/Rows.tsx", base: nil, page: page), "/Users/me/app/Rows.tsx")
        XCTAssertEqual(WebSourceMaps.file(named: "webpack://_N_E/./app/Rows.tsx", base: nil, page: page), "/app/Rows.tsx")
        XCTAssertEqual(WebSourceMaps.file(named: "webpack:///./src/App.js", base: nil, page: page), "/src/App.js")
        XCTAssertEqual(WebSourceMaps.file(named: "turbopack:///[project]/app/page.tsx", base: nil, page: page), "/app/page.tsx")
    }

    func testProductionBuildKeepsNamesWithoutLines() throws {
        let answer = try XCTUnwrap(WebSourceLocator.decode(#"{"v":2,"framework":"react","production":true,"components":["Card","Grid"]}"#))
        XCTAssertNil(answer.source)
        let info = ComponentInfo(framework: "react", name: "Card", ancestors: ["Grid"], props: [], source: nil, renderedAt: nil)
        let md = MarkdownBuilder.build(capture(element(component: info)))
        XCTAssertTrue(md.contains("Component: Card in Grid (React, read from the page)\n"), md)
        XCTAssertFalse(md.contains("Source:"))
        XCTAssertFalse(md.contains("Rendered at:"))
    }

    func testMarkdownShowsComponentLinesUnderTheElement() throws {
        var info = card
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
        located.component = card
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

    func testMatchURLDropsTheFragment() {
        XCTAssertEqual(WebSourceLocator.matchURL("http://localhost:5176/#/brick/g2"), "http://localhost:5176/")
        XCTAssertEqual(WebSourceLocator.matchURL("http://localhost:5176/brick/g2?x=1"), "http://localhost:5176/brick/g2?x=1")
    }

    func testPageScriptFillsTheHandles() throws {
        let script = try XCTUnwrap(WebSourceLocator.pageScript(for: element(), area: CGRect(x: 22, y: 148, width: 1200, height: 1107)), "web-source.js is in the app bundle")
        XCTAssertFalse(script.contains("__LOCANT_ARGS__"))
        XCTAssertTrue(script.contains(#""id":"caption-g2""#), String(script.suffix(200)))
        XCTAssertTrue(script.contains(#""area":{"#), String(script.suffix(200)))
        XCTAssertFalse(script.contains("XMLHttpRequest") || script.contains("fetch("), "the page fetches nothing (R152)")
        // It parses as JavaScript.
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("var f = function () { return " + script + " }")
        XCTAssertNil(context.exception, context.exception?.toString() ?? "")
    }

    /// The script against a stand-in page: a node with a React 19 fiber whose stacks are Chromium's and
    /// WebKit's own shapes, under a client component that a server component rendered.
    func testThePageScriptReadsNamesPropsAndStacks() throws {
        let page = #"""
        var window = { innerWidth: 1200, innerHeight: 1107 };
        var location = { origin: 'http://localhost:3987' };
        var home = { name: 'Home', env: 'Prerender', props: { params: { status: 'fulfilled', _debugChunk: null } }, owner: null };
        var rows = { tag: 0, type: function Rows() {}, memoizedProps: {}, _debugOwner: home };
        var title = { tag: 5, type: 'h1', _debugOwner: home };
        var heading = { tagName: 'H1', id: 'server-title', classList: [], parentNode: null, '__reactFiber$x1': title };
        var row = { tag: 0, type: function Row() {}, memoizedProps: { item: { id: 'b2', title: 'Bravo', price: 5 }, children: 1 },
          _debugStack: { stack: 'exports.jsxDEV@http://localhost:3987/a.js:291:33\n@http://localhost:3987/a.js:61:239\nRows@http://localhost:3987/a.js:61:25' },
          _debugOwner: rows };
        var fiber = { tag: 5, type: 'span', _debugOwner: row,
          _debugStack: { stack: 'Error: react-stack-top-frame\n    at exports.jsxDEV (webpack-internal:///(app-pages-browser)/./node_modules/next/dist/compiled/react/cjs/react-jsx-dev-runtime.development.js:333:29)\n    at Row (webpack-internal:///(app-pages-browser)/./app/Rows.tsx:28:88)\n    at Array.map (<anonymous>)' } };
        var node = { tagName: 'SPAN', id: 'row-b2', classList: ['row-title'], parentNode: null, '__reactFiber$x1': fiber };
        var document = { getElementById: function (id) { return id === 'row-b2' ? node : id === 'server-title' ? heading : null; },
          scripts: [{ src: 'http://localhost:3987/_next/static/chunks/app/page.js' }, { src: 'https://cdn.example.com/x.js' }, { src: '' }] };
        """#
        let row = ResolvedElement(role: "text", rawRole: "AXStaticText", label: "Bravo", identifier: nil, identifierSource: .unknown, value: nil,
                                  frame: Frame(x: 100, y: 300, w: 60, h: 18), path: [], dom: DOMInfo(id: "row-b2", classes: ["row-title"]))
        let script = try XCTUnwrap(WebSourceLocator.pageScript(for: row))
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript(page)
        let reply = try XCTUnwrap(context.evaluateScript(script)?.toString())
        XCTAssertNil(context.exception, context.exception?.toString() ?? "")
        let answer = try XCTUnwrap(WebSourceLocator.decode(reply), reply)
        XCTAssertNil(answer.error, reply)
        XCTAssertEqual(answer.components, ["Row", "Rows", "Home"], "the server component is named by its record")
        XCTAssertEqual(answer.props?.map(\.name), ["item"], "children are left out")
        XCTAssertEqual(answer.props?.first?.value, "{id, title, price}")
        XCTAssertEqual(answer.source?.stack, [
            StackFrame(fn: "exports.jsxDEV", url: "webpack-internal:///(app-pages-browser)/./node_modules/next/dist/compiled/react/cjs/react-jsx-dev-runtime.development.js", line: 333, column: 29),
            StackFrame(fn: "Row", url: "webpack-internal:///(app-pages-browser)/./app/Rows.tsx", line: 28, column: 88),
        ], "a webpack address keeps its own brackets, and a frame without a place is dropped")
        XCTAssertEqual(answer.renderedAt?.stack, [
            StackFrame(fn: "exports.jsxDEV", url: "http://localhost:3987/a.js", line: 291, column: 33),
            StackFrame(fn: "", url: "http://localhost:3987/a.js", line: 61, column: 239),
            StackFrame(fn: "Rows", url: "http://localhost:3987/a.js", line: 61, column: 25),
        ], "WebKit's shape")
        XCTAssertEqual(answer.scripts, ["http://localhost:3987/_next/static/chunks/app/page.js"], "only the page's own, only for webpack")

        // An element a server component rendered: the component is named, and the promises it was handed are not props.
        let served = ResolvedElement(role: "heading", rawRole: "AXHeading", label: "Probe", identifier: nil, identifierSource: .unknown, value: nil,
                                     frame: Frame(x: 100, y: 200, w: 90, h: 30), path: [], dom: DOMInfo(id: "server-title", classes: []))
        let home = try XCTUnwrap(WebSourceLocator.decode(try XCTUnwrap(context.evaluateScript(try XCTUnwrap(WebSourceLocator.pageScript(for: served)))?.toString())))
        XCTAssertEqual(home.components, ["Home"])
        XCTAssertEqual(home.props?.count, 0)
        XCTAssertNil(home.source)

        // A page that is not React says so.
        context.evaluateScript("delete node['__reactFiber$x1']")
        let none = try XCTUnwrap(WebSourceLocator.decode(try XCTUnwrap(context.evaluateScript(script)?.toString())))
        XCTAssertEqual(none.error, "no React fiber on the node or its ancestors")
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
        let wrapped = WebSourceLocator.pageWorldScript(#"JSON.stringify({v:2,framework:"react",components:["Card"]})"#, event: "locant-web-source-test")
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript(fakeDOM)
        let result = context.evaluateScript(wrapped)?.toString()
        XCTAssertNil(context.exception, context.exception?.toString() ?? "")
        XCTAssertEqual(WebSourceLocator.decode(result ?? "")?.components, ["Card"])

        // A page that never runs the script (Content-Security-Policy) says so.
        context.evaluateScript("document.documentElement.appendChild = function () {}")
        XCTAssertTrue(context.evaluateScript(wrapped)?.toString().contains("did not run the script") ?? false)
    }

    func testAnswerGivesUpAtTheLimitWithoutStoppingTheTask() async {
        let slow = Task<Int, Never> { try? await Task.sleep(for: .milliseconds(400)); return 7 }
        let start = ContinuousClock.now
        let early = await WebSourceLocator.answer(of: slow, within: .milliseconds(50))
        XCTAssertNil(early)
        XCTAssertLessThan(ContinuousClock.now - start, .milliseconds(300))
        let later = await slow.value
        XCTAssertEqual(later, 7)
        let fast = Task<Int, Never> { 3 }
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
