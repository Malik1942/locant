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
