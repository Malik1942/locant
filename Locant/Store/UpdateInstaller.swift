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

/// R180: a checked copy beside the running one, ready to swap.
struct PreparedUpdate: Sendable {
    let work: URL
    let incoming: URL
    let running: URL
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
}
