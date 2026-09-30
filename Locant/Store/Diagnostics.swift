import Foundation

/// v0.9 R70: the block Settings › General › Copy Diagnostics puts on the clipboard, for pasting
/// into an issue. Pure: `AppState` gathers the `Values`, this renders them. Nothing about the
/// user beyond the home folder path, shortened to `~`; nothing from any capture.
enum Diagnostics {
    struct Display: Equatable, Sendable {
        var width: Int
        var height: Int
        var scale: Int
    }

    struct ActionHotkey: Equatable, Sendable {
        var action: String
        var hotkey: String?
    }

    struct AgentLine: Equatable, Sendable {
        var name: String
        var connected: Bool
    }

    struct Values: Equatable, Sendable {
        var version: String?
        var build: String?
        var macOS: String
        var architecture: String
        var translated: Bool
        var displays: [Display]
        var accessibility: Bool?
        var screenRecording: Bool?
        var appPath: String
        var pointHotkey: String
        var actionHotkeys: [ActionHotkey]
        var ballEnabled: Bool
        var ballAutoHide: Bool
        var trackpadTaps: Bool
        var sounds: Bool
        var pastesIntoAgent: Bool
        var collectsIterations: Bool
        var retentionDays: Int
        var captureFolder: String
        var homeDirectory: String
        var organization: String
        var captureCount: Int?
        var agents: [AgentLine]
        var checksForUpdates: Bool
        var lastUpdateCheck: Date?
    }

    /// The block, one fact per line, in the order the spec lists them.
    static func render(_ v: Values, timeZone: TimeZone = .current) -> String {
        var lines: [String] = ["## Locant diagnostics"]
        lines.append("Locant: \(v.version ?? "unknown") (\(v.build ?? "unknown"))")
        lines.append("macOS: \(v.macOS)")
        lines.append("Chip: \(v.architecture)\(v.translated ? ", translated under Rosetta" : "")")
        if v.displays.isEmpty {
            lines.append("Displays: unknown")
        } else {
            let list = v.displays.map { "\($0.width)×\($0.height) @\($0.scale)x" }.joined(separator: ", ")
            lines.append("Displays: \(v.displays.count) · \(list)")
        }
        lines.append("Accessibility: \(grant(v.accessibility))")
        lines.append("Screen Recording: \(grant(v.screenRecording))")
        lines.append("App: \(shorten(v.appPath, home: v.homeDirectory))")
        let actions = v.actionHotkeys.map { "\($0.action) \($0.hotkey ?? "none")" }
        lines.append(("Hotkeys: Point \(v.pointHotkey)" + (actions.isEmpty ? "" : " · " + actions.joined(separator: " · "))))
        lines.append("Ball: \(onOff(v.ballEnabled)), auto-hide \(onOff(v.ballAutoHide))")
        lines.append("Feedback: taps \(onOff(v.trackpadTaps)), sounds \(onOff(v.sounds))")
        lines.append("Paste into agent: \(onOff(v.pastesIntoAgent))")
        lines.append("Iterations: \(onOff(v.collectsIterations))")
        lines.append("Retention: \(v.retentionDays == 0 ? "forever" : "\(v.retentionDays) days")")
        let count = v.captureCount.map { "\($0) capture\($0 == 1 ? "" : "s")" } ?? "unknown count"
        lines.append("Captures: \(shorten(v.captureFolder, home: v.homeDirectory)) · \(v.organization) · \(count)")
        if v.agents.isEmpty {
            lines.append("Agents: none")
        } else {
            lines.append("Agents: " + v.agents.map { "\($0.name) \($0.connected ? "connected" : "not connected")" }.joined(separator: " · "))
        }
        let last = v.lastUpdateCheck.map { "last checked \(dateText($0, timeZone: timeZone))" } ?? "never checked"
        lines.append("Updates: \(v.checksForUpdates ? "checked daily" : "check off") · \(last)")
        return lines.joined(separator: "\n") + "\n"
    }

    /// `~` for the home folder, so the block names no user.
    static func shorten(_ path: String, home: String) -> String {
        let home = home.hasSuffix("/") ? String(home.dropLast()) : home
        guard !home.isEmpty else { return path }
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    private static func grant(_ granted: Bool?) -> String {
        switch granted {
        case .some(true): "granted"
        case .some(false): "not granted"
        case .none: "unknown"
        }
    }

    private static func onOff(_ on: Bool) -> String { on ? "on" : "off" }

    private static func dateText(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
