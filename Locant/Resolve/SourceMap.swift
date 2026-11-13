import Foundation

/// One frame of a stack React recorded in the page, in the built code's own lines (specs/web-source.md R152).
struct StackFrame: Codable, Sendable, Equatable {
    var fn: String
    var url: String
    var line: Int
    var column: Int
}

/// A source map (revision 3): built line and column to the line as written. Flat maps, and the
/// sectioned index maps Turbopack writes. Read here, in Locant, so the page fetches nothing.
struct SourceMap: Sendable {
    struct Position: Equatable, Sendable {
        /// The source as the map names it, joined with the map's `sourceRoot`.
        var source: String
        var line: Int
        var column: Int
        /// The map's own `ignoreList` names this source: a library, not the user's code.
        var ignored: Bool
    }

    private struct Section: Sendable {
        var line: Int
        var column: Int
        var map: SourceMap
    }

    private var sources: [String] = []
    private var ignored: Set<Int> = []
    private var lines: [Substring] = []
    private var sections: [Section] = []

    init?(json: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
        self.init(object: object, depth: 0)
    }

    private init?(object: [String: Any], depth: Int) {
        if let list = object["sections"] as? [[String: Any]] {
            guard depth < 2 else { return nil }
            for entry in list {
                guard let offset = entry["offset"] as? [String: Any], let line = offset["line"] as? Int,
                      let column = offset["column"] as? Int, let inner = entry["map"] as? [String: Any],
                      let map = SourceMap(object: inner, depth: depth + 1) else { continue }
                sections.append(Section(line: line, column: column, map: map))
            }
            guard !sections.isEmpty else { return nil }
            sections.sort { ($0.line, $0.column) < ($1.line, $1.column) }
            return
        }
        guard let mappings = object["mappings"] as? String, let names = object["sources"] as? [Any] else { return nil }
        let root = (object["sourceRoot"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        sources = names.map { name in
            guard let name = name as? String else { return "" }
            guard let root, !name.hasPrefix("/"), !name.contains("://") else { return name }
            return root.hasSuffix("/") ? root + name : root + "/" + name
        }
        let list = (object["ignoreList"] ?? object["x_google_ignoreList"]) as? [Int] ?? []
        ignored = Set(list)
        lines = mappings.split(separator: ";", omittingEmptySubsequences: false)
    }

    /// One-based built line and column to the one-based place as written. Nil where the map says nothing.
    func position(line: Int, column: Int) -> Position? {
        guard line >= 1, column >= 1 else { return nil }
        if !sections.isEmpty {
            // The last section that starts at or before the place; its map counts from the section's start.
            guard let section = sections.last(where: { ($0.line, $0.column) <= (line - 1, column - 1) }) else { return nil }
            let innerColumn = line - 1 == section.line ? column - section.column : column
            return section.map.position(line: line - section.line, column: innerColumn)
        }
        guard line <= lines.count else { return nil }
        var source = 0, originalLine = 0, originalColumn = 0
        var best: (source: Int, line: Int, column: Int)?
        for index in 0..<line {
            var builtColumn = 0
            for segment in lines[index].split(separator: ",") {
                let fields = Self.decode(segment)
                guard let first = fields.first else { continue }
                builtColumn += first
                guard fields.count >= 4 else { continue }
                source += fields[1]; originalLine += fields[2]; originalColumn += fields[3]
                if index == line - 1, builtColumn <= column - 1 { best = (source, originalLine, originalColumn) }
            }
        }
        guard let best, sources.indices.contains(best.source), !sources[best.source].isEmpty else { return nil }
        return Position(source: sources[best.source], line: best.line + 1, column: best.column + 1, ignored: ignored.contains(best.source))
    }

    /// The numbers of one mapping segment: base64 digits, five bits each, the sixth meaning "more", the lowest the sign.
    static func decode(_ segment: Substring) -> [Int] {
        var out: [Int] = [], shift = 0, value = 0
        for byte in segment.utf8 {
            let digit: Int
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"): digit = Int(byte - UInt8(ascii: "A"))
            case UInt8(ascii: "a")...UInt8(ascii: "z"): digit = Int(byte - UInt8(ascii: "a")) + 26
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = Int(byte - UInt8(ascii: "0")) + 52
            case UInt8(ascii: "+"): digit = 62
            case UInt8(ascii: "/"): digit = 63
            default: return out
            }
            value += (digit & 31) << shift
            if digit & 32 != 0 {
                shift += 5
                guard shift < 60 else { return out }
                continue
            }
            out.append(value & 1 == 1 ? -(value >> 1) : value >> 1)
            shift = 0; value = 0
        }
        return out
    }
}

/// Turns the stacks a page reported into source lines: fetches each module and its map from the dev
/// server the page came from, never from anywhere else, and picks the first frame that is the user's.
/// One of these lives for one lookup, so a module edited since the last capture is read again.
actor WebSourceMaps {
    typealias Fetch = @Sendable (URL) async -> String?

    private let page: URL
    private let scripts: [String]
    private let fetch: Fetch
    private var texts: [String: String?] = [:]
    private var maps: [String: Loaded] = [:]

    /// What a built module offered: a map, the fact that it has none (its lines are the source's own),
    /// or nothing Locant could read.
    private enum Loaded {
        case map(SourceMap, base: URL?)
        case unmapped
        case unreadable
    }

    init(page: URL, scripts: [String] = [], fetch: @escaping Fetch = WebSourceMaps.fetchText) {
        self.page = page
        self.scripts = scripts
        self.fetch = fetch
    }

    /// How many frames past the JSX runtime are tried before giving up.
    static let candidateLimit = 4

    /// The place in the user's code where the stack's JSX ran. Nil when no frame maps to one.
    func location(of stack: [StackFrame]) async -> SourceLocation? {
        for frame in stack.filter({ !Self.isRuntime($0) }).prefix(Self.candidateLimit) {
            switch await loaded(for: frame.url) {
            case .map(let map, let base):
                guard let position = map.position(line: frame.line, column: frame.column) else { continue }
                let file = Self.file(named: position.source, base: base, page: page)
                if position.ignored || Self.isLibrary(file) { continue }
                return SourceLocation(file: file, line: position.line, column: position.column)
            case .unmapped:
                guard let url = URL(string: frame.url), Self.isLocal(url) else { continue }
                return SourceLocation(file: url.path(percentEncoded: false), line: frame.line, column: frame.column)
            case .unreadable:
                continue
            }
        }
        return nil
    }

    // MARK: Which frames

    private static let runtimeFunctions: Set<String> = [
        "jsxDEV", "jsx", "jsxs", "createElement", "cloneElement", "fakeJSXCallSite", "react_stack_bottom_frame",
    ]

    /// React's own frames: the JSX runtime's call on top (bundlers put it in the app's chunk, so its
    /// address alone does not tell), and anything under node_modules or a React package.
    static func isRuntime(_ frame: StackFrame) -> Bool {
        let name = frame.fn.split(whereSeparator: { $0 == "." || $0 == " " }).last.map(String.init) ?? ""
        if runtimeFunctions.contains(name) { return true }
        return isLibrary(frame.url)
    }

    static func isLibrary(_ address: String) -> Bool {
        ["/node_modules/", "react-dom", "react_jsx", "jsx-dev-runtime", "jsx-runtime", "/@react-refresh", "react-server-dom"]
            .contains { address.contains($0) }
    }

    // MARK: Loading

    private func loaded(for address: String) async -> Loaded {
        if let known = maps[address] { return known }
        let result = await load(address)
        maps[address] = result
        return result
    }

    private func load(_ address: String) async -> Loaded {
        if address.hasPrefix("webpack-internal:") { return await loadEvaluated(address) }
        guard let url = URL(string: address), Self.isLocal(url), let code = await text(at: url) else { return .unreadable }
        guard let reference = Self.mapReference(in: code) else { return .unmapped }
        if let inline = Self.inlineMap(reference) {
            return SourceMap(json: inline).map { .map($0, base: url) } ?? .unreadable
        }
        guard let mapURL = URL(string: reference, relativeTo: url)?.absoluteURL, Self.isLocal(mapURL),
              let json = await text(at: mapURL), let map = SourceMap(json: Data(json.utf8)) else { return .unreadable }
        return .map(map, base: mapURL)
    }

    /// webpack's eval source maps: each module is a string inside a chunk, evaluated under a
    /// `webpack-internal:` name, with its map inline just before that name.
    private func loadEvaluated(_ address: String) async -> Loaded {
        for script in scripts {
            guard let url = URL(string: script), Self.isLocal(url), url.host() == page.host(), url.port == page.port,
                  let code = await text(at: url), let inline = Self.evaluatedMap(for: address, in: code) else { continue }
            return SourceMap(json: inline).map { .map($0, base: nil) } ?? .unreadable
        }
        return .unreadable
    }

    private func text(at url: URL) async -> String? {
        let key = url.absoluteString
        if let known = texts[key] { return known }
        let value = await fetch(url)
        texts[key] = value
        return value
    }

    /// Only the Mac's own dev servers are asked: the rule that makes a page local (R151).
    static func isLocal(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        return ModeInference.isLocalhost(url.host())
    }

    /// The module's last `sourceMappingURL` comment.
    static func mapReference(in code: String) -> String? {
        guard let marker = code.range(of: "sourceMappingURL=", options: .backwards) else { return nil }
        // The comment closes the file; the same words inside a string earlier in it are not a reference.
        let tail = code[marker.upperBound...]
        let reference = tail.prefix { !$0.isWhitespace }
        guard !reference.isEmpty, tail[reference.endIndex...].allSatisfy(\.isWhitespace),
              !reference.contains(where: { $0 == "\"" || $0 == "'" || $0 == "\\" }) else { return nil }
        return String(reference)
    }

    static func inlineMap(_ reference: String) -> Data? {
        guard reference.hasPrefix("data:application/json"), let comma = reference.firstIndex(of: ","),
              reference[..<comma].hasSuffix(";base64") else { return nil }
        return Data(base64Encoded: String(reference[reference.index(after: comma)...]))
    }

    static func evaluatedMap(for address: String, in chunk: String) -> Data? {
        guard let name = chunk.range(of: "sourceURL=" + address + "\\n"),
              let marker = chunk.range(of: "sourceMappingURL=", options: .backwards, range: chunk.startIndex..<name.lowerBound) else { return nil }
        // Nothing but the map's own comment may sit between the two: another module's map is not this one's.
        let between = chunk[marker.upperBound..<name.lowerBound]
        guard !between.contains("sourceURL=") else { return nil }
        return inlineMap(String(between.prefix { $0 != "\\" && !$0.isWhitespace }))
    }

    // MARK: Names

    /// A map's source as a path: the file itself where the map says so, else the path the dev server
    /// serves it under (`/src/Library.tsx`), which `WebSourceLocator.absolutize` joins to the server's folder.
    static func file(named source: String, base: URL?, page: URL) -> String {
        if source.hasPrefix("file://") { return URL(string: source)?.path(percentEncoded: false) ?? source }
        if source.hasPrefix("/") { return source }
        for scheme in ["webpack://", "turbopack://"] where source.hasPrefix(scheme) {
            // webpack://name/./src/App.tsx, turbopack:///[project]/app/page.tsx: the path after the name.
            var path = source.dropFirst(scheme.count).drop { $0 != "/" }
            for prefix in ["/[project]", "/."] where path.hasPrefix(prefix + "/") { path = path.dropFirst(prefix.count) }
            return path.isEmpty ? source : String(path)
        }
        if source.contains("://"), !source.hasPrefix("http") { return source }
        guard let base, let resolved = URL(string: source, relativeTo: base)?.absoluteURL else { return source }
        let samePlace = resolved.host() == page.host() && resolved.port == page.port
        return samePlace ? resolved.path(percentEncoded: false) : resolved.absoluteString
    }

    // MARK: The network

    static let fetchLimit = 40_000_000

    static let fetchText: Fetch = { url in
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 3)
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count <= fetchLimit else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()
}
