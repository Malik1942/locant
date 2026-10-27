import AppKit
import Darwin

/// R5: what the user was looking at when the hotkey fired. Runs before the overlay appears.
@MainActor
enum ContextCollector {
    /// Where the payload's window title comes from.
    enum WindowTitle {
        /// The app's focused window, falling back to its main window: right for a click in a normal window.
        case focused
        /// Already known, or known to be absent: a widget names its own window, a desktop icon or a
        /// menu bar item sits in none, and the app's focused window would be unrelated.
        case known(String?)
    }

    /// With no `pid`, describes the frontmost app (hotkey time). With a `pid`, describes that app
    /// (the owner of the clicked window), so the source matches what was actually pointed at.
    static func collect(reader: AccessibilityReader, pid targetPID: pid_t? = nil, windowTitle: WindowTitle = .focused) async -> CaptureContext? {
        let app: NSRunningApplication?
        if let targetPID {
            app = NSRunningApplication(processIdentifier: targetPID)
        } else {
            app = NSWorkspace.shared.frontmostApplication
        }
        guard let app else { return nil }
        let bundleId = app.bundleIdentifier ?? "unknown"
        let name = app.localizedName ?? bundleId
        let pid = app.processIdentifier
        let title: String?
        switch windowTitle {
        case .focused: title = await reader.focusedWindowTitle(pid: pid)
        case .known(let known): title = known
        }

        let simulator = simulatorInfo(bundleId: bundleId, windowTitle: title, booted: { SimulatorApps.booted() },
                                      simulatedApp: SimulatorApps.mostRecentlyLaunchedApp(onDevice:))
        let source = SourceInfo(
            app: AppInfo(bundleId: bundleId, name: name),
            window: WindowInfo(title: title),
            url: nil, // Safari/Chrome read still deferred
            simulator: simulator?.info
        )
        let bundleURL = app.bundleURL
        return CaptureContext(
            source: source,
            frontPID: pid,
            bundlePath: bundleURL?.path(percentEncoded: false),
            teamID: bundleURL.flatMap(CodeSigning.teamID(ofBundleAt:)),
            simulatedBundlePath: simulator?.bundlePath
        )
    }

    /// The device and the app it runs, when `bundleId` shows a simulator; nil for any other app. With them,
    /// the app's running copy, the build on screen (specs/simulator-project-root.md R105).
    /// `booted` reads the device set and `simulatedApp` walks every process, so they run only then.
    static func simulatorInfo(bundleId: String, windowTitle: String?, booted: () -> [SimulatorApps.Device],
                              simulatedApp: (_ onDevice: String?) -> SimulatorApps.RunningApp?) -> (info: SimulatorInfo, bundlePath: String?)? {
        switch bundleId {
        case ModeInference.simulatorBundleId:
            // Simulator.app shows nothing but simulators.
            let app = simulatedApp(nil)
            return (SimulatorInfo(device: deviceName(fromWindowTitle: windowTitle) ?? "Simulator", appBundleId: app?.bundleId), app?.bundlePath)
        case ModeInference.deviceHubBundleId:
            // Xcode 27: Device Hub also shows physical devices and simulators that are shut down. Only a
            // booted simulator named by the window counts, and the app is the one on that device.
            guard let windowTitle, let device = SimulatorApps.device(titled: windowTitle, among: booted()) else { return nil }
            let app = simulatedApp(device.udid)
            return (SimulatorInfo(device: device.name, appBundleId: app?.bundleId), app?.bundlePath)
        default:
            return nil
        }
    }

    /// "iPhone 17 Pro – iOS 26.5" → "iPhone 17 Pro"
    static func deviceName(fromWindowTitle title: String?) -> String? {
        guard let title, !title.isEmpty else { return nil }
        for separator in [" – ", " — ", " - "] {
            if let range = title.range(of: separator) {
                return String(title[..<range.lowerBound])
            }
        }
        return title
    }
}

/// On-screen windows, front to back, in CG coordinates, in every layer: desktop icons (Finder),
/// widgets (Notification Center), status items (Control Center and the apps that own them), the Dock,
/// and normal windows. Feeds the window hit-test (R3) and crop clamp (R4).
enum WindowList {
    static func onScreen() -> [Geometry.WindowRecord] {
        // Read before the overlay comes up, so this is the app whose menu titles are showing.
        let menuBarOwner = NSWorkspace.shared.menuBarOwningApplication?.processIdentifier
        let menuBarLayer = Int(CGWindowLevelForKey(.mainMenuWindow))
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as! CFDictionary),
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0
            else { return nil }
            let id = info[kCGWindowNumber as String] as? CGWindowID ?? 0
            if NSRunningApplication(processIdentifier: pid) == nil {
                // Window Server draws the menu bar backdrop, the cursor, and the display backstop.
                // Only the menu bar is a target, and its titles belong to the app that owns the menu bar.
                guard layer == menuBarLayer, let menuBarOwner else { return nil }
                return Geometry.WindowRecord(ownerPID: menuBarOwner, layer: layer, bounds: bounds, windowID: id)
            }
            return Geometry.WindowRecord(ownerPID: pid, layer: layer, bounds: bounds, windowID: id)
        }
    }

    /// specs/frozen-screen.md R121: whether a window from an earlier list is still on screen. One
    /// window's description, so it is cheap enough for every hover.
    static func isOnScreen(_ window: Geometry.WindowRecord) -> Bool {
        // The array holds the ids themselves as its values, not numbers: an array of NSNumbers
        // finds nothing, and every window would read as closed (Oct 26, Malik could select only
        // menu bar items).
        var id = UnsafeRawPointer(bitPattern: UInt(window.windowID))
        guard window.windowID != 0,
              let ids = CFArrayCreate(kCFAllocatorDefault, &id, 1, nil),
              let list = CGWindowListCreateDescriptionFromArray(ids) as? [[String: Any]],
              let info = list.first else { return false }
        return info[kCGWindowIsOnscreen as String] as? Bool ?? false
    }

    /// R122: whether another app has a menu open. Only windows at a menu's level are looked up, so
    /// it is quick enough to run on a mouse press.
    static func hasOpenMenu(excludingPID: pid_t) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
        let windows = list.compactMap { info -> Geometry.WindowRecord? in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  Geometry.menuLayers.contains(layer),
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  NSRunningApplication(processIdentifier: pid) != nil // not Window Server's own
            else { return nil }
            return Geometry.WindowRecord(ownerPID: pid, layer: layer, bounds: .zero)
        }
        return Geometry.hasOpenMenu(windows: windows, excludingPID: excludingPID)
    }
}

/// The simulated app is a Mac process under CoreSimulator. The most recently launched one (highest
/// pid), on the device the window shows when that is known, is the best public-API guess for what
/// the window shows.
enum SimulatorApps {
    /// A simulator in CoreSimulator's device set.
    struct Device: Equatable, Sendable {
        var udid: String
        var name: String
    }

    /// A simulated app's process: its bundle id, and the bundle it runs from in the device's container.
    struct RunningApp: Equatable, Sendable {
        var bundleId: String
        var bundlePath: String
    }

    static let deviceSet = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Developer/CoreSimulator/Devices", directoryHint: .isDirectory)

    /// The booted simulators: each device's `device.plist` names it and gives its state (3 is booted).
    static func booted(in deviceSet: URL = Self.deviceSet) -> [Device] {
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: deviceSet.path(percentEncoded: false))) ?? []
        return folders.sorted().compactMap { folder in
            guard let data = try? Data(contentsOf: deviceSet.appending(path: folder).appending(path: "device.plist")),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  plist["state"] as? Int == 3,
                  let udid = plist["UDID"] as? String, let name = plist["name"] as? String
            else { return nil }
            return Device(udid: udid, name: name)
        }
    }

    /// The device a window title names: the title is its name, or its name then " – " and the OS.
    /// The longest name wins, for a name that has a separator in it.
    static func device(titled title: String, among devices: [Device]) -> Device? {
        devices
            .filter { device in title == device.name || [" – ", " — ", " - "].contains { title.hasPrefix(device.name + $0) } }
            .max { $0.name.count < $1.name.count }
    }

    static func mostRecentlyLaunchedApp(onDevice udid: String? = nil) -> RunningApp? {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: Int(count) * 2)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return nil }

        var buffer = [CChar](repeating: 0, count: 4096)
        var best: (pid: pid_t, app: RunningApp)?
        for pid in pids.prefix(Int(filled)) where pid > 0 {
            let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
            guard length > 0 else { continue }
            let path = String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            guard let bundlePath = simulatedAppBundle(executable: path, onDevice: udid) else { continue }
            if let best, pid <= best.pid { continue }
            if let bundleId = Bundle(url: URL(filePath: bundlePath))?.bundleIdentifier {
                best = (pid, RunningApp(bundleId: bundleId, bundlePath: bundlePath))
            }
        }
        return best?.app
    }

    /// The app bundle whose main executable `path` is, when it is a simulated app (on the device
    /// `udid`, when given); nil for anything else, app extensions included.
    static func simulatedAppBundle(executable path: String, onDevice udid: String?) -> String? {
        guard let devices = path.range(of: "/CoreSimulator/Devices/"),
              path.contains("/Containers/Bundle/Application/"),
              !path.contains(".appex/"),
              let appRange = path.range(of: ".app/")
        else { return nil }
        if let udid, !path[devices.upperBound...].hasPrefix(udid + "/") { return nil }
        let bundlePath = String(path[..<appRange.lowerBound]) + ".app"
        let remainder = path.dropFirst(bundlePath.count + 1)
        return remainder.contains("/") ? nil : bundlePath // main executable only
    }
}
