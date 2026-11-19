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
        // A failed test can leave a disk image attached under the fixture.
        for mount in UpdateInstaller.mountPoints(inInfoPlist: UpdateInstaller.runTool("/usr/bin/hdiutil", ["info", "-plist"]) ?? Data(), under: temp) {
            UpdateInstaller.runTool("/usr/bin/hdiutil", ["detach", "-force", mount])
        }
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

    func testUnpackRefusesALocantThatIsASymbolicLink() throws {
        let source = try makeFolder("src")
        let real = source.appending(path: "Real.app/Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: source.appending(path: "Locant.app").path(percentEncoded: false),
                                                   withDestinationPath: "Real.app")
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

    // R181: a swap that didn't happen
    func testPendingOutcome() {
        let url = URL(string: "https://github.com/Malik1942/locant/releases/download/v1.4.0/Locant.dmg")!
        let pending = PendingUpdate(version: "1.4.0", downloadURL: url)
        XCTAssertEqual(UpdateInstaller.pendingOutcome(pending: pending, current: AppVersion("1.3.1")!),
                       .failed(version: "1.4.0", downloadURL: url))
        XCTAssertEqual(UpdateInstaller.pendingOutcome(pending: pending, current: AppVersion("1.4.0")!), .installed)
        XCTAssertEqual(UpdateInstaller.pendingOutcome(pending: pending, current: AppVersion("1.4.1")!), .installed)
    }

    func testPendingFileIsReadOnce() throws {
        let tmp = try makeFolder("tmp")
        let pending = PendingUpdate(version: "1.4.0", downloadURL: URL(string: "https://example.com/Locant.dmg")!)
        try UpdateInstaller.writePending(pending, temporary: tmp)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.appending(path: "Locant-pending-update.json").path(percentEncoded: false)))
        XCTAssertEqual(UpdateInstaller.takePending(temporary: tmp), pending)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: tmp.path(percentEncoded: false)), [])
        XCTAssertNil(UpdateInstaller.takePending(temporary: tmp))
    }

    func testPendingFileThatDoesNotDecodeIsDeleted() throws {
        let tmp = try makeFolder("tmp")
        try Data("{\"version\": 3}".utf8).write(to: tmp.appending(path: "Locant-pending-update.json"))
        XCTAssertNil(UpdateInstaller.takePending(temporary: tmp))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: tmp.path(percentEncoded: false)), [])
    }

    // R182
    func testLeftoversAreRemoved() throws {
        let apps = try makeFolder("apps")
        let tmp = try makeFolder("tmp")
        for name in ["Locant.app", ".Locant-1.4.0.incoming.app", ".Locant-1.3.1.outgoing.app", "Other.app"] {
            try FileManager.default.createDirectory(at: apps.appending(path: name), withIntermediateDirectories: true)
        }
        for name in ["Locant-update-ABC", "keep"] {
            try FileManager.default.createDirectory(at: tmp.appending(path: name), withIntermediateDirectories: true)
        }
        // A quit during unpacking leaves the dmg attached inside the download folder.
        let source = try makeFolder("src")
        try Data("x".utf8).write(to: source.appending(path: "readme.txt"))
        let download = tmp.appending(path: "Locant-update-DEF", directoryHint: .isDirectory)
        let mounts = download.appending(path: "mnt", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: mounts, withIntermediateDirectories: true)
        let dmg = try makeDiskImage(from: source)
        let attached = UpdateInstaller.runTool("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountrandom",
                                                                    mounts.path(percentEncoded: false), "-plist", dmg.path(percentEncoded: false)])
        XCTAssertNotNil(attached.flatMap(UpdateInstaller.mountPoint(inAttachPlist:)), "hdiutil attach failed")

        UpdateInstaller.removeLeftovers(beside: apps.appending(path: "Locant.app"), temporary: tmp)

        let left = Set(try FileManager.default.contentsOfDirectory(atPath: apps.path(percentEncoded: false)))
        XCTAssertEqual(left, ["Locant.app", "Other.app"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: tmp.path(percentEncoded: false)), ["keep"])
        let info = String(decoding: UpdateInstaller.runTool("/usr/bin/hdiutil", ["info"]) ?? Data(), as: UTF8.self)
        XCTAssertFalse(info.contains(download.path(percentEncoded: false)), "the disk image is still attached")
    }

    func testMountPointsUnderAFolder() throws {
        // `hdiutil info` names /private/var/folders where the temporary directory says /var/folders.
        func spelledPrivate(_ url: URL) -> String {
            let path = url.path(percentEncoded: false)
            return path.hasPrefix("/var/") || path.hasPrefix("/tmp/") ? "/private" + path : path
        }
        let inside = try makeFolder("Locant-update-A/mnt/dmg.1")
        let sibling = try makeFolder("Locant-update-AB/mnt/dmg.2")
        let plist: [String: Any] = ["images": [
            ["system-entities": [["dev-entry": "/dev/disk8"], ["dev-entry": "/dev/disk8s1", "mount-point": spelledPrivate(inside)]]],
            ["system-entities": [["dev-entry": "/dev/disk9s1", "mount-point": sibling.path(percentEncoded: false)]]],
            ["system-entities": [["dev-entry": "/dev/disk10s1", "mount-point": "/Volumes/Other"]]],
        ]]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        XCTAssertEqual(UpdateInstaller.mountPoints(inInfoPlist: data, under: temp.appending(path: "Locant-update-A")), [spelledPrivate(inside)])
        XCTAssertEqual(UpdateInstaller.mountPoints(inInfoPlist: data, under: temp.appending(path: "Nothing")), [])
        XCTAssertEqual(UpdateInstaller.mountPoints(inInfoPlist: Data("not a plist".utf8), under: temp), [])
    }

    // R180
    func testScriptNamesNoPath() {
        XCTAssertFalse(UpdateInstaller.script.contains("/Applications"))
        XCTAssertFalse(UpdateInstaller.script.contains("Locant.app"))
    }

    func testScriptSwapsAfterThePidExits() throws {
        let (running, incoming, work, home) = try makeSwapFixture(incomingExists: true)
        let run = try runSwap(running: running, incoming: incoming, work: work, home: home, waitFor: 0.3)
        XCTAssertGreaterThanOrEqual(run.elapsed, 0.25, "the script did not wait for the pid")
        XCTAssertFalse(run.sleeperStillRunning, "the script finished before the pid exited")
        XCTAssertEqual(try marker(in: running), "new")
        XCTAssertEqual(try marker(in: home.appending(path: ".Trash/Locant 1.3.1.app")), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: incoming.path(percentEncoded: false)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: work.path(percentEncoded: false)))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: running.deletingLastPathComponent().path(percentEncoded: false)),
                       ["Locant.app"], "an .outgoing.app was left")
        XCTAssertEqual(run.opened, running.path(percentEncoded: false))
    }

    func testScriptKeepsTheRunningCopyWhenTheIncomingOneIsMissing() throws {
        let (running, incoming, work, home) = try makeSwapFixture(incomingExists: false)
        let run = try runSwap(running: running, incoming: incoming, work: work, home: home, waitFor: 0)
        XCTAssertEqual(try marker(in: running), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appending(path: ".Trash/Locant 1.3.1.app").path(percentEncoded: false)))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: home.appending(path: ".Trash").path(percentEncoded: false)), [])
        XCTAssertEqual(run.opened, running.path(percentEncoded: false))
    }

    func testScriptGivesTheTrashCopyAnotherNameWhenTheFirstIsTaken() throws {
        let (running, incoming, work, home) = try makeSwapFixture(incomingExists: true)
        try FileManager.default.createDirectory(at: home.appending(path: ".Trash/Locant 1.3.1.app"), withIntermediateDirectories: true)
        _ = try runSwap(running: running, incoming: incoming, work: work, home: home, waitFor: 0)
        XCTAssertEqual(try marker(in: running), "new")
        let trash = try FileManager.default.contentsOfDirectory(atPath: home.appending(path: ".Trash").path(percentEncoded: false))
        XCTAssertEqual(trash.count, 2)
        let renamed = try XCTUnwrap(trash.first { $0.hasPrefix("Locant 1.3.1 ") && $0.hasSuffix(".app") })
        XCTAssertEqual(try marker(in: home.appending(path: ".Trash/\(renamed)")), "old")
    }

    func testScriptPutsTheOldCopyBackWhenTheIncomingOneCannotMove() throws {
        let (running, _, work, home) = try makeSwapFixture(incomingExists: false)
        // Renaming out of a folder that can't be written fails with EACCES; the same volume, so `mv`
        // doesn't fall back to a copy.
        let locked = try makeFolder("locked")
        let incoming = locked.appending(path: ".Locant-9.9.9.incoming.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: incoming.appending(path: "marker"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path(percentEncoded: false))
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path(percentEncoded: false)) }

        let run = try runSwap(running: running, incoming: incoming, work: work, home: home, waitFor: 0)

        XCTAssertEqual(try marker(in: running), "old")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: running.deletingLastPathComponent().path(percentEncoded: false)),
                       ["Locant.app"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: home.appending(path: ".Trash").path(percentEncoded: false)), [])
        XCTAssertEqual(run.opened, running.path(percentEncoded: false))
    }

    func testScriptKeepsTheNewCopyWhenTheTrashCannotTakeTheOldOne() throws {
        let (running, incoming, work, home) = try makeSwapFixture(incomingExists: true)
        let trash = home.appending(path: ".Trash")
        try FileManager.default.removeItem(at: trash)
        try Data().write(to: trash) // a plain file, so nothing can go in it

        let run = try runSwap(running: running, incoming: incoming, work: work, home: home, waitFor: 0)

        XCTAssertEqual(try marker(in: running), "new")
        XCTAssertEqual(run.opened, running.path(percentEncoded: false))
        // R182 removes it at the next start.
        XCTAssertEqual(try marker(in: running.deletingLastPathComponent().appending(path: ".Locant-1.3.1.outgoing.app")), "old")
    }

    func testSwapArgumentsAreInTheOrderTheScriptReadsThem() {
        let arguments = UpdateInstaller.swapArguments(
            pid: 42, running: URL(filePath: "/Apps/Locant.app"), incoming: URL(filePath: "/Apps/.Locant-1.4.0.incoming.app"),
            oldVersion: AppVersion("1.3.1")!, work: URL(filePath: "/tmp/Locant-update-X"), opener: "/usr/bin/open")
        XCTAssertEqual(arguments, ["42", "/Apps/Locant.app", "/Apps/.Locant-1.4.0.incoming.app", "1.3.1", "/tmp/Locant-update-X", "/usr/bin/open"])
        XCTAssertTrue(UpdateInstaller.script.contains("pid=$1 running=$2 incoming=$3 old=$4 work=$5 opener=$6"))
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

    /// Runs the script as `startSwap` does (`/bin/sh -c <script> sh` and `swapArguments`), with `HOME`
    /// pointed at the fixture and an opener that writes down what it was asked to open, against the pid
    /// of a `sleep` that ends after `waitFor` seconds. Returns how long the shell ran, whether the
    /// sleeper was still alive the moment the shell exited (a script that does not wait for the pid
    /// finishes first, so the test sees it), and the path the opener got.
    private func runSwap(running: URL, incoming: URL, work: URL, home: URL, waitFor: Double) throws
        -> (elapsed: TimeInterval, sleeperStillRunning: Bool, opened: String?) {
        let openerFolder = try makeFolder("opener")
        let opener = openerFolder.appending(path: "open.sh")
        let opened = openerFolder.appending(path: "opened")
        try "#!/bin/sh\nprintf '%s' \"$1\" > '\(opened.path(percentEncoded: false))'\n".write(to: opener, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: opener.path(percentEncoded: false))
        let sleeper = Process()
        sleeper.executableURL = URL(filePath: "/bin/sleep")
        sleeper.arguments = [String(waitFor)]
        try sleeper.run()
        let shell = Process()
        shell.executableURL = URL(filePath: "/bin/sh")
        shell.arguments = ["-c", UpdateInstaller.script, "sh"] + UpdateInstaller.swapArguments(
            pid: sleeper.processIdentifier, running: running, incoming: incoming, oldVersion: AppVersion("1.3.1")!,
            work: work, opener: opener.path(percentEncoded: false))
        shell.environment = ["HOME": home.path(percentEncoded: false)]
        let started = Date()
        try shell.run()
        shell.waitUntilExit()
        let elapsed = Date().timeIntervalSince(started)
        let sleeperStillRunning = sleeper.isRunning
        sleeper.waitUntilExit()
        XCTAssertEqual(shell.terminationStatus, 0)
        return (elapsed, sleeperStillRunning, try? String(contentsOf: opened, encoding: .utf8))
    }

    private func marker(in app: URL) throws -> String {
        try String(contentsOf: app.appending(path: "marker"), encoding: .utf8)
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
}
