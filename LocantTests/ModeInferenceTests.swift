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
        env.simulatorProjectRoot = { $0 == "com.inspireocean.app" ? "/Users/me/Code/Oryne" : nil }
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

        XCTAssertEqual(ModeEnvironment.projectRoot(ofSimulatedApp: "com.inspireocean.app", derivedData: real), "/Users/me/Code/Oryne")
        XCTAssertEqual(ModeEnvironment.projectRoot(ofSimulatedApp: "com.inspireocean.app", derivedData: link), "/Users/me/Code/Oryne")
        XCTAssertNil(ModeEnvironment.projectRoot(ofSimulatedApp: "com.other", derivedData: link))
    }

    /// Xcode 27 has no Simulator.app; Device Hub shows simulators, and physical devices too, so its
    /// bundle id alone is not the simulator: the classifier says when its window shows one.
    func testDeviceHubIsFixOnlyWhenItShowsASimulator() {
        let hub = ModeSignals(bundleId: "com.apple.dt.Devices", bundlePath: "/Applications/Xcode.app/Contents/Applications/DeviceHub.app")
        XCTAssertEqual(ModeInference.infer(hub, environment: environment()), ModeDecision(mode: .reference, projectRoot: nil, rule: .none))
        let showing = ModeSignals(bundleId: "com.apple.dt.Devices", isSimulator: true, simulatedBundleId: "com.someone.else")
        XCTAssertEqual(ModeInference.infer(showing, environment: environment()), ModeDecision(mode: .fix, projectRoot: nil, rule: .simulator))
    }

    func testDeviceHubCaptureGetsTheSimulatedAppsProjectRoot() {
        var env = environment()
        env.simulatorProjectRoot = { $0 == "com.inspireocean.app" ? "/Users/me/Code/Oryne" : nil }
        let source = SourceInfo(
            app: AppInfo(bundleId: "com.apple.dt.Devices", name: "Device Hub"),
            window: WindowInfo(title: "iPhone 17 Pro – iOS 26.5"),
            url: nil,
            simulator: SimulatorInfo(device: "iPhone 17 Pro", appBundleId: "com.inspireocean.app")
        )
        let context = CaptureContext(source: source, frontPID: 0, bundlePath: "/Applications/Xcode.app/Contents/Applications/DeviceHub.app")
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
