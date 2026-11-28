import Foundation

/// v0.7.1 R53: `Locant --mcp`. JSON-RPC 2.0 over stdio, one message per line, the MCP stdio
/// transport. `handle` is pure over dictionaries and gets the tests; `serve` is the loop.
struct MCPServer {
    var index: CaptureIndex
    var version: String

    static let protocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]
    /// R185: written as when to call, not what it is. Clients that defer tools read only this to decide
    /// whether to search for Locant's tools, and tool search ranks on names and descriptions.
    static let instructions = """
        Locant lets the user point at things on their Mac's screen instead of describing them. They click one \
        element (a button, a row, a view, part of a web page or a simulator, or a frame they drew) and type a \
        note such as "make this bigger". Locant saves a capture: the note, a cropped screenshot, the app or page \
        URL, the element's role, label, accessibility identifier or DOM id and classes, frame, ancestry, and \
        often an "In source:" file and line.

        Call latest_capture first when the user:
        - refers to something on screen you cannot see: "this", "that button", "here", "what I just pointed at", \
        "the one I selected", in any language;
        - asks to change, fix, restyle, move, or explain part of an app's or a web page's interface without \
        giving a screenshot, a file, or a line;
        - mentions Locant or a capture.
        Do this before asking them for a screenshot or a description: the capture is what they meant. Check \
        its Captured time; if it is old or about something else, say so and ask.

        Then open the Image path, go to the "In source:" line if there is one (otherwise search the code for \
        the identifier, the DOM id or classes, or the label text), and do what the note asks. If a Project line \
        names a different checkout than yours, change the code there or ask which copy to change. Call \
        resolve_capture with the capture's id when the change is done. Use list_captures and get_capture only \
        when the user asks about an earlier capture.
        """

    /// `--mcp [--folder <path>]`; nil when the app should start normally.
    struct Options: Equatable {
        var folder: URL?

        init?(arguments: [String]) {
            guard let start = arguments.firstIndex(of: "--mcp") else { return nil }
            let rest = arguments[(start + 1)...]
            if let flag = rest.firstIndex(of: "--folder"), flag + 1 < rest.endIndex {
                folder = URL(filePath: rest[flag + 1], directoryHint: .isDirectory)
            }
        }
    }

    /// The folder the app writes to, from the shared defaults, unless the arguments name another.
    static func captureFolder(_ options: Options, defaults: UserDefaults = .standard) -> URL {
        if let folder = options.folder { return folder }
        let path = defaults.string(forKey: Preferences.Key.captureFolder) ?? ModeInference.directoryPath(FileStore.defaultDirectory)
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    // MARK: Loop

    /// Reads stdin until it closes. Only responses reach stdout.
    static func serve(_ options: Options) {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
        let server = MCPServer(index: CaptureIndex(folder: captureFolder(options)), version: version)
        let out = FileHandle.standardOutput
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if let response = server.handle(line: line) {
                out.write(response)
                out.write(Data([0x0A]))
            }
        }
    }

    /// One line in, one line out (or nil for a notification).
    func handle(line: String) -> Data? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Self.encode(Self.error(id: NSNull(), code: -32700, message: "Parse error"))
        }
        guard let response = handle(object) else { return nil }
        return Self.encode(response)
    }

    private static func encode(_ object: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes, .sortedKeys])
    }

    // MARK: Requests

    /// A JSON-RPC message in, a response out; nil for notifications.
    func handle(_ message: [String: Any]) -> [String: Any]? {
        let method = message["method"] as? String ?? ""
        let id = message["id"]
        let params = message["params"] as? [String: Any] ?? [:]
        guard let id, !(id is NSNull) else {
            return nil // a notification: notifications/initialized, notifications/cancelled, …
        }
        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? ""
            let version = Self.protocolVersions.contains(requested) ? requested : Self.protocolVersions[0]
            return Self.result(id: id, [
                "protocolVersion": version,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "locant", "version": self.version],
                "instructions": Self.instructions,
            ])
        case "ping":
            return Self.result(id: id, [:])
        case "tools/list":
            return Self.result(id: id, ["tools": Self.tools])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            guard Self.tools.contains(where: { $0["name"] as? String == name }) else {
                return Self.error(id: id, code: -32602, message: "Unknown tool: \(name)")
            }
            return Self.result(id: id, call(name, arguments))
        default:
            return Self.error(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private static func result(id: Any, _ result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private static func error(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    // MARK: Tools (R54)

    static var tools: [[String: Any]] { [
        [
            "name": "latest_capture",
            "title": "Latest capture",
            "description": "Call this when the user refers to something on their screen you cannot see (\"this\", \"this button\", \"here\", \"what I just pointed at\") or asks to change part of an app or web page UI without giving a screenshot or a file. Call it before asking them for a screenshot. Returns the UI element the user last pointed at with Locant on their Mac: the path of a cropped screenshot (PNG) first, and also the app or page URL, the user's note saying what to change, the element's role, label, accessibility identifier or DOM id and classes, frame, ancestry, and often an \"In source:\" file and line.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "include_image": ["type": "boolean", "description": "Also return the PNG as an image content block. Default false: the path is enough for agents that can open files."],
                    "unresolved_only": ["type": "boolean", "description": "Skip captures already marked resolved. Default false."],
                ],
                "additionalProperties": false,
            ],
            "annotations": ["readOnlyHint": true, "openWorldHint": false],
        ],
        [
            "name": "list_captures",
            "title": "List captures",
            "description": "Call this only when the user asks about an earlier Locant capture (\"the one before\", \"the buttons I pointed at this morning\") or what is still open. Lists recent captures of on-screen UI elements, newest first, one line each: id, when, fix or reference, app, element, note, resolved or not. Then call get_capture with an id.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "unresolved_only": ["type": "boolean", "description": "Only captures not yet marked resolved. Default false."],
                    "limit": ["type": "integer", "minimum": 1, "maximum": 200, "description": "How many, newest first. Default 20."],
                ],
                "additionalProperties": false,
            ],
            "annotations": ["readOnlyHint": true, "openWorldHint": false],
        ],
        [
            "name": "get_capture",
            "title": "Get capture",
            "description": "Call this with an id from list_captures to read an earlier Locant capture in full, the same way latest_capture reads the newest: the screenshot path first, the element, its ancestry, the note, then the JSON sidecar with everything else, including iterations recorded after an edit.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "The capture id, as list_captures prints it (yyyyMMdd-HHmmss-xxxx)."],
                    "include_image": ["type": "boolean", "description": "Also return the PNG as an image content block. Default false."],
                ],
                "required": ["id"],
                "additionalProperties": false,
            ],
            "annotations": ["readOnlyHint": true, "openWorldHint": false],
        ],
        [
            "name": "resolve_capture",
            "title": "Resolve capture",
            "description": "Call this after you have made the change a Locant capture asked for. Marks the capture resolved (sets resolved: true in its sidecar), so it no longer counts as open and Locant keeps it instead of expiring it.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "The capture id."],
                ],
                "required": ["id"],
                "additionalProperties": false,
            ],
            "annotations": ["readOnlyHint": false, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false],
        ],
    ] }

    private func call(_ name: String, _ arguments: [String: Any]) -> [String: Any] {
        let includeImage = arguments["include_image"] as? Bool ?? false
        let unresolvedOnly = arguments["unresolved_only"] as? Bool ?? false
        switch name {
        case "latest_capture":
            let entries = index.entries().filter { !unresolvedOnly || !$0.capture.resolved }
            guard let entry = entries.first else { return Self.text(emptyMessage(unresolvedOnly: unresolvedOnly)) }
            return captureResult(entry, includeImage: includeImage)
        case "list_captures":
            let limit = max(1, min(200, arguments["limit"] as? Int ?? 20))
            let all = index.entries().filter { !unresolvedOnly || !$0.capture.resolved }
            guard !all.isEmpty else { return Self.text(emptyMessage(unresolvedOnly: unresolvedOnly)) }
            let shown = all.prefix(limit)
            var lines = ["\(all.count) capture\(all.count == 1 ? "" : "s") in \(folderPath), newest first\(shown.count < all.count ? " (first \(shown.count))" : ""):"]
            lines += shown.map { "- " + CaptureIndex.summaryLine($0.capture) }
            return Self.text(lines.joined(separator: "\n"))
        case "get_capture":
            guard let id = arguments["id"] as? String, !id.isEmpty else { return Self.text("Missing id.", isError: true) }
            guard let entry = index.entry(id: id) else { return Self.text("No capture with id \(id) in \(folderPath).", isError: true) }
            return captureResult(entry, includeImage: includeImage)
        case "resolve_capture":
            guard let id = arguments["id"] as? String, !id.isEmpty else { return Self.text("Missing id.", isError: true) }
            do {
                let entry = try index.resolve(id: id)
                return Self.text("Resolved \(entry.capture.id). Locant keeps it.")
            } catch CaptureIndex.Failure.notFound {
                return Self.text("No capture with id \(id) in \(folderPath).", isError: true)
            } catch {
                return Self.text("Could not rewrite the sidecar for \(id): \(error)", isError: true)
            }
        default:
            return Self.text("Unknown tool: \(name)", isError: true)
        }
    }

    /// R55: text first, the image path first in the text, an image block only on request, never structuredContent.
    private func captureResult(_ entry: CaptureIndex.Entry, includeImage: Bool) -> [String: Any] {
        var text = MarkdownBuilder.build(entry.capture)
        text += "\n\n### Sidecar\n\(entry.url.path(percentEncoded: false))\n"
        if let data = try? Data(contentsOf: entry.url), let json = String(data: data, encoding: .utf8) {
            text += "```json\n\(json)\n```"
        }
        var content: [[String: Any]] = [["type": "text", "text": text]]
        if includeImage {
            if let png = try? Data(contentsOf: URL(filePath: entry.capture.image.path)) {
                content.append(["type": "image", "data": png.base64EncodedString(), "mimeType": "image/png"])
            } else {
                content.append(["type": "text", "text": "The image at \(entry.capture.image.path) could not be read."])
            }
        }
        return ["content": content, "isError": false]
    }

    private var folderPath: String { ModeInference.directoryPath(index.folder) }

    private func emptyMessage(unresolvedOnly: Bool) -> String {
        if unresolvedOnly, !index.entries().isEmpty { return "Every capture in \(folderPath) is resolved." }
        return "No captures in \(folderPath). Point at something with Locant first: press the hotkey (⌃⌃ by default) or click the ball, click an element, type a note, press Return."
    }

    private static func text(_ text: String, isError: Bool = false) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": isError]
    }
}
