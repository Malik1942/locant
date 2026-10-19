import XCTest
@testable import Locant

final class ModeInferenceTests: XCTestCase {
    /// A fake disk: the entries of each directory, and DerivedData workspace paths.
    private func environment(entries: [String: [String]] = [:], workspaces: [String: String] = [:]) -> ModeEnvironment {
        ModeEnvironment(
            directoryEntries: { entries[$0] ?? [] },
            derivedDataWorkspacePath: { workspaces[$0] }
        )
    }

    // 1
    func testMyAppsWins() {
        let s = ModeSignals(bundleId: "com.figma.Desktop", bundlePath: "/Applications/Figma.app", myApps: ["com.figma.Desktop"])
        let d = ModeInference.infer(s, environment: environment())
        XCTAssertEqual(d, ModeDecision(mode: .fix, projectRoot: nil, rule: .myApps))
        let sim = ModeSignals(bundleId: ModeInference.simulatorBundleId, isSimulator: true, simulatedBundleId: "com.x.y", myApps: ["com.x.y"])
        XCTAssertEqual(ModeInference.infer(sim, environment: environment()).rule, .myApps)
    }

    // 2
    func testSimulatorIsFix() {
        let s = ModeSignals(bundleId: ModeInference.simulatorBundleId, isSimulator: true, simulatedBundleId: "com.someone.else")
        XCTAssertEqual(ModeInference.infer(s, environment: environment()), ModeDecision(mode: .fix, projectRoot: nil, rule: .simulator))
    }

    func testSimulatedAppGetsProjectRootFromDerivedDataProduct() {
        var env = environment()
        env.simulatorProjectRoot = { bundleId, _ in bundleId == "com.inspireocean.app" ? "/Users/me/Code/Oryne" : nil }
        let s = ModeSignals(bundleId: ModeInference.simulatorBundleId, isSimulator: true, simulatedBundleId: "com.inspireocean.app", bundlePath: "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app")
        XCTAssertEqual(ModeInference.infer(s, environment: env), ModeDecision(mode: .fix, projectRoot: "/Users/me/Code/Oryne", rule: .simulator))
        XCTAssertNil(ModeInference.infer(ModeSignals(bundleId: ModeInference.simulatorBundleId, isSimulator: true, simulatedBundleId: "com.other"), environment: env).projectRoot)
    }

    /// DerivedData can be a symlink (to DerivedData.noindex, which keeps built apps out of Spotlight).
    func testSimulatorProjectRootFollowsASymlinkedDerivedData() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appending(path: "ModeInferenceTests-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tmp) }
        let real = tmp.appending(path: "DerivedData.noindex")
        let project = real.appending(path: "Oryne-abc")
        let app = project.appending(path: "Build/Products/Debug-iphonesimulator/Oryne.app")
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.inspireocean.app"], format: .xml, options: 0)
            .write(to: app.appending(path: "Info.plist"))
        try PropertyListSerialization.data(fromPropertyList: ["WorkspacePath": "/Users/me/Code/Oryne/Oryne.xcodeproj"], format: .xml, options: 0)
            .write(to: project.appending(path: "info.plist"))
        let link = tmp.appending(path: "DerivedData")
        try fm.createSymbolicLink(at: link, withDestinationURL: real)

        XCTAssertEqual(ModeEnvironment.projectRoot(ofSimulatedApp: "com.inspireocean.app", runningAt: nil, derivedData: real), "/Users/me/Code/Oryne")
        XCTAssertEqual(ModeEnvironment.projectRoot(ofSimulatedApp: "com.inspireocean.app", runningAt: nil, derivedData: link), "/Users/me/Code/Oryne")
        XCTAssertNil(ModeEnvironment.projectRoot(ofSimulatedApp: "com.other", runningAt: nil, derivedData: link))
    }

    /// specs/simulator-project-root.md R107: two worktrees build the same app, and the newer build is not
    /// the one on screen (Oct 18: the Watch worktree's build named on captures of the redesign). The
    /// running copy's debug map names the folder that built it.
    func testSimulatedAppsProjectRootIsTheBuildThatIsRunning() throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let derivedData = tmp.appending(path: "DerivedData")
        let redesign = try product("Oryne-redesign", in: derivedData, workspace: "/Users/me/Code/oryne-redesign/Oryne.xcodeproj", modified: Date(timeIntervalSinceNow: -3600))
        try product("Oryne-watch", in: derivedData, workspace: "/Users/me/Code/oryne-watch/Oryne.xcodeproj", modified: Date())
        let folder = redesign.path(percentEncoded: false)
        let running = try runningCopy(in: tmp, debugMap: [MachOFixture.objectFile(in: folder, "AppState"), MachOFixture.objectFile(in: folder, "NodeCard")])

        XCTAssertEqual(ModeEnvironment.projectRoot(ofSimulatedApp: "com.inspireocean.app", runningAt: running, derivedData: derivedData), "/Users/me/Code/oryne-redesign")
    }

    /// R107 step 2: without a debug map, the products answer only when they name one project; the newest
    /// of several is a guess, and a wrong Project line sends the agent to the wrong checkout.
    func testWithoutADebugMapProductsAnswerOnlyWhenTheyAgree() throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let running = try runningCopy(in: tmp, debugMap: nil)
        let split = tmp.appending(path: "Split")
        try product("Oryne-redesign", in: split, workspace: "/Users/me/Code/oryne-redesign/Oryne.xcodeproj", modified: Date(timeIntervalSinceNow: -3600))
        try product("Oryne-watch", in: split, workspace: "/Users/me/Code/oryne-watch/Oryne.xcodeproj", modified: Date())
        XCTAssertNil(ModeEnvironment.projectRoot(ofSimulatedApp: "com.inspireocean.app", runningAt: running, derivedData: split))
        XCTAssertNil(ModeEnvironment.projectRoot(ofSimulatedApp: "com.inspireocean.app", runningAt: nil, derivedData: split))

        let agreed = tmp.appending(path: "Agreed")
        try product("Oryne-abc", in: agreed, workspace: "/Users/me/Code/Oryne/Oryne.xcodeproj", modified: Date(timeIntervalSinceNow: -3600))
        try product("Oryne-tests", in: agreed, workspace: "/Users/me/Code/Oryne/Oryne.xcodeproj", modified: Date())
        try product("Other-xyz", in: agreed, workspace: "/Users/me/Code/Other/Other.xcodeproj", bundleId: "com.other", modified: Date())
        XCTAssertEqual(ModeEnvironment.projectRoot(ofSimulatedApp: "com.inspireocean.app", runningAt: running, derivedData: agreed), "/Users/me/Code/Oryne")
        XCTAssertEqual(ModeEnvironment.projectRoot(ofSimulatedApp: "com.inspireocean.app", runningAt: nil, derivedData: agreed), "/Users/me/Code/Oryne")
    }

    /// A DerivedData project folder holding a simulator product of `bundleId`, built from `workspace`.
    @discardableResult
    private func product(_ name: String, in derivedData: URL, workspace: String, bundleId: String = "com.inspireocean.app", modified: Date) throws -> URL {
        let folder = derivedData.appending(path: name)
        let app = folder.appending(path: "Build/Products/Debug-iphonesimulator/Oryne.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": bundleId, "CFBundleExecutable": "Oryne"], format: .xml, options: 0)
            .write(to: app.appending(path: "Info.plist"))
        try PropertyListSerialization.data(fromPropertyList: ["WorkspacePath": workspace], format: .xml, options: 0)
            .write(to: folder.appending(path: "info.plist"))
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: app.path(percentEncoded: false))
        return folder
    }

    /// The running copy in a device's container, as Xcode's Debug builds make it: a stub executable with no
    /// debug map and, when `debugMap` is given, `Oryne.debug.dylib` whose debug map names those object files.
    private func runningCopy(in root: URL, debugMap: [String]?) throws -> String {
        let app = root.appending(path: "Devices/0EBF66EE-3E7D-48F9-9D44-E7B1A58DACF1/data/Containers/Bundle/Application/6B736A38-BE47-46BC-8031-7AE59797D488/Oryne.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.inspireocean.app", "CFBundleExecutable": "Oryne"], format: .xml, options: 0)
            .write(to: app.appending(path: "Info.plist"))
        try MachOFixture.thin(symbols: []).write(to: app.appending(path: "Oryne"))
        if let debugMap { try MachOFixture.debugMap(debugMap).write(to: app.appending(path: "Oryne.debug.dylib")) }
        return app.path(percentEncoded: false)
    }

    /// Xcode 27 has no Simulator.app; Device Hub shows simulators, and physical devices too, so its
    /// bundle id alone is not the simulator: the classifier says when its window shows one.
    func testDeviceHubIsFixOnlyWhenItShowsASimulator() {
        let hub = ModeSignals(bundleId: "com.apple.dt.Devices", bundlePath: "/Applications/Xcode.app/Contents/Applications/DeviceHub.app")
        XCTAssertEqual(ModeInference.infer(hub, environment: environment()), ModeDecision(mode: .reference, projectRoot: nil, rule: .none))
        let showing = ModeSignals(bundleId: "com.apple.dt.Devices", isSimulator: true, simulatedBundleId: "com.someone.else")
        XCTAssertEqual(ModeInference.infer(showing, environment: environment()), ModeDecision(mode: .fix, projectRoot: nil, rule: .simulator))
    }

    /// The running copy found at capture time reaches the project lookup (specs/simulator-project-root.md R105).
    func testDeviceHubCaptureGetsTheSimulatedAppsProjectRoot() {
        let running = "/Users/me/Library/Developer/CoreSimulator/Devices/0EBF66EE/data/Containers/Bundle/Application/6B736A38/Oryne.app"
        var env = environment()
        env.simulatorProjectRoot = { bundleId, runningAt in
            bundleId == "com.inspireocean.app" && runningAt == running ? "/Users/me/Code/Oryne" : nil
        }
        let source = SourceInfo(
            app: AppInfo(bundleId: "com.apple.dt.Devices", name: "Device Hub"),
            window: WindowInfo(title: "iPhone 17 Pro – iOS 26.5"),
            url: nil,
            simulator: SimulatorInfo(device: "iPhone 17 Pro", appBundleId: "com.inspireocean.app")
        )
        let context = CaptureContext(source: source, frontPID: 0, bundlePath: "/Applications/Xcode.app/Contents/Applications/DeviceHub.app",
                                     simulatedBundlePath: running)
        let signals = ModeClassifier.signals(for: context, myApps: [], userTeamIDs: [])
        XCTAssertEqual(ModeInference.infer(signals, environment: env), ModeDecision(mode: .fix, projectRoot: "/Users/me/Code/Oryne", rule: .simulator))
    }

    // 3
    func testLocalhostHosts() {
        for host in ["localhost", "127.0.0.1", "0.0.0.0", "::1", "myapp.local", "LOCALHOST"] {
            XCTAssertTrue(ModeInference.isLocalhost(host), host)
        }
        XCTAssertFalse(ModeInference.isLocalhost("example.com"))
        XCTAssertFalse(ModeInference.isLocalhost(nil))
        let s = ModeSignals(bundleId: "com.apple.Safari", bundlePath: "/Applications/Safari.app", urlHost: "localhost")
        XCTAssertEqual(ModeInference.infer(s, environment: environment()).rule, .localhost)
    }

    // 4
    func testDerivedDataBuildIsFixWithProjectRoot() {
        let path = "/Users/me/Library/Developer/Xcode/DerivedData/Locant-abc123/Build/Products/Debug/Locant.app"
        let env = environment(workspaces: ["/Users/me/Library/Developer/Xcode/DerivedData/Locant-abc123": "/Users/me/Code/Locant/Locant.xcodeproj"])
        let d = ModeInference.infer(ModeSignals(bundleId: "com.malikzhang.deixis", bundlePath: path), environment: env)
        XCTAssertEqual(d, ModeDecision(mode: .fix, projectRoot: "/Users/me/Code/Locant", rule: .builtHere))
        // Without a readable info.plist, DerivedData still means fix, but no root is guessed.
        let blind = ModeInference.infer(ModeSignals(bundleId: "com.malikzhang.deixis", bundlePath: path), environment: environment())
        XCTAssertEqual(blind.mode, .reference, "DerivedData without WorkspacePath and no ancestor marker: nothing proves it was built here")
    }

    // 5
    func testAncestorWithProjectMarkerGivesFixAndRoot() {
        let path = "/Users/me/Code/Oryne/build/Debug-iphonesimulator/Oryne.app"
        let env = environment(entries: [
            "/Users/me/Code/Oryne/build/Debug-iphonesimulator": ["Oryne.app"],
            "/Users/me/Code/Oryne/build": ["Debug-iphonesimulator"],
            "/Users/me/Code/Oryne": ["Oryne.xcodeproj", "Oryne", "README.md"],
        ])
        let d = ModeInference.infer(ModeSignals(bundleId: "com.inspireocean.app", bundlePath: path), environment: env)
        XCTAssertEqual(d, ModeDecision(mode: .fix, projectRoot: "/Users/me/Code/Oryne", rule: .builtHere))
        let swiftPackage = environment(entries: ["/Users/me/Code/Tool": ["Package.swift", "Sources"]])
        XCTAssertEqual(ModeInference.projectRoot(forBundleAt: "/Users/me/Code/Tool/.build/debug/tool", environment: swiftPackage), "/Users/me/Code/Tool")
    }

    // 6
    func testMatchingTeamIDIsFix() {
        let s = ModeSignals(bundleId: "com.malikzhang.deixis", bundlePath: "/Applications/Locant.app", teamID: "MVAUZXPK9M", userTeamIDs: ["MVAUZXPK9M"])
        XCTAssertEqual(ModeInference.infer(s, environment: environment()), ModeDecision(mode: .fix, projectRoot: nil, rule: .signedByUser))
        let other = ModeSignals(bundleId: "com.figma.Desktop", bundlePath: "/Applications/Figma.app", teamID: "T8RHJ3WLGX", userTeamIDs: ["MVAUZXPK9M"])
        XCTAssertEqual(ModeInference.infer(other, environment: environment()).mode, .reference)
    }

    // 7
    func testNothingMatchesIsReferenceWithoutRoot() {
        let s = ModeSignals(bundleId: "com.anthropic.claudefordesktop", bundlePath: "/Applications/Claude.app", teamID: "Q6L7ARMD6X")
        XCTAssertEqual(ModeInference.infer(s, environment: environment(entries: ["/Applications": ["Claude.app", "Figma.app"]])), ModeDecision(mode: .reference, projectRoot: nil, rule: .none))
    }
}
