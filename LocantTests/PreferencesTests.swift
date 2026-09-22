import XCTest
@testable import Locant

@MainActor
final class PreferencesTests: XCTestCase {
    // 1
    func testDefaultsWhenNothingStored() {
        let p = Preferences(defaults: isolatedDefaults())
        XCTAssertEqual(p.hotkey, .default)
        XCTAssertEqual(p.hotkey.title, "Double-tap ⌃")
        XCTAssertEqual(p.captureFolder, Preferences.defaultCaptureFolder)
        XCTAssertTrue(p.captureFolder.hasSuffix("/Pictures/Locant"))
        XCTAssertTrue(p.ballEnabled)
        XCTAssertTrue(p.ballAutoHide)
        XCTAssertNil(p.ballPosition)
        XCTAssertEqual(p.myApps, [])
        XCTAssertEqual(p.organization, .none)
        XCTAssertTrue(p.adjustSelection)
        XCTAssertTrue(p.checksForUpdates)
        XCTAssertTrue(p.collectsIterations)
        XCTAssertFalse(p.pastesIntoAgent)
        XCTAssertTrue(p.trackpadTaps)
        XCTAssertTrue(p.sounds)
        XCTAssertNil(p.lastUpdateCheck)
        XCTAssertNil(p.skippedUpdateVersion)
        XCTAssertEqual(p.actionHotkeys, Preferences.defaultActionHotkeys)
        XCTAssertEqual(p.actionHotkeys["point"]?.title, "⌃⌥1")
        XCTAssertEqual(p.actionHotkeys["snap"]?.title, "⌃⌥2")
        XCTAssertEqual(p.actionHotkeys["text"]?.title, "⌃⌥3")
        XCTAssertEqual(p.actionHotkeys["color"]?.title, "⌃⌥4")
        XCTAssertEqual(p.actionHotkeys["cut"]?.title, "⌃⌥5")
        XCTAssertNil(Preferences.defaultActionHotkey("nope"))
    }

    // v0.5 R40: hint bookkeeping persists; the store counts, the caller caps.
    func testHintCountsPersistAndDoNotCap() {
        let defaults = isolatedDefaults()
        let p = Preferences(defaults: defaults)
        XCTAssertEqual(p.hintCount("launch"), 0)
        p.markHintShown("launch")
        XCTAssertEqual(p.hintCount("launch"), 1)
        for _ in 0..<4 { p.markHintShown("overlay.point") }
        XCTAssertEqual(p.hintCount("overlay.point"), 4)
        let again = Preferences(defaults: defaults)
        XCTAssertEqual(again.hintCount("launch"), 1)
        XCTAssertEqual(again.hintCount("overlay.point"), 4)
        XCTAssertEqual(again.hintCount("color"), 0)
    }

    // R29: a recorded hotkey and a cleared one both survive a relaunch; the rest stay default.
    func testActionHotkeyRecordAndClearPersist() {
        let defaults = isolatedDefaults()
        let p = Preferences(defaults: defaults)
        var changes = 0
        p.onActionHotkeysChange = { changes += 1 }
        let custom = Hotkey.chord(keyCode: 1, modifiers: [.command, .shift], key: "S")
        p.setActionHotkey(custom, for: "snap")
        p.setActionHotkey(custom, for: "snap")
        p.setActionHotkey(nil, for: "text")
        XCTAssertEqual(changes, 2, "only real changes restart the monitor")

        let again = Preferences(defaults: defaults)
        XCTAssertEqual(again.actionHotkeys["snap"], custom)
        XCTAssertNil(again.actionHotkeys["text"], "a cleared action stays cleared")
        XCTAssertEqual(again.actionHotkeys["point"], Preferences.defaultActionHotkey("point"))
        XCTAssertEqual(again.actionHotkeys["color"], Preferences.defaultActionHotkey("color"))
        XCTAssertEqual(again.actionHotkeys["cut"], Preferences.defaultActionHotkey("cut"))

        again.setActionHotkey(Preferences.defaultActionHotkey("snap"), for: "snap")
        again.setActionHotkey(Preferences.defaultActionHotkey("text"), for: "text")
        XCTAssertEqual(Preferences(defaults: defaults).actionHotkeys, Preferences.defaultActionHotkeys)
    }

    // v0.3 early builds stored only what the user recorded; those stay, the rest take the defaults.
    func testLegacyActionHotkeysMigrate() throws {
        let defaults = isolatedDefaults()
        let custom = Hotkey.chord(keyCode: 7, modifiers: [.command, .option], key: "X")
        defaults.set(try JSONEncoder().encode(["cut": custom]), forKey: Preferences.Key.actionHotkeys)
        let p = Preferences(defaults: defaults)
        XCTAssertEqual(p.actionHotkeys["cut"], custom)
        XCTAssertEqual(p.actionHotkeys["snap"], Preferences.defaultActionHotkey("snap"))
        XCTAssertEqual(p.actionHotkeys.count, 5)
    }

    func testActionUsingHotkey() {
        let p = Preferences(defaults: isolatedDefaults())
        XCTAssertEqual(p.action(using: .doubleTap(.control)), "capture")
        XCTAssertNil(p.action(using: .doubleTap(.control), excluding: "capture"))
        XCTAssertEqual(p.action(using: Preferences.defaultActionHotkey("snap")!), "snap")
        XCTAssertNil(p.action(using: Preferences.defaultActionHotkey("snap")!, excluding: "snap"))
        XCTAssertEqual(p.action(using: Preferences.defaultActionHotkey("snap")!, excluding: "text"), "snap")
        XCTAssertNil(p.action(using: .chord(keyCode: 0, modifiers: [.command], key: "A")))
    }

    // 2
    func testRoundTripThroughDefaults() {
        let defaults = isolatedDefaults()
        let p = Preferences(defaults: defaults)
        var hotkeyChanges = 0
        p.onHotkeyChange = { hotkeyChanges += 1 }
        p.hotkey = .chord(keyCode: 2, modifiers: [.command, .shift], key: "D")
        p.hotkey = .chord(keyCode: 2, modifiers: [.command, .shift], key: "D")
        p.captureFolder = "/tmp/captures"
        p.ballEnabled = false
        p.ballAutoHide = false
        p.ballPosition = CGPoint(x: 1200, y: 40)
        p.myApps = ["com.inspireocean.app"]
        p.organization = .byProject
        p.adjustSelection = false
        p.checksForUpdates = false
        p.collectsIterations = false
        p.pastesIntoAgent = true
        p.trackpadTaps = false
        p.sounds = false
        p.lastUpdateCheck = Date(timeIntervalSince1970: 1_800_000_000)
        p.skippedUpdateVersion = "0.7.0"
        XCTAssertEqual(hotkeyChanges, 1, "only a real change restarts the monitor")

        let again = Preferences(defaults: defaults)
        XCTAssertEqual(again.hotkey, .chord(keyCode: 2, modifiers: [.command, .shift], key: "D"))
        XCTAssertEqual(again.hotkey.title, "⇧⌘D")
        XCTAssertEqual(again.captureFolder, "/tmp/captures")
        XCTAssertFalse(again.ballEnabled)
        XCTAssertFalse(again.ballAutoHide)
        XCTAssertEqual(again.ballPosition, CGPoint(x: 1200, y: 40))
        XCTAssertEqual(again.myApps, ["com.inspireocean.app"])
        XCTAssertEqual(again.organization, .byProject)
        XCTAssertFalse(again.adjustSelection)
        XCTAssertFalse(again.checksForUpdates)
        XCTAssertFalse(again.collectsIterations)
        XCTAssertTrue(again.pastesIntoAgent)
        XCTAssertFalse(again.trackpadTaps)
        XCTAssertFalse(again.sounds)
        XCTAssertEqual(again.lastUpdateCheck, Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(again.skippedUpdateVersion, "0.7.0")
        XCTAssertEqual(again.captureFolderURL.path(percentEncoded: false), "/tmp/captures/")
        again.skippedUpdateVersion = nil
        again.lastUpdateCheck = nil
        let third = Preferences(defaults: defaults)
        XCTAssertNil(third.skippedUpdateVersion)
        XCTAssertNil(third.lastUpdateCheck)
    }

    func testLegacyHotkeyModifierMigrates() {
        let defaults = isolatedDefaults()
        defaults.set("option", forKey: Preferences.Key.hotkeyModifier)
        XCTAssertEqual(Preferences(defaults: defaults).hotkey, .doubleTap(.option))
    }

    // 3
    func testBallPositionClears() {
        let defaults = isolatedDefaults()
        let p = Preferences(defaults: defaults)
        p.ballPosition = CGPoint(x: 5, y: 6)
        p.ballPosition = nil
        XCTAssertNil(Preferences(defaults: defaults).ballPosition)
    }
}

extension XCTestCase {
    /// A defaults store of its own that never touches disk. A suite per test left a plist behind on
    /// every run: emptying the domain afterwards is not enough, cfprefsd writes the empty file back
    /// seconds later.
    func isolatedDefaults() -> UserDefaults { InMemoryDefaults(suiteName: "LocantTests-InMemory")! }
}

/// `UserDefaults` held in memory. Every getter `Preferences` uses (`string`, `data`, `array`,
/// `dictionary`, and `object` for Bools and Ints) reads through `object(forKey:)`, and every setter
/// writes through `set(_:forKey:)`; the round-trip test fails if one does not. It is made with a
/// throwaway suite name, never the app's own domain.
final class InMemoryDefaults: UserDefaults, @unchecked Sendable {
    private var values: [String: Any] = [:]

    override func object(forKey defaultName: String) -> Any? { values[defaultName] }
    override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
    override func removeObject(forKey defaultName: String) { values[defaultName] = nil }
}
