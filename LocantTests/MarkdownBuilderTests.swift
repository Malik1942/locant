import XCTest
@testable import Locant

final class MarkdownBuilderTests: XCTestCase {
    private func element(identifier: String? = "captureButton", role: String = "button", label: String? = "Capture",
                         source: IdentifierSource = .declared) -> ResolvedElement {
        ResolvedElement(
            role: role, rawRole: "AX" + role.prefix(1).uppercased() + role.dropFirst(), label: label,
            identifier: identifier, identifierSource: source, value: nil,
            frame: Frame(x: 312, y: 88, w: 64, h: 32),
            path: [PathEntry(role: "group", identifier: nil), PathEntry(role: "toolbar", identifier: nil), PathEntry(role: role, identifier: identifier)]
        )
    }

    private func capture(mode: CaptureMode = .fix, element: ResolvedElement?, note: String = "make this rounded") -> Capture {
        Capture(
            id: "20260912-140312-k7q2",
            createdAt: "2026-09-12T14:03:12-07:00",
            mode: mode,
            image: ImageInfo(path: "/Users/malik/Pictures/Locant/locant-simulator-20260912-140312-k7q2.png", widthPt: 144, heightPt: 112, scale: 2, crop: Frame(x: 272, y: 48, w: 144, h: 112)),
            source: SourceInfo(
                app: AppInfo(bundleId: "com.apple.iphonesimulator", name: "Simulator"),
                window: WindowInfo(title: "iPhone 17 Pro"),
                url: nil,
                simulator: SimulatorInfo(device: "iPhone 17 Pro", appBundleId: "com.malikzhang.oryne")
            ),
            element: element,
            note: note
        )
    }

    private func lines(_ md: String) -> [String] { md.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) }

    // 1
    func testFixModeOrdering() {
        let md = MarkdownBuilder.build(capture(element: element()))
        let l = lines(md)
        XCTAssertEqual(l[0], "## Locant capture (fix)")
        XCTAssertEqual(l[1], "Image: /Users/malik/Pictures/Locant/locant-simulator-20260912-140312-k7q2.png")
        XCTAssertEqual(l[2], "App: Simulator (com.malikzhang.oryne) · Window: iPhone 17 Pro")
        XCTAssertEqual(l[3], "Captured: 2026-09-12 14:03 · Image region: 144×112 pt @2x (element + 40 pt)")
        let element = try! XCTUnwrap(md.range(of: "### Target element"))
        let note = try! XCTUnwrap(md.range(of: "### Note"))
        XCTAssertLessThan(element.lowerBound, note.lowerBound)
        XCTAssertTrue(md.contains("button \"Capture\" · id=captureButton\n"))
        XCTAssertTrue(md.contains("Frame: x=312 y=88 w=64 h=32\n"))
        XCTAssertTrue(md.contains("Path: group > toolbar > button#captureButton\n"))
        XCTAssertTrue(md.hasSuffix("### Note\nmake this rounded\n"))
    }

    // 2
    func testReferenceModeLeadsWithNote() {
        let md = MarkdownBuilder.build(capture(mode: .reference, element: element(), note: "make mine like this"))
        let l = lines(md)
        XCTAssertEqual(l[0], "## Locant capture (reference)")
        XCTAssertEqual(l[1], "### Note")
        XCTAssertEqual(l[2], "make mine like this")
        XCTAssertEqual(l[3], "")
        let note = md.range(of: "### Note")!, image = md.range(of: "Image: ")!, element = md.range(of: "### Target element")!
        XCTAssertLessThan(note.lowerBound, image.lowerBound)
        XCTAssertLessThan(image.lowerBound, element.lowerBound)
    }

    // 3
    func testNullElementRendersNoInformationBlock() {
        let md = MarkdownBuilder.build(capture(element: nil))
        XCTAssertTrue(md.contains("### Target element\nNo element information available (app exposes no accessibility tree). Use the image.\n"))
        XCTAssertTrue(md.contains("(around the click point)"))
        XCTAssertFalse(md.contains("Frame:"))
    }

    // 4
    func testEmptyNoteOmitsNoteSection() {
        XCTAssertFalse(MarkdownBuilder.build(capture(element: element(), note: "")).contains("### Note"))
        XCTAssertFalse(MarkdownBuilder.build(capture(element: element(), note: "  \n")).contains("### Note"))
    }

    // 5
    func testIdentifierWithHashAndQuotesIsNotEscaped() {
        let weird = "tab#2\"main\""
        let md = MarkdownBuilder.build(capture(element: element(identifier: weird)))
        XCTAssertTrue(md.contains("· id=tab#2\"main\"\n"))
        XCTAssertTrue(md.contains("> button#tab#2\"main\"\n"))
        XCTAssertFalse(md.contains("\\\""))
    }

    // 6
    func testSymbolNameCaveat() {
        let symbol = MarkdownBuilder.build(capture(element: element(identifier: "plus", role: "image", label: nil, source: .possiblySymbolName)))
        XCTAssertTrue(symbol.contains("image · id=plus (may be a symbol name, not a declared identifier)\n"))
        let declared = MarkdownBuilder.build(capture(element: element()))
        XCTAssertFalse(declared.contains("may be a symbol name"))
    }

    // 7
    func testNullIdentifierRendersHint() {
        let md = MarkdownBuilder.build(capture(element: element(identifier: nil, source: .unknown)))
        XCTAssertTrue(md.contains("button \"Capture\" · no identifier\nNo identifier. Grep the label text; add .accessibilityIdentifier(\"…\") to this view so the next capture is exact.\n"))
        XCTAssertTrue(md.contains("Path: group > toolbar > button\n"))
    }

    func testClusterRendersMembers() throws {
        let cluster = ResolvedElement(
            role: "cluster", rawRole: "LocantCluster", label: nil, identifier: nil, identifierSource: .unknown, value: nil,
            frame: Frame(x: 43, y: 590, w: 370, h: 120),
            path: [PathEntry(role: "window", identifier: nil), PathEntry(role: "group", identifier: nil), PathEntry(role: "cluster", identifier: nil)],
            members: [
                ElementMember(role: "staticText", label: "Shortcut", identifier: nil),
                ElementMember(role: "button", label: "Action Button", identifier: "shortcutActionButton"),
            ]
        )
        let md = MarkdownBuilder.build(capture(element: cluster))
        XCTAssertTrue(md.contains("cluster · 2 elements (visual grouping computed by Locant, not an accessibility element; frame approximate)\nMembers: staticText \"Shortcut\" · button \"Action Button\"#shortcutActionButton\nFrame: x=43 y=590 w=370 h=120\nPath: window > group > cluster\n"))
        XCTAssertFalse(md.contains("no identifier"))

        let data = try JSONEncoder().encode(capture(element: cluster))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let el = try XCTUnwrap(json["element"] as? [String: Any])
        XCTAssertEqual((el["members"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual(try JSONDecoder().decode(Capture.self, from: data).element, cluster)
        let plain = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(capture(element: element()))) as? [String: Any]
        XCTAssertNil((plain?["element"] as? [String: Any])?["members"], "members only exist on clusters")
    }

    // specs/capture-shapes.md R121: a shape's frame is its visible edges; a cluster's stays approximate.
    func testShapeHeadLineSaysItsFrameIsTheVisibleEdges() {
        let shape = ResolvedElement(
            role: "cluster", rawRole: "LocantShape", label: nil, identifier: nil, identifierSource: .unknown, value: nil,
            frame: Frame(x: 2036, y: -1147, w: 163, h: 37),
            path: [PathEntry(role: "group", identifier: nil), PathEntry(role: "cluster", identifier: nil)],
            members: [ElementMember(role: "button", label: "Recent", identifier: nil),
                      ElementMember(role: "button", label: "Currents", identifier: nil)]
        )
        let md = MarkdownBuilder.build(capture(element: shape))
        XCTAssertTrue(md.contains("cluster · 2 elements (shape found on screen by Locant, not an accessibility element; frame from its visible edges)\nMembers: button \"Recent\" · button \"Currents\"\n"), md)
        XCTAssertFalse(md.contains("frame approximate"))
    }

    // specs/capture-shapes.md R124: a row of touching controls says what it is, and that its frame is their union.
    func testGroupHeadLineSaysItsFrameIsTheUnionOfTheControls() {
        let group = ResolvedElement(
            role: "cluster", rawRole: "LocantGroup", label: nil, identifier: nil, identifierSource: .unknown, value: nil,
            frame: Frame(x: 559.6, y: 398.2, w: 118.1, h: 39.3),
            path: [PathEntry(role: "group", identifier: nil), PathEntry(role: "cluster", identifier: nil)],
            members: [ElementMember(role: "button", label: nil, identifier: "folder"),
                      ElementMember(role: "button", label: nil, identifier: "square.and.arrow.up"),
                      ElementMember(role: "button", label: nil, identifier: "trash")]
        )
        let md = MarkdownBuilder.build(capture(element: group))
        XCTAssertTrue(md.contains("cluster · 3 elements (controls in one row or column, grouped by Locant, not an accessibility element; frame is their union)\nMembers: button#folder · button#square.and.arrow.up · button#trash\n"), md)
        XCTAssertFalse(md.contains("frame approximate"))
        XCTAssertFalse(md.contains("visible edges"))
    }

    // specs/capture-shapes.md R127: a line read from the screen prints like any element, and says what it is.
    func testATextLineSaysLocantReadItFromTheScreen() {
        let line = ResolvedElement(
            role: "staticText", rawRole: "LocantText", label: "Weeknight noodles", identifier: nil, identifierSource: .unknown, value: nil,
            frame: Frame(x: 375, y: 558, w: 124, h: 16),
            path: [PathEntry(role: "group", identifier: nil), PathEntry(role: "button", identifier: nil), PathEntry(role: "staticText", identifier: nil)]
        )
        let md = MarkdownBuilder.build(capture(element: line))
        XCTAssertTrue(md.contains("### Target element\nstaticText \"Weeknight noodles\" · no identifier\nText read from the screen by Locant; not an accessibility element. The element it sits in is the next ⌥ level.\nNo identifier. Grep the label text; it is drawn by that element's view, the last step of Path before staticText.\nFrame: x=375 y=558 w=124 h=16\nPath: group > button > staticText\n"), md)
        XCTAssertFalse(md.contains("accessibilityIdentifier"), "a line is no view of its own: nothing to add an identifier to")

        var element = line
        element.rawRole = "AXStaticText"
        let plain = MarkdownBuilder.build(capture(element: element))
        XCTAssertFalse(plain.contains("Text read from the screen"), "an accessibility element says nothing of the kind")
        XCTAssertTrue(plain.contains("add .accessibilityIdentifier(\"…\") to this view"))
    }

    func testNullElementHintsAtIdentifier() {
        let md = MarkdownBuilder.build(capture(element: nil))
        XCTAssertTrue(md.contains("Use the image.\nIf this view is yours, give it .accessibilityElement() and .accessibilityIdentifier(\"…\") so Locant can point at it next time.\n"))
    }

    // v0.2
    private func regionElement(_ role: String, label: String?, id: String?, x: Double, y: Double, w: Double, h: Double) -> RegionElement {
        RegionElement(role: role, rawRole: "AX" + role, label: label, identifier: id, identifierSource: id == nil ? .unknown : .declared, frame: Frame(x: x, y: y, w: w, h: h))
    }

    func testElementsInFrameBlockAndRegionSourceLine() throws {
        var c = capture(element: element(identifier: "shortcutActionButton", label: "Action Button"))
        c.elements = [
            regionElement("staticText", label: "Shortcut", id: nil, x: 95, y: 590, w: 140, h: 28),
            regionElement("button", label: "Action Button", id: "shortcutActionButton", x: 59, y: 660, w: 169, h: 50),
        ]
        let md = MarkdownBuilder.build(c)
        XCTAssertTrue(md.contains("(drawn frame)\n"))
        XCTAssertTrue(md.contains("### Elements in frame (2)\nstaticText \"Shortcut\" · x=95 y=590 w=140 h=28\nbutton \"Action Button\" · id=shortcutActionButton · x=59 y=660 w=169 h=50\n"))
        let elements = md.range(of: "### Elements in frame")!, note = md.range(of: "### Note")!, target = md.range(of: "### Target element")!
        XCTAssertLessThan(target.lowerBound, elements.lowerBound)
        XCTAssertLessThan(elements.lowerBound, note.lowerBound)
        c.elements = []
        XCTAssertTrue(MarkdownBuilder.build(c).contains("### Elements in frame (0)\nNo accessibility elements inside the frame.\n"))

        let data = try JSONEncoder().encode(c)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["elements"])
        XCTAssertEqual(try JSONDecoder().decode(Capture.self, from: data), c)
    }

    func testNearbyAndTextBlocksForNullElement() {
        var c = capture(element: nil)
        c.image.crop = Frame(x: 100, y: 350, w: 200, h: 200) // click at (200, 450)
        c.nearby = [regionElement("button", label: "Resurfacing", id: nil, x: 43, y: 304, w: 370, h: 48)]
        c.ocr = "Product Ideas\nCooking"
        let md = MarkdownBuilder.build(c)
        XCTAssertTrue(md.contains("### Nearby\nbutton \"Resurfacing\" · 98 pt above\n"))
        XCTAssertTrue(md.contains("### Text in image\nProduct Ideas\nCooking\n"))
        XCTAssertLessThan(md.range(of: "### Nearby")!.lowerBound, md.range(of: "### Text in image")!.lowerBound)
        XCTAssertFalse(md.contains("### Elements in frame"))
    }

    func testProjectLineWhenRootKnown() {
        var c = capture(element: element())
        XCTAssertFalse(MarkdownBuilder.build(c).contains("Project:"))
        c.source.projectRoot = "/Users/malik/Documents/inspire-ocean"
        let l = lines(MarkdownBuilder.build(c))
        XCTAssertEqual(l[4], "Project: /Users/malik/Documents/inspire-ocean")
        XCTAssertEqual(l[5], MarkdownBuilder.projectAdvice, "the path alone went unread by agents in another checkout")
        XCTAssertEqual(l[6], "", "the source block ends after the advice")
    }

    func testNoProjectAdviceWithoutRoot() {
        XCTAssertFalse(MarkdownBuilder.build(capture(element: element())).contains(MarkdownBuilder.projectAdvice))
    }

    func testNumberFormatting() {
        XCTAssertEqual(MarkdownBuilder.number(57.99999), "58")
        XCTAssertEqual(MarkdownBuilder.number(58.0), "58")
        XCTAssertEqual(MarkdownBuilder.number(893.6667), "893.7")
        XCTAssertEqual(MarkdownBuilder.number(0.04), "0")
    }

    func testCaptureJSONRoundTripsWithExplicitNulls() throws {
        let c = capture(element: nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(c)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue(json["element"] is NSNull)
        XCTAssertTrue(json["ocr"] is NSNull)
        XCTAssertEqual((json["iterations"] as? [Any])?.count, 0)
        let source = try XCTUnwrap(json["source"] as? [String: Any])
        XCTAssertTrue(source["url"] is NSNull)
        let decoded = try JSONDecoder().decode(Capture.self, from: data)
        XCTAssertEqual(decoded, c)

        let withElement = capture(element: element(identifier: nil, source: .unknown))
        let json2 = try XCTUnwrap(JSONSerialization.jsonObject(with: try encoder.encode(withElement)) as? [String: Any])
        let el = try XCTUnwrap(json2["element"] as? [String: Any])
        XCTAssertTrue(el["identifier"] is NSNull)
        XCTAssertTrue(el["value"] is NSNull)
        XCTAssertEqual(el["rawRole"] as? String, "AXButton")
    }
}
