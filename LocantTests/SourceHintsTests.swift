import XCTest
@testable import Locant

/// specs/source-hints.md R157–R168.
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
        var located = element(dom: DOMInfo(id: "save", classes: []))
        located.component = ComponentInfo(framework: "react", name: "Card", ancestors: [], props: [],
                                          source: SourceLocation(file: "/src/Card.tsx", line: 3, column: 1), renderedAt: nil)
        XCTAssertNil(SourceHints.query(for: located, neighbors: [], ocr: nil), "a web node the page already located needs no search")
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
        try write("AppTests/ATests.swift", "XCTAssertEqual(title, \"Recent\")\n")
        try write("App/LibraryTests.swift", "XCTAssertEqual(title, \"Recent\")\n")
        XCTAssertEqual(try hint(element())?.kind, .only)
        XCTAssertEqual(try hint(element())?.places.map(\.file), ["App/A.swift"])
    }

    /// Nov 13 2026: a worktree under `.claude/worktrees/` was read as empty, and its captures were told
    /// that no file held their strings.
    func testAProjectUnderAHiddenFolderIsRead() throws {
        let hidden = root.appending(path: ".claude/worktrees/feature")
        let saved = root
        root = hidden
        defer { root = saved }
        try write("App/A.swift", "Text(\"Recent\")\n")
        try write(".build/checkouts/B.swift", "Text(\"Recent\")\n")
        try write("App/.hidden.swift", "Text(\"Recent\")\n")
        XCTAssertEqual(try hint(element())?.places.map(\.file), ["App/A.swift"])
    }

    func testAFolderWithNoSourceSaysNothing() throws {
        try write("notes/readme.md", "\"Recent\"\n")
        XCTAssertNil(try hint(element()), "not `none`: nothing was there to look in")
        try write("src/App.tsx", "<p>Recent</p>\n")
        XCTAssertNil(try hint(element()), "a web file is not where a native element's strings would be")
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

    /// Seen in the app Nov 13 2026: a Settings switch has no label of its own; the row's title is a text
    /// beside it, and on the Mac a text keeps its words in its value.
    func testAMacRowIsFoundByTheTextBesideItsControl() throws {
        try write("App/SettingsView.swift", "Toggle(\"Sounds\", isOn: $sounds)\nToggle(\"Haptic feedback\", isOn: $taps)\n")
        let texts = ["Sounds", "Haptic feedback"].enumerated().map { index, words in
            AttributeSet(role: "AXStaticText", value: .string(words), frame: Frame(x: 20, y: Double(index) * 40, w: 100, h: 20))
        }
        let neighbors = SourceHints.neighborLabels(of: Frame(x: 400, y: 0, w: 38, h: 18), among: texts)
        XCTAssertEqual(neighbors, ["Sounds", "Haptic feedback"])
        let found = try XCTUnwrap(try hint(element(label: nil, role: "switch"), neighbors: neighbors))
        XCTAssertEqual(found.kind, .beside)
        XCTAssertEqual(found.places, [SourcePlace(file: "App/SettingsView.swift", lines: [1, 2])])
        var text = ResolvedElement(role: "staticText", rawRole: "AXStaticText", label: nil, identifier: nil, identifierSource: .unknown,
                                   value: .string("Sounds"), frame: Frame(x: 20, y: 0, w: 100, h: 20), path: [])
        XCTAssertEqual(SourceHints.query(for: text, neighbors: [], ocr: nil)?.anchors, ["Sounds"])
        text.label = "Volume"
        XCTAssertEqual(SourceHints.query(for: text, neighbors: [], ocr: nil)?.anchors, ["Volume"], "a label, when there is one, is the element's own")
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
                       "In source: no \"Tide\" string in the project, so a search for that text will find nothing. The text may be data, or the app on screen was built from other code than this folder holds now. If the image and the path do not settle where it is drawn, say so rather than guess.")
    }

    func testTheHintTakesThePlaceOfTheGrepAdviceAndTheHostsPathIsLeftOut() throws {
        let data = try Data(contentsOf: try XCTUnwrap(Bundle(for: Self.self).url(forResource: "sidecar-source-hint", withExtension: "json")))
        let capture = try JSONDecoder().decode(Capture.self, from: data)
        let markdown = MarkdownBuilder.build(capture)
        XCTAssertTrue(markdown.contains("""
        ### Target element
        button "Recent" · no identifier
        In source: "Recent" is a string in 2 files. Likeliest: Oryne/Features/Library/LibraryView.swift:543 (it also has "Currents" from this capture). Others: OceanWidgets/RecentWidget.swift:12, :40. Other text from this capture ("Search the Ocean" and "Library") is in Oryne/Features/Library/LibraryHeader.swift:12, :30, which may be what draws it. "Recent" is the key for "最近" in Localizable.xcstrings.
        Position: 1 of 2 alike on screen, left to right (as drawn now; not the item's place in the data).
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

    // R164: the other file.

    func testAMenuRowNamesTheFileThatDrawsTheMenu() throws {
        try write("Shared/Enums.swift", "case .voice: \"Whisper\"\ncase .image: \"Image\"\n")
        try write("App/LibraryView.swift", "Picker(\"Kind\") {\n  Text(\"All kinds\")\n}\nToggle(\"Show archived\", isOn: $archived)\n")
        let found = try XCTUnwrap(try hint(element(label: "Whisper"), neighbors: ["All kinds", "Image", "Show archived"]))
        XCTAssertEqual(found.kind, .only)
        XCTAssertEqual(found.places, [SourcePlace(file: "Shared/Enums.swift", lines: [1])])
        XCTAssertEqual(found.around, SourceAround(strings: ["All kinds", "Show archived"], place: SourcePlace(file: "App/LibraryView.swift", lines: [2, 4])))
        XCTAssertEqual(MarkdownBuilder.sourceLine(found, element: element(label: "Whisper")),
                       "In source: Shared/Enums.swift:1 (the only file in the project with the string \"Whisper\"). Other text from this capture (\"All kinds\" and \"Show archived\") is in App/LibraryView.swift:2, :4, which may be what draws it.")
    }

    func testOneNeighborElsewhereIsNotEnoughForAnotherFile() throws {
        try write("App/A.swift", "Text(\"Recent\")\n")
        try write("App/B.swift", "Text(\"Currents\")\n")
        XCTAssertNil(try hint(element(), neighbors: ["Currents"])?.around)
    }

    // R165: string catalogs.

    func testAStringCatalogGivesTheKeyOfATranslation() throws {
        try write("App/Capture.swift", "Button(\"Add a thought\") {}\n")
        try write("App/Localizable.xcstrings", """
        {"sourceLanguage":"en","version":"1.0","strings":{
          "Add a thought":{"localizations":{"zh-Hans":{"stringUnit":{"state":"translated","value":"添加想法"}}}},
          "%lld thoughts":{"localizations":{"zh-Hans":{"variations":{"plural":{"other":{"stringUnit":{"state":"translated","value":"%lld 条想法"}}}}}}},
          "Tide":{"localizations":{"en":{"stringUnit":{"state":"translated","value":"Tide"}}}}
        }}
        """)
        let found = try XCTUnwrap(try hint(element(label: "添加想法")))
        XCTAssertEqual(found.kind, .only)
        XCTAssertEqual(found.strings, ["Add a thought"])
        XCTAssertEqual(found.places, [SourcePlace(file: "App/Capture.swift", lines: [1])])
        XCTAssertEqual(found.localized, [LocalizedString(shown: "添加想法", key: "Add a thought", table: "Localizable.xcstrings")])
        XCTAssertEqual(MarkdownBuilder.sourceLine(found, element: element(label: "添加想法")),
                       "In source: App/Capture.swift:1 (the only file in the project with the string \"Add a thought\"). \"Add a thought\" is the key for \"添加想法\" in Localizable.xcstrings.")
    }

    func testCatalogFormats() {
        let plural = Catalogs.xcstrings(Data(#"{"strings":{"k":{"localizations":{"de":{"variations":{"plural":{"one":{"stringUnit":{"value":"ein"}},"other":{"stringUnit":{"value":"viele"}}}}}}}}}"#.utf8), table: "T.xcstrings")
        XCTAssertEqual(plural.map(\.shown).sorted(), ["ein", "viele"])
        XCTAssertEqual(Catalogs.xcstrings(Data("not json".utf8), table: "T"), [])
        let legacy = "/* a comment */\n\"capture.title\" = \"Capture a \\\"thought\\\"\";\n\"cancel\"=\"Abbrechen\";\n"
        XCTAssertEqual(Catalogs.strings(Data(legacy.utf8), table: "L.strings"),
                       [LocalizedString(shown: "Capture a \"thought\"", key: "capture.title", table: "L.strings"),
                        LocalizedString(shown: "Abbrechen", key: "cancel", table: "L.strings")])
        XCTAssertEqual(Catalogs.strings(legacy.data(using: .utf16)!, table: "L.strings").count, 2, "the UTF-16 Xcode used to write")
    }

    func testALegacyStringsFileIsReadToo() throws {
        try write("App/Sheet.swift", "Button(\"cancel\") {}\n")
        try write("App/de.lproj/Localizable.strings", "\"cancel\" = \"Abbrechen\";\n")
        let found = try XCTUnwrap(try hint(element(label: "Abbrechen")))
        XCTAssertEqual(found.places.first?.file, "App/Sheet.swift")
        XCTAssertEqual(found.localized?.first?.key, "cancel")
    }

    // R166: a web node, when the page was not asked or had nothing to say.

    private func webElement(id: String? = nil, classes: [String], label: String? = nil) -> ResolvedElement {
        element(label: label, role: "group", dom: DOMInfo(id: id, classes: classes))
    }

    func testAWebNodeIsFoundByItsRareClass() throws {
        try write("src/Library.tsx", "<div className=\"card\">\n  <span className={`card-caption ${tone}`}>saved</span>\n</div>\n")
        try write("src/Grid.tsx", "<div className=\"card flex\" />\n")
        try write("src/styles.css", ".card-caption { color: gray; }\n.card { padding: 8px; }\n")
        try write("src/Other.swift", "let s = \"card-caption\"\n")
        for index in 1...9 { try write("src/U\(index).tsx", "<div className=\"flex\" />\n") }
        let query = try XCTUnwrap(SourceHints.query(for: webElement(id: "caption-g2", classes: ["card-caption", "flex"], label: "saved Jun 21"), neighbors: [], ocr: nil))
        XCTAssertEqual(query, SourceHints.Query(anchors: ["card-caption", "flex"], context: ["saved Jun 21"], web: true, id: "caption-g2"))
        let found = try XCTUnwrap(SourceHints.find(query, in: root))
        XCTAssertEqual(found.kind, .several, "the id is built at run time, flex is everywhere: the one rare class decides")
        XCTAssertEqual(found.strings, ["card-caption"])
        XCTAssertEqual(found.places, [SourcePlace(file: "src/Library.tsx", lines: [2]), SourcePlace(file: "src/styles.css", lines: [1])],
                       "web files only, markup before the stylesheet, and `card` is not `card-caption`")
        let same = try XCTUnwrap(SourceHints.query(for: webElement(id: "hero", classes: ["hero", "wide"]), neighbors: [], ocr: nil))
        XCTAssertEqual(same.anchors, ["wide"], "a class that repeats the id is not looked for twice")
        try FileManager.default.removeItem(at: root.appending(path: "src/Library.tsx"))
        let styled = try XCTUnwrap(SourceHints.find(query, in: root))
        XCTAssertEqual(MarkdownBuilder.sourceLine(styled, element: webElement(id: "caption-g2", classes: ["card-caption", "flex"])),
                       "In source: src/styles.css:1 (the only file in the project with \"card-caption\"). Every place is a stylesheet: it styles the class, and the file that draws the element builds the name at run time.")
    }

    func testAWebNodesIdWinsAndItsPlacesAreAbsolute() throws {
        try write("src/Checkout.tsx", "<button id=\"checkout-button\" className=\"btn\">Pay</button>\n")
        try write("src/Cart.tsx", "<button className=\"btn\">Remove</button>\n")
        let node = webElement(id: "checkout-button", classes: ["btn"], label: "Pay")
        let capture = Capture(
            id: "20261113-120000-aaaa", createdAt: "2026-11-13T12:00:00-08:00", mode: .fix,
            image: ImageInfo(path: "", widthPt: 10, heightPt: 10, scale: 2, crop: nil),
            source: SourceInfo(app: AppInfo(bundleId: "company.thebrowser.dia", name: "Dia"), window: nil, url: "http://localhost:5173/", simulator: nil),
            element: node, note: ""
        )
        let hint = try XCTUnwrap(SourceHints.annotate(capture, root: root, neighbors: []).element?.sourceHint)
        XCTAssertEqual(hint.kind, .likeliest)
        XCTAssertEqual(hint.strings, ["checkout-button", "btn"])
        let base = root.standardizedFileURL.path(percentEncoded: false)
        XCTAssertEqual(hint.places.first, SourcePlace(file: (base as NSString).appendingPathComponent("src/Checkout.tsx"), lines: [1]))
        XCTAssertEqual(hint.places.count, 2)
        let markdown = MarkdownBuilder.build(SourceHints.annotate(capture, root: root, neighbors: []))
        XCTAssertTrue(markdown.contains("In source: \"checkout-button\" and \"btn\" appear in 2 files. Likeliest: "), markdown)
        XCTAssertFalse(markdown.contains("Grep the class names"))
    }

    func testAWebNodeWithOnlyEverywhereClassesGetsNoHint() throws {
        for index in 1...10 { try write("src/C\(index).tsx", "<h1 className=\"serif\">Title \(index)</h1>\n") }
        let query = try XCTUnwrap(SourceHints.query(for: webElement(classes: ["serif"], label: "Oryne"), neighbors: ["Ask"], ocr: "Oryne\nAsk the Ocean"))
        XCTAssertEqual(query.context, ["Oryne"], "a page's other words are data; only the node's own text is looked for")
        XCTAssertNil(SourceHints.find(query, in: root), "saying no file has `serif` would be untrue, and ten files are no lead")
    }

    func testAWebNodeFallsBackToItsOwnText() throws {
        try write("src/data/projects.ts", "export const sections = [{ title: 'Final Design' }]\n")
        try write("src/data/projects.test.ts", "expect(title).toBe('Final Design')\n")
        try write("src/styles.css", ".masthead-old { }\n")
        var text = webElement(classes: [])
        text.value = .string("Final Design")
        let found = try XCTUnwrap(try hint(text))
        XCTAssertEqual(found, SourceHint(kind: .beside, strings: ["Final Design"], places: [SourcePlace(file: "src/data/projects.ts", lines: [1])], fileCount: 1),
                       "a test file repeats the words without drawing them")
        XCTAssertEqual(MarkdownBuilder.sourceLine(found, element: text),
                       "In source: no id or rare class to go by; this element's own text \"Final Design\" is at src/data/projects.ts:1.")
        let gone = try XCTUnwrap(try hint(webElement(id: "hero", classes: ["masthead"])))
        XCTAssertEqual(gone, SourceHint(kind: .none, strings: ["hero", "masthead"], places: [], fileCount: 0))
        XCTAssertEqual(MarkdownBuilder.sourceLine(gone, element: webElement(id: "hero", classes: ["masthead"])),
                       "In source: no \"hero\" and \"masthead\" in the project's files, so a search for them will find nothing. The page may be built from other code than this folder holds now. If the image and the path do not settle where it is drawn, say so rather than guess.")
    }

    // MARK: R171, R172

    func testATextNodeIsLookedUpByItsParentsClass() throws {
        try write("src/Header.tsx", "<TextLink className=\"nav-link\">Connect</TextLink>\n<TextLink className=\"nav-link\">Work</TextLink>\n")
        try write("src/Footer.tsx", "<a className=\"nav-link\">Colophon</a>\n")
        var text = webElement(classes: [])
        text.rawRole = "AXStaticText"
        text.role = "staticText"
        text.value = .string("Connect")
        text.dom?.parent = DOMInfo.Parent(role: "link", id: nil, classes: ["nav-link"])
        let query = try XCTUnwrap(SourceHints.query(for: text, neighbors: [], ocr: nil))
        XCTAssertEqual(query, SourceHints.Query(anchors: ["nav-link"], context: ["Connect"], web: true, id: nil))
        let found = try XCTUnwrap(SourceHints.find(query, in: root))
        XCTAssertEqual(found.kind, .likeliest)
        XCTAssertEqual(found.places.first, SourcePlace(file: "src/Header.tsx", lines: [1, 2]))
        XCTAssertEqual(found.alsoThere, ["Connect"])
        func lines(_ element: ResolvedElement) -> [String] {
            let app = AppInfo(bundleId: "com.github.Electron", name: "Electron")
            let capture = Capture(id: "20261113-120000-cccc", createdAt: "2026-11-13T12:00:00-08:00", mode: .fix,
                                  image: ImageInfo(path: "/tmp/x.png", widthPt: 10, heightPt: 10, scale: 2, crop: nil),
                                  source: SourceInfo(app: app, window: nil, url: "http://localhost:5191/", simulator: nil), element: element, note: "")
            return MarkdownBuilder.build(capture).components(separatedBy: "\n")
        }
        let inside = "Inside: link · .nav-link (a text node has no id or class of its own; these are its parent's)."
        XCTAssertTrue(lines(text).contains(inside), "with no hint the parent is still named")
        XCTAssertFalse(lines(text).contains { $0.hasPrefix("No id or class") }, "and nobody is told to give a text node an id")
        text.sourceHint = found
        XCTAssertTrue(lines(text).contains(inside))
        XCTAssertTrue(lines(text).contains { $0.hasPrefix("In source: \"nav-link\" appears in 2 files. Likeliest: src/Header.tsx:1, :2 (it also has \"Connect\" from this capture).") })
    }

    func testAnIdThatIsAlsoAWordIsLookedUpQuoted() throws {
        try write("src/ProjectList.tsx", "<section id=\"projects\" className=\"px-6\">\n")
        for index in 1...12 { try write("src/P\(index).tsx", "const projects = load()\n") }
        var item = webElement(classes: [])
        item.dom?.parent = DOMInfo.Parent(role: "group", id: "projects", classes: [])
        let found = try XCTUnwrap(try hint(item))
        XCTAssertEqual(found, SourceHint(kind: .only, strings: ["projects"], places: [SourcePlace(file: "src/ProjectList.tsx", lines: [1])], fileCount: 1))
        XCTAssertTrue(MarkdownBuilder.insideLine(DOMInfo.Parent(role: "group", id: "projects", classes: []), text: false)
            .hasSuffix("(this element has no id or class of its own; these are its parent's)."))
    }

    func testAnElementsOwnHandlesComeBeforeItsParents() throws {
        var node = webElement(classes: ["card-caption"], label: "Notes")
        node.dom?.parent = DOMInfo.Parent(role: "group", id: "shelf", classes: ["grid"])
        XCTAssertEqual(SourceHints.query(for: node, neighbors: [], ocr: nil)?.anchors, ["card-caption"])
        XCTAssertNil(SourceHints.query(for: node, neighbors: [], ocr: nil)?.id)
    }

    func testAParentOfATextNodeRoundTripsAndIsOptional() throws {
        let with = DOMInfo(id: nil, classes: [], parent: DOMInfo.Parent(role: "link", id: nil, classes: ["nav-link"]))
        XCTAssertEqual(try JSONDecoder().decode(DOMInfo.self, from: JSONEncoder().encode(with)), with)
        let bare = try JSONDecoder().decode(DOMInfo.self, from: Data(#"{"id":null,"classes":["a"]}"#.utf8))
        XCTAssertNil(bare.parent)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(bare), as: UTF8.self).contains("parent"))
    }

    func testUtilityClassesAreFoundWhereTheyShareALine() throws {
        // Tailwind: every class is in every file; the list on one line is the handle.
        for index in 1...10 {
            try write("src/C\(index).tsx", "<div className=\"h-6 flex\">\n<span className=\"w-auto\">\n<p className=\"select-none\">\n")
        }
        try write("src/SiteHeader.tsx", "<header>\n<img alt=\"Malik Zhang\" className=\"h-6 w-auto select-none\" />\n</header>\n")
        let logo = webElement(classes: ["h-6", "w-auto", "select-none"], label: "Malik Zhang")
        let found = try XCTUnwrap(try hint(logo))
        XCTAssertEqual(found.kind, .only)
        XCTAssertEqual(found.strings, ["h-6", "w-auto", "select-none"])
        XCTAssertEqual(found.places, [SourcePlace(file: "src/SiteHeader.tsx", lines: [2])])
        XCTAssertEqual(found.together, true)
        XCTAssertEqual(MarkdownBuilder.sourceLine(found, element: logo),
                       "In source: src/SiteHeader.tsx:2 (the only file with \"h-6\", \"w-auto\" and \"select-none\" on one line).")

        try write("src/Specimen.tsx", "<img className=\"h-6 w-auto select-none\" />\n")
        let two = try XCTUnwrap(try hint(logo))
        XCTAssertEqual(two.kind, .likeliest, "the header also holds the alt text")
        XCTAssertEqual(two.fileCount, 2, "the ten files that hold the classes apart are not listed")
        XCTAssertEqual(MarkdownBuilder.sourceLine(two, element: logo),
                       "In source: \"h-6\", \"w-auto\" and \"select-none\" are on one line in 2 files. Likeliest: src/SiteHeader.tsx:2 (it also has \"Malik Zhang\" from this capture). Others: src/Specimen.tsx:1.")
        let bare = try XCTUnwrap(try hint(webElement(classes: ["h-6", "w-auto", "select-none"])))
        XCTAssertEqual(bare.kind, .several)
        XCTAssertEqual(MarkdownBuilder.sourceLine(bare, element: logo),
                       "In source: \"h-6\", \"w-auto\" and \"select-none\" are on one line in 2 files, and nothing in this capture says which: src/SiteHeader.tsx:2, src/Specimen.tsx:1. Use the image and the note to choose.")
    }

    func testTwoCommonClassesOnOneLineInManyFilesAreNoHandle() throws {
        for index in 1...10 { try write("src/C\(index).tsx", "<div className=\"flex items-center\">\n") }
        XCTAssertNil(try hint(webElement(classes: ["flex", "items-center"])), "ten files are no lead")
        // Part of a list is shared between components; only the whole list on one line counts.
        try write("src/Strip.tsx", "<a className=\"group alpha beta gamma delta\">\n")
        try write("src/Recipe.ts", "form: \"nav-link\",\nmaterial: \"alpha beta gamma delta\",\n")
        let link = webElement(classes: ["nav-link", "alpha", "beta", "gamma", "delta"])
        let found = try XCTUnwrap(try hint(link))
        XCTAssertNil(found.together, "four of five on one line is another component's line")
        XCTAssertEqual(found.places.first?.file, "src/Recipe.ts", "the one rare class leads (R166)")
    }

    func testAHintsTogetherKeyIsOptional() throws {
        let plain = SourceHint(kind: .only, strings: ["a"], places: [], fileCount: 1)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(plain), as: UTF8.self).contains("together"))
        var marked = plain
        marked.together = true
        XCTAssertEqual(try JSONDecoder().decode(SourceHint.self, from: JSONEncoder().encode(marked)), marked)
    }

    func testAnUnbuiltTreeIsNothingOrTheNativeContainer() {
        XCTAssertTrue(AppState.isUnbuilt(nil))
        XCTAssertTrue(AppState.isUnbuilt(element(label: nil, role: "scrollArea")))
        XCTAssertFalse(AppState.isUnbuilt(element(label: "Work", role: "link")))
        XCTAssertFalse(AppState.isUnbuilt(webElement(classes: [])), "a web node, even a bare group, means the tree is there")
    }

    func testWordsNotClockTimes() {
        XCTAssertFalse(SourceHints.hasWords("9:41"))
        XCTAssertFalse(SourceHints.hasWords("2025"))
        XCTAssertFalse(SourceHints.hasWords("..."))
        XCTAssertTrue(SourceHints.hasWords("Ask"))
        XCTAssertTrue(SourceHints.isTestOrGenerated("Card.test.tsx"))
        XCTAssertTrue(SourceHints.isTestOrGenerated("types.d.ts"))
        XCTAssertFalse(SourceHints.isTestOrGenerated("Contest.tsx"))
    }

    func testANeedleKnowsWhereAWordEnds() {
        let token = SourceHints.Needle(text: "card", kind: .token)
        XCTAssertTrue(token.matches("<div class=\"card wide\">"))
        XCTAssertTrue(token.matches(".card{}"))
        XCTAssertFalse(token.matches("class=\"card-caption\""))
        XCTAssertFalse(token.matches("discard()"))
        XCTAssertFalse(token.matches("my_card"))
        XCTAssertTrue(token.matches("cards card"), "a later place in the line can still be the word")
        XCTAssertTrue(SourceHints.Needle(text: "Save", kind: .literalStart).matches("Text(\"Saved\")"))
        XCTAssertFalse(SourceHints.Needle(text: "Save", kind: .literal).matches("Text(\"Saved\")"))
    }

    // R163: one reading serves the search at Enter.

    func testACorpusReadOnceAnswersLater() throws {
        try write("App/A.swift", "Text(\"Recent\")\n")
        let corpus = try XCTUnwrap(SourceHints.Corpus.load(root: root))
        try FileManager.default.removeItem(at: root.appending(path: "App/A.swift"))
        let query = try XCTUnwrap(SourceHints.query(for: element(), neighbors: [], ocr: nil))
        XCTAssertEqual(SourceHints.find(query, in: corpus)?.places.map(\.file), ["App/A.swift"], "the search reads memory, not the disk")
        XCTAssertEqual(SourceHints.commitWait, .milliseconds(300))
    }

    // R167: the place among siblings.

    func testRowPositionCountsWhatLinesUp() {
        func node(_ role: String, x: Double, y: Double, w: Double = 300, h: Double = 40) -> AttributeSet {
            AttributeSet(role: role, frame: Frame(x: x, y: y, w: w, h: h))
        }
        let column = [node("AXButton", x: 20, y: 300), node("AXButton", x: 20, y: 100), node("AXButton", x: 20, y: 200),
                      node("AXStaticText", x: 20, y: 150), node("AXButton", x: 20, y: 400, w: 120)]
        XCTAssertEqual(SourceHints.rowPosition(of: Frame(x: 20, y: 200, w: 300, h: 40), rawRole: "AXButton", among: column),
                       RowPosition(index: 2, count: 3, axis: .column), "top to bottom; another role and another width do not count")
        let tabs = [node("AXButton", x: 10, y: 800, w: 80), node("AXButton", x: 100, y: 800, w: 120), node("AXButton", x: 230, y: 800, w: 60)]
        XCTAssertEqual(SourceHints.rowPosition(of: Frame(x: 230, y: 800, w: 60, h: 40), rawRole: "AXButton", among: tabs),
                       RowPosition(index: 3, count: 3, axis: .row))
        XCTAssertNil(SourceHints.rowPosition(of: Frame(x: 20, y: 100, w: 300, h: 40), rawRole: "AXButton", among: [node("AXButton", x: 20, y: 100)]), "alone")
        XCTAssertNil(SourceHints.rowPosition(of: Frame(x: 500, y: 500, w: 9, h: 9), rawRole: "AXButton", among: column), "not one of them")
        XCTAssertEqual(MarkdownBuilder.positionLine(RowPosition(index: 2, count: 3, axis: .column)),
                       "Position: 2 of 3 alike on screen, top to bottom (as drawn now; not the item's place in the data).")
    }

    func testThePositionLineFollowsTheSourceLine() {
        var placed = element()
        placed.sourceHint = SourceHint(kind: .none, strings: ["Recent"], places: [], fileCount: 0)
        placed.row = RowPosition(index: 1, count: 2, axis: .row)
        let app = AppInfo(bundleId: "com.apple.dt.Devices", name: "Device Hub")
        let capture = Capture(id: "20261113-120000-bbbb", createdAt: "2026-11-13T12:00:00-08:00", mode: .fix,
                              image: ImageInfo(path: "/tmp/x.png", widthPt: 10, heightPt: 10, scale: 2, crop: nil),
                              source: SourceInfo(app: app, window: nil, url: nil, simulator: nil), element: placed, note: "")
        let lines = MarkdownBuilder.build(capture).components(separatedBy: "\n")
        let at = try? XCTUnwrap(lines.firstIndex { $0.hasPrefix("In source:") })
        XCTAssertEqual(at.map { lines[$0 + 1] }, "Position: 1 of 2 alike on screen, left to right (as drawn now; not the item's place in the data).")
    }

    // A page is not a SwiftUI view.

    func testNoElementOnAPageDoesNotAdviseSwiftUI() {
        func capture(_ app: AppInfo, url: String?) -> Capture {
            Capture(id: "20261113-120000-cccc", createdAt: "2026-11-13T12:00:00-08:00", mode: .reference,
                    image: ImageInfo(path: "/tmp/x.png", widthPt: 10, heightPt: 10, scale: 2, crop: nil),
                    source: SourceInfo(app: app, window: nil, url: url, simulator: nil), element: nil, note: "")
        }
        let page = MarkdownBuilder.build(capture(AppInfo(bundleId: "com.example.browser", name: "Browser"), url: "https://example.com/"))
        XCTAssertTrue(page.contains(MarkdownBuilder.noElementWebAdvice))
        XCTAssertFalse(page.contains(".accessibilityElement()"))
        let chrome = MarkdownBuilder.build(capture(AppInfo(bundleId: "com.google.Chrome", name: "Google Chrome"), url: nil))
        XCTAssertTrue(chrome.contains(MarkdownBuilder.noElementWebAdvice), "a browser Locant knows, even when the frame gave no address")
        let native = MarkdownBuilder.build(capture(AppInfo(bundleId: "com.apple.calculator", name: "Calculator"), url: nil))
        XCTAssertTrue(native.contains(MarkdownBuilder.noElementAdvice))
    }
}
