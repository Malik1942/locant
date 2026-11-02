import Foundation

/// R7: writes the PNG and its JSON sidecar to the capture folder. Nothing is written until both
/// bytes and the capture exist, so a failed capture leaves the folder untouched.
struct FileStore: Sendable {
    var directory: URL
    var organization: CaptureOrganization = .none

    static let defaultDirectory: URL = FileManager.default
        .urls(for: .picturesDirectory, in: .userDomainMask)[0]
        .appending(path: "Locant", directoryHint: .isDirectory)

    init(directory: URL = FileStore.defaultDirectory, organization: CaptureOrganization = .none) {
        self.directory = directory
        self.organization = organization
    }

    /// The folder a capture lands in: the root, or one subfolder per app, project, or month (R21).
    func folder(for capture: Capture) -> URL {
        folder(appName: capture.source.app.name, projectRoot: capture.source.projectRoot, id: capture.id)
    }

    func folder(appName: String, projectRoot: String?, id: String) -> URL {
        switch organization {
        case .none:
            return directory
        case .byApp:
            return directory.appending(path: Self.slug(appName), directoryHint: .isDirectory)
        case .byProject:
            let name = projectRoot.map { URL(filePath: $0).lastPathComponent } ?? Self.slug(appName)
            return directory.appending(path: name, directoryHint: .isDirectory)
        case .byMonth:
            let month = id.count >= 6 ? "\(id.prefix(4))-\(id.dropFirst(4).prefix(2))" : "undated"
            return directory.appending(path: month, directoryHint: .isDirectory)
        }
    }

    /// Snap and Cut: an image file with Finder tags and no sidecar.
    @discardableResult
    func writeImage(png: Data, fileName: String, appName: String, tag: String) throws -> URL {
        let id = String(fileName.dropLast(4).suffix(20))
        let folder = folder(appName: appName, projectRoot: nil, id: id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: fileName)
        try png.write(to: url, options: .atomic)
        Self.setFinderTags(["Locant", appName, tag], on: url)
        return url
    }

    /// v0.8 R58: a further crop of a multi-element capture, `<base>-2.png` beside the capture's own
    /// image, tagged like it. Written before the sidecar so the sidecar can name it.
    func writeExtraImage(png: Data, capture: Capture, index: Int) throws -> URL {
        let folder = folder(for: capture)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "locant-\(Self.slug(capture.source.app.name))-\(capture.id)-\(index).png")
        try png.write(to: url, options: .atomic)
        Self.setFinderTags(Self.tags(for: capture), on: url)
        return url
    }

    /// Finder tags for a capture: Locant, the app, the mode, and the project name when known.
    static func tags(for capture: Capture) -> [String] {
        var tags = ["Locant", capture.source.app.name, capture.mode.rawValue]
        if let root = capture.source.projectRoot { tags.append(URL(filePath: root).lastPathComponent) }
        return tags
    }

    /// Writes the PNG, fills `image.path`, then writes the sidecar, then tags both. Returns the
    /// capture as written.
    @discardableResult
    func write(png: Data, capture: Capture) throws -> Capture {
        let folder = folder(for: capture)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let slug = Self.slug(capture.source.app.name)
        let base = "locant-\(slug)-\(capture.id)"
        let pngURL = folder.appending(path: "\(base).png")
        let jsonURL = folder.appending(path: "\(base).json")

        var written = capture
        written.image.path = pngURL.path(percentEncoded: false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let json = try encoder.encode(written)

        try png.write(to: pngURL, options: .atomic)
        try json.write(to: jsonURL, options: .atomic)
        let tags = Self.tags(for: written)
        for url in [pngURL, jsonURL] {
            Self.setFinderTags(tags, on: url)
        }
        return written
    }

    /// Finder tags live in the `com.apple.metadata:_kMDItemUserTags` extended attribute as a binary
    /// plist array of strings. Written directly, since the URL resource setter needs macOS 26.
    static func setFinderTags(_ tags: [String], on url: URL) {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: tags, format: .binary, options: 0) else { return }
        let path = url.path(percentEncoded: false)
        _ = data.withUnsafeBytes { bytes in
            setxattr(path, "com.apple.metadata:_kMDItemUserTags", bytes.baseAddress, data.count, 0, 0)
        }
    }

    /// `data` written atomically, then the extended attributes the file had put back. An atomic
    /// write is a new inode, and the Finder tags and the pin (`app.locant.pinned`) lived on the
    /// old one: a sidecar resolved by an agent or given an iteration lost its tags (Nov 2 2026).
    /// An attribute the system will not take back (its provenance, say) is skipped.
    static func rewrite(_ data: Data, at url: URL) throws {
        let attributes = extendedAttributes(of: url)
        try data.write(to: url, options: .atomic)
        let path = url.path(percentEncoded: false)
        for (name, value) in attributes {
            _ = value.withUnsafeBytes { setxattr(path, name, $0.baseAddress, value.count, 0, 0) }
        }
    }

    /// Every extended attribute on the file, by name.
    static func extendedAttributes(of url: URL) -> [String: Data] {
        let path = url.path(percentEncoded: false)
        let length = listxattr(path, nil, 0, 0)
        guard length > 0 else { return [:] }
        var names = [CChar](repeating: 0, count: length)
        guard listxattr(path, &names, length, 0) == length else { return [:] }
        var attributes: [String: Data] = [:]
        for name in names.split(separator: 0).map({ String(decoding: $0.map { UInt8(bitPattern: $0) }, as: UTF8.self) }) {
            let size = getxattr(path, name, nil, 0, 0, 0)
            guard size >= 0 else { continue }
            var value = Data(count: size)
            let read = value.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, size, 0, 0) }
            guard read == size else { continue }
            attributes[name] = value
        }
        return attributes
    }

    /// App name lowercased, non-alphanumerics removed, max 16 characters.
    static func slug(_ appName: String) -> String {
        let cleaned = appName.lowercased().filter { $0.isLetter || $0.isNumber }
        let cut = String(cleaned.prefix(16))
        return cut.isEmpty ? "app" : cut
    }

    /// `yyyyMMdd-HHmmss-xxxx`: local stamp plus four base36 characters.
    static func makeID(date: Date, timeZone: TimeZone = .current, suffix: String = randomSuffix()) -> String {
        "\(stamp(date: date, timeZone: timeZone))-\(suffix)"
    }

    static func stamp(date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }

    /// ISO 8601 with the local UTC offset, e.g. `2026-09-12T14:03:12-07:00`.
    static func isoTimestamp(date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssxxx"
        return f.string(from: date)
    }

    static func randomSuffix() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<4).map { _ in alphabet.randomElement()! })
    }
}
