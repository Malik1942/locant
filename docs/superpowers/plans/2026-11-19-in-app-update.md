# In-App Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The update alert's **Install and Relaunch** downloads the new release, checks it is signed by the same developer and notarized, swaps it in place of the running copy, and reopens Locant (`specs/in-app-update.md`, R175–R184).

**Architecture:**
- **`UpdateInstaller.swift`:** a new file in `Locant/Store`. It holds:
  - the pure decisions (`InstallPlace`, `BundleFacts`, `checkBundle`, the requirement text, the `hdiutil` plist reader);
  - the system steps (download, unpack, signature check, leftover cleanup);
  - the swap script, a constant, which `/bin/sh` runs after Locant quits.
- **`UpdatePanel.swift`:** a new file in `Locant/App`, the progress panel.
- **`AppState`:** it already runs the daily check (R45). It gains the new alert, the install task, the failure alert, and the leftover cleanup at start.
- **`UpdateCheck`:** it gains `installerAsset(version:)` and a Debug-only `-updateFeed`.

**Tech Stack:** Swift 6 (strict concurrency complete), AppKit (`NSAlert`, `NSPanel`), Foundation (`URLSession.bytes`, `Process`, `PropertyListSerialization`), Security (`SecCodeCopySelf`, `SecStaticCodeCheckValidity`), `/usr/bin/hdiutil`, `/usr/bin/ditto`, `/bin/sh`, XCTest. No packages.

## Global Constraints

- **Dependencies:** no third-party packages; only frameworks already in use (`docs/CLAUDE.md`). The Security calls come through `import Foundation`, as in `CodeSigning` (`ModeInference.swift`); add no `import Security` (it is not in `docs/CLAUDE.md`'s list).
- **Errors:** typed enums, never strings. The failures are `InstallFailure`; a cancel is `CancellationError`.
- **Network:** the only new request is the download after the click, with `User-Agent: Locant/<version>`, an ephemeral session, no cookies, and no cache (R177).
- **Never over a session:** no alert and no relaunch while `phase != .idle`. Wait for idle first, because an alert's `runModal` blocks the main actor (see memory "runModal blocks the main actor").
- **The running copy is never touched before the swap script runs** (R181).
- **Copy, verbatim:**
  - "Locant 1.4.0 is available" (`Locant \(newest) is available`)
  - "You have \(current). Locant downloads the new version, checks that it is signed by the same developer, and reopens. Your permissions carry over."
  - "You have \(current). Drag the new copy over the old one in Applications; your permissions carry over." (the existing R48 text, kept for the browser path)
  - "Install and Relaunch", "Download", "Later", "Skip This Version"
  - "Locant is running from a download or a disk image. Move it to Applications, open it from there, and it can update itself next time."
  - "Locant can't write to the folder it is in, \(folder)."
  - "Downloading Locant \(newest)…" and "Checking Locant \(newest)…" (with the ellipsis character)
  - "Locant couldn't install \(newest)", "Download in Browser", "Cancel"
  - The reasons:
    - "The release has no installer."
    - "The download failed."
    - "There isn't enough space to unpack it."
    - "The download doesn't hold Locant."
    - "The download isn't signed by Locant's developer."
    - "The download isn't the version that was offered."
    - "Something went wrong unpacking it."
- **Limits:**
  - download: 60 s timeout without data, 200 MB cap;
  - swap script: waits up to 20 s for Locant to exit (200 × 0.1 s).
- **Names:**
  - incoming copy `.Locant-<version>.incoming.app`, beside the running copy;
  - download folder `Locant-update-<UUID>` in `FileManager.default.temporaryDirectory`;
  - trash name `~/.Trash/Locant <old version>.app`.
- **Launch argument:** `-updateFeed <path>`, Debug builds only, read from the argument domain alone (R183).
- **Commits:**
  - Messages in the form `area: what changed`.
  - Never commit without a green build. No attribution lines. Don't push.
- **Comments:** match the file's density and voice. Cite `specs/in-app-update.md R1xx` the first time in a file, then `R1xx`.
- **New files:** groups are file-system-synchronized, so new files need no `project.pbxproj` edit.

Shell setup used by every task (zsh). Derived data must be outside `~/Documents`, or CodeSign fails on iCloud's Finder info:

```bash
cd /Users/malik/Documents/Locant/.claude/worktrees/great-roentgen-1aacfa
SP=/private/tmp/claude-501/-Users-malik-Documents-Locant--claude-worktrees-great-roentgen-1aacfa/4ecfb415-c677-44dc-9e0b-ca7d3763037f/scratchpad
DD=$SP/dd
TEST="xcodebuild -scheme Locant -derivedDataPath $DD -destination platform=macOS,arch=arm64 CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -quiet"
```

---

### Task 1: The pure decisions

**Files:**
- Create: `Locant/Store/UpdateInstaller.swift`
- Modify: `Locant/Store/UpdateCheck.swift` (add `installerAsset(version:)` to `GitHubRelease`)
- Test: `LocantTests/UpdateInstallerTests.swift`

**Interfaces:**
- Produces:
  - `enum InstallPlace: Equatable, Sendable { case ok, translocated, readOnlyVolume, notWritable(folder: String) }`, with:
    - `static func check(bundlePath: String, volumeIsReadOnly: Bool, parentIsWritable: Bool) -> InstallPlace`
    - `static func current(bundleURL: URL = Bundle.main.bundleURL) -> InstallPlace`
    - `var reason: String?`
  - `enum InstallFailure: Error, Equatable, Sendable { case noInstaller, downloadFailed, noSpace, notLocant, notSigned, wrongVersion, unpackFailed }`, with `var reason: String`
  - `struct BundleFacts: Equatable, Sendable { var identifier: String?; var version: String? }`, with `static func read(_ app: URL) -> BundleFacts`
  - `enum UpdateInstaller`:
    - `static func checkBundle(incoming: BundleFacts, running: BundleFacts, offered: AppVersion, current: AppVersion) -> InstallFailure?` (nil means it passes)
    - `static func requirement(designated: String) -> String`
    - `static func mountPoint(inAttachPlist: Data) -> String?`
  - `GitHubRelease.installerAsset(version: AppVersion) -> URL?`

- [ ] **Step 1: Write the failing tests**

Create `LocantTests/UpdateInstallerTests.swift`:

```swift
import XCTest
@testable import Locant

final class UpdateInstallerTests: XCTestCase {
    private var temp: URL!

    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory
            .appending(path: "UpdateInstallerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temp)
    }

    // R176
    func testInstallPlace() {
        XCTAssertEqual(InstallPlace.check(bundlePath: "/Applications/Locant.app", volumeIsReadOnly: false, parentIsWritable: true), .ok)
        XCTAssertEqual(InstallPlace.check(bundlePath: "/private/var/folders/ab/xyz/T/AppTranslocation/1234-ABCD/d/Locant.app",
                                          volumeIsReadOnly: true, parentIsWritable: false), .translocated)
        XCTAssertEqual(InstallPlace.check(bundlePath: "/Volumes/Locant/Locant.app", volumeIsReadOnly: true, parentIsWritable: false), .readOnlyVolume)
        XCTAssertEqual(InstallPlace.check(bundlePath: "/Applications/Locant.app", volumeIsReadOnly: false, parentIsWritable: false),
                       .notWritable(folder: "Applications"))
        XCTAssertNil(InstallPlace.ok.reason)
        let moveIt = "Locant is running from a download or a disk image. Move it to Applications, open it from there, and it can update itself next time."
        XCTAssertEqual(InstallPlace.translocated.reason, moveIt)
        XCTAssertEqual(InstallPlace.readOnlyVolume.reason, moveIt)
        XCTAssertEqual(InstallPlace.notWritable(folder: "Applications").reason, "Locant can't write to the folder it is in, Applications.")
    }

    // R177
    func testInstallerAssetIsTheVersionedDiskImage() throws {
        let json = """
        {"tag_name": "v1.4.0", "html_url": "https://github.com/Malik1942/locant/releases/tag/v1.4.0", "assets": [
          {"name": "Locant.dmg", "browser_download_url": "https://github.com/Malik1942/locant/releases/download/v1.4.0/Locant.dmg"},
          {"name": "Locant-1.4.0.dmg", "browser_download_url": "https://github.com/Malik1942/locant/releases/download/v1.4.0/Locant-1.4.0.dmg"}
        ]}
        """
        let release = try GitHubRelease.decode(Data(json.utf8))
        XCTAssertEqual(release.installerAsset(version: AppVersion("1.4.0")!)?.lastPathComponent, "Locant-1.4.0.dmg")
        let onlyStable = """
        {"tag_name": "v1.4.0", "html_url": "https://github.com/Malik1942/locant/releases/tag/v1.4.0", "assets": [
          {"name": "Locant.dmg", "browser_download_url": "https://github.com/Malik1942/locant/releases/download/v1.4.0/Locant.dmg"}
        ]}
        """
        XCTAssertNil(try GitHubRelease.decode(Data(onlyStable.utf8)).installerAsset(version: AppVersion("1.4.0")!))
    }

    // R179
    func testCheckBundle() {
        let running = BundleFacts(identifier: "com.malikzhang.deixis", version: "1.3.1")
        let current = AppVersion("1.3.1")!
        let offered = AppVersion("1.4.0")!
        func check(_ identifier: String?, _ version: String?, offered: AppVersion = offered) -> InstallFailure? {
            UpdateInstaller.checkBundle(incoming: BundleFacts(identifier: identifier, version: version), running: running, offered: offered, current: current)
        }
        XCTAssertNil(check("com.malikzhang.deixis", "1.4.0"))
        XCTAssertEqual(check("com.example.other", "1.4.0"), .notSigned)
        XCTAssertEqual(check(nil, "1.4.0"), .notSigned)
        XCTAssertEqual(check("com.malikzhang.deixis", "1.4.1"), .wrongVersion)
        XCTAssertEqual(check("com.malikzhang.deixis", nil), .wrongVersion)
        XCTAssertEqual(check("com.malikzhang.deixis", "1.3.1", offered: AppVersion("1.3.1")!), .wrongVersion)
        XCTAssertEqual(check("com.malikzhang.deixis", "1.2.0", offered: AppVersion("1.2.0")!), .wrongVersion)
    }

    func testBundleFactsReadTheInfoPlist() throws {
        let contents = temp.appending(path: "Foo.app/Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "com.malikzhang.deixis", "CFBundleShortVersionString": "9.9.9"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appending(path: "Info.plist"))
        XCTAssertEqual(BundleFacts.read(temp.appending(path: "Foo.app")), BundleFacts(identifier: "com.malikzhang.deixis", version: "9.9.9"))
        XCTAssertEqual(BundleFacts.read(temp.appending(path: "Missing.app")), BundleFacts(identifier: nil, version: nil))
    }

    func testRequirementWrapsTheDesignatedOne() {
        XCTAssertEqual(UpdateInstaller.requirement(designated: "anchor apple generic and (a or b)"),
                       "(anchor apple generic and (a or b)) and notarized")
    }

    // R178
    func testMountPointFromTheAttachPlist() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>system-entities</key><array>
          <dict><key>content-hint</key><string>GUID_partition_scheme</string><key>dev-entry</key><string>/dev/disk9</string></dict>
          <dict><key>content-hint</key><string>Apple_HFS</string><key>dev-entry</key><string>/dev/disk9s1</string>
                <key>mount-point</key><string>/private/tmp/work/mnt/dmg.Ab12Cd</string></dict>
        </array></dict></plist>
        """
        XCTAssertEqual(UpdateInstaller.mountPoint(inAttachPlist: Data(plist.utf8)), "/private/tmp/work/mnt/dmg.Ab12Cd")
        XCTAssertNil(UpdateInstaller.mountPoint(inAttachPlist: Data("not a plist".utf8)))
    }

    // R181
    func testFailureReasons() {
        XCTAssertEqual(InstallFailure.noInstaller.reason, "The release has no installer.")
        XCTAssertEqual(InstallFailure.downloadFailed.reason, "The download failed.")
        XCTAssertEqual(InstallFailure.noSpace.reason, "There isn't enough space to unpack it.")
        XCTAssertEqual(InstallFailure.notLocant.reason, "The download doesn't hold Locant.")
        XCTAssertEqual(InstallFailure.notSigned.reason, "The download isn't signed by Locant's developer.")
        XCTAssertEqual(InstallFailure.wrongVersion.reason, "The download isn't the version that was offered.")
        XCTAssertEqual(InstallFailure.unpackFailed.reason, "Something went wrong unpacking it.")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `eval $TEST test -only-testing:LocantTests/UpdateInstallerTests 2>&1 | tail -20`
Expected: build FAILS with "cannot find 'InstallPlace' in scope" (and the other new names).

- [ ] **Step 3: Add `installerAsset(version:)`**

In `Locant/Store/UpdateCheck.swift`, inside `struct GitHubRelease`, after `var downloadURL: URL { … }`:

```swift
    /// specs/in-app-update.md R177: the versioned dmg, the one the Homebrew cask uses. `Locant.dmg`
    /// is the same file under a stable name, but only the versioned name says which version it is.
    func installerAsset(version: AppVersion) -> URL? {
        assets.first { $0.name == "Locant-\(version).dmg" }?.browserDownloadURL
    }
```

- [ ] **Step 4: Write the pure part of `UpdateInstaller.swift`**

Create `Locant/Store/UpdateInstaller.swift`:

```swift
import Foundation

/// specs/in-app-update.md R176: whether Locant can replace itself where it runs, decided before the
/// alert offers Install and Relaunch. Pure given the three facts; `current` reads them.
enum InstallPlace: Equatable, Sendable {
    case ok, translocated, readOnlyVolume, notWritable(folder: String)

    static func check(bundlePath: String, volumeIsReadOnly: Bool, parentIsWritable: Bool) -> InstallPlace {
        if bundlePath.contains("/AppTranslocation/") { return .translocated }
        if volumeIsReadOnly { return .readOnlyVolume }
        if !parentIsWritable {
            return .notWritable(folder: URL(filePath: bundlePath).deletingLastPathComponent().lastPathComponent)
        }
        return .ok
    }

    static func current(bundleURL: URL = Bundle.main.bundleURL) -> InstallPlace {
        let readOnly = (try? bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? true
        let parent = bundleURL.deletingLastPathComponent().path(percentEncoded: false)
        return check(bundlePath: bundleURL.path(percentEncoded: false), volumeIsReadOnly: readOnly,
                     parentIsWritable: FileManager.default.isWritableFile(atPath: parent))
    }

    /// The alert's second paragraph when Locant cannot update itself; nil when it can.
    var reason: String? {
        switch self {
        case .ok: nil
        case .translocated, .readOnlyVolume:
            "Locant is running from a download or a disk image. Move it to Applications, open it from there, and it can update itself next time."
        case .notWritable(let folder): "Locant can't write to the folder it is in, \(folder)."
        }
    }
}

/// R181: why an install stopped. Each has the sentence the failure alert shows.
enum InstallFailure: Error, Equatable, Sendable {
    case noInstaller, downloadFailed, noSpace, notLocant, notSigned, wrongVersion, unpackFailed

    var reason: String {
        switch self {
        case .noInstaller: "The release has no installer."
        case .downloadFailed: "The download failed."
        case .noSpace: "There isn't enough space to unpack it."
        case .notLocant: "The download doesn't hold Locant."
        case .notSigned: "The download isn't signed by Locant's developer."
        case .wrongVersion: "The download isn't the version that was offered."
        case .unpackFailed: "Something went wrong unpacking it."
        }
    }
}

/// R179: the two Info.plist facts the checks compare.
struct BundleFacts: Equatable, Sendable {
    var identifier: String?
    var version: String?

    /// Read from the file, not through `Bundle`, which caches by path.
    static func read(_ app: URL) -> BundleFacts {
        let plist = app.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return BundleFacts() }
        return BundleFacts(identifier: dict["CFBundleIdentifier"] as? String,
                           version: dict["CFBundleShortVersionString"] as? String)
    }
}

/// R177–R180: download, unpack, check, and swap. The decisions are pure and tested; the steps that
/// touch the network, the disk images, and the signatures are below them.
enum UpdateInstaller {
    /// R179: nil when the incoming copy is the offered version of the same app, newer than this one.
    static func checkBundle(incoming: BundleFacts, running: BundleFacts, offered: AppVersion, current: AppVersion) -> InstallFailure? {
        guard let identifier = incoming.identifier, identifier == running.identifier else { return .notSigned }
        guard let text = incoming.version, let version = AppVersion(text), version == offered, current < version else {
            return .wrongVersion
        }
        return nil
    }

    /// R179: the running copy's designated requirement, which holds an `or`, so it is wrapped before
    /// `notarized` is added.
    static func requirement(designated: String) -> String {
        "(\(designated)) and notarized"
    }

    /// R178: the first mount point in `hdiutil attach -plist` output.
    static func mountPoint(inAttachPlist data: Data) -> String? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else { return nil }
        return entities.lazy.compactMap { $0["mount-point"] as? String }.first
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `eval $TEST test -only-testing:LocantTests/UpdateInstallerTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`, with 7 tests passing.

- [ ] **Step 6: Commit**

```bash
git add Locant/Store/UpdateInstaller.swift Locant/Store/UpdateCheck.swift LocantTests/UpdateInstallerTests.swift
git commit -m "update: where Locant can update itself, and the checks on what it downloads"
```

---

### Task 2: Unpack, signature check, leftovers

**Files:**
- Modify: `Locant/Store/UpdateInstaller.swift` (add to `enum UpdateInstaller`)
- Test: `LocantTests/UpdateInstallerTests.swift`

**Interfaces:**
- Consumes: `InstallFailure`, `BundleFacts`, `checkBundle`, `requirement(designated:)`, `mountPoint(inAttachPlist:)` (Task 1).
- Produces, all in `enum UpdateInstaller`:
  - `static func unpack(dmg: URL, in work: URL, to incoming: URL) throws` (throws `InstallFailure`; synchronous, call it off the main actor)
  - `static func signatureIsValid(_ app: URL, requirement: String) -> Bool`
  - `static func designatedRequirementOfSelf() -> String?`
  - `static func verify(incoming: URL, running: URL, offered: AppVersion, current: AppVersion) throws` (throws `InstallFailure`)
  - `static func removeLeftovers(beside running: URL, temporary: URL = FileManager.default.temporaryDirectory)`
  - `static func discard(work: URL, incoming: URL)`
  - `@discardableResult static func runTool(_ path: String, _ arguments: [String]) -> Data?` (nil on failure)

- [ ] **Step 1: Write the failing tests**

Append inside `final class UpdateInstallerTests` in `LocantTests/UpdateInstallerTests.swift`:

```swift
    // R178
    func testUnpackCopiesLocantOutOfTheDiskImage() throws {
        let source = temp.appending(path: "src", directoryHint: .isDirectory)
        let contents = source.appending(path: "Locant.app/Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: contents.appending(path: "marker"))
        let dmg = try makeDiskImage(from: source)
        let work = try makeFolder("work")
        let incoming = temp.appending(path: ".Locant-9.9.9.incoming.app", directoryHint: .isDirectory)

        try UpdateInstaller.unpack(dmg: dmg, in: work, to: incoming)

        XCTAssertEqual(try String(contentsOf: incoming.appending(path: "Contents/marker"), encoding: .utf8), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dmg.path(percentEncoded: false)))
        let info = String(decoding: UpdateInstaller.runTool("/usr/bin/hdiutil", ["info"]) ?? Data(), as: UTF8.self)
        XCTAssertFalse(info.contains(work.path(percentEncoded: false)), "the disk image is still attached")
    }

    func testUnpackRefusesADiskImageWithoutLocant() throws {
        let source = try makeFolder("src")
        try Data("x".utf8).write(to: source.appending(path: "readme.txt"))
        let dmg = try makeDiskImage(from: source)
        let work = try makeFolder("work")
        let incoming = temp.appending(path: ".Locant-9.9.9.incoming.app", directoryHint: .isDirectory)

        XCTAssertThrowsError(try UpdateInstaller.unpack(dmg: dmg, in: work, to: incoming)) { error in
            XCTAssertEqual(error as? InstallFailure, .notLocant)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: incoming.path(percentEncoded: false)))
    }

    // R179
    func testSignatureCheck() {
        let calculator = URL(filePath: "/System/Applications/Calculator.app")
        XCTAssertTrue(UpdateInstaller.signatureIsValid(calculator, requirement: "anchor apple"))
        // Apple's own apps are not notarized, so the notarized clause refuses them.
        XCTAssertFalse(UpdateInstaller.signatureIsValid(calculator, requirement: UpdateInstaller.requirement(designated: "anchor apple")))
        XCTAssertFalse(UpdateInstaller.signatureIsValid(calculator, requirement: "anchor apple generic and identifier \"com.malikzhang.deixis\""))
        XCTAssertFalse(UpdateInstaller.signatureIsValid(temp.appending(path: "Missing.app"), requirement: "anchor apple"))
        XCTAssertFalse(UpdateInstaller.signatureIsValid(calculator, requirement: "this is not a requirement"))
    }

    func testInstalledLocantPassesTheReleaseRequirement() throws {
        let installed = URL(filePath: "/Applications/Locant.app")
        guard FileManager.default.fileExists(atPath: installed.path(percentEncoded: false)) else { throw XCTSkip("no installed Locant") }
        let designated = "anchor apple generic and identifier \"com.malikzhang.deixis\" and certificate leaf[subject.OU] = MVAUZXPK9M"
        XCTAssertTrue(UpdateInstaller.signatureIsValid(installed, requirement: UpdateInstaller.requirement(designated: designated)))
    }

    // R182
    func testLeftoversAreRemoved() throws {
        let apps = try makeFolder("apps")
        let tmp = try makeFolder("tmp")
        for name in ["Locant.app", ".Locant-1.4.0.incoming.app", "Other.app"] {
            try FileManager.default.createDirectory(at: apps.appending(path: name), withIntermediateDirectories: true)
        }
        for name in ["Locant-update-ABC", "keep"] {
            try FileManager.default.createDirectory(at: tmp.appending(path: name), withIntermediateDirectories: true)
        }

        UpdateInstaller.removeLeftovers(beside: apps.appending(path: "Locant.app"), temporary: tmp)

        let left = Set(try FileManager.default.contentsOfDirectory(atPath: apps.path(percentEncoded: false)))
        XCTAssertEqual(left, ["Locant.app", "Other.app"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: tmp.path(percentEncoded: false)), ["keep"])
    }

    private func makeFolder(_ name: String) throws -> URL {
        let folder = temp.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func makeDiskImage(from folder: URL) throws -> URL {
        let dmg = temp.appending(path: "test-\(UUID().uuidString).dmg")
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/hdiutil")
        process.arguments = ["create", "-volname", "LocantTest", "-srcfolder", folder.path(percentEncoded: false),
                             "-format", "UDZO", "-quiet", dmg.path(percentEncoded: false)]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "hdiutil create failed")
        return dmg
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `eval $TEST test -only-testing:LocantTests/UpdateInstallerTests 2>&1 | tail -20`
Expected: build FAILS with "type 'UpdateInstaller' has no member 'unpack'" (and the other new names).

- [ ] **Step 3: Implement the system steps**

In `Locant/Store/UpdateInstaller.swift`, add inside `enum UpdateInstaller`, after `mountPoint(inAttachPlist:)`:

```swift
    // MARK: System steps

    /// R178: attach the dmg read-only and hidden, copy `Locant.app` out to `incoming`, and always detach
    /// and delete the dmg. Synchronous; call it off the main actor.
    static func unpack(dmg: URL, in work: URL, to incoming: URL) throws {
        let fm = FileManager.default
        let mounts = work.appending(path: "mnt", directoryHint: .isDirectory)
        try? fm.createDirectory(at: mounts, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dmg) }
        guard let plist = runTool("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen",
                                                      "-mountrandom", mounts.path(percentEncoded: false),
                                                      "-plist", dmg.path(percentEncoded: false)]),
              let mount = mountPoint(inAttachPlist: plist)
        else { throw InstallFailure.unpackFailed }
        defer { runTool("/usr/bin/hdiutil", ["detach", "-force", mount]) }

        let app = URL(filePath: mount).appending(path: "Locant.app", directoryHint: .isDirectory)
        guard fm.fileExists(atPath: app.path(percentEncoded: false)) else { throw InstallFailure.notLocant }
        try? fm.removeItem(at: incoming)
        guard runTool("/usr/bin/ditto", [app.path(percentEncoded: false), incoming.path(percentEncoded: false)]) != nil else {
            try? fm.removeItem(at: incoming)
            throw spaceIsLow(at: incoming.deletingLastPathComponent()) ? InstallFailure.noSpace : InstallFailure.unpackFailed
        }
    }

    /// R179: all checks on the incoming copy. Synchronous; call it off the main actor.
    static func verify(incoming: URL, running: URL, offered: AppVersion, current: AppVersion) throws {
        guard let designated = designatedRequirementOfSelf(),
              signatureIsValid(incoming, requirement: requirement(designated: designated))
        else { throw InstallFailure.notSigned }
        if let failure = checkBundle(incoming: .read(incoming), running: .read(running), offered: offered, current: current) {
            throw failure
        }
    }

    /// The running copy's designated requirement as text. For a release copy it names the Developer ID
    /// anchor, the team, and the bundle id; macOS keys the privacy permissions to the same requirement.
    static func designatedRequirementOfSelf() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement else { return nil }
        var text: CFString?
        guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text else { return nil }
        return text as String
    }

    /// Every architecture, strict, nested code included, against `requirement`.
    static func signatureIsValid(_ app: URL, requirement text: String) -> Bool {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement else { return false }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    /// R182: what a crash or a stopped script leaves: incoming copies beside Locant, download folders.
    static func removeLeftovers(beside running: URL, temporary: URL = FileManager.default.temporaryDirectory) {
        let fm = FileManager.default
        let folder = running.deletingLastPathComponent()
        for name in (try? fm.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        where name.hasPrefix(".Locant-") && name.hasSuffix(".incoming.app") {
            try? fm.removeItem(at: folder.appending(path: name))
        }
        for name in (try? fm.contentsOfDirectory(atPath: temporary.path(percentEncoded: false))) ?? []
        where name.hasPrefix("Locant-update-") {
            try? fm.removeItem(at: temporary.appending(path: name))
        }
    }

    /// R181: undo everything before the swap; the running copy was never touched.
    static func discard(work: URL, incoming: URL) {
        try? FileManager.default.removeItem(at: incoming)
        try? FileManager.default.removeItem(at: work)
    }

    /// Runs a tool and returns its standard output, or nil when it fails. The tools here print little
    /// (`hdiutil -plist` a few KB), so reading to the end before waiting cannot fill the pipe.
    @discardableResult
    static func runTool(_ path: String, _ arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(filePath: path)
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    /// Under 200 MB free where the copy goes: the likely reason `ditto` failed.
    private static func spaceIsLow(at folder: URL) -> Bool {
        let free = (try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? .max
        return free < 200 * 1024 * 1024
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `eval $TEST test -only-testing:LocantTests/UpdateInstallerTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`. `testInstalledLocantPassesTheReleaseRequirement` passes when `/Applications/Locant.app` is installed, and is skipped otherwise.
- If `kSecCS…` constants don't combine as `UInt32`, write `SecCSFlags(rawValue: UInt32(kSecCSCheckAllArchitectures) | UInt32(kSecCSStrictValidate) | UInt32(kSecCSCheckNestedCode))`.

- [ ] **Step 5: Commit**

```bash
git add Locant/Store/UpdateInstaller.swift LocantTests/UpdateInstallerTests.swift
git commit -m "update: unpack the dmg, check the signature, clear leftovers"
```

---

### Task 3: The swap script

**Files:**
- Modify: `Locant/Store/UpdateInstaller.swift`
- Test: `LocantTests/UpdateInstallerTests.swift`

**Interfaces:**
- Consumes: `InstallFailure` (Task 1).
- Produces:
  - `struct PreparedUpdate: Sendable { let work: URL; let incoming: URL; let running: URL }` (top level in `UpdateInstaller.swift`)
  - `UpdateInstaller.script: String`
  - `UpdateInstaller.startSwap(_ prepared: PreparedUpdate, oldVersion: AppVersion, pid: pid_t = ProcessInfo.processInfo.processIdentifier, opener: String = "/usr/bin/open") throws` (throws `InstallFailure.unpackFailed` when it can't start)

- [ ] **Step 1: Write the failing tests**

Append inside `final class UpdateInstallerTests`:

```swift
    // R180
    func testScriptNamesNoPath() {
        XCTAssertFalse(UpdateInstaller.script.contains("/Applications"))
        XCTAssertFalse(UpdateInstaller.script.contains("Locant.app"))
    }

    func testScriptSwapsAfterThePidExits() throws {
        let (running, incoming, work, home) = try makeSwapFixture(incomingExists: true)
        let started = Date()
        try runSwap(running: running, incoming: incoming, work: work, home: home, waitFor: 0.3)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 0.25, "the script did not wait for the pid")
        XCTAssertEqual(try marker(in: running), "new")
        XCTAssertEqual(try marker(in: home.appending(path: ".Trash/Locant 1.3.1.app")), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: incoming.path(percentEncoded: false)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: work.path(percentEncoded: false)))
    }

    func testScriptKeepsTheRunningCopyWhenTheIncomingOneIsMissing() throws {
        let (running, incoming, work, home) = try makeSwapFixture(incomingExists: false)
        try runSwap(running: running, incoming: incoming, work: work, home: home, waitFor: 0)
        XCTAssertEqual(try marker(in: running), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appending(path: ".Trash/Locant 1.3.1.app").path(percentEncoded: false)))
    }

    func testScriptGivesTheTrashCopyAnotherNameWhenTheFirstIsTaken() throws {
        let (running, incoming, work, home) = try makeSwapFixture(incomingExists: true)
        try FileManager.default.createDirectory(at: home.appending(path: ".Trash/Locant 1.3.1.app"), withIntermediateDirectories: true)
        try runSwap(running: running, incoming: incoming, work: work, home: home, waitFor: 0)
        XCTAssertEqual(try marker(in: running), "new")
        let trash = try FileManager.default.contentsOfDirectory(atPath: home.appending(path: ".Trash").path(percentEncoded: false))
        XCTAssertEqual(trash.count, 2)
        XCTAssertTrue(trash.contains { $0.hasPrefix("Locant 1.3.1 ") && $0.hasSuffix(".app") })
    }

    private func makeSwapFixture(incomingExists: Bool) throws -> (running: URL, incoming: URL, work: URL, home: URL) {
        let apps = try makeFolder("apps")
        let home = try makeFolder("home")
        try FileManager.default.createDirectory(at: home.appending(path: ".Trash"), withIntermediateDirectories: true)
        let work = try makeFolder("Locant-update-test")
        let running = apps.appending(path: "Locant.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: running, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: running.appending(path: "marker"))
        let incoming = apps.appending(path: ".Locant-9.9.9.incoming.app", directoryHint: .isDirectory)
        if incomingExists {
            try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
            try Data("new".utf8).write(to: incoming.appending(path: "marker"))
        }
        return (running, incoming, work, home)
    }

    /// Runs the script as `startSwap` would, with `HOME` pointed at the fixture and `/usr/bin/true` as
    /// the opener, against the pid of a `sleep` that ends after `waitFor` seconds.
    private func runSwap(running: URL, incoming: URL, work: URL, home: URL, waitFor: Double) throws {
        let script = work.appending(path: "swap.sh")
        try UpdateInstaller.script.write(to: script, atomically: true, encoding: .utf8)
        let sleeper = Process()
        sleeper.executableURL = URL(filePath: "/bin/sleep")
        sleeper.arguments = [String(waitFor)]
        try sleeper.run()
        let shell = Process()
        shell.executableURL = URL(filePath: "/bin/sh")
        shell.arguments = [script.path(percentEncoded: false), String(sleeper.processIdentifier), running.path(percentEncoded: false),
                           incoming.path(percentEncoded: false), "1.3.1", work.path(percentEncoded: false), "/usr/bin/true"]
        shell.environment = ["HOME": home.path(percentEncoded: false)]
        try shell.run()
        shell.waitUntilExit()
        sleeper.waitUntilExit()
        XCTAssertEqual(shell.terminationStatus, 0)
    }

    private func marker(in app: URL) throws -> String {
        try String(contentsOf: app.appending(path: "marker"), encoding: .utf8)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `eval $TEST test -only-testing:LocantTests/UpdateInstallerTests 2>&1 | tail -20`
Expected: build FAILS with "type 'UpdateInstaller' has no member 'script'".

- [ ] **Step 3: Implement the script and `startSwap`**

In `Locant/Store/UpdateInstaller.swift`, add at top level after `struct BundleFacts`:

```swift
/// R180: a checked copy beside the running one, ready to swap.
struct PreparedUpdate: Sendable {
    let work: URL
    let incoming: URL
    let running: URL
}
```

Add inside `enum UpdateInstaller`, after `discard(work:incoming:)`:

```swift
    /// R180: run by `/bin/sh` after Locant quits. Everything comes in as arguments: the pid to wait for,
    /// the running path, the incoming path, the old version, the download folder, and the command that
    /// opens the result. The old copy goes to the Trash, so it can be put back by hand.
    static let script = """
    PATH=/usr/bin:/bin
    pid=$1 running=$2 incoming=$3 old=$4 work=$5 opener=$6
    tries=0
    while kill -0 "$pid" 2>/dev/null; do
      tries=$((tries + 1))
      if [ "$tries" -ge 200 ]; then
        rm -rf "$incoming" "$work"
        exit 1
      fi
      sleep 0.1
    done
    mkdir -p "$HOME/.Trash"
    trash="$HOME/.Trash/Locant $old.app"
    if [ -e "$trash" ]; then
      trash="$HOME/.Trash/Locant $old $(date '+%Y-%m-%d %H.%M.%S').app"
    fi
    if mv "$running" "$trash"; then
      if ! mv "$incoming" "$running"; then
        mv "$trash" "$running"
        rm -rf "$incoming"
      fi
    else
      rm -rf "$incoming"
    fi
    "$opener" "$running"
    rm -rf "$work"

    """

    /// R180: write the script into the download folder and start it. The caller quits right after.
    /// A child started with `Process` outlives its parent: Locant has no terminal to hang up.
    static func startSwap(_ prepared: PreparedUpdate, oldVersion: AppVersion,
                          pid: pid_t = ProcessInfo.processInfo.processIdentifier, opener: String = "/usr/bin/open") throws {
        let scriptURL = prepared.work.appending(path: "swap.sh")
        do { try script.write(to: scriptURL, atomically: true, encoding: .utf8) } catch { throw InstallFailure.unpackFailed }
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = [scriptURL.path(percentEncoded: false), String(pid), prepared.running.path(percentEncoded: false),
                             prepared.incoming.path(percentEncoded: false), oldVersion.description,
                             prepared.work.path(percentEncoded: false), opener]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw InstallFailure.unpackFailed }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `eval $TEST test -only-testing:LocantTests/UpdateInstallerTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`.
- If `testScriptSwapsAfterThePidExits` takes about 20 s and fails, the `sleep` child was left a zombie, so `kill -0` kept succeeding. In that case, run the sleeper under `/bin/sh -c 'sleep 0.3 & echo $!'` and pass the printed pid instead. Its parent `sh` reaps it.

- [ ] **Step 5: Commit**

```bash
git add Locant/Store/UpdateInstaller.swift LocantTests/UpdateInstallerTests.swift
git commit -m "update: the swap script that replaces Locant after it quits"
```

---

### Task 4: Download, prepare, and the Debug feed

**Files:**
- Modify: `Locant/Store/UpdateInstaller.swift`
- Modify: `Locant/Store/UpdateCheck.swift`

**Interfaces:**
- Consumes: `unpack`, `verify`, `discard`, `PreparedUpdate`, `InstallFailure` (Tasks 1–3).
- Produces, both in `enum UpdateInstaller`:
  - `static func prepare(asset: URL, offered: AppVersion, current: AppVersion, running: URL, progress: @escaping @MainActor @Sendable (Double?) -> Void, checking: @escaping @MainActor @Sendable () -> Void) async throws -> PreparedUpdate` (throws `InstallFailure` or `CancellationError`)
  - `static func download(_ url: URL, to file: URL, current: AppVersion, progress: @escaping @MainActor @Sendable (Double?) -> Void) async throws`

No unit test: these touch the network. Task 5's manual run and Task 7 cover them.

- [ ] **Step 1: Add download and prepare**

In `Locant/Store/UpdateInstaller.swift`, add inside `enum UpdateInstaller`, after `mountPoint(inAttachPlist:)` and before `// MARK: System steps`:

```swift
    static let downloadTimeout: TimeInterval = 60
    static let maxDownload: Int64 = 200 * 1024 * 1024

    /// R177–R179: download the dmg, unpack it beside the running copy, and check it. Everything is
    /// removed again on any failure or cancel; the running copy is not touched.
    static func prepare(asset: URL, offered: AppVersion, current: AppVersion, running: URL,
                        progress: @escaping @MainActor @Sendable (Double?) -> Void,
                        checking: @escaping @MainActor @Sendable () -> Void) async throws -> PreparedUpdate {
        let work = FileManager.default.temporaryDirectory
            .appending(path: "Locant-update-\(UUID().uuidString)", directoryHint: .isDirectory)
        let incoming = running.deletingLastPathComponent()
            .appending(path: ".Locant-\(offered).incoming.app", directoryHint: .isDirectory)
        do {
            do { try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true) }
            catch { throw InstallFailure.unpackFailed }
            let dmg = work.appending(path: "Locant-\(offered).dmg")
            try await download(asset, to: dmg, current: current, progress: progress)
            await checking()
            try await Task.detached {
                try UpdateInstaller.unpack(dmg: dmg, in: work, to: incoming)
                try UpdateInstaller.verify(incoming: incoming, running: running, offered: offered, current: current)
            }.value
            try Task.checkCancellation()
            return PreparedUpdate(work: work, incoming: incoming, running: running)
        } catch {
            discard(work: work, incoming: incoming)
            throw error
        }
    }

    /// R177: like the release check's request (R45): ephemeral, no cookies, no cache, the version in the
    /// User-Agent. Written in 64 KB pieces so the panel can show progress.
    static func download(_ url: URL, to file: URL, current: AppVersion,
                         progress: @escaping @MainActor @Sendable (Double?) -> Void) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = downloadTimeout
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: downloadTimeout)
        request.setValue("Locant/\(current)", forHTTPHeaderField: "User-Agent")

        do {
            let (bytes, response) = try await session.bytes(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw InstallFailure.downloadFailed }
            let expected = response.expectedContentLength > 0 ? response.expectedContentLength : nil
            if let expected, expected > maxDownload { throw InstallFailure.downloadFailed }
            await progress(nil)

            guard FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil) else {
                throw InstallFailure.unpackFailed
            }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            let piece = 1 << 16
            var buffer = Data()
            buffer.reserveCapacity(piece)
            var written: Int64 = 0
            var shown = -1
            for try await byte in bytes {
                buffer.append(byte)
                guard buffer.count == piece else { continue }
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if written > maxDownload { throw InstallFailure.downloadFailed }
                if let expected {
                    let percent = Int(written * 100 / expected)
                    if percent != shown {
                        shown = percent
                        await progress(Double(percent) / 100)
                    }
                }
            }
            try handle.write(contentsOf: buffer)
        } catch let failure as InstallFailure {
            throw failure
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as CocoaError where error.code == .fileWriteOutOfSpace {
            throw InstallFailure.noSpace
        } catch let error as POSIXError where error.code == .ENOSPC {
            throw InstallFailure.noSpace
        } catch {
            throw InstallFailure.downloadFailed
        }
    }
```

- [ ] **Step 2: Add the Debug feed to `UpdateCheck`**

In `Locant/Store/UpdateCheck.swift`, inside `enum UpdateCheck`, after `static let launchDelay`:

```swift
    #if DEBUG
    /// specs/in-app-update.md R183: `-updateFeed <path>` reads the release JSON from that file in place of
    /// asking GitHub. Debug builds only, read from the launch arguments alone, so a persisted default can
    /// never turn it on.
    static let debugFeed = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)["updateFeed"] as? String
    #endif
```

At the top of `static func fetch(current: AppVersion?) async throws -> GitHubRelease`, before `let configuration`:

```swift
        #if DEBUG
        if let debugFeed { return try GitHubRelease.decode(Data(contentsOf: URL(filePath: debugFeed))) }
        #endif
```

- [ ] **Step 3: Build and run the whole test suite**

Run: `eval $TEST test 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`, with no new warnings in `UpdateInstaller.swift` or `UpdateCheck.swift`. Check with `eval $TEST build 2>&1 | grep -E "UpdateInstaller|UpdateCheck"`, which should print nothing.

- [ ] **Step 4: Commit**

```bash
git add Locant/Store/UpdateInstaller.swift Locant/Store/UpdateCheck.swift
git commit -m "update: download and prepare an update; Debug -updateFeed"
```

---

### Task 5: The panel and the alerts

**Files:**
- Create: `Locant/App/UpdatePanel.swift`
- Modify: `Locant/App/AppState.swift`:
  - the `updateTask` property, around line 113;
  - `start()`, around line 171;
  - `offerUpdate`, around lines 462–476.

**Interfaces:**
- Consumes:
  - `InstallPlace.current()`, `InstallPlace.reason`;
  - `GitHubRelease.installerAsset(version:)`;
  - `UpdateInstaller.prepare`, `startSwap`, `discard`, `removeLeftovers`;
  - `InstallFailure.reason`;
  - `PreparedUpdate`.
- Produces: `@MainActor final class UpdatePanel: NSObject`, with:
  - `show(_ text: String, onCancel: @escaping @MainActor () -> Void)`
  - `setText(_:)`
  - `setProgress(_ fraction: Double?)`
  - `close()`

- [ ] **Step 1: Create the panel**

Create `Locant/App/UpdatePanel.swift`:

```swift
import AppKit

/// specs/in-app-update.md R177: the small panel while an update downloads and is checked. Cancel stops
/// it; nothing else is shown after a cancel.
@MainActor
final class UpdatePanel: NSObject {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()
    private var onCancel: (@MainActor () -> Void)?

    override init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 110), styleMask: [.titled], backing: .buffered, defer: true)
        super.init()
        panel.title = "Locant Update"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        bar.style = .bar
        bar.minValue = 0
        bar.maxValue = 1
        bar.isIndeterminate = true
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancel.keyEquivalent = "\u{1b}"
        let stack = NSStackView(views: [label, bar, cancel])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 16, right: 20)
        label.widthAnchor.constraint(equalToConstant: 320).isActive = true
        bar.widthAnchor.constraint(equalToConstant: 320).isActive = true
        panel.contentView = stack
    }

    func show(_ text: String, onCancel: @escaping @MainActor () -> Void) {
        self.onCancel = onCancel
        setText(text)
        panel.center()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    /// A new step: the bar spins until progress arrives.
    func setText(_ text: String) {
        label.stringValue = text
        setProgress(nil)
    }

    /// nil while the size is unknown.
    func setProgress(_ fraction: Double?) {
        if let fraction {
            bar.stopAnimation(nil)
            bar.isIndeterminate = false
            bar.doubleValue = fraction
        } else {
            bar.isIndeterminate = true
            bar.startAnimation(nil)
        }
    }

    func close() {
        onCancel = nil
        bar.stopAnimation(nil)
        panel.orderOut(nil)
    }

    @objc private func cancelClicked() {
        let cancel = onCancel
        close()
        cancel?()
    }
}
```

- [ ] **Step 2: Add the install task property**

In `Locant/App/AppState.swift`, after `@ObservationIgnored private var updateTask: Task<Void, Never>?`:

```swift
    /// specs/in-app-update.md R177–R180: an install under way, from Install and Relaunch to the quit.
    @ObservationIgnored private var installTask: Task<Void, Never>?
```

- [ ] **Step 3: Clear leftovers at start (R182)**

In `start()`, right after `scheduleUpdateChecks()`:

```swift
        let bundle = Bundle.main.bundleURL
        Task.detached { UpdateInstaller.removeLeftovers(beside: bundle) } // R182
```

- [ ] **Step 4: Replace `offerUpdate` and add the install flow**

Replace the whole `private func offerUpdate(_ release: GitHubRelease, current: AppVersion) { … }` with:

```swift
    /// specs/in-app-update.md R175 (over specs/v0.6.md R48): Install and Relaunch where Locant can replace
    /// itself (R176), the browser download where it can't, with the reason.
    private func offerUpdate(_ release: GitHubRelease, current: AppVersion) {
        let newest = release.version.map(\.description) ?? release.tagName
        let place = InstallPlace.current()
        let alert = NSAlert()
        alert.messageText = "Locant \(newest) is available"
        if place == .ok {
            alert.informativeText = "You have \(current). Locant downloads the new version, checks that it is signed by the same developer, and reopens. Your permissions carry over."
            alert.addButton(withTitle: "Install and Relaunch")
        } else {
            alert.informativeText = "You have \(current). Drag the new copy over the old one in Applications; your permissions carry over.\n\n\(place.reason ?? "")"
            alert.addButton(withTitle: "Download")
        }
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if place == .ok { install(release, current: current) } else { NSWorkspace.shared.open(release.downloadURL) }
        case .alertThirdButtonReturn: preferences.skippedUpdateVersion = newest
        default: break
        }
    }

    /// R177–R180: download, check, wait for idle, start the swap script, quit. Any failure ends in R181.
    private func install(_ release: GitHubRelease, current: AppVersion) {
        guard installTask == nil else { return }
        let newest = release.version.map(\.description) ?? release.tagName
        guard let offered = release.version, let asset = release.installerAsset(version: offered) else {
            offerBrowserDownload(release, newest: newest, failure: .noInstaller)
            return
        }
        let panel = UpdatePanel()
        panel.show("Downloading Locant \(newest)…") { [weak self] in self?.installTask?.cancel() }
        installTask = Task { @MainActor [weak self] in
            var prepared: PreparedUpdate?
            do {
                prepared = try await UpdateInstaller.prepare(
                    asset: asset, offered: offered, current: current, running: Bundle.main.bundleURL,
                    progress: { panel.setProgress($0) },
                    checking: { panel.setText("Checking Locant \(newest)…") })
                panel.close()
                // R180: an install never cuts a session short.
                while let self, self.phase != .idle { try await Task.sleep(for: .milliseconds(200)) }
                guard let ready = prepared else { return }
                try UpdateInstaller.startSwap(ready, oldVersion: current)
                NSApp.terminate(nil)
            } catch {
                panel.close()
                if let prepared { UpdateInstaller.discard(work: prepared.work, incoming: prepared.incoming) }
                self?.installTask = nil
                guard !(error is CancellationError), let self else { return }
                await self.waitForIdle()
                self.offerBrowserDownload(release, newest: newest, failure: error as? InstallFailure ?? .unpackFailed)
            }
        }
    }

    /// R181: the reason, and the browser download as before.
    private func offerBrowserDownload(_ release: GitHubRelease, newest: String, failure: InstallFailure) {
        log.error("Update to \(newest, privacy: .public) failed: \(String(describing: failure), privacy: .public)")
        let alert = NSAlert()
        alert.messageText = "Locant couldn't install \(newest)"
        alert.informativeText = failure.reason
        alert.addButton(withTitle: "Download in Browser")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.downloadURL) }
    }

    /// Alerts wait for the session to end: `runModal` blocks the main actor, and the overlay's deferred
    /// work with it.
    private func waitForIdle() async {
        while phase != .idle { try? await Task.sleep(for: .milliseconds(200)) }
    }
```

- [ ] **Step 5: Build and run the whole test suite**

Run: `eval $TEST test 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`, with no new warnings in `AppState.swift` or `UpdatePanel.swift`.
- If Swift 6 complains that `panel` is captured in a `@Sendable` closure, it can't be: `UpdatePanel` is `@MainActor`, so it is `Sendable`. A complaint means the `@MainActor` attribute is missing on the class.

- [ ] **Step 6: Run the failure path in the app (no notarization needed)**

A Debug build is ad-hoc signed, so its designated requirement is its own cdhash. Any downloaded copy therefore fails R179. That makes it a quick test of the panel and of R181.

1. Quit the installed Locant (shared hotkeys and defaults), and save the defaults:

   ```bash
   defaults export com.malikzhang.deixis $SP/defaults-before.plist
   osascript -e 'quit app "Locant"'
   ```

2. Build, and make a dmg and a feed:

   ```bash
   eval $TEST build
   APP=$DD/Build/Products/Debug/Locant.app
   mkdir -p $SP/feed/src && rm -rf $SP/feed/src/* && ditto $APP $SP/feed/src/Locant.app
   defaults write $SP/feed/src/Locant.app/Contents/Info CFBundleShortVersionString 9.9.9
   hdiutil create -volname Locant -srcfolder $SP/feed/src -format UDZO -ov -quiet $SP/feed/Locant-9.9.9.dmg
   cat > $SP/feed/feed.json <<'EOF'
   {"tag_name": "v9.9.9", "html_url": "https://github.com/Malik1942/locant/releases",
    "assets": [{"name": "Locant-9.9.9.dmg", "browser_download_url": "http://127.0.0.1:8765/Locant-9.9.9.dmg"}]}
   EOF
   ```

3. Serve the folder in the background, from its own terminal. Run it with Bash `run_in_background`:

   ```bash
   python3 -m http.server 8765 --bind 127.0.0.1 --directory $SP/feed
   ```

4. Start the Debug copy from the shell (not `open -n`):

   ```bash
   mkdir -p ~/Applications/LocantUpdateTest && rm -rf ~/Applications/LocantUpdateTest/Locant.app
   ditto $APP ~/Applications/LocantUpdateTest/Locant.app
   ~/Applications/LocantUpdateTest/Locant.app/Contents/MacOS/Locant -updateFeed $SP/feed/feed.json &
   ```

5. In Settings › General, choose Check Now.
   - Expected: the alert "Locant 9.9.9 is available" with **Install and Relaunch**.
   - Click it. The panel shows "Downloading Locant 9.9.9…", then "Checking Locant 9.9.9…".
   - Then the alert "Locant couldn't install 9.9.9" with "The download isn't signed by Locant's developer."
   - Then:

     ```bash
     ls -a ~/Applications/LocantUpdateTest
     ls $TMPDIR | grep Locant-update
     ```

     The first lists only `.`, `..`, and `Locant.app`; the second prints nothing.
   - The Debug copy still runs.
   - If the download fails instead ("The download failed."), App Transport Security refused plain HTTP. Then serve over `http://localhost:8765` and change the feed's URL to match.

6. Check the panel's Cancel:
   - Throttle nothing. Instead, click Install and Relaunch and press Esc while "Downloading" shows. It may be too quick on a local server; that's fine.
   - Expected: no alert follows a cancel.

7. Check the translocated path:

   ```bash
   hdiutil attach -nobrowse $SP/feed/Locant-9.9.9.dmg
   ```

   Quit the test copy and start `/Volumes/Locant/Locant.app/Contents/MacOS/Locant -updateFeed $SP/feed/feed.json &`. Its version is 9.9.9, so make the feed's tag `v9.9.10` for this one check.
   - Expected: the alert shows the R176 sentence and **Download**.
   - Detach afterwards.

8. Clean up:

   ```bash
   pkill -f LocantUpdateTest/Locant.app; pkill -f /Volumes/Locant/Locant.app
   hdiutil detach /Volumes/Locant 2>/dev/null
   defaults import com.malikzhang.deixis $SP/defaults-before.plist
   rm -rf ~/Applications/LocantUpdateTest
   open -a /Applications/Locant.app
   ```

   Stop the `http.server` background job.

- [ ] **Step 7: Commit**

```bash
git add Locant/App/UpdatePanel.swift Locant/App/AppState.swift
git commit -m "update: Install and Relaunch in the update alert, the progress panel, the failure alert"
```

---

### Task 6: Words elsewhere

**Files:**
- Modify: `README.md` (around lines 74–75 and 324)
- Modify: `site/index.html` (around line 856)
- Modify: `CHANGELOG.md` (intro line 3, new Unreleased section above `## 1.3.1`)
- Modify: `docs/CLAUDE.md` (the "No network calls" line)
- Modify: `packaging/homebrew/locant.rb`

- [ ] **Step 1: README Install.** Replace

```
   There is no third prompt. Nothing leaves the machine: no telemetry, no accounts. The one request Locant
   makes is a daily check for a newer release on GitHub; turn it off in Settings › General.
```

with

```
   There is no third prompt. Nothing leaves the machine: no telemetry, no accounts. The one request Locant
   makes is a daily check for a newer release on GitHub. When you click Install and Relaunch, it downloads
   that release from GitHub. Turn the check off in Settings › General.
```

- [ ] **Step 2: README Git facts.** In the line starting `` `defaults write com.malikzhang.deixis completesPaste -bool NO` ``, replace `It never talks to the network except the release check and, for a local page's source lines, your own dev server` with `It never talks to the network except the release check and the update you install, and, for a local page's source lines, your own dev server`.

- [ ] **Step 3: Site.** In `site/index.html`, replace

```
<p>No telemetry, no accounts. The one request that leaves it is a daily check for a newer version, and you can turn it&nbsp;off.</p>
```

with

```
<p>No telemetry, no accounts. The one request that leaves it is a daily check for a newer version, and you can turn it&nbsp;off. An update downloads only when you click&nbsp;Install.</p>
```

Open `site/index.html` in the browser pane at desktop and 375 px widths. The card's text must not overflow its box. If it does, say so in the report; don't restyle.

- [ ] **Step 4: CHANGELOG.**
1. Replace line 3 with:

   ```
   Every release is a signed, notarized `Locant.dmg` on [GitHub Releases](https://github.com/Malik1942/locant/releases). From 1.4.0 on, Locant installs it for you from the update alert; your permissions carry over.
   ```

2. Insert above `## 1.3.1 (2026-11-13)`:

   ```
   ## Unreleased

   - **Locant installs its own updates.** The update alert's Install and Relaunch downloads the new version from GitHub, checks that it is signed by the same developer and notarized, puts it in place of the old copy, and reopens Locant. Your permissions carry over, and the old copy goes to the Trash. Where Locant can't replace itself (opened from a disk image or Downloads, or from a folder you can't write to), the alert says why and offers the browser download as before. Copies older than this version update through the browser one last time.

   ```

- [ ] **Step 5: `docs/CLAUDE.md`.** Replace

```
- No network calls except the release check (specs/v0.6.md R45) and, for a local web page's source lines, that page's source maps from the dev server on this Mac (specs/web-source.md R152). No telemetry. No analytics.
```

with

```
- No network calls except the release check (specs/v0.6.md R45), the update the user clicks Install and Relaunch for (specs/in-app-update.md R177), and, for a local web page's source lines, that page's source maps from the dev server on this Mac (specs/web-source.md R152). No telemetry. No analytics.
```

- [ ] **Step 6: Cask.** In `packaging/homebrew/locant.rb`, between the `livecheck do … end` block and `depends_on macos: :sequoia`, add:

```ruby
  # specs/in-app-update.md R184: Locant installs its own updates, so `brew upgrade` leaves it alone.
  auto_updates true

```

Then confirm `scripts/cask.sh` only rewrites `version` and `sha256`, so the new line survives:

```bash
grep -n "sed\|version\|sha256" scripts/cask.sh
```

If it rewrites the whole file from a template, add the line there too.

- [ ] **Step 7: Build and commit**

Run: `eval $TEST build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

```bash
git add README.md site/index.html CHANGELOG.md docs/CLAUDE.md packaging/homebrew/locant.rb
git commit -m "docs: the update installs from the app; cask auto_updates"
```

---

### Task 7: End to end with a notarized copy (spec §3)

This proves the real path: Developer ID signature, notarization, the swap, the relaunch, and permissions kept.
- **Ask Malik before step 1:** it uploads a 9.9.9 build to Apple's notary service. Nothing is published.
- **Quit the installed Locant for the run.**

**Files:** none changed. The scratch copies live in `$SP`, and nothing is committed.

- [ ] **Step 1: The new copy, 9.9.9, notarized.** Build from a clean export, because iCloud Documents breaks `release.sh`'s codesign:

```bash
rm -rf $SP/rel && mkdir -p $SP/rel && git archive HEAD | tar -x -C $SP/rel
sed -i '' 's/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = 9.9.9;/' $SP/rel/Locant.xcodeproj/project.pbxproj
xcrun notarytool history --keychain-profile locant-notary >/dev/null 2>&1 && echo locant-notary || echo "use NOTARY_PROFILE=deixis-notary"
```

Then, with the profile the last line named, run it in the background (two notarizations, several minutes):

```bash
cd $SP/rel && NOTARY_PROFILE=<profile> scripts/release.sh
```

Expected: `$SP/rel/build/release/Locant-9.9.9.dmg` exists, and `spctl -a -t open --context context:primary-signature -vv` on it says "accepted … Notarized Developer ID".

- [ ] **Step 2: The old copy, Debug, signed with the Developer ID.** From the worktree:

```bash
xcodebuild -scheme Locant -configuration Debug -derivedDataPath $SP/dd-old build \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application: YUE ZHANG (MVAUZXPK9M)" \
  DEVELOPMENT_TEAM=MVAUZXPK9M ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS=--timestamp \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO -quiet
mkdir -p ~/Applications/LocantUpdateTest && rm -rf ~/Applications/LocantUpdateTest/Locant.app
ditto $SP/dd-old/Build/Products/Debug/Locant.app ~/Applications/LocantUpdateTest/Locant.app
codesign -d -r- ~/Applications/LocantUpdateTest/Locant.app 2>&1 | grep designated
```

Expected: the designated line names `identifier "com.malikzhang.deixis"` and `MVAUZXPK9M`.

- [ ] **Step 3: The feed.**

```bash
mkdir -p $SP/feed && cp $SP/rel/build/release/Locant-9.9.9.dmg $SP/feed/
cat > $SP/feed/feed.json <<'EOF'
{"tag_name": "v9.9.9", "html_url": "https://github.com/Malik1942/locant/releases",
 "assets": [{"name": "Locant-9.9.9.dmg", "browser_download_url": "http://127.0.0.1:8765/Locant-9.9.9.dmg"}]}
EOF
```

Run `python3 -m http.server 8765 --bind 127.0.0.1 --directory $SP/feed` with Bash `run_in_background`.

- [ ] **Step 4: Install.**

```bash
defaults export com.malikzhang.deixis $SP/defaults-before.plist
osascript -e 'quit app "Locant"'
~/Applications/LocantUpdateTest/Locant.app/Contents/MacOS/Locant -updateFeed $SP/feed/feed.json &
```

In Settings › General, choose Check Now, then **Install and Relaunch**. Then:

```bash
sleep 5
defaults read ~/Applications/LocantUpdateTest/Locant.app/Contents/Info CFBundleShortVersionString
ls ~/.Trash | grep "Locant "
pgrep -fl LocantUpdateTest
```

Expected:
- the version is `9.9.9`;
- the Trash holds `Locant <branch version>.app`;
- one Locant process runs from `~/Applications/LocantUpdateTest/Locant.app`;
- Settings shows Version 9.9.9.

Then press ⌃⌃ and Point at any element, type a note, and press Return. Expected: a capture is written without any Accessibility or Screen Recording prompt.

- [ ] **Step 5: Failure on an unsigned copy.**
1. Rebuild the feed's dmg from an ad-hoc copy with version 9.9.9:

   ```bash
   rm -rf $SP/feed/src && mkdir -p $SP/feed/src
   ditto $SP/rel/build/release/Locant.app $SP/feed/src/Locant.app
   codesign --force --deep -s - $SP/feed/src/Locant.app
   hdiutil create -volname Locant -srcfolder $SP/feed/src -format UDZO -ov -quiet $SP/feed/Locant-9.9.9.dmg
   ```

2. Put the old Debug copy back:

   ```bash
   pkill -f LocantUpdateTest/Locant.app; rm -rf ~/Applications/LocantUpdateTest/Locant.app
   ditto $SP/dd-old/Build/Products/Debug/Locant.app ~/Applications/LocantUpdateTest/Locant.app
   ```

3. Start it with `-updateFeed` as in step 4, and choose Check Now, then Install and Relaunch.

Expected:
- "Locant couldn't install 9.9.9" with "The download isn't signed by Locant's developer.";
- the old copy still runs at its version;
- `ls -a ~/Applications/LocantUpdateTest` shows no `.incoming.app`.

- [ ] **Step 6: Clean up.**

```bash
pkill -f LocantUpdateTest/Locant.app
rm -rf ~/Applications/LocantUpdateTest $SP/rel $SP/feed $SP/dd-old
defaults import com.malikzhang.deixis $SP/defaults-before.plist
open -a /Applications/Locant.app
```

- Stop the `http.server` job.
- Leave the `Locant <version>.app` copies in the Trash for Malik to empty; never empty the Trash.
- Report each expected line as seen or not seen.

---

## Not in this plan

- **The release itself:** bump to 1.4.0, `release.sh`, tag, `publish.sh`, `cask.sh`, the tap push. It follows the usual release recipe, and Malik approves each step.
- **The PR:** opened after the tasks pass, with Malik's go-ahead.
