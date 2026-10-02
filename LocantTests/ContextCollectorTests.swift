import XCTest
@testable import Locant

/// Which windows show a simulator, which device, and which app. Pure: no device set or process is read.
@MainActor
final class ContextCollectorTests: XCTestCase {
    private let iPhone = SimulatorApps.Device(udid: "0EBF66EE-3E7D-48F9-9D44-E7B1A58DACF1", name: "iPhone 17 Pro")
    private let iPad = SimulatorApps.Device(udid: "5EDCDCC1-50FF-42FF-A34F-8004735D9FBF", name: "iPad Pro 13-inch (M5)")

    /// Xcode 27: Device Hub shows a booted simulator, its window titled "device – OS"; the app is the
    /// newest one on that device.
    func testDeviceHubWindowShowingABootedSimulator() {
        var asked: [String?] = []
        let info = ContextCollector.simulatorInfo(bundleId: "com.apple.dt.Devices", windowTitle: "iPhone 17 Pro – iOS 26.5",
                                                  booted: { [iPhone, iPad] }, simulatedApp: { asked.append($0); return "com.inspireocean.app" })
        XCTAssertEqual(info, SimulatorInfo(device: "iPhone 17 Pro", appBundleId: "com.inspireocean.app"))
        XCTAssertEqual(asked, [iPhone.udid])
    }

    func testDeviceHubTakesTheAppFromTheDeviceItShows() {
        var asked: [String?] = []
        let info = ContextCollector.simulatorInfo(bundleId: "com.apple.dt.Devices", windowTitle: "iPad Pro 13-inch (M5) – iPadOS 26.5",
                                                  booted: { [iPhone, iPad] }, simulatedApp: { asked.append($0); return nil })
        XCTAssertEqual(info, SimulatorInfo(device: "iPad Pro 13-inch (M5)", appBundleId: nil))
        XCTAssertEqual(asked, [iPad.udid])
    }

    /// Device Hub also shows physical devices, and simulators that are shut down: neither is the simulator.
    func testDeviceHubShowingAnythingElseIsNotTheSimulator() {
        var scanned = false
        for title in ["Malik’s iPhone – iOS 27.0", "iPhone 17 – iOS 26.5", "iPhone 17 Pro Max – iOS 26.5", "Device Hub", nil] {
            let info = ContextCollector.simulatorInfo(bundleId: "com.apple.dt.Devices", windowTitle: title,
                                                      booted: { [iPhone] }, simulatedApp: { _ in scanned = true; return "com.inspireocean.app" })
            XCTAssertNil(info, title ?? "no title")
        }
        XCTAssertFalse(scanned)
    }

    /// Xcode 26 and earlier: Simulator.app shows nothing but simulators, so it needs no device set.
    func testSimulatorAppWindowIsTheSimulator() {
        var asked: [String?] = []
        let info = ContextCollector.simulatorInfo(bundleId: "com.apple.iphonesimulator", windowTitle: "iPhone 17 Pro",
                                                  booted: { XCTFail("Simulator.app needs no device set"); return [] },
                                                  simulatedApp: { asked.append($0); return nil })
        XCTAssertEqual(info, SimulatorInfo(device: "iPhone 17 Pro", appBundleId: nil))
        XCTAssertEqual(asked, [nil], "the newest app on any device, as before")
    }

    func testOtherAppsShowNoSimulatorAndReadNothing() {
        var read = false
        let info = ContextCollector.simulatorInfo(bundleId: "com.apple.Safari", windowTitle: "iPhone 17 Pro – iOS 26.5",
                                                  booted: { read = true; return [] }, simulatedApp: { _ in read = true; return "com.inspireocean.app" })
        XCTAssertNil(info)
        XCTAssertFalse(read)
    }

    // MARK: SimulatorApps

    func testDeviceIsTheOneTheWindowTitleNames() {
        let iPhone17 = SimulatorApps.Device(udid: "073A746A", name: "iPhone 17")
        let dashed = SimulatorApps.Device(udid: "D7ADAC67", name: "QA - dark")
        let devices = [iPhone17, iPhone, dashed]
        XCTAssertEqual(SimulatorApps.device(titled: "iPhone 17 Pro – iOS 26.5", among: devices), iPhone)
        XCTAssertEqual(SimulatorApps.device(titled: "iPhone 17 – iOS 26.5", among: devices), iPhone17)
        XCTAssertEqual(SimulatorApps.device(titled: "iPhone 17 Pro", among: devices), iPhone, "a title that is the name alone")
        XCTAssertEqual(SimulatorApps.device(titled: "QA - dark – iOS 26.5", among: devices), dashed, "a separator inside the name")
        XCTAssertNil(SimulatorApps.device(titled: "iPhone 17 Pro Max – iOS 26.5", among: devices))
        XCTAssertNil(SimulatorApps.device(titled: "Malik’s iPhone – iOS 27.0", among: devices))
    }

    func testBootedDevicesComeFromTheDeviceSet() throws {
        let fm = FileManager.default
        let set = fm.temporaryDirectory.appending(path: "ContextCollectorTests-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: set) }
        func device(_ folder: String, _ plist: [String: Any]?) throws {
            let url = set.appending(path: folder)
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            guard let plist else { return }
            try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0).write(to: url.appending(path: "device.plist"))
        }
        try device("0EBF66EE", ["UDID": "0EBF66EE", "name": "iPhone 17 Pro", "state": 3])
        try device("073A746A", ["UDID": "073A746A", "name": "iPhone 17", "state": 1])
        try device("unreadable", nil)
        XCTAssertEqual(SimulatorApps.booted(in: set), [SimulatorApps.Device(udid: "0EBF66EE", name: "iPhone 17 Pro")])
        XCTAssertEqual(SimulatorApps.booted(in: set.appending(path: "missing")), [])
    }

    func testSimulatedAppIsAMainExecutableInADeviceContainer() {
        let app = "/Users/me/Library/Developer/CoreSimulator/Devices/0EBF66EE/data/Containers/Bundle/Application/8707/Oryne.app"
        XCTAssertEqual(SimulatorApps.simulatedAppBundle(executable: app + "/Oryne", onDevice: nil), app)
        XCTAssertEqual(SimulatorApps.simulatedAppBundle(executable: app + "/Oryne", onDevice: "0EBF66EE"), app)
        XCTAssertNil(SimulatorApps.simulatedAppBundle(executable: app + "/Oryne", onDevice: "5EDCDCC1"), "another device's app")
        XCTAssertNil(SimulatorApps.simulatedAppBundle(executable: app + "/PlugIns/OceanWidgets.appex/OceanWidgets", onDevice: nil), "an extension")
        XCTAssertNil(SimulatorApps.simulatedAppBundle(executable: app + "/Frameworks/Helper", onDevice: nil), "not the main executable")
        XCTAssertNil(SimulatorApps.simulatedAppBundle(executable: "/Applications/Safari.app/Contents/MacOS/Safari", onDevice: nil))
    }
}
