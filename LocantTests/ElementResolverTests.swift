import CoreGraphics
import XCTest
@testable import Locant

final class ElementResolverTests: XCTestCase {
    private func fixture(_ name: String) throws -> ElementSnapshot {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"), "fixture \(name)")
        return try JSONDecoder().decode(ElementSnapshot.self, from: Data(contentsOf: url))
    }

    // 1
    func testSwiftUIButtonWithIdentifier() throws {
        let e = try XCTUnwrap(ElementResolver.resolve(try fixture("swiftui-button")))
        XCTAssertEqual(e.role, "button")
        XCTAssertEqual(e.rawRole, "AXButton")
        XCTAssertEqual(e.identifier, "captureButton")
        XCTAssertEqual(e.label, "Capture")
        XCTAssertEqual(e.frame, Frame(x: 43, y: 893.6667, w: 370, h: 50.3333))
    }

    // 2
    func testAppKitTextFieldWithoutIdentifier() throws {
        let e = try XCTUnwrap(ElementResolver.resolve(try fixture("appkit-textfield")))
        XCTAssertEqual(e.role, "textField")
        XCTAssertNil(e.identifier)
        XCTAssertEqual(e.identifierSource, .unknown)
        XCTAssertEqual(e.label, "Name")
        XCTAssertEqual(e.value, .string("Malik"))
    }

    // 3
    func testUnknownRoleKeepsRawRole() throws {
        let e = try XCTUnwrap(ElementResolver.resolve(try fixture("unknown-role")))
        XCTAssertEqual(e.role, "unknown")
        XCTAssertEqual(e.rawRole, "AXCustomThing")
    }

    // 4
    func testPathTruncatesAtSixAncestorsRootFirst() throws {
        let e = try XCTUnwrap(ElementResolver.resolve(try fixture("deep-path")))
        XCTAssertEqual(e.path.count, 7)
        XCTAssertEqual(e.path.map(\.identifier), ["a6", "a5", "a4", "a3", "a2", "a1", "leaf"])
        XCTAssertEqual(e.path[2].role, "toolbar")
        XCTAssertEqual(e.path.last?.role, "button")
    }

    // 5
    func testMissingFrameReturnsNil() throws {
        XCTAssertNil(ElementResolver.resolve(try fixture("missing-frame")))
    }

    // 6
    func testSimulatorPathIncludesWindowAndResolvesIdentifier() throws {
        let e = try XCTUnwrap(ElementResolver.resolve(try fixture("simulator-path")))
        XCTAssertEqual(e.identifier, "captureButton")
        XCTAssertEqual(e.identifierSource, .declared)
        XCTAssertTrue(e.path.contains { $0.role == "window" })
        XCTAssertEqual(e.path.first?.role, "application", "five ancestors fit, so the root is the Simulator app")
        XCTAssertEqual(e.path[1].role, "window")
        XCTAssertEqual(e.path.count, 6)
    }

    // 7
    func testRetryReturnsPopulatedReadAfterEmptyOnes() async throws {
        let provider = ScriptedProvider(script: [nil, try fixture("empty-group"), try fixture("swiftui-button")])
        let e = await ElementResolver.resolve(at: CGPoint(x: 228, y: 927), using: provider, retries: 5, delay: .zero)
        XCTAssertEqual(e?.identifier, "captureButton")
        let calls = await provider.calls
        XCTAssertEqual(calls, 3)
    }

    func testRetryGivesUpAfterRetriesAndReturnsNil() async throws {
        let provider = ScriptedProvider(script: [])
        let e = await ElementResolver.resolve(at: .zero, using: provider, retries: 2, delay: .zero)
        XCTAssertNil(e)
        let calls = await provider.calls
        XCTAssertEqual(calls, 3, "one read plus two retries")
    }

    func testRetryReReadsAFirstContainerHitOnce() async throws {
        let container = ElementSnapshot(element: AttributeSet(role: "AXGroup", frame: Frame(x: 0, y: 0, w: 1448, h: 944), childCount: 40), ancestors: [])
        let refined = ScriptedProvider(script: [container, try fixture("swiftui-button")])
        let e = await ElementResolver.resolve(at: .zero, using: refined, retries: 5, delay: .zero)
        XCTAssertEqual(e?.identifier, "captureButton")
        let calls = await refined.calls
        XCTAssertEqual(calls, 2)

        let stubborn = ScriptedProvider(script: [container, container])
        let f = await ElementResolver.resolve(at: .zero, using: stubborn, retries: 1, delay: .zero)
        XCTAssertEqual(f?.role, "group", "a container that stays a container is still the answer")
    }

    // 8
    func testIdentifierSourceForSymbolImageAndDeclaredButton() throws {
        let image = try XCTUnwrap(ElementResolver.resolve(try fixture("symbol-image")))
        XCTAssertEqual(image.role, "image")
        XCTAssertEqual(image.identifier, "plus")
        XCTAssertEqual(image.identifierSource, .possiblySymbolName)

        let button = try XCTUnwrap(ElementResolver.resolve(try fixture("swiftui-button")))
        XCTAssertEqual(button.identifierSource, .declared)

        XCTAssertEqual(ElementResolver.identifierSource(role: "image", identifier: "person.crop.circle"), .possiblySymbolName)
        XCTAssertEqual(ElementResolver.identifierSource(role: "image", identifier: "avatarImage"), .declared)
        XCTAssertEqual(ElementResolver.identifierSource(role: "button", identifier: "plus"), .declared)
        XCTAssertEqual(ElementResolver.identifierSource(role: "image", identifier: ""), .unknown)
    }

    // R2 hover precision
    private func node(_ role: String, id: String? = nil, x: Double, y: Double, w: Double, h: Double) -> AttributeSet {
        AttributeSet(role: role, identifier: id, frame: Frame(x: x, y: y, w: w, h: h), childCount: 0)
    }

    func testRefinerPicksSmallestControlNearPoint() {
        let window = node("AXGroup", x: 0, y: 0, w: 456, h: 900)
        let candidates = [
            node("AXGroup", id: "content", x: 0, y: 0, w: 456, h: 900),   // same size as base: never
            node("AXToolbar", x: 0, y: 840, w: 456, h: 60),               // container, near
            node("AXButton", id: "capture", x: 43, y: 850, w: 370, h: 40), // control, 5 pt away
            node("AXButton", id: "far", x: 43, y: 700, w: 370, h: 40),     // control, far
        ]
        let point = CGPoint(x: 228, y: 895) // 5 pt below the capture button
        XCTAssertEqual(HitRefiner.choose(from: candidates, replacing: window, at: point)?.identifier, "capture")
    }

    func testRefinerFallsBackToSmallerContainerThenNil() {
        let window = node("AXGroup", x: 0, y: 0, w: 456, h: 900)
        let toolbar = node("AXToolbar", x: 0, y: 840, w: 456, h: 60)
        let button = node("AXButton", id: "capture", x: 43, y: 850, w: 100, h: 40)
        XCTAssertNil(HitRefiner.choose(from: [toolbar, button], replacing: window, at: CGPoint(x: 228, y: 895))?.identifier)
        XCTAssertEqual(HitRefiner.choose(from: [toolbar, button], replacing: window, at: CGPoint(x: 228, y: 895))?.role, "AXToolbar")
        XCTAssertNil(HitRefiner.choose(from: [toolbar, button], replacing: window, at: CGPoint(x: 228, y: 400)), "blank area keeps the container")
    }

    func testStickinessKeepsControlsNotContainers() throws {
        let button = try XCTUnwrap(ElementResolver.resolve(try fixture("swiftui-button"))) // 43,893.67 370×50.33
        XCTAssertTrue(HitRefiner.sticks(button, to: CGPoint(x: 228, y: 950)))   // 6 pt below
        XCTAssertFalse(HitRefiner.sticks(button, to: CGPoint(x: 228, y: 970)))  // 26 pt below
        let group = try XCTUnwrap(ElementResolver.resolve(try fixture("empty-group")))
        XCTAssertFalse(HitRefiner.sticks(group, to: CGPoint(x: 100, y: 300)))
        XCTAssertFalse(HitRefiner.sticks(nil, to: .zero))
    }

    func testAncestorDepthReRootsSnapshot() throws {
        let snapshot = try fixture("swiftui-button")
        let parent = try XCTUnwrap(HitRefiner.ancestor(of: snapshot, depth: 1))
        XCTAssertEqual(ElementResolver.resolve(parent)?.role, "group")
        XCTAssertEqual(parent.ancestors.count, 2)
        XCTAssertEqual(ElementResolver.resolve(try XCTUnwrap(HitRefiner.ancestor(of: snapshot, depth: 3)))?.role, "window")
        XCTAssertNil(HitRefiner.ancestor(of: snapshot, depth: 4))
        XCTAssertEqual(HitRefiner.ancestor(of: snapshot, depth: 0), snapshot)
    }

    // R2a clusters (flat SwiftUI trees expose leaves, not cards)
    func testClustersGroupByProximity() throws {
        let snapshot = try fixture("card-siblings")
        let nodes = HitRefiner.content(of: snapshot.siblings ?? [], within: snapshot.ancestors[0].frame)
        XCTAssertEqual(nodes.count, 7, "the window-sized Background sibling is dropped")
        let groups = HitRefiner.clusters(among: nodes)
        XCTAssertEqual(groups.count, 3, "Ocean title, the card, the tab bar")
        let card = try XCTUnwrap(groups.first { $0.contains { $0.description == "Shortcut" } })
        XCTAssertEqual(card.count, 5)
        XCTAssertEqual(HitRefiner.union(of: card), CGRect(x: 59, y: 590, width: 338, height: 120))
    }

    func testSelectionLevelsFromLeafGoLeafClusterParentWindow() throws {
        let snapshot = try fixture("card-siblings")
        let levels = HitRefiner.selectionLevels(for: snapshot, at: CGPoint(x: 100, y: 600))
        XCTAssertEqual(levels.map { $0?.role }, ["staticText", "cluster", "group", "window"], "the frameless application is skipped")
        let cluster = try XCTUnwrap(levels[1])
        XCTAssertEqual(cluster.rawRole, "LocantCluster")
        XCTAssertEqual(cluster.frame, Frame(x: 43, y: 574, w: 370, h: 152), "members' bounds plus 16 pt, inside the parent")
        XCTAssertEqual(cluster.members?.map(\.role), ["staticText", "image", "staticText", "button", "button"])
        XCTAssertEqual(cluster.members?.compactMap(\.identifier), ["bolt.fill", "shortcutActionButton"])
        XCTAssertEqual(cluster.path.last?.role, "cluster")
        XCTAssertEqual(cluster.path.first?.role, "application")
    }

    func testSelectionLevelsOnSpanningContainerPickClusterUnderPointOrNothing() throws {
        let leaf = try fixture("card-siblings")
        let group = ElementSnapshot(element: leaf.ancestors[0], ancestors: Array(leaf.ancestors[1...]), children: leaf.siblings)
        let onCard = HitRefiner.selectionLevels(for: group, at: CGPoint(x: 300, y: 600)) // blank card area
        XCTAssertEqual(onCard.map { $0?.role }, ["cluster", "group", "window"])
        let onNothing = HitRefiner.selectionLevels(for: group, at: CGPoint(x: 200, y: 450)) // the orb: no elements
        XCTAssertEqual(onNothing.map { $0?.role }, [nil, "group", "window"])
        XCTAssertNil(onNothing[0], "nothing specific here: fallback square, element null on click")
    }

    /// The Finder desktop: a screen-sized group under a scroll area, no window anywhere in the chain.
    /// It counts as spanning its root, so blank desktop is "nothing here" and an icon area is a cluster.
    func testDesktopWithoutWindowAncestorSpansItsRoot() throws {
        let screen = Frame(x: 0, y: 0, w: 2056, h: 1329)
        let desktop = AttributeSet(role: "AXGroup", description: "desktop", frame: screen, childCount: 2)
        let scrollArea = AttributeSet(role: "AXScrollArea", description: "desktop", frame: screen)
        let application = AttributeSet(role: "AXApplication", title: "Finder")
        let icon = node("AXImage", x: 1958, y: 47, w: 64, h: 64)
        let label = node("AXStaticText", x: 1950, y: 115, w: 80, h: 16)
        let snapshot = ElementSnapshot(element: desktop, ancestors: [scrollArea, application], children: [icon, label])
        XCTAssertEqual(HitRefiner.windowFrame(in: snapshot), screen)
        let blank = HitRefiner.selectionLevels(for: snapshot, at: CGPoint(x: 1000, y: 600))
        XCTAssertEqual(blank.map { $0?.role }, [nil, "group", "scrollArea"])
        let nearIcon = HitRefiner.selectionLevels(for: snapshot, at: CGPoint(x: 1990, y: 100))
        XCTAssertEqual(nearIcon.first??.role, "cluster", "icon and its label form one cluster")
    }

    func testDesktopAndMenuBarRoles() {
        XCTAssertEqual(ElementResolver.mapRole("AXMenuBarItem", subrole: "AXMenuExtra"), "menuExtra")
        XCTAssertEqual(ElementResolver.mapRole("AXMenuBarItem", subrole: nil), "menuBarItem")
        XCTAssertEqual(ElementResolver.mapRole("AXDockItem", subrole: nil), "dockItem")
        XCTAssertEqual(ElementResolver.mapRole("AXUnknown", subrole: nil), "unknown", "a widget's cell")
    }

    func testZeroFrameResolvesToNil() {
        let ghost = ElementSnapshot(element: AttributeSet(role: "AXApplication", frame: Frame(x: 0, y: 0, w: 0, h: 0)), ancestors: [])
        XCTAssertNil(ElementResolver.resolve(ghost))
    }

    func testModeClassifier() {
        func source(app: String, simApp: String? = nil, url: String? = nil) -> SourceInfo {
            SourceInfo(
                app: AppInfo(bundleId: app, name: "x"),
                window: nil,
                url: url,
                simulator: app == ModeClassifier.simulatorBundleId ? SimulatorInfo(device: "iPhone", appBundleId: simApp) : nil
            )
        }
        let mine = ["com.example.mine"]
        XCTAssertEqual(ModeClassifier.classify(source(app: "com.example.mine"), myApps: mine), .fix)
        XCTAssertEqual(ModeClassifier.classify(source(app: "com.figma.Desktop"), myApps: mine), .reference)
        XCTAssertEqual(ModeClassifier.classify(source(app: ModeClassifier.simulatorBundleId, simApp: "com.example.mine"), myApps: mine), .fix)
        XCTAssertEqual(ModeClassifier.classify(source(app: ModeClassifier.simulatorBundleId, simApp: "com.other.app"), myApps: mine), .fix, "v0.3: anything in the Simulator was built by the user")
        XCTAssertEqual(ModeClassifier.classify(source(app: ModeClassifier.simulatorBundleId, simApp: nil), myApps: mine), .fix)
        XCTAssertEqual(ModeClassifier.classify(source(app: "com.apple.Safari", url: "http://localhost:3000/x"), myApps: mine), .fix)
        XCTAssertEqual(ModeClassifier.classify(source(app: "com.apple.Safari", url: "https://example.com"), myApps: mine), .reference)
    }

    /// Xcode 27: Device Hub is the simulator when its window shows one (the context then carries a
    /// simulator block), and an Apple app like any other when it shows a physical device.
    func testModeClassifierTreatsDeviceHubAsTheSimulatorItShows() {
        var source = SourceInfo(
            app: AppInfo(bundleId: "com.apple.dt.Devices", name: "Device Hub"),
            window: WindowInfo(title: "iPhone 17 Pro – iOS 26.5"),
            url: nil,
            simulator: SimulatorInfo(device: "iPhone 17 Pro", appBundleId: "com.other.app")
        )
        let signals = ModeClassifier.signals(for: CaptureContext(source: source, frontPID: 0), myApps: [], userTeamIDs: [])
        XCTAssertTrue(signals.isSimulator)
        XCTAssertEqual(signals.simulatedBundleId, "com.other.app")
        XCTAssertEqual(ModeClassifier.classify(source), .fix)

        source.window = WindowInfo(title: "Malik’s iPhone – iOS 27.0")
        source.simulator = nil
        XCTAssertFalse(ModeClassifier.signals(for: CaptureContext(source: source, frontPID: 0), myApps: [], userTeamIDs: []).isSimulator)
        XCTAssertEqual(ModeClassifier.classify(source), .reference)
    }
}

/// Returns scripted snapshots in order, then nil forever. Counts calls.
actor ScriptedProvider: ElementProvider {
    private var script: [ElementSnapshot?]
    private(set) var calls = 0

    init(script: [ElementSnapshot?]) { self.script = script }

    func snapshot(at point: CGPoint) async -> ElementSnapshot? {
        calls += 1
        return script.isEmpty ? nil : script.removeFirst()
    }
}
