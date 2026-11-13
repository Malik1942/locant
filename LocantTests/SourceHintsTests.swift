import XCTest
@testable import Locant

/// specs/source-hints.md R157–R162.
final class SourceHintsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "LocantSource-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ path: String, _ text: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func element(label: String? = "Recent", identifier: String? = nil, role: String = "button",
                         members: [ElementMember]? = nil, dom: DOMInfo? = nil) -> ResolvedElement {
        ResolvedElement(role: role, rawRole: "AXButton", label: label, identifier: identifier,
                        identifierSource: identifier == nil ? .unknown : .declared, value: nil,
                        frame: Frame(x: 10, y: 10, w: 80, h: 30), path: [PathEntry(role: role, identifier: identifier)],
                        members: members, dom: dom)
    }

    private func hint(_ element: ResolvedElement, neighbors: [String] = [], ocr: String? = nil) throws -> SourceHint? {
        let query = try XCTUnwrap(SourceHints.query(for: element, neighbors: neighbors, ocr: ocr))
        return SourceHints.find(query, in: root)
    }

    // R158: what is looked for.

    func testTheQueryHoldsTheIdentifierTheLabelAndItsParts() {
        let query = SourceHints.query(for: element(label: "Resurfacing, Catching a thought", identifier: "tide.card"),
                                      neighbors: ["Ocean", "Resurfacing"], ocr: "•ll Transcript\n10 fragments")
        XCTAssertEqual(query?.anchors, ["tide.card", "Resurfacing, Catching a thought", "Resurfacing", "Catching a thought"])
        XCTAssertEqual(query?.context, ["Ocean", "•ll Transcript", "ll Transcript", "Transcript", "10 fragments", "fragments"],
                       "the element's own strings are not their own context; an icon read as a glyph or a letter or two is dropped")
    }

    func testWhatCannotBeAStringLiteralIsLeftOut() {
        XCTAssertNil(SourceHints.clean("say \"hi\""))
        XCTAssertNil(SourceHints.clean("a\\b"))
        XCTAssertNil(SourceHints.clean("x"))
        XCTAssertNil(SourceHints.clean(String(repeating: "long ", count: 30)))
        XCTAssertEqual(SourceHints.clean("  Cancel "), "Cancel")
        XCTAssertNil(SourceHints.query(for: element(label: nil), neighbors: [], ocr: nil))
        XCTAssertNil(SourceHints.query(for: element(dom: DOMInfo(id: "save", classes: [])), neighbors: [], ocr: nil),
                     "a web node keeps its DOM handles; no search")
        XCTAssertEqual(SourceHints.query(for: element(label: nil, identifier: "_TtGC7SwiftUI32NavigationStackHosting"), neighbors: ["Tide"], ocr: nil)?.anchors, [],
                       "a mangled Swift type name is nobody's string")
    }

    // R159–R160: the search and what it concludes.

    func testOneFileIsTheOnlyPlace() throws {
        try write("App/LibraryView.swift", "struct LibraryView {\n  let a = 1\n  Text(\"Recent\")\n}\n")
        try write("App/Other.swift", "// Recent changes\nlet recent = \"Recently\"\n")
        let found = try hint(element())
        XCTAssertEqual(found, SourceHint(kind: .only, strings: ["Recent"], places: [SourcePlace(file: "App/LibraryView.swift", lines: [3])], fileCount: 1),
                       "a whole string literal, not the word in a comment or inside a longer string")
    }

    func testTheFileWithOtherTextFromTheCaptureIsLikeliest() throws {
        try write("App/AskView.swift", ".navigationTitle(\"Ask\")\nTextField(\"Find a thought\", text: $q)\n")
        try write("App/RootTabView.swift", "Label(\"Ask\", systemImage: \"bubble\")\n")
        try write("Widgets/Widget.swift", "Text(\"Ask\")\n")
        let found = try XCTUnwrap(try hint(element(label: "Ask", role: "heading"), ocr: "Ask\nFind a though"))
        XCTAssertEqual(found.kind, .likeliest)
        XCTAssertEqual(found.places.first, SourcePlace(file: "App/AskView.swift", lines: [1]))
        XCTAssertEqual(found.places.map(\.file).dropFirst().sorted(), ["App/RootTabView.swift", "Widgets/Widget.swift"])
        XCTAssertEqual(found.fileCount, 3)
        XCTAssertEqual(found.alsoThere, ["Find a though"], "text read from the image is matched by its start")
    }

    func testSeveralFilesAndNothingToTellThemApart() throws {
        for index in 1...8 { try write("App/Sheet\(index).swift", "Button(\"Cancel\") {}\n") }
        let found = try XCTUnwrap(try hint(element(label: "Cancel")))
        XCTAssertEqual(found.kind, .several)
        XCTAssertEqual(found.fileCount, 8)
        XCTAssertEqual(found.places.count, SourceHints.listLimit)
        XCTAssertEqual(found.places.first?.file, "App/Sheet1.swift", "ties are listed in path order")
    }

    func testANeighborTellsCancelsApart() throws {
        try write("App/EditSheet.swift", "Button(\"Cancel\") {}\nButton(\"Save\") {}\n")
        try write("App/MoveSheet.swift", "Button(\"Cancel\") {}\nButton(\"Move\") {}\n")
        let found = try XCTUnwrap(try hint(element(label: "Cancel"), neighbors: ["Save"]))
        XCTAssertEqual(found.kind, .likeliest)
        XCTAssertEqual(found.places.first?.file, "App/EditSheet.swift")
        XCTAssertEqual(found.alsoThere, ["Save"])
    }

    func testTheIdentifierAndTheLabelInOneFileBeatTheLabelAlone() throws {
        try write("App/Detail.swift", "Image(systemName: \"folder\")\n  .accessibilityLabel(\"Move to a current\")\n")
        try write("App/MoveSheet.swift", ".navigationTitle(\"Move to a current\")\n")
        let found = try XCTUnwrap(try hint(element(label: "Move to a current", identifier: "folder")))
        XCTAssertEqual(found.kind, .likeliest)
        XCTAssertEqual(found.places.first, SourcePlace(file: "App/Detail.swift", lines: [1]))
        XCTAssertEqual(found.strings, ["folder", "Move to a current"])
        XCTAssertEqual(found.alsoThere, [])
    }

    func testDataTextPointsAtTheFixedTextBesideIt() throws {
        try write("App/Detail.swift", "Label(\"Transcript\", systemImage: \"waveform\")\nText(node.transcription)\n")
        let found = try XCTUnwrap(try hint(element(label: "So, the idea is, for now, More"), ocr: "•ll Transcript\nSo, the idea is, for now"))
        XCTAssertEqual(found, SourceHint(kind: .beside, strings: ["Transcript"], places: [SourcePlace(file: "App/Detail.swift", lines: [1])], fileCount: 1))
    }

    func testAClusterIsFoundByWhatItHolds() throws {
        try write("App/RootTabView.swift", "Label(\"Tide\", systemImage: \"water.waves\")\nLabel(\"Ask\", systemImage: \"bubble\")\nLabel(\"Library\", systemImage: \"books\")\n")
        try write("App/LibraryView.swift", ".navigationTitle(\"Library\")\n")
        let members = ["Tide", "Ask", "Library"].map { ElementMember(role: "button", label: $0, identifier: nil) }
        let found = try XCTUnwrap(try hint(element(label: nil, role: "cluster", members: members)))
        XCTAssertEqual(found.kind, .beside)
        XCTAssertEqual(found.places, [SourcePlace(file: "App/RootTabView.swift", lines: [1, 2, 3])])
        XCTAssertEqual(Set(found.strings), ["Tide", "Ask", "Library"])
    }

    func testNothingFoundIsSaid() throws {
        try write("App/A.swift", "Text(\"Ocean\")\n")
        XCTAssertEqual(try hint(element(label: "Tide")), SourceHint(kind: .none, strings: ["Tide"], places: [], fileCount: 0))
    }

    func testBuildsHiddenFoldersAndOtherFilesAreNotRead() throws {
        try write("App/A.swift", "Text(\"Recent\")\n")
        try write(".claude/worktrees/copy/App/A.swift", "Text(\"Recent\")\n")
        try write("DerivedData/x/A.swift", "Text(\"Recent\")\n")
        try write("node_modules/pkg/a.swift", "Text(\"Recent\")\n")
        try write("docs/notes.md", "\"Recent\"\n")
        XCTAssertEqual(try hint(element())?.kind, .only)
        XCTAssertEqual(try hint(element())?.places.map(\.file), ["App/A.swift"])
    }

    func testAnUnfinishedSearchSaysNothing() throws {
        for index in 1...40 { try write("App/F\(index).swift", "Text(\"Recent\")\n") }
        let query = try XCTUnwrap(SourceHints.query(for: element(), neighbors: [], ocr: nil))
        XCTAssertNil(SourceHints.find(query, in: root, fileLimit: 10), "more files than the limit")
        var clock = Date(timeIntervalSince1970: 0)
        let late = SourceHints.find(query, in: root, now: { clock += 1; return clock }, budget: 0.5)
        XCTAssertNil(late, "out of time")
        XCTAssertNotNil(SourceHints.find(query, in: root))
    }

    // R157: a capture, and a set.

    func testEveryElementOfASetGetsItsOwnHint() throws {
        try write("App/LibraryView.swift", "OceanSegmentedSwitch(\"Recent\", \"Currents\")\n")
        try write("App/OceanFieldView.swift", "Text(\"Currents\")\n")
        let app = AppInfo(bundleId: "com.apple.dt.Devices", name: "Device Hub")
        let first = element(label: "Recent"), second = element(label: "Currents")
        let capture = Capture(
            id: "20261023-022759-bkzx", createdAt: "2026-10-23T02:27:59-07:00", mode: .fix,
            image: ImageInfo(path: "", widthPt: 10, heightPt: 10, scale: 2, crop: nil),
            source: SourceInfo(app: app, window: nil, url: nil, simulator: nil, projectRoot: root.path(percentEncoded: false)),
            element: first, note: "",
            targets: [CaptureTarget(element: first, app: app, window: nil), CaptureTarget(element: second, app: app, window: nil)]
        )
        let hinted = SourceHints.annotate(capture, root: root, neighbors: [])
        XCTAssertEqual(hinted.element?.sourceHint?.kind, .only)
        XCTAssertEqual(hinted.targets?[0].element.sourceHint, hinted.element?.sourceHint)
        XCTAssertEqual(hinted.targets?[1].element.sourceHint?.kind, .likeliest)
        XCTAssertEqual(hinted.targets?[1].element.sourceHint?.places.first?.file, "App/LibraryView.swift")
        XCTAssertEqual(hinted.targets?[1].element.sourceHint?.alsoThere, ["Recent"])

        var none = capture
        none.element = nil
        none.targets = nil
        XCTAssertEqual(SourceHints.annotate(none, root: root, neighbors: ["Recent"]), none)
    }

    func testNeighborLabelsAreNearestFirstAndUnique() {
        func node(_ title: String?, x: Double) -> AttributeSet {
            AttributeSet(role: "AXButton", title: title, frame: Frame(x: x, y: 0, w: 10, h: 10))
        }
        let labels = SourceHints.neighborLabels(of: Frame(x: 100, y: 0, w: 10, h: 10),
                                                among: [node("Far", x: 900), node("Save", x: 120), node(nil, x: 101), node("Save", x: 300), node("Title", x: 60)])
        XCTAssertEqual(labels, ["Save", "Title", "Far"])
    }

    // R160, R162: what the payload says.

    func testThePayloadLines() {
        let one = element()
        let place = SourcePlace(file: "App/LibraryView.swift", lines: [543])
        XCTAssertEqual(MarkdownBuilder.sourceLine(SourceHint(kind: .only, strings: ["Recent"], places: [place], fileCount: 1), element: one),
                       "In source: App/LibraryView.swift:543 (the only file in the project with the string \"Recent\").")
        let likeliest = SourceHint(kind: .likeliest, strings: ["Ask"], places: [SourcePlace(file: "A.swift", lines: [52, 284]), SourcePlace(file: "B.swift", lines: [61])],
                                   fileCount: 2, alsoThere: ["Find a though"])
        XCTAssertEqual(MarkdownBuilder.sourceLine(likeliest, element: one),
                       "In source: \"Ask\" is a string in 2 files. Likeliest: A.swift:52, :284 (it also has \"Find a though\" from this capture). Others: B.swift:61.")
        let several = SourceHint(kind: .several, strings: ["Cancel"], places: [SourcePlace(file: "A.swift", lines: [1]), SourcePlace(file: "B.swift", lines: [2])], fileCount: 12)
        XCTAssertEqual(MarkdownBuilder.sourceLine(several, element: one),
                       "In source: \"Cancel\" is a string in 12 files, and nothing in this capture says which: A.swift:1, B.swift:2 and 10 more. Use the image and the note to choose.")
        let beside = SourceHint(kind: .beside, strings: ["Transcript"], places: [SourcePlace(file: "A.swift", lines: [257])], fileCount: 1)
        XCTAssertEqual(MarkdownBuilder.sourceLine(beside, element: one),
                       "In source: no string in the project matches this element's own text, so that text is probably data or the system's. Fixed text in or beside it: \"Transcript\" at A.swift:257.")
        XCTAssertEqual(MarkdownBuilder.sourceLine(beside, element: element(label: nil, role: "cluster")),
                       "In source: fixed text in or beside it: \"Transcript\" at A.swift:257.")
        XCTAssertEqual(MarkdownBuilder.sourceLine(SourceHint(kind: .none, strings: ["Tide"], places: [], fileCount: 0), element: one),
                       "In source: no \"Tide\" string in the project. The text may be data, or the app on screen was built from other code than this folder holds now.")
    }

    func testTheHintTakesThePlaceOfTheGrepAdviceAndTheHostsPathIsLeftOut() throws {
        let data = try Data(contentsOf: try XCTUnwrap(Bundle(for: Self.self).url(forResource: "sidecar-source-hint", withExtension: "json")))
        let capture = try JSONDecoder().decode(Capture.self, from: data)
        let markdown = MarkdownBuilder.build(capture)
        XCTAssertTrue(markdown.contains("""
        ### Target element
        button "Recent" · no identifier
        In source: "Recent" is a string in 2 files. Likeliest: Oryne/Features/Library/LibraryView.swift:543 (it also has "Currents" from this capture). Others: OceanWidgets/RecentWidget.swift:12, :40.
        Frame: x=2039.1 y=-1144.2 w=77.8 h=29.9

        ### Text in image
        """), markdown)
        XCTAssertFalse(markdown.contains("Grep the label text"))
        XCTAssertFalse(markdown.contains("DeviceManagementWindow"))
    }

    func testAPathKeepsWhatTheAppNames() {
        let host = PathEntry(role: "splitGroup", identifier: "com.apple.dt.DeviceKit.DeviceManagementWindow-AppWindow-1, SidebarNavigationSplitView")
        let path = [PathEntry(role: "group", identifier: nil), host, PathEntry(role: "group", identifier: nil), PathEntry(role: "button", identifier: "composer.attach")]
        XCTAssertNil(MarkdownBuilder.pathLine(path, mirrored: true), "the element's own identifier is on its head line; no ancestor names anything")
        let named = [host, PathEntry(role: "group", identifier: "composer"), PathEntry(role: "button", identifier: nil)]
        XCTAssertEqual(MarkdownBuilder.pathLine(named, mirrored: true), "Path: group#composer > button")
        XCTAssertEqual(MarkdownBuilder.pathLine(path, mirrored: false)?.hasPrefix("Path: group > splitGroup#com.apple.dt"), true,
                       "a Mac app's own path is not touched")
        XCTAssertEqual(MarkdownBuilder.pathLine([PathEntry(role: "group", identifier: nil), PathEntry(role: "button", identifier: nil)], mirrored: true),
                       "Path: group > button", "no host step to cut at: shown whole")
    }
}
