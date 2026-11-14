import Foundation

/// specs/source-hints.md R157–R172: where the pointed-at element's own strings sit in the project's source,
/// looked up by Locant while the note is typed so the agent starts at a file and line.
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
    /// Best first, at most `SourceHints.listLimit`. Paths are relative to the project folder; for a web
    /// node, which has no Project line, they are absolute.
    var places: [SourcePlace]
    /// How many files matched in all.
    var fileCount: Int
    /// `likeliest`: the other text from the capture that the first place's file also holds.
    var alsoThere: [String]? = nil
    /// R164: a file that holds two or more of the strings around the element and none of its own: the
    /// view that draws a row whose words are defined elsewhere.
    var around: SourceAround? = nil
    /// R165: the strings above that are keys of a string catalog, with the text that was on screen.
    var localized: [LocalizedString]? = nil
    /// R172: `strings` are a web node's classes and every line listed holds all of them at once.
    var together: Bool? = nil

    private enum CodingKeys: String, CodingKey { case kind, strings, places, fileCount, alsoThere, around, localized, together }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(strings, forKey: .strings)
        try c.encode(places, forKey: .places)
        try c.encode(fileCount, forKey: .fileCount)
        try c.encodeIfPresent(alsoThere, forKey: .alsoThere)
        try c.encodeIfPresent(around, forKey: .around)
        try c.encodeIfPresent(localized, forKey: .localized)
        try c.encodeIfPresent(together, forKey: .together)
    }
}

struct SourcePlace: Codable, Sendable, Equatable {
    var file: String
    var lines: [Int]
}

struct SourceAround: Codable, Sendable, Equatable {
    var strings: [String]
    var place: SourcePlace
}

/// R165: `shown` was on screen; `key` is what the code says; `table` is the catalog that maps one to the other.
struct LocalizedString: Codable, Sendable, Equatable, Hashable {
    var shown: String
    var key: String
    var table: String
}

/// R167: where an element sits among the siblings that look like it, counted on screen.
struct RowPosition: Codable, Sendable, Equatable {
    enum Axis: String, Codable, Sendable { case column, row }
    /// 1-based, top to bottom in a column, left to right in a row.
    var index: Int
    var count: Int
    var axis: Axis
}

enum SourceHints {
    /// What to look for: the element's own strings, and the text around it that can tell files apart.
    struct Query: Sendable, Equatable {
        var anchors: [String]
        var context: [String]
        /// R166: a web node's handles are words inside longer strings (`className="card card-caption"`).
        var web = false
        /// R166: the web node's `id` attribute, which counts however many files hold it; `anchors` are its classes.
        var id: String? = nil
    }

    /// How a string must sit in a line to count.
    struct Needle: Hashable, Sendable {
        enum Kind: Sendable { case literal, literalStart, token }
        var text: String
        var kind: Kind

        func matches(_ line: Substring) -> Bool {
            switch kind {
            case .literal: return line.contains("\"\(text)\"")
            case .literalStart: return line.contains("\"\(text)")
            case .token:
                var from = line.startIndex
                while let found = line.range(of: text, range: from..<line.endIndex) {
                    let before = found.lowerBound == line.startIndex ? nil : line[line.index(before: found.lowerBound)]
                    let after = found.upperBound == line.endIndex ? nil : line[found.upperBound]
                    if !Self.joins(before), !Self.joins(after) { return true }
                    from = found.upperBound
                }
                return false
            }
        }

        /// A character that would make the match part of a longer name: `card` inside `card-caption`.
        private static func joins(_ c: Character?) -> Bool {
            guard let c else { return false }
            return c.isLetter || c.isNumber || c == "_" || c == "-"
        }
    }

    /// One needle found in one file.
    struct Hit: Sendable, Equatable {
        var needle: Needle
        var file: String
        var lines: [Int]
    }

    static let listLimit = 6
    static let staticTextRole = "AXStaticText"
    static let anchorLimit = 6
    static let contextLimit = 40
    static let classLimit = 8
    static let maxLength = 80
    /// A context string this short is matched whole; a longer one by its start, since text read from the
    /// image is often cut off.
    static let wholeMatchBelow = 6
    static let fileLimit = 8000
    static let maxFileBytes = 1_000_000
    static let maxCatalogBytes = 8_000_000
    static let maxCorpusBytes = 64_000_000
    static let budget: TimeInterval = 0.8
    /// R163: the folder is read from the click on; at Enter the capture waits this much longer for it.
    static let commitWait: Duration = .milliseconds(300)
    /// R166: a class in more files than this is a utility (`flex`, `card`), not a handle.
    static let utilityFileCount = 8
    /// R172: a class list this long, written out whole on one line, is a fingerprint.
    static let togetherAtLeast = 2

    static let nativeExtensions: Set<String> = ["swift", "m", "mm", "h", "kt", "java", "dart", "xib", "storyboard"]
    static let webExtensions: Set<String> = ["tsx", "jsx", "ts", "js", "mjs", "vue", "svelte", "astro", "html", "mdx", "css", "scss"]
    static let catalogExtensions: Set<String> = ["xcstrings", "strings"]
    /// Folders that hold builds or other people's code. Folders whose name starts with a dot (.git, .build,
    /// .next, .claude) are skipped too, wherever the project itself sits.
    static let skippedFolders: Set<String> = [
        "node_modules", "build", "Build", "DerivedData", "Pods", "Carthage", "dist", "vendor", "Vendor", "out", "coverage",
    ]

    // MARK: Query

    /// R158. `neighbors` are labels read around the element (its siblings on screen, the other elements of a
    /// set or a frame); `ocr` is the text read from the image.
    static func query(for element: ResolvedElement, neighbors: [String], ocr: String?) -> Query? {
        // R166: a web node the page already located needs no search.
        if element.dom != nil, element.component?.source != nil { return nil }
        if let dom = element.dom {
            // A page's words are mostly data, and the text around a node says little about which file draws
            // it. Only the node's own handles and its own text are looked for.
            // R171: a text node has no id or class; the element that holds it does, and that is what the
            // markup names.
            let own = dom.id != nil || !dom.classes.isEmpty
            let id = (own ? dom.id : dom.parent?.id).flatMap(clean)
            let classes = unique((own ? dom.classes : dom.parent?.classes ?? []).compactMap(clean))
                .filter { $0 != id }.prefix(classLimit).map { $0 }
            var words: [String] = []
            if let label = element.label { words.append(label) }
            if case .string(let text)? = element.value { words.append(text) }
            words = unique(words.compactMap(clean)).filter(hasWords)
            guard id != nil || !classes.isEmpty || !words.isEmpty else { return nil }
            return Query(anchors: classes, context: words, web: true, id: id)
        }
        var anchors: [String] = []
        if let identifier = element.identifier, !identifier.hasPrefix("_Tt") { anchors.append(identifier) }
        anchors.append(contentsOf: variants(of: element.label))
        // On the Mac a text's words are its value, not its label.
        if element.label == nil, element.rawRole == staticTextRole, case .string(let text)? = element.value { anchors.append(text) }
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
            .filter { !own.contains($0) && hasWords($0) }
            .prefix(contextLimit).map { $0 }
        guard !anchors.isEmpty || !context.isEmpty else { return nil }
        return Query(anchors: anchors, context: context)
    }

    /// Three letters at least: "9:41", "2025" and "..." are on every screen and say nothing about a file.
    static func hasWords(_ text: String) -> Bool { text.count >= 3 && text.filter(\.isLetter).count >= 3 }

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

    private static func unique<T: Hashable>(_ items: [T]) -> [T] {
        var seen = Set<T>()
        return items.filter { seen.insert($0).inserted }
    }

    /// An anchor is searched as a whole string literal; context by its start unless it is short. A web
    /// node's id, classes and text are whole words anywhere in a line (R166).
    static func needle(anchor: String, web: Bool = false) -> Needle { Needle(text: anchor, kind: web ? .token : .literal) }
    static func needle(context: String, web: Bool = false) -> Needle {
        Needle(text: context, kind: web ? .token : context.count < wholeMatchBelow ? .literal : .literalStart)
    }

    // MARK: Corpus

    /// R163: the project's source, read once at the click so that Enter only has to search what is in memory.
    struct Corpus: Sendable {
        struct File: Sendable {
            var path: String
            var web: Bool
            /// A stylesheet says how a class looks, not what draws the element; markup is listed before it.
            var style: Bool
            var data: Data
        }

        var root: String
        var files: [File]
        /// R165: text on screen → the keys the code uses for it.
        var keys: [String: [LocalizedString]]

        /// Nil when the folder could not be read to the end in time: an unfinished search proves nothing.
        static func load(root: URL, now: () -> Date = Date.init, budget: TimeInterval = SourceHints.budget,
                         fileLimit: Int = SourceHints.fileLimit) -> Corpus? {
            let deadline = now().addingTimeInterval(budget)
            let base = root.standardizedFileURL.path(percentEncoded: false)
            let prefix = base.hasSuffix("/") ? base : base + "/"
            // Not `.skipsHiddenFiles`: under a hidden folder (a worktree in `.claude/worktrees/…`) that option
            // hides every file, and a project read as empty would be reported as holding nothing. Dot
            // names are skipped by hand, below the root only.
            guard let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsPackageDescendants]
            ) else { return nil }
            var files: [File] = []
            var keys: [String: [LocalizedString]] = [:]
            var seen = 0
            var bytes = 0
            for case let url as URL in walker {
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                let name = url.lastPathComponent
                if values?.isDirectory == true {
                    if name.hasPrefix(".") || skippedFolders.contains(name) || isTestFolder(name) { walker.skipDescendants() }
                    continue
                }
                if name.hasPrefix(".") || name.hasSuffix("Tests.swift") { continue }
                let kind = url.pathExtension.lowercased()
                let catalog = catalogExtensions.contains(kind)
                let web = webExtensions.contains(kind)
                guard catalog || web || nativeExtensions.contains(kind) else { continue }
                if web, isTestOrGenerated(url.lastPathComponent) { continue }
                seen += 1
                if seen > fileLimit || (seen % 32 == 0 && now() > deadline) { return nil }
                let size = values?.fileSize ?? 0
                guard size <= (catalog ? maxCatalogBytes : maxFileBytes), let data = try? Data(contentsOf: url) else { continue }
                if catalog {
                    for entry in Catalogs.entries(in: data, kind: kind, table: url.lastPathComponent) where entry.shown != entry.key {
                        if keys[entry.shown]?.contains(entry) != true { keys[entry.shown, default: []].append(entry) }
                    }
                    continue
                }
                bytes += data.count
                if bytes > maxCorpusBytes { return nil }
                let path = url.standardizedFileURL.path(percentEncoded: false)
                files.append(File(path: path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path, web: web,
                                  style: kind == "css" || kind == "scss", data: data))
            }
            return now() > deadline ? nil : Corpus(root: base, files: files, keys: keys)
        }

        /// Every needle's lines, file by file. Native needles look in native files, a web node's in web files.
        func hits(for needles: [Needle], web: Bool) -> [Hit] {
            guard !needles.isEmpty else { return [] }
            var hits: [Hit] = []
            // Bytes first: most files hold none of the needles, and a byte search is many times faster
            // than a string's. Only a file that holds one is split into lines.
            let patterns = needles.map { ($0, Data($0.text.utf8)) }
            for file in files where file.web == web {
                let found = patterns.filter { file.data.range(of: $0.1) != nil }.map(\.0)
                guard !found.isEmpty else { continue }
                var lines: [Needle: [Int]] = [:]
                var number = 0
                for line in String(decoding: file.data, as: UTF8.self).split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
                    number += 1
                    for needle in found where needle.matches(line) { lines[needle, default: []].append(number) }
                }
                for needle in found { if let at = lines[needle] { hits.append(Hit(needle: needle, file: file.path, lines: at)) } }
            }
            return hits
        }
    }

    /// `LocantTests`, `AppUITests`, `__tests__`: tests repeat the app's words without drawing them.
    static func isTestFolder(_ name: String) -> Bool { name.hasSuffix("Tests") || name == "__tests__" }

    /// `Card.test.tsx`, `types.d.ts`, `app.min.js`: files that repeat the app's words without drawing them.
    static func isTestOrGenerated(_ name: String) -> Bool {
        let lower = name.lowercased()
        return [".test.", ".spec.", ".stories.", ".min.", ".d.ts"].contains { lower.contains($0) }
    }

    // MARK: Search

    /// R159. One element against a folder on disk; `annotate` shares one corpus between elements.
    static func find(_ query: Query, in root: URL, now: () -> Date = Date.init,
                     budget: TimeInterval = SourceHints.budget, fileLimit: Int = SourceHints.fileLimit) -> SourceHint? {
        guard let corpus = Corpus.load(root: root, now: now, budget: budget, fileLimit: fileLimit) else { return nil }
        return find(query, in: corpus)
    }

    static func find(_ query: Query, in corpus: Corpus) -> SourceHint? {
        // A folder with no source of this kind was not the project: say nothing sooner than "no such string".
        guard corpus.files.contains(where: { $0.web == query.web }) else { return nil }
        let (expanded, localized) = localize(query, keys: corpus.keys)
        let styles = Set(corpus.files.filter(\.style).map(\.path))
        return rank(expanded, hits: corpus.hits(for: needles(of: expanded), web: expanded.web), localized: localized, styles: styles)
    }

    static func needles(of query: Query) -> [Needle] {
        let anchors = (query.id.map { [$0] } ?? []) + query.anchors
        let quotedID = query.web ? (query.id.map { [needle(anchor: $0)] } ?? []) : []
        return unique(quotedID + anchors.map { needle(anchor: $0, web: query.web) } + query.context.map { needle(context: $0, web: query.web) })
    }

    /// R165: a string that is a translation is also looked for under its key.
    static func localize(_ query: Query, keys: [String: [LocalizedString]]) -> (Query, [LocalizedString]) {
        guard !keys.isEmpty, !query.web else { return (query, []) }
        var found: [LocalizedString] = []
        func expand(_ strings: [String], limit: Int) -> [String] {
            var out: [String] = []
            for text in strings {
                out.append(text)
                for entry in keys[text] ?? [] where clean(entry.key) != nil {
                    out.append(entry.key)
                    found.append(entry)
                }
            }
            return Array(unique(out).prefix(limit))
        }
        let anchors = expand(query.anchors, limit: anchorLimit * 2)
        let context = expand(query.context, limit: contextLimit * 2).filter { !anchors.contains($0) }
        return (Query(anchors: anchors, context: context, web: false), unique(found))
    }

    // MARK: Rank

    /// R160. Pure: the hits of one finished search, turned into what the payload says.
    static func rank(_ query: Query, hits: [Hit], localized: [LocalizedString] = [], styles: Set<String> = []) -> SourceHint? {
        func files(_ needle: Needle) -> [String: [Int]] {
            Dictionary(hits.filter { $0.needle == needle }.map { ($0.file, $0.lines) }, uniquingKeysWith: { a, _ in a })
        }
        var anchorFiles = query.anchors.map { ($0, files(needle(anchor: $0, web: query.web))) }
        let contextFiles = query.context.map { ($0, files(needle(context: $0, web: query.web))) }.filter { !$0.1.isEmpty }
        if query.web, query.id == nil, let hint = together(query, classFiles: anchorFiles, contextFiles: contextFiles, styles: styles) {
            return hint
        }
        var utilities = false
        if query.web {
            // R166: the id counts wherever it is; a class counts only while it is rare enough to be a handle.
            utilities = anchorFiles.contains { $0.1.count > utilityFileCount }
            anchorFiles = anchorFiles.filter { $0.1.count <= utilityFileCount }
            if let id = query.id {
                // An id that is also a plain word (`projects`) is in dozens of files as a word and in one as
                // `id="projects"`: the quoted string counts when it is anywhere, the bare word otherwise.
                let quoted = files(needle(anchor: id))
                anchorFiles.insert((id, quoted.isEmpty ? files(needle(anchor: id, web: true)) : quoted), at: 0)
            }
        }
        let found = anchorFiles.filter { !$0.1.isEmpty }
        func keys(for strings: [String]) -> [LocalizedString]? {
            let used = localized.filter { strings.contains($0.key) }
            return used.isEmpty ? nil : used
        }

        guard !found.isEmpty else {
            guard var hint = besideOrNone(query, contextFiles: contextFiles) else { return nil }
            // A class that is everywhere was found; saying "no such string" would be untrue, so say nothing.
            if hint.kind == .none, utilities { return nil }
            if hint.kind == .none, let id = query.id { hint.strings = Array(([id] + query.anchors).prefix(2)) }
            hint.localized = keys(for: hint.strings)
            return hint
        }

        var score: [String: Int] = [:]
        var lines: [String: [Int]] = [:]
        var also: [String: [String]] = [:]
        for (_, byFile) in found {
            for (file, at) in byFile {
                score[file, default: 0] += 10
                if lines[file] == nil { lines[file] = at }
            }
        }
        var elsewhere: [String: [(String, Int)]] = [:]
        for (text, byFile) in contextFiles {
            for (file, at) in byFile {
                if score[file] != nil {
                    score[file, default: 0] += 1
                    also[file, default: []].append(text)
                } else {
                    elsewhere[file, default: []].append((text, at.first ?? 0))
                }
            }
        }
        // Highest score first; on a tie markup before a stylesheet, then by path.
        func order(_ file: String) -> (Int, Int, String) { (-score[file]!, styles.contains(file) ? 1 : 0, file) }
        let ranked = score.keys.sorted { order($0) < order($1) }
        let strings = found.map(\.0)
        func place(_ file: String) -> SourcePlace { SourcePlace(file: file, lines: Array((lines[file] ?? []).prefix(3))) }
        var hint: SourceHint
        if ranked.count == 1 {
            hint = SourceHint(kind: .only, strings: strings, places: [place(ranked[0])], fileCount: 1)
        } else if score[ranked[0]]! > score[ranked[1]]! {
            hint = SourceHint(kind: .likeliest, strings: strings, places: ranked.prefix(listLimit).map(place),
                              fileCount: ranked.count, alsoThere: Array((also[ranked[0]] ?? []).prefix(2)))
        } else {
            hint = SourceHint(kind: .several, strings: strings, places: ranked.prefix(listLimit).map(place), fileCount: ranked.count)
        }
        // R164: the words of a menu row or a tab are often defined in one file and drawn in another. A file
        // with two or more of the surrounding strings, and more than the first place holds, is that other.
        let top = (also[ranked[0]] ?? []).count
        if !query.web, let other = elsewhere.max(by: { ($0.value.count, $1.key) < ($1.value.count, $0.key) }),
           other.value.count >= 2, other.value.count > top {
            let at = other.value.map(\.1).filter { $0 > 0 }.sorted()
            hint.around = SourceAround(strings: Array(other.value.map(\.0).prefix(3)),
                                       place: SourcePlace(file: other.key, lines: Array(at.prefix(3))))
        }
        hint.localized = keys(for: strings)
        return hint
    }

    /// R172: utility classes (Tailwind's) are each in every file, so none is a handle; the list an element
    /// carries is, where it is written out whole on one line. Whole, because a part of the list is shared:
    /// seven of a link's nine classes sat on one line of another component that copies its focus ring
    /// (malik-portfolio, Nov 13, 2026), and naming that file was wrong.
    private static func together(_ query: Query, classFiles: [(String, [String: [Int]])],
                                 contextFiles: [(String, [String: [Int]])], styles: Set<String>) -> SourceHint? {
        var onLine: [String: [Int: Set<String>]] = [:]
        for (name, byFile) in classFiles {
            for (file, at) in byFile where !styles.contains(file) {
                for line in at { onLine[file, default: [:]][line, default: []].insert(name) }
            }
        }
        let most = onLine.values.flatMap { $0.values.map(\.count) }.max() ?? 0
        guard most >= togetherAtLeast, most == query.anchors.count else { return nil }
        var lines: [String: [Int]] = [:]
        for (file, byLine) in onLine {
            let best = byLine.filter { $0.value.count == most }.keys.sorted()
            if !best.isEmpty { lines[file] = best }
        }
        guard lines.count <= utilityFileCount else { return nil }
        var also: [String: [String]] = [:]
        for (text, byFile) in contextFiles {
            for file in byFile.keys where lines[file] != nil { also[file, default: []].append(text) }
        }
        let ranked = lines.keys.sorted { (-(also[$0]?.count ?? 0), $0) < (-(also[$1]?.count ?? 0), $1) }
        let first = ranked[0]
        let held = onLine[first]?[lines[first]?.first ?? 0] ?? []
        let strings = query.anchors.filter(held.contains)
        func place(_ file: String) -> SourcePlace { SourcePlace(file: file, lines: Array((lines[file] ?? []).prefix(3))) }
        var hint: SourceHint
        if ranked.count == 1 {
            hint = SourceHint(kind: .only, strings: strings, places: [place(first)], fileCount: 1)
        } else if (also[first]?.count ?? 0) > (also[ranked[1]]?.count ?? 0) {
            hint = SourceHint(kind: .likeliest, strings: strings, places: ranked.prefix(listLimit).map(place),
                              fileCount: ranked.count, alsoThere: Array((also[first] ?? []).prefix(2)))
        } else {
            hint = SourceHint(kind: .several, strings: strings, places: ranked.prefix(listLimit).map(place), fileCount: ranked.count)
        }
        hint.together = true
        return hint
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
        guard !query.anchors.isEmpty || query.id != nil else { return nil }
        return SourceHint(kind: .none, strings: Array(query.anchors.prefix(2)), places: [], fileCount: 0)
    }

    // MARK: Capture

    /// R157: every pointed-at element of a fix capture gets its hint from one reading of the project folder.
    static func annotate(_ capture: Capture, root: URL, neighbors: [String], now: () -> Date = Date.init,
                         budget: TimeInterval = SourceHints.budget) -> Capture {
        guard let corpus = Corpus.load(root: root, now: now, budget: budget) else { return capture }
        return annotate(capture, corpus: corpus, neighbors: neighbors)
    }

    static func annotate(_ capture: Capture, corpus: Corpus, neighbors: [String]) -> Capture {
        var subjects = capture.targets?.map(\.element) ?? capture.element.map { [$0] } ?? []
        guard !subjects.isEmpty else { return capture }
        let around = (capture.elements ?? []).compactMap(\.label) + (capture.nearby ?? []).compactMap(\.label) + neighbors
        for index in subjects.indices {
            let others = subjects.indices.filter { $0 != index }.compactMap { subjects[$0].label }
            guard let query = query(for: subjects[index], neighbors: others + around, ocr: capture.ocr),
                  var hint = find(query, in: corpus) else { continue }
            if query.web {
                // R166: a web capture has no Project line to read a relative path against.
                func absolute(_ place: SourcePlace) -> SourcePlace {
                    SourcePlace(file: (corpus.root as NSString).appendingPathComponent(place.file), lines: place.lines)
                }
                hint.places = hint.places.map(absolute)
                hint.around = hint.around.map { SourceAround(strings: $0.strings, place: absolute($0.place)) }
            }
            subjects[index].sourceHint = hint
        }
        var capture = capture
        capture.element = subjects[0]
        if capture.targets != nil {
            for index in subjects.indices { capture.targets![index].element = subjects[index] }
        }
        return capture
    }

    // MARK: Neighbors

    /// R158: the labels of what sits around an element on screen, nearest first. In Device Hub the device's
    /// screen is one flat list, so these are the screen's own words: the title, the tabs, the button beside.
    static func neighborLabels(of frame: Frame, among nodes: [AttributeSet], limit: Int = 24) -> [String] {
        let (cx, cy) = (frame.x + frame.w / 2, frame.y + frame.h / 2)
        func distance(_ node: AttributeSet) -> Double {
            guard let f = node.frame else { return .greatestFiniteMagnitude }
            return hypot(f.x + f.w / 2 - cx, f.y + f.h / 2 - cy)
        }
        let labels = nodes.sorted { distance($0) < distance($1) }.compactMap { node -> String? in
            if let label = ElementResolver.nonEmpty(node.title) ?? ElementResolver.nonEmpty(node.description) { return label }
            // On the Mac the title of a row is a text beside its control, and a text's words are its value.
            if node.role == staticTextRole, case .string(let text)? = node.value { return ElementResolver.nonEmpty(text) }
            return nil
        }
        return Array(unique(labels).prefix(limit))
    }

    /// R167: the element's place among the siblings of its role that line up with it: the same left edge
    /// and width (a column of rows), or the same top edge and height (a row of items). Nil when it stands alone.
    static func rowPosition(of frame: Frame, rawRole: String, among nodes: [AttributeSet], tolerance: Double = 2) -> RowPosition? {
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= tolerance }
        let alike = nodes.compactMap { node in node.role == rawRole ? node.frame : nil }.filter { $0.w > 0 && $0.h > 0 }
        guard alike.contains(where: { near($0.x, frame.x) && near($0.y, frame.y) && near($0.w, frame.w) && near($0.h, frame.h) }) else { return nil }
        let column = alike.filter { near($0.x, frame.x) && near($0.w, frame.w) }.sorted { $0.y < $1.y }
        let row = alike.filter { near($0.y, frame.y) && near($0.h, frame.h) }.sorted { $0.x < $1.x }
        if column.count >= row.count, column.count >= 2, let index = column.firstIndex(where: { near($0.y, frame.y) }) {
            return RowPosition(index: index + 1, count: column.count, axis: .column)
        }
        if row.count >= 2, let index = row.firstIndex(where: { near($0.x, frame.x) }) {
            return RowPosition(index: index + 1, count: row.count, axis: .row)
        }
        return nil
    }
}

/// R165: the two string-catalog formats Xcode writes, read for "what the screen says → what the code says".
enum Catalogs {
    static func entries(in data: Data, kind: String, table: String) -> [LocalizedString] {
        kind == "xcstrings" ? xcstrings(data, table: table) : strings(data, table: table)
    }

    /// `{"strings": {"<key>": {"localizations": {"<lang>": {"stringUnit": {"value": "…"}}}}}}`; plural and
    /// device variations nest more `stringUnit`s under `variations`.
    static func xcstrings(_ data: Data, table: String) -> [LocalizedString] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = root["strings"] as? [String: Any] else { return [] }
        var out: [LocalizedString] = []
        func values(in node: Any) -> [String] {
            guard let dictionary = node as? [String: Any] else { return [] }
            var found: [String] = []
            if let unit = dictionary["stringUnit"] as? [String: Any], let value = unit["value"] as? String { found.append(value) }
            for (name, child) in dictionary where name != "stringUnit" { found.append(contentsOf: values(in: child)) }
            return found
        }
        for (key, entry) in strings {
            guard let localizations = (entry as? [String: Any])?["localizations"] else { continue }
            for value in Set(values(in: localizations)) { out.append(LocalizedString(shown: value, key: key, table: table)) }
        }
        return out.sorted { ($0.key, $0.shown) < ($1.key, $1.shown) }
    }

    /// `"key" = "value";`, in UTF-8 or the UTF-16 Xcode used to write.
    static func strings(_ data: Data, table: String) -> [LocalizedString] {
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? ""
        guard let pattern = try? NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;"#) else { return [] }
        let whole = NSRange(text.startIndex..., in: text)
        return pattern.matches(in: text, range: whole).compactMap { match in
            guard let key = Range(match.range(at: 1), in: text), let value = Range(match.range(at: 2), in: text) else { return nil }
            return LocalizedString(shown: unescaped(String(text[value])), key: unescaped(String(text[key])), table: table)
        }
    }

    private static func unescaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\\\", with: "\\")
    }
}
