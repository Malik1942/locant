import Foundation

/// specs/source-hints.md R151–R155: where the pointed-at element's own strings sit in the project's source,
/// looked up by Locant at capture time so the agent starts at a file and line.
struct SourceHint: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable {
        /// The element's strings are in exactly one file.
        case only
        /// In several files, and one of them also holds other text from the capture.
        case likeliest
        /// In several files, and nothing in the capture tells them apart.
        case several
        /// The element's own strings are in no file; fixed text beside it is.
        case beside
        /// Looked, and nothing matched.
        case none
    }

    var kind: Kind
    /// The strings that were found; for `none`, the ones looked for. The element's own for `only`,
    /// `likeliest`, `several`, and `none`; the neighbors' for `beside`.
    var strings: [String]
    /// Best first, at most `SourceHints.listLimit`. Paths are relative to the project folder.
    var places: [SourcePlace]
    /// How many files matched in all.
    var fileCount: Int
    /// `likeliest`: the other text from the capture that the first place's file also holds.
    var alsoThere: [String]? = nil

    private enum CodingKeys: String, CodingKey { case kind, strings, places, fileCount, alsoThere }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(strings, forKey: .strings)
        try c.encode(places, forKey: .places)
        try c.encode(fileCount, forKey: .fileCount)
        try c.encodeIfPresent(alsoThere, forKey: .alsoThere)
    }
}

struct SourcePlace: Codable, Sendable, Equatable {
    var file: String
    var lines: [Int]
}

enum SourceHints {
    /// What to look for: the element's own strings, and the text around it that can tell files apart.
    struct Query: Sendable, Equatable {
        var anchors: [String]
        var context: [String]
    }

    /// One needle found in one file.
    struct Hit: Sendable, Equatable {
        var needle: String
        var file: String
        var lines: [Int]
    }

    static let listLimit = 6
    static let anchorLimit = 6
    static let contextLimit = 40
    static let maxLength = 80
    /// A context string this short is matched whole; a longer one by its start, since text read from the
    /// image is often cut off.
    static let wholeMatchBelow = 6
    static let fileLimit = 8000
    static let maxFileBytes = 1_000_000
    static let budget: TimeInterval = 0.8

    static let extensions: Set<String> = [
        "swift", "m", "mm", "h", "kt", "java", "dart", "xib", "storyboard",
    ]
    /// Folders that hold builds or other people's code. Hidden folders (.git, .build, .claude) are skipped too.
    static let skippedFolders: Set<String> = [
        "node_modules", "build", "Build", "DerivedData", "Pods", "Carthage", "dist", "vendor", "Vendor",
    ]

    // MARK: Query

    /// R152. `neighbors` are labels read around the element (its siblings on screen, the other elements of a
    /// set or a frame); `ocr` is the text read from the image.
    static func query(for element: ResolvedElement, neighbors: [String], ocr: String?) -> Query? {
        guard element.dom == nil else { return nil } // web nodes have their own handles (v0.8)
        var anchors: [String] = []
        if let identifier = element.identifier, !identifier.hasPrefix("_Tt") { anchors.append(identifier) }
        anchors.append(contentsOf: variants(of: element.label))
        anchors = unique(anchors.compactMap(clean)).prefix(anchorLimit).map { $0 }

        var context = (element.members ?? []).compactMap(\.label) + neighbors
        for line in (ocr ?? "").split(separator: "\n") {
            context.append(String(line))
            // An icon before the words is read as a glyph or a letter or two ("•ll Transcript",
            // "Q Search the Ocean"); neither is in the source.
            let words = line.drop { !$0.isLetter }
            context.append(String(words))
            if let space = words.firstIndex(of: " "), words.distance(from: words.startIndex, to: space) <= 2 {
                context.append(String(words[words.index(after: space)...]))
            }
        }
        let own = Set(anchors)
        context = unique(context.flatMap(variants).compactMap(clean))
            .filter { !own.contains($0) && $0.count >= 3 }
            .prefix(contextLimit).map { $0 }
        guard !anchors.isEmpty || !context.isEmpty else { return nil }
        return Query(anchors: anchors, context: context)
    }

    /// The label, and its parts when SwiftUI merged several texts with ", ".
    static func variants(of label: String?) -> [String] {
        guard let label, !label.isEmpty else { return [] }
        let parts = label.components(separatedBy: ", ")
        return parts.count > 1 ? [label] + parts : [label]
    }

    /// Nil for what cannot be a plain string literal, or is too short or long to be worth a search.
    static func clean(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.count <= maxLength else { return nil }
        guard !trimmed.contains(where: { $0 == "\"" || $0 == "\\" || $0.isNewline }) else { return nil }
        return trimmed
    }

    private static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }

    /// An anchor is searched as a whole string literal; context by its start unless it is short.
    static func needle(anchor: String) -> String { "\"\(anchor)\"" }
    static func needle(context: String) -> String { context.count < wholeMatchBelow ? "\"\(context)\"" : "\"\(context)" }

    // MARK: Search

    /// R153. Nil when the folder could not be read to the end in time: an unfinished search proves nothing.
    static func find(_ query: Query, in root: URL, now: () -> Date = Date.init,
                     budget: TimeInterval = SourceHints.budget, fileLimit: Int = SourceHints.fileLimit) -> SourceHint? {
        let needles = unique(query.anchors.map(needle(anchor:)) + query.context.map(needle(context:)))
        guard let hits = scan(root: root, needles: needles, deadline: now().addingTimeInterval(budget), now: now, fileLimit: fileLimit)
        else { return nil }
        return rank(query, hits: hits)
    }

    static func scan(root: URL, needles: [String], deadline: Date, now: () -> Date = Date.init,
                     fileLimit: Int = SourceHints.fileLimit) -> [Hit]? {
        guard !needles.isEmpty else { return [] }
        let base = root.standardizedFileURL.path(percentEncoded: false)
        let prefix = base.hasSuffix("/") ? base : base + "/"
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }
        var hits: [Hit] = []
        var seen = 0
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true {
                if skippedFolders.contains(url.lastPathComponent) { walker.skipDescendants() }
                continue
            }
            guard extensions.contains(url.pathExtension.lowercased()) else { continue }
            seen += 1
            if seen > fileLimit || (seen % 32 == 0 && now() > deadline) { return nil }
            guard (values?.fileSize ?? 0) <= maxFileBytes, let data = try? Data(contentsOf: url) else { continue }
            let text = String(decoding: data, as: UTF8.self)
            let found = needles.filter { text.contains($0) }
            guard !found.isEmpty else { continue }
            let path = url.standardizedFileURL.path(percentEncoded: false)
            let file = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
            var lines: [String: [Int]] = [:]
            var number = 0
            text.enumerateLines { line, _ in
                number += 1
                for needle in found where line.contains(needle) { lines[needle, default: []].append(number) }
            }
            for needle in found { hits.append(Hit(needle: needle, file: file, lines: lines[needle] ?? [])) }
        }
        return now() > deadline ? nil : hits
    }

    // MARK: Rank

    /// R154. Pure: the hits of one finished search, turned into what the payload says.
    static func rank(_ query: Query, hits: [Hit]) -> SourceHint? {
        func files(_ needle: String) -> [String: [Int]] {
            Dictionary(hits.filter { $0.needle == needle }.map { ($0.file, $0.lines) }, uniquingKeysWith: { a, _ in a })
        }
        let anchorFiles = query.anchors.map { ($0, files(needle(anchor: $0))) }
        let contextFiles = query.context.map { ($0, files(needle(context: $0))) }.filter { !$0.1.isEmpty }
        let found = anchorFiles.filter { !$0.1.isEmpty }

        guard !found.isEmpty else { return besideOrNone(query, contextFiles: contextFiles) }

        var score: [String: Int] = [:]
        var lines: [String: [Int]] = [:]
        var also: [String: [String]] = [:]
        for (_, byFile) in found {
            for (file, at) in byFile {
                score[file, default: 0] += 10
                if lines[file] == nil { lines[file] = at }
            }
        }
        for (text, byFile) in contextFiles {
            for file in byFile.keys where score[file] != nil {
                score[file, default: 0] += 1
                also[file, default: []].append(text)
            }
        }
        let ranked = score.keys.sorted { (score[$0]!, $1) > (score[$1]!, $0) }
        let strings = found.map(\.0)
        func place(_ file: String) -> SourcePlace { SourcePlace(file: file, lines: Array((lines[file] ?? []).prefix(3))) }
        if ranked.count == 1 {
            return SourceHint(kind: .only, strings: strings, places: [place(ranked[0])], fileCount: 1)
        }
        if score[ranked[0]]! > score[ranked[1]]! {
            return SourceHint(kind: .likeliest, strings: strings, places: ranked.prefix(listLimit).map(place),
                              fileCount: ranked.count, alsoThere: Array((also[ranked[0]] ?? []).prefix(2)))
        }
        return SourceHint(kind: .several, strings: strings, places: ranked.prefix(listLimit).map(place), fileCount: ranked.count)
    }

    private static func besideOrNone(_ query: Query, contextFiles: [(String, [String: [Int]])]) -> SourceHint? {
        // One file that holds more of the surrounding text than any other.
        var held: [String: [(String, Int)]] = [:]
        for (text, byFile) in contextFiles {
            for (file, at) in byFile { held[file, default: []].append((text, at.first ?? 0)) }
        }
        let byCount = held.sorted { ($0.value.count, $1.key) > ($1.value.count, $0.key) }
        if let top = byCount.first, top.value.count >= 2, byCount.count == 1 || top.value.count > byCount[1].value.count {
            let at = top.value.map(\.1).filter { $0 > 0 }.sorted()
            return SourceHint(kind: .beside, strings: Array(top.value.map(\.0).prefix(3)),
                              places: [SourcePlace(file: top.key, lines: Array(at.prefix(3)))], fileCount: 1)
        }
        // Else the rarest neighbor, when it is in few enough files to list.
        if let rarest = contextFiles.min(by: { ($0.1.count, $0.0) < ($1.1.count, $1.0) }), rarest.1.count <= 3 {
            let places = rarest.1.keys.sorted().map { SourcePlace(file: $0, lines: Array((rarest.1[$0] ?? []).prefix(3))) }
            return SourceHint(kind: .beside, strings: [rarest.0], places: places, fileCount: places.count)
        }
        guard !query.anchors.isEmpty else { return nil }
        return SourceHint(kind: .none, strings: Array(query.anchors.prefix(2)), places: [], fileCount: 0)
    }

    // MARK: Capture

    /// R151: every pointed-at element of a fix capture gets its hint from one walk of the project folder.
    /// The capture comes back unchanged when the walk did not finish.
    static func annotate(_ capture: Capture, root: URL, neighbors: [String], now: () -> Date = Date.init,
                         budget: TimeInterval = SourceHints.budget) -> Capture {
        var subjects = capture.targets?.map(\.element) ?? capture.element.map { [$0] } ?? []
        guard !subjects.isEmpty else { return capture }
        let around = (capture.elements ?? []).compactMap(\.label) + (capture.nearby ?? []).compactMap(\.label) + neighbors
        let queries = subjects.indices.map { index in
            let others = subjects.indices.filter { $0 != index }.compactMap { subjects[$0].label }
            return query(for: subjects[index], neighbors: others + around, ocr: capture.ocr)
        }
        let needles = unique(queries.compactMap { $0 }.flatMap { $0.anchors.map(needle(anchor:)) + $0.context.map(needle(context:)) })
        guard !needles.isEmpty,
              let hits = scan(root: root, needles: needles, deadline: now().addingTimeInterval(budget), now: now)
        else { return capture }
        for index in subjects.indices { subjects[index].sourceHint = queries[index].flatMap { rank($0, hits: hits) } }
        var capture = capture
        capture.element = subjects[0]
        if capture.targets != nil {
            for index in subjects.indices { capture.targets![index].element = subjects[index] }
        }
        return capture
    }

    // MARK: Neighbors

    /// R152: the labels of what sits around an element on screen, nearest first. In Device Hub the device's
    /// screen is one flat list, so these are the screen's own words: the title, the tabs, the button beside.
    static func neighborLabels(of frame: Frame, among nodes: [AttributeSet], limit: Int = 24) -> [String] {
        let (cx, cy) = (frame.x + frame.w / 2, frame.y + frame.h / 2)
        func distance(_ node: AttributeSet) -> Double {
            guard let f = node.frame else { return .greatestFiniteMagnitude }
            return hypot(f.x + f.w / 2 - cx, f.y + f.h / 2 - cy)
        }
        let labels = nodes.sorted { distance($0) < distance($1) }
            .compactMap { ElementResolver.nonEmpty($0.title) ?? ElementResolver.nonEmpty($0.description) }
        return Array(unique(labels).prefix(limit))
    }
}
