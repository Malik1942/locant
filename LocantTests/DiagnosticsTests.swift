import XCTest
@testable import Locant

/// v0.9 R70: the diagnostics block is rendered from values, in a fixed order, with nothing
/// about the user beyond `~`.
final class DiagnosticsTests: XCTestCase {
    private var full: Diagnostics.Values {
        Diagnostics.Values(
            version: "0.9.0",
            build: "1",
            macOS: "Version 26.0 (Build 25A354)",
            architecture: "arm64",
            translated: false,
            displays: [.init(width: 1728, height: 1117, scale: 2), .init(width: 2560, height: 1440, scale: 2)],
            accessibility: true,
            screenRecording: false,
            appPath: "/Applications/Locant.app",
            pointHotkey: "⌃⌃",
            actionHotkeys: [.init(action: "point", hotkey: "⌃⌥1"), .init(action: "snap", hotkey: "⌃⌥2"), .init(action: "cut", hotkey: nil)],
            ballEnabled: true,
            ballAutoHide: false,
            trackpadTaps: true,
            sounds: true,
            pastesIntoAgent: false,
            collectsIterations: true,
            retentionDays: 30,
            captureFolder: "/Users/someone/Pictures/Locant",
            homeDirectory: "/Users/someone",
            organization: "One folder",
            captureCount: 42,
            agents: [.init(name: "Claude Code", connected: true), .init(name: "Cursor", connected: false)],
            checksForUpdates: true,
            lastUpdateCheck: Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21 UTC
        )
    }

    // 1: the lines, in the spec's order, with the home folder shortened.
    func testRendersEveryLineInOrder() {
        let text = Diagnostics.render(full, timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(text, """
        ## Locant diagnostics
        Locant: 0.9.0 (1)
        macOS: Version 26.0 (Build 25A354)
        Chip: arm64
        Displays: 2 · 1728×1117 @2x, 2560×1440 @2x
        Accessibility: granted
        Screen Recording: not granted
        App: /Applications/Locant.app
        Hotkeys: Point ⌃⌃ · point ⌃⌥1 · snap ⌃⌥2 · cut none
        Ball: on, auto-hide off
        Feedback: taps on, sounds on
        Paste into agent: off
        Iterations: on
        Retention: 30 days
        Captures: ~/Pictures/Locant · One folder · 42 captures
        Agents: Claude Code connected · Cursor not connected
        Updates: checked daily · last checked 2026-09-21

        """)
        XCTAssertFalse(text.contains("someone"))
    }

    // 2: every optional slot has a word for "missing"; nothing renders as nil.
    func testMissingValues() {
        var v = full
        v.version = nil
        v.build = nil
        v.displays = []
        v.accessibility = nil
        v.screenRecording = nil
        v.captureCount = nil
        v.agents = []
        v.lastUpdateCheck = nil
        v.checksForUpdates = false
        v.retentionDays = 0
        v.translated = true
        v.architecture = "x86_64"
        let text = Diagnostics.render(v)
        XCTAssertTrue(text.contains("Locant: unknown (unknown)\n"))
        XCTAssertTrue(text.contains("Chip: x86_64, translated under Rosetta\n"))
        XCTAssertTrue(text.contains("Displays: unknown\n"))
        XCTAssertTrue(text.contains("Accessibility: unknown\n"))
        XCTAssertTrue(text.contains("Screen Recording: unknown\n"))
        XCTAssertTrue(text.contains("Retention: forever\n"))
        XCTAssertTrue(text.contains("· unknown count\n"))
        XCTAssertTrue(text.contains("Agents: none\n"))
        XCTAssertTrue(text.contains("Updates: check off · never checked\n"))
        XCTAssertFalse(text.contains("nil"))
        XCTAssertFalse(text.contains("Optional"))
    }

    // 3: the home folder becomes ~ only as a whole path component.
    func testShorten() {
        XCTAssertEqual(Diagnostics.shorten("/Users/someone/Pictures/Locant", home: "/Users/someone"), "~/Pictures/Locant")
        XCTAssertEqual(Diagnostics.shorten("/Users/someone", home: "/Users/someone/"), "~")
        XCTAssertEqual(Diagnostics.shorten("/Users/someone-else/Pictures", home: "/Users/someone"), "/Users/someone-else/Pictures")
        XCTAssertEqual(Diagnostics.shorten("/Applications/Locant.app", home: ""), "/Applications/Locant.app")
        XCTAssertEqual(Diagnostics.shorten("/Volumes/Data/Locant.app", home: "/Users/someone"), "/Volumes/Data/Locant.app")
    }

    // 4: one capture, not "1 captures".
    func testSingularCapture() {
        var v = full
        v.captureCount = 1
        XCTAssertTrue(Diagnostics.render(v).contains("· 1 capture\n"))
    }
}
