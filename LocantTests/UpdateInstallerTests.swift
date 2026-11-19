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
