import Foundation

/// v0.3 R17: is this the user's own code on screen? Inferred from signals that need nothing from
/// the user; My Apps is the override. Pure given a `ModeEnvironment`.
struct ModeSignals: Sendable, Equatable {
    var bundleId: String?
    var isSimulator = false
    var simulatedBundleId: String?
    /// The simulated app's running copy, in the device's container: the build on screen.
    var simulatedBundlePath: String?
    /// The app bundle's path on disk (the simulated app's path for Simulator captures).
    var bundlePath: String?
    var urlHost: String?
    var teamID: String?
    var userTeamIDs: Set<String> = []
    var myApps: [String] = []
}

enum ModeRule: String, Sendable {
    case myApps, simulator, localhost, builtHere, signedByUser, none
}

struct ModeDecision: Sendable, Equatable {
    var mode: CaptureMode
    var projectRoot: String?
    var rule: ModeRule
}

/// The filesystem, injectable for tests.
struct ModeEnvironment: Sendable {
    var directoryEntries: @Sendable (String) -> [String]
    /// Given a DerivedData project folder, the `WorkspacePath` from its info.plist.
    var derivedDataWorkspacePath: @Sendable (String) -> String?
    /// Given a simulated app's bundle id and its running copy's path, the project root that built it.
    var simulatorProjectRoot: @Sendable (_ bundleId: String, _ runningAt: String?) -> String? = { _, _ in nil }

    static let derivedDataFolder = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Developer/Xcode/DerivedData", directoryHint: .isDirectory)

    static let live = ModeEnvironment(
        directoryEntries: { path in (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [] },
        derivedDataWorkspacePath: { folder in workspacePath(inDerivedDataFolder: folder) },
        simulatorProjectRoot: { bundleId, running in projectRoot(ofSimulatedApp: bundleId, runningAt: running, derivedData: derivedDataFolder) }
    )

    /// Simulated apps run from the device container, not from DerivedData (specs/simulator-project-root.md
    /// R107). The running copy's debug map names the build folder that made it, whatever was built since.
    /// Without one, the products in DerivedData/<Project-hash>/Build/Products/<Config>-iphonesimulator/<App>.app
    /// answer only when they all name one project: the newest of several worktrees is a guess, and the
    /// Project line tells the agent to change that folder.
    static func projectRoot(ofSimulatedApp bundleId: String, runningAt running: String?, derivedData: URL) -> String? {
        if let running,
           let binary = BuildProvenance.codeBinary(ofBundleAt: URL(filePath: running)),
           let data = try? Data(contentsOf: binary, options: .alwaysMapped),
           let folder = BuildProvenance.buildFolder(inMachO: data),
           let workspace = workspacePath(inDerivedDataFolder: folder) {
            return ModeInference.directoryPath(URL(filePath: workspace).deletingLastPathComponent())
        }
        let fm = FileManager.default
        // DerivedData may be a symlink (to DerivedData.noindex, say); the URL listing does not follow one.
        guard let projects = try? fm.contentsOfDirectory(at: derivedData.resolvingSymlinksInPath(), includingPropertiesForKeys: nil) else { return nil }
        var roots = Set<String>()
        for project in projects {
            let products = project.appending(path: "Build/Products")
            guard let configs = try? fm.contentsOfDirectory(at: products, includingPropertiesForKeys: nil) else { continue }
            for config in configs where config.lastPathComponent.contains("iphonesimulator") {
                guard let apps = try? fm.contentsOfDirectory(at: config, includingPropertiesForKeys: nil) else { continue }
                for app in apps where app.pathExtension == "app" {
                    guard Bundle(url: app)?.bundleIdentifier == bundleId,
                          let workspace = workspacePath(inDerivedDataFolder: project.path(percentEncoded: false)) else { continue }
                    roots.insert(ModeInference.directoryPath(URL(filePath: workspace).deletingLastPathComponent()))
                }
            }
        }
        return roots.count == 1 ? roots.first : nil
    }

    static func workspacePath(inDerivedDataFolder folder: String) -> String? {
        let plist = URL(filePath: folder).appending(path: "info.plist")
        guard let data = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return dict["WorkspacePath"] as? String
    }
}

enum ModeInference {
    static let simulatorBundleId = "com.apple.iphonesimulator"
    /// Xcode 27 has no Simulator.app; Device Hub shows simulators, and physical devices too.
    static let deviceHubBundleId = "com.apple.dt.Devices"
    static let projectMarkers = [".xcodeproj", ".xcworkspace", "Package.swift"]
    static let derivedDataMarker = "/Library/Developer/Xcode/DerivedData/"
    static let localHosts: Set<String> = ["localhost", "127.0.0.1", "0.0.0.0", "::1"]

    static func infer(_ s: ModeSignals, environment: ModeEnvironment = .live) -> ModeDecision {
        let root = s.bundlePath.flatMap { projectRoot(forBundleAt: $0, environment: environment) }
            ?? s.simulatedBundleId.flatMap { environment.simulatorProjectRoot($0, s.simulatedBundlePath) }
        if let id = s.bundleId, s.myApps.contains(id) { return ModeDecision(mode: .fix, projectRoot: root, rule: .myApps) }
        if let id = s.simulatedBundleId, s.myApps.contains(id) { return ModeDecision(mode: .fix, projectRoot: root, rule: .myApps) }
        if s.isSimulator || s.bundleId == simulatorBundleId { return ModeDecision(mode: .fix, projectRoot: root, rule: .simulator) }
        if isLocalhost(s.urlHost) { return ModeDecision(mode: .fix, projectRoot: root, rule: .localhost) }
        if let root { return ModeDecision(mode: .fix, projectRoot: root, rule: .builtHere) }
        if let team = s.teamID, s.userTeamIDs.contains(team) { return ModeDecision(mode: .fix, projectRoot: nil, rule: .signedByUser) }
        return ModeDecision(mode: .reference, projectRoot: nil, rule: .none)
    }

    /// A directory path without the trailing slash that directory URLs print with.
    static func directoryPath(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    static func isLocalhost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return localHosts.contains(host) || host.hasSuffix(".local")
    }

    /// The project directory that produced a bundle: through DerivedData's `WorkspacePath`, or the
    /// nearest ancestor holding an `.xcodeproj`, `.xcworkspace`, or `Package.swift`. Nil when neither.
    static func projectRoot(forBundleAt path: String, environment: ModeEnvironment) -> String? {
        if let range = path.range(of: derivedDataMarker) {
            let rest = path[range.upperBound...]
            if let slash = rest.firstIndex(of: "/") {
                let folder = String(path[..<slash])
                if let workspace = environment.derivedDataWorkspacePath(folder) {
                    return directoryPath(URL(filePath: workspace).deletingLastPathComponent())
                }
            }
            return nil
        }
        var url = URL(filePath: path).deletingLastPathComponent()
        for _ in 0..<12 {
            let dir = directoryPath(url)
            guard dir.count > 1 else { break }
            let entries = environment.directoryEntries(dir)
            if entries.contains(where: { entry in projectMarkers.contains { entry == $0 || entry.hasSuffix($0) } }) {
                return dir
            }
            url = url.deletingLastPathComponent()
        }
        return nil
    }
}

/// Code signature facts, through the Security framework. Best effort: nil or empty on any failure.
enum CodeSigning {
    static func teamID(ofBundleAt url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(code, flags, &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict["teamid"] as? String
    }

    /// Team IDs of the user's own signing identities (Apple Development, Distribution, Developer ID).
    static func userTeamIDs() -> Set<String> {
        let query: [String: Any] = [
            "class": "idnt",          // kSecClass: kSecClassIdentity
            "m_Limit": "m_LimitAll",  // kSecMatchLimit: kSecMatchLimitAll
            "r_Ref": true,            // kSecReturnRef
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [AnyObject] else { return [] }
        var teams = Set<String>()
        for item in items where CFGetTypeID(item) == SecIdentityGetTypeID() {
            let identity = item as! SecIdentity
            var certificate: SecCertificate?
            guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate else { continue }
            let summary = (SecCertificateCopySubjectSummary(certificate) as String?) ?? ""
            let prefixes = ["Apple Development", "Apple Distribution", "Developer ID Application", "iPhone Developer", "Mac Developer"]
            guard prefixes.contains(where: { summary.hasPrefix($0) }) else { continue }
            if let team = organizationalUnit(of: certificate) { teams.insert(team) }
        }
        return teams
    }

    private static func organizationalUnit(of certificate: SecCertificate) -> String? {
        let subjectOID = "2.5.4.11" // organizationalUnitName
        guard let values = SecCertificateCopyValues(certificate, nil, nil) as? [String: Any],
              let subject = values["X509V1SubjectName"] as? [String: Any],
              let items = subject["value"] as? [[String: Any]] else { return nil }
        for item in items where (item["label"] as? String) == subjectOID {
            return item["value"] as? String
        }
        return nil
    }
}
