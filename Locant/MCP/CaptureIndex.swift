import Foundation

/// v0.7.1 R53: the sidecars under the capture folder as the MCP server sees them. Nothing is
/// cached; every call reads the folder, so a capture made a second ago is already there.
struct CaptureIndex: Sendable {
    var folder: URL

    struct Entry: Sendable, Equatable {
        var capture: Capture
        var url: URL
    }

    enum Failure: Error, Equatable {
        case notFound(String)
        case unreadable(String)
    }

    /// Every capture under the folder, newest first: `createdAt`, ties broken by id (schema).
    func entries() -> [Entry] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return [] }
        var found: [Entry] = []
        let decoder = JSONDecoder()
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            guard url.pathExtension == "json", name.hasPrefix("locant-") || name.hasPrefix("deixis-"),
                  let data = try? Data(contentsOf: url),
                  let capture = try? decoder.decode(Capture.self, from: data),
                  capture.schemaVersion == 1 else { continue }
            found.append(Entry(capture: capture, url: url))
        }
        return found.sorted { a, b in
            let (da, db) = (Self.date(a.capture.createdAt), Self.date(b.capture.createdAt))
            if let da, let db, da != db { return da > db }
            return a.capture.id > b.capture.id
        }
    }

    func entry(id: String) -> Entry? {
        entries().first { $0.capture.id == id }
    }

    /// Sets `resolved: true` and rewrites the sidecar with every other key, and its Finder tags
    /// and pin, as they were.
    @discardableResult
    func resolve(id: String) throws -> Entry {
        guard let entry = entry(id: id) else { throw Failure.notFound(id) }
        guard let data = try? Data(contentsOf: entry.url),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.unreadable(entry.url.path(percentEncoded: false))
        }
        object["resolved"] = true
        let json = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try FileStore.rewrite(json, at: entry.url)
        var resolved = entry
        resolved.capture.resolved = true
        return resolved
    }

    /// One line for `list_captures`: id, when, mode, app, the element in the payload's words, note, state.
    static func summaryLine(_ c: Capture) -> String {
        var parts = [c.id, c.createdAt, c.mode.rawValue, c.source.app.name, elementSummary(c)]
        if !c.note.isEmpty { parts.append("note: \"\(c.note)\"") }
        parts.append(c.resolved ? "resolved" : "unresolved")
        return parts.joined(separator: " · ")
    }

    static func elementSummary(_ c: Capture) -> String {
        if let targets = c.targets, targets.count > 1 {
            return "\(targets.count) elements: " + targets.map { $0.element.identifier ?? $0.element.domReadout ?? $0.element.label ?? $0.element.role }.joined(separator: ", ")
        }
        if let e = c.element {
            var s = e.role
            if let id = e.identifier { s += " id=\(id)" } else if let handle = e.domReadout { s += " \(handle)" } else if let label = e.label { s += " \"\(label)\"" } else { s += " (no identifier)" }
            return s
        }
        if let elements = c.elements, !elements.isEmpty { return "drawn frame with \(elements.count) elements" }
        return "no element"
    }

    private static func date(_ iso: String) -> Date? {
        ISO8601DateFormatter().date(from: iso)
    }
}
