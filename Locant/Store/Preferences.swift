import CoreGraphics
import Foundation
import Observation

/// v0.3 R18: the user's few settings, backed by UserDefaults. Owned by `AppState`; there is no
/// second shared object. A fresh install works with every default.
enum HotkeyModifier: String, CaseIterable, Codable, Sendable {
    case control, option, shift, command, rightCommand

    var title: String {
        switch self {
        case .control: "Double-tap Control"
        case .option: "Double-tap Option"
        case .shift: "Double-tap Shift"
        case .command: "Double-tap Command"
        case .rightCommand: "Double-tap Right Command"
        }
    }

    /// For the menu bar item title.
    var symbol: String {
        switch self {
        case .control: "⌃⌃"
        case .option: "⌥⌥"
        case .shift: "⇧⇧"
        case .command: "⌘⌘"
        case .rightCommand: "right ⌘⌘"
        }
    }

    var glyph: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        case .rightCommand: "right ⌘"
        }
    }
}

/// v0.3 R21: how captures are organized on disk. Finder tags are always written; this only adds
/// subfolders for people who think in folders.
enum CaptureOrganization: String, CaseIterable, Codable, Sendable {
    case none, byApp, byProject, byMonth

    var title: String {
        switch self {
        case .none: "One folder"
        case .byApp: "By app"
        case .byProject: "By project"
        case .byMonth: "By month"
        }
    }
}

/// Modifier keys of a chord, AppKit-free so the store stays pure.
struct KeyModifiers: OptionSet, Codable, Sendable, Hashable {
    let rawValue: UInt8
    static let control = KeyModifiers(rawValue: 1)
    static let option = KeyModifiers(rawValue: 2)
    static let shift = KeyModifiers(rawValue: 4)
    static let command = KeyModifiers(rawValue: 8)

    /// In the order macOS prints them: ⌃ ⌥ ⇧ ⌘.
    var symbols: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

/// v0.3: the capture hotkey, recorded by the user. Either a double-tap of one modifier (the v0.1
/// convention) or a key pressed with modifiers.
enum Hotkey: Codable, Equatable, Sendable {
    case doubleTap(HotkeyModifier)
    case chord(keyCode: UInt16, modifiers: KeyModifiers, key: String)

    static let `default` = Hotkey.doubleTap(.control)

    /// "Double-tap ⌃", "⌘⇧D", "F5".
    var title: String {
        switch self {
        case .doubleTap(let modifier): "Double-tap \(modifier.glyph)"
        case .chord(_, let modifiers, let key): modifiers.symbols + key
        }
    }

    /// Short form for the menu bar item: "⌃⌃", "⌘⇧D".
    var symbol: String {
        switch self {
        case .doubleTap(let modifier): modifier.symbol
        case .chord(_, let modifiers, let key): modifiers.symbols + key
        }
    }
}

@Observable
@MainActor
final class Preferences {
    enum Key {
        static let hotkey = "hotkey"
        static let hotkeyModifier = "hotkeyModifier" // v0.3 early builds; migrated on read
        static let captureFolder = "captureFolder"
        static let ballEnabled = "ballEnabled"
        static let ballPosition = "ballPosition"
        static let ballAutoHide = "ballAutoHide"
        static let myApps = "myApps"
        static let organization = "organization"
        static let colorFormat = "colorFormat"
        static let colorSpace = "colorSpace"
        static let retentionDays = "retentionDays"
        static let adjustSelection = "adjustSelection"
        static let actionHotkeys = "actionHotkeys" // v0.3 early builds: only what the user recorded; migrated on read
        static let actionHotkeySettings = "actionHotkeySettings"
        static let hintCounts = "hintCounts" // v0.5 R40
        static let collectsIterations = "collectsIterations" // v0.6 R52
        static let checksForUpdates = "checksForUpdates" // v0.6 R46
        static let lastUpdateCheck = "lastUpdateCheck"
        static let skippedUpdateVersion = "skippedUpdateVersion"
        static let pastesIntoAgent = "pastesIntoAgent" // v0.8.1 R63
        static let trackpadTaps = "trackpadTaps" // v0.8.1 R61
        static let sounds = "sounds" // v0.8.1 R61
    }

    /// The actions that can carry a hotkey (R29), in menu and ring order; each one's digit is its position here.
    static let hotkeyActions = ["point", "snap", "text", "color", "cut"]

    /// R29: ⌃⌥ and the action's digit. Types nothing on any keyboard layout, macOS assigns nothing
    /// there, and neither do Xcode, Figma, or the window managers. Nil for an unknown action.
    static func defaultActionHotkey(_ action: String) -> Hotkey? {
        guard let index = hotkeyActions.firstIndex(of: action) else { return nil }
        let digitKeyCodes: [UInt16] = [18, 19, 20, 21, 23] // ANSI 1 2 3 4 5
        return .chord(keyCode: digitKeyCodes[index], modifiers: [.control, .option], key: String(index + 1))
    }

    static var defaultActionHotkeys: [String: Hotkey] {
        Dictionary(uniqueKeysWithValues: hotkeyActions.compactMap { action in defaultActionHotkey(action).map { (action, $0) } })
    }

    static let retentionChoices = [7, 30, 90, 0]

    static var defaultCaptureFolder: String { ModeInference.directoryPath(FileStore.defaultDirectory) }

    @ObservationIgnored private let defaults: UserDefaults
    /// Called after the hotkey changes so the monitor can restart.
    @ObservationIgnored var onHotkeyChange: (() -> Void)?
    /// Called after the ball toggle changes so it can show or hide at once.
    @ObservationIgnored var onBallEnabledChange: (() -> Void)?
    /// Called after the auto-hide toggle changes so the ball tucks in or comes out at once.
    @ObservationIgnored var onBallAutoHideChange: (() -> Void)?
    /// Called after any per-action hotkey changes so the monitors can restart.
    @ObservationIgnored var onActionHotkeysChange: (() -> Void)?

    var hotkey: Hotkey {
        didSet {
            if let data = try? JSONEncoder().encode(hotkey) { defaults.set(data, forKey: Key.hotkey) }
            if hotkey != oldValue { onHotkeyChange?() }
        }
    }

    var captureFolder: String {
        didSet { defaults.set(captureFolder, forKey: Key.captureFolder) }
    }

    var ballEnabled: Bool {
        didSet {
            defaults.set(ballEnabled, forKey: Key.ballEnabled)
            if ballEnabled != oldValue { onBallEnabledChange?() }
        }
    }

    /// Idle, the ball tucks into the nearest screen edge, part of it showing.
    var ballAutoHide: Bool {
        didSet {
            defaults.set(ballAutoHide, forKey: Key.ballAutoHide)
            if ballAutoHide != oldValue { onBallAutoHideChange?() }
        }
    }

    /// AppKit screen points; nil until the user moves the ball.
    var ballPosition: CGPoint? {
        didSet {
            if let ballPosition {
                defaults.set([ballPosition.x, ballPosition.y], forKey: Key.ballPosition)
            } else {
                defaults.removeObject(forKey: Key.ballPosition)
            }
        }
    }

    var myApps: [String] {
        didSet { defaults.set(myApps, forKey: Key.myApps) }
    }

    var organization: CaptureOrganization {
        didSet { defaults.set(organization.rawValue, forKey: Key.organization) }
    }

    var colorFormat: ColorFormat {
        didSet { defaults.set(colorFormat.rawValue, forKey: Key.colorFormat) }
    }

    var colorSpace: ColorSpaceChoice {
        didSet { defaults.set(colorSpace.rawValue, forKey: Key.colorSpace) }
    }

    /// Days before images go to the Trash; 0 keeps everything.
    var retentionDays: Int {
        didSet { defaults.set(retentionDays, forKey: Key.retentionDays) }
    }

    /// A dragged region for Snap, Text, or Cut waits with handles until Return.
    var adjustSelection: Bool {
        didSet { defaults.set(adjustSelection, forKey: Key.adjustSelection) }
    }

    /// What the user changed about an action's hotkey: recorded another, or cleared it (`hotkey` nil).
    struct ActionHotkeySetting: Codable, Equatable, Sendable {
        var hotkey: Hotkey?
    }

    /// R29: only departures from the defaults are stored, so a cleared action stays cleared and
    /// an untouched one follows any future default.
    private var actionHotkeySettings: [String: ActionHotkeySetting] {
        didSet {
            if let data = try? JSONEncoder().encode(actionHotkeySettings) { defaults.set(data, forKey: Key.actionHotkeySettings) }
            if actionHotkeySettings != oldValue { onActionHotkeysChange?() }
        }
    }

    /// The assigned hotkey of each action (Point, Snap, Text, Color, Cut) by name; a cleared action is absent.
    var actionHotkeys: [String: Hotkey] {
        var result = Self.defaultActionHotkeys
        for (action, setting) in actionHotkeySettings { result[action] = setting.hotkey }
        return result
    }

    /// Record `hotkey` for `action`, or clear it with nil. Recording the default forgets the departure.
    func setActionHotkey(_ hotkey: Hotkey?, for action: String) {
        if hotkey == Self.defaultActionHotkey(action) {
            actionHotkeySettings[action] = nil
        } else {
            actionHotkeySettings[action] = ActionHotkeySetting(hotkey: hotkey)
        }
    }

    /// The action already bound to `hotkey`, if any: "capture" for the capture hotkey, else the
    /// action's name. `excluding` is the action being recorded, which may keep its own hotkey.
    func action(using hotkey: Hotkey, excluding: String? = nil) -> String? {
        if excluding != "capture", self.hotkey == hotkey { return "capture" }
        return Self.hotkeyActions.first { $0 != excluding && actionHotkeys[$0] == hotkey }
    }

    /// v0.5 R40: how many times each hint has been shown, by key. The cap is the caller's.
    private var hintCounts: [String: Int] {
        didSet { defaults.set(hintCounts, forKey: Key.hintCounts) }
    }

    func hintCount(_ key: String) -> Int { hintCounts[key] ?? 0 }

    func markHintShown(_ key: String) { hintCounts[key] = hintCount(key) + 1 }

    /// v0.6 R52: after a Point capture in one of the user's apps, capture the element again each
    /// time that app launches or comes forward within a day, when it looks different.
    var collectsIterations: Bool {
        didSet { defaults.set(collectsIterations, forKey: Key.collectsIterations) }
    }

    /// v0.6 R46: the daily release check (R45). Off means Locant opens no socket at all.
    var checksForUpdates: Bool {
        didSet { defaults.set(checksForUpdates, forKey: Key.checksForUpdates) }
    }

    /// v0.8.1 R63: after Return, bring the agent app used last forward and paste the capture there.
    var pastesIntoAgent: Bool {
        didSet { defaults.set(pastesIntoAgent, forKey: Key.pastesIntoAgent) }
    }

    /// v0.8.1 R61: a tap under the finger as the outline moves, the ring opens, the segments pass.
    var trackpadTaps: Bool {
        didSet { defaults.set(trackpadTaps, forKey: Key.trackpadTaps) }
    }

    /// v0.8.1 R61: `landed` when a capture reaches the clipboard, `missed` when nothing did.
    var sounds: Bool {
        didSet { defaults.set(sounds, forKey: Key.sounds) }
    }

    /// When the last check ran, whatever it found; nil until the first.
    var lastUpdateCheck: Date? {
        didSet {
            if let lastUpdateCheck {
                defaults.set(lastUpdateCheck, forKey: Key.lastUpdateCheck)
            } else {
                defaults.removeObject(forKey: Key.lastUpdateCheck)
            }
        }
    }

    /// The version the user chose "Skip This Version" for; the next one asks again.
    var skippedUpdateVersion: String? {
        didSet {
            if let skippedUpdateVersion {
                defaults.set(skippedUpdateVersion, forKey: Key.skippedUpdateVersion)
            } else {
                defaults.removeObject(forKey: Key.skippedUpdateVersion)
            }
        }
    }

    var captureFolderURL: URL { URL(filePath: captureFolder, directoryHint: .isDirectory) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Key.hotkey), let stored = try? JSONDecoder().decode(Hotkey.self, from: data) {
            hotkey = stored
        } else if let legacy = defaults.string(forKey: Key.hotkeyModifier).flatMap(HotkeyModifier.init(rawValue:)) {
            hotkey = .doubleTap(legacy)
        } else {
            hotkey = .default
        }
        captureFolder = defaults.string(forKey: Key.captureFolder) ?? Self.defaultCaptureFolder
        ballEnabled = defaults.object(forKey: Key.ballEnabled) as? Bool ?? true
        ballAutoHide = defaults.object(forKey: Key.ballAutoHide) as? Bool ?? true
        if let pair = defaults.array(forKey: Key.ballPosition) as? [Double], pair.count == 2 {
            ballPosition = CGPoint(x: pair[0], y: pair[1])
        } else {
            ballPosition = nil
        }
        myApps = defaults.stringArray(forKey: Key.myApps) ?? []
        organization = defaults.string(forKey: Key.organization).flatMap(CaptureOrganization.init(rawValue:)) ?? .none
        colorFormat = defaults.string(forKey: Key.colorFormat).flatMap(ColorFormat.init(rawValue:)) ?? .hex
        colorSpace = defaults.string(forKey: Key.colorSpace).flatMap(ColorSpaceChoice.init(rawValue:)) ?? .sRGB
        retentionDays = defaults.object(forKey: Key.retentionDays) as? Int ?? 30
        adjustSelection = defaults.object(forKey: Key.adjustSelection) as? Bool ?? true
        hintCounts = defaults.dictionary(forKey: Key.hintCounts) as? [String: Int] ?? [:]
        collectsIterations = defaults.object(forKey: Key.collectsIterations) as? Bool ?? true
        checksForUpdates = defaults.object(forKey: Key.checksForUpdates) as? Bool ?? true
        pastesIntoAgent = defaults.object(forKey: Key.pastesIntoAgent) as? Bool ?? false
        trackpadTaps = defaults.object(forKey: Key.trackpadTaps) as? Bool ?? true
        sounds = defaults.object(forKey: Key.sounds) as? Bool ?? true
        lastUpdateCheck = defaults.object(forKey: Key.lastUpdateCheck) as? Date
        skippedUpdateVersion = defaults.string(forKey: Key.skippedUpdateVersion)
        if let data = defaults.data(forKey: Key.actionHotkeySettings), let stored = try? JSONDecoder().decode([String: ActionHotkeySetting].self, from: data) {
            actionHotkeySettings = stored
        } else if let data = defaults.data(forKey: Key.actionHotkeys), let legacy = try? JSONDecoder().decode([String: Hotkey].self, from: data) {
            actionHotkeySettings = legacy.mapValues { ActionHotkeySetting(hotkey: $0) }
        } else {
            actionHotkeySettings = [:]
        }
    }
}
