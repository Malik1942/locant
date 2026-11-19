import Foundation

/// v0.6 R45: a marketing version as dotted integers, so "0.10.0" sorts after "0.9.1". A leading
/// "v" and anything after the first "-" or "+" (a pre-release or build suffix) are ignored.
struct AppVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    let components: [Int]

    init?(_ text: String) {
        var body = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if body.first == "v" || body.first == "V" { body = body.dropFirst() }
        if let cut = body.firstIndex(where: { $0 == "-" || $0 == "+" }) { body = body[..<cut] }
        let parts = body.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        components = parts.map { $0! }
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for i in 0..<count {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }

    var description: String { components.map(String.init).joined(separator: ".") }
}

/// The part of GitHub's `releases/latest` reply that Locant reads.
struct GitHubRelease: Decodable, Equatable, Sendable {
    struct Asset: Decodable, Equatable, Sendable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let htmlURL: URL
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }

    var version: AppVersion? { AppVersion(tagName) }

    /// The dmg to open from the alert, or the release page when the release carries none.
    var downloadURL: URL {
        assets.first { $0.name.lowercased().hasSuffix(".dmg") }?.browserDownloadURL ?? htmlURL
    }

    /// specs/in-app-update.md R177: the versioned dmg, the one the Homebrew cask uses. `Locant.dmg`
    /// is the same file under a stable name, but only the versioned name says which version it is.
    func installerAsset(version: AppVersion) -> URL? {
        assets.first { $0.name == "Locant-\(version).dmg" }?.browserDownloadURL
    }

    static func decode(_ data: Data) throws -> GitHubRelease {
        try JSONDecoder().decode(GitHubRelease.self, from: data)
    }
}

/// R45: the daily release check. The decision is pure; only `fetch` touches the network.
enum UpdateCheck {
    static let endpoint = URL(string: "https://api.github.com/repos/Malik1942/locant/releases/latest")!
    static let interval: TimeInterval = 24 * 60 * 60
    static let timeout: TimeInterval = 15
    /// After `AppState.start()`, so the check never races the permission alerts or the Help window.
    static let launchDelay: Duration = .seconds(10)

    enum Outcome: Equatable, Sendable {
        /// A newer release the user has not skipped.
        case available(GitHubRelease)
        case upToDate
        /// Newer, but `skippedUpdateVersion` names it; only Check Now shows it.
        case skipped(GitHubRelease)
    }

    /// The installed version, from the bundle; nil in a test host without one.
    static var currentVersion: AppVersion? {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
    }

    /// Whether the daily check is due: never checked, or the last check is `interval` or more ago.
    static func isDue(lastCheck: Date?, now: Date = .now) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    /// What to do with the newest release, given the installed version and the one the user skipped.
    static func outcome(latest: GitHubRelease, current: AppVersion, skipped: String?) -> Outcome {
        guard let newest = latest.version, current < newest else { return .upToDate }
        if let skipped, let skippedVersion = AppVersion(skipped), skippedVersion == newest { return .skipped(latest) }
        return .available(latest)
    }

    /// The one request Locant makes: the version number in the User-Agent, nothing else.
    static func request(current: AppVersion?) -> URLRequest {
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Locant/\(current.map(\.description) ?? "unknown")", forHTTPHeaderField: "User-Agent")
        return request
    }

    enum FetchError: Error, Equatable {
        case badStatus(Int)
        case notHTTP
    }

    /// Fetch the newest release. Throws on any failure; the caller stays silent.
    static func fetch(current: AppVersion?) async throws -> GitHubRelease {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request(current: current))
        guard let http = response as? HTTPURLResponse else { throw FetchError.notHTTP }
        guard (200..<300).contains(http.statusCode) else { throw FetchError.badStatus(http.statusCode) }
        return try GitHubRelease.decode(data)
    }
}
