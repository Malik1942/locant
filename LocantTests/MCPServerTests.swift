import XCTest
@testable import Locant

final class MCPServerTests: XCTestCase {
    private var dir: URL!
    private var server: MCPServer!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "LocantMCP-\(UUID().uuidString)")
        server = MCPServer(index: CaptureIndex(folder: dir), version: "0.7.1")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: Fixtures

    private static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    private func write(id: String, createdAt: String, note: String = "", identifier: String? = "saveButton", resolved: Bool = false) throws -> Capture {
        let element = ResolvedElement(
            role: "button", rawRole: "AXButton", label: "Save", identifier: identifier,
            identifierSource: identifier == nil ? .unknown : .declared, value: nil,
            frame: Frame(x: 10, y: 20, w: 100, h: 30),
            path: [PathEntry(role: "window", identifier: nil), PathEntry(role: "button", identifier: identifier)]
        )
        var capture = Capture(
            id: id, createdAt: createdAt, mode: .fix,
            image: ImageInfo(path: "", widthPt: 100, heightPt: 30, scale: 2, crop: nil),
            source: SourceInfo(app: AppInfo(bundleId: "com.apple.iphonesimulator", name: "Simulator"), window: WindowInfo(title: "iPhone 17 Pro"), url: nil, simulator: nil),
            element: element, note: note
        )
        capture.resolved = resolved
        return try FileStore(directory: dir).write(png: Self.png, capture: capture)
    }

    private func request(_ id: Int, _ method: String, _ params: [String: Any] = [:]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
    }

    private func call(_ name: String, _ arguments: [String: Any] = [:]) -> [String: Any] {
        let response = server.handle(request(7, "tools/call", ["name": name, "arguments": arguments]))
        return response?["result"] as? [String: Any] ?? [:]
    }

    private func text(_ result: [String: Any]) -> String {
        let content = result["content"] as? [[String: Any]] ?? []
        return content.first?["text"] as? String ?? ""
    }

    // 1
    func testInitializeNegotiatesVersionAndOffersToolsOnly() throws {
        let response = try XCTUnwrap(server.handle(request(1, "initialize", ["protocolVersion": "2025-03-26", "capabilities": [:], "clientInfo": ["name": "test", "version": "1"]])))
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-03-26")
        XCTAssertEqual((result["capabilities"] as? [String: Any])?.keys.sorted(), ["tools"])
        XCTAssertEqual((result["serverInfo"] as? [String: Any])?["name"] as? String, "locant")
        XCTAssertEqual((result["serverInfo"] as? [String: Any])?["version"] as? String, "0.7.1")
        XCTAssertTrue((result["instructions"] as? String ?? "").contains("latest_capture"))

        let unknown = try XCTUnwrap(server.handle(request(2, "initialize", ["protocolVersion": "1999-01-01"])))
        XCTAssertEqual((unknown["result"] as? [String: Any])?["protocolVersion"] as? String, "2025-06-18")
        XCTAssertEqual((server.handle(request(3, "ping"))?["result"] as? [String: Any])?.isEmpty, true)
    }

    // 2
    func testToolsListNamesTheFourTools() throws {
        let response = try XCTUnwrap(server.handle(request(1, "tools/list")))
        let tools = try XCTUnwrap((response["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.map { $0["name"] as? String }, ["latest_capture", "list_captures", "get_capture", "resolve_capture"])
        for tool in tools {
            let schema = try XCTUnwrap(tool["inputSchema"] as? [String: Any], "\(tool["name"] ?? "")")
            XCTAssertEqual(schema["type"] as? String, "object")
            XCTAssertFalse((tool["description"] as? String ?? "").isEmpty)
        }
        let get = try XCTUnwrap(tools.first { $0["name"] as? String == "get_capture" })
        XCTAssertEqual((get["inputSchema"] as? [String: Any])?["required"] as? [String], ["id"])
        XCTAssertEqual((get["annotations"] as? [String: Any])?["readOnlyHint"] as? Bool, true)
    }

    // 3
    func testListCapturesIsNewestFirstAndFiltersResolved() throws {
        _ = try write(id: "20260914-100000-aaaa", createdAt: "2026-09-14T10:00:00-07:00", note: "older")
        _ = try write(id: "20260914-110000-bbbb", createdAt: "2026-09-14T11:00:00-07:00", note: "newer", resolved: true)
        _ = try write(id: "20260914-103000-cccc", createdAt: "2026-09-14T17:30:00Z", note: "utc, between")

        let all = text(call("list_captures"))
        let lines = all.split(separator: "\n").map(String.init)
        XCTAssertTrue(lines[0].hasPrefix("3 captures in "), lines[0])
        XCTAssertTrue(lines[1].hasPrefix("- 20260914-110000-bbbb"), lines[1])
        XCTAssertTrue(lines[2].hasPrefix("- 20260914-103000-cccc"), lines[2])
        XCTAssertTrue(lines[3].hasPrefix("- 20260914-100000-aaaa"), lines[3])
        XCTAssertTrue(lines[1].contains("resolved"), lines[1])
        XCTAssertTrue(lines[1].contains("· button id=saveButton ·"), lines[1])
        XCTAssertTrue(lines[1].contains("note: \"newer\""), lines[1])

        let unresolved = text(call("list_captures", ["unresolved_only": true, "limit": 1]))
        XCTAssertTrue(unresolved.hasPrefix("2 captures in "), unresolved)
        XCTAssertTrue(unresolved.contains("(first 1)"), unresolved)
        XCTAssertTrue(unresolved.contains("20260914-103000-cccc"))
        XCTAssertFalse(unresolved.contains("20260914-110000-bbbb"))
    }

    // 4
    func testLatestCaptureIsTheMarkdownPayloadWithThePathFirst() throws {
        _ = try write(id: "20260914-100000-aaaa", createdAt: "2026-09-14T10:00:00-07:00")
        let newest = try write(id: "20260914-110000-bbbb", createdAt: "2026-09-14T11:00:00-07:00", note: "make this rounded")

        let result = call("latest_capture")
        XCTAssertEqual(result["isError"] as? Bool, false)
        let payload = text(result)
        XCTAssertTrue(payload.hasPrefix("## Locant capture (fix)\nImage: \(newest.image.path)\n"), "expected \(newest.image.path)")
        XCTAssertTrue(payload.contains("button \"Save\" · id=saveButton"), payload)
        XCTAssertTrue(payload.contains("make this rounded"), payload)
        XCTAssertTrue(payload.contains("### Sidecar\n/"), payload)
        XCTAssertTrue(payload.contains("/locant-simulator-20260914-110000-bbbb.json\n```json\n{"), payload)
        XCTAssertTrue(payload.contains("\"resolved\" : false"), payload)
        XCTAssertEqual((result["content"] as? [[String: Any]])?.count, 1)
        XCTAssertNil(result["structuredContent"])

        _ = try server.index.resolve(id: newest.id)
        XCTAssertTrue(text(call("latest_capture", ["unresolved_only": true])).contains("20260914-100000-aaaa"))
    }

    // 5
    func testIncludeImageAddsOneImageBlock() throws {
        let capture = try write(id: "20260914-100000-aaaa", createdAt: "2026-09-14T10:00:00-07:00")
        let result = call("get_capture", ["id": capture.id, "include_image": true])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 2)
        XCTAssertEqual(content[0]["type"] as? String, "text")
        XCTAssertEqual(content[1]["type"] as? String, "image")
        XCTAssertEqual(content[1]["mimeType"] as? String, "image/png")
        XCTAssertEqual(content[1]["data"] as? String, Self.png.base64EncodedString())
        XCTAssertNil(result["structuredContent"])

        let plain = call("get_capture", ["id": capture.id])
        XCTAssertEqual((plain["content"] as? [[String: Any]])?.count, 1)
    }

    // 6
    func testResolveFlipsOnlyResolved() throws {
        let capture = try write(id: "20260914-100000-aaaa", createdAt: "2026-09-14T10:00:00-07:00", note: "keep me")
        let url = URL(filePath: capture.image.path).deletingPathExtension().appendingPathExtension("json")
        let before = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]

        let result = call("resolve_capture", ["id": capture.id])
        XCTAssertEqual(result["isError"] as? Bool, false)
        XCTAssertTrue(text(result).contains("Resolved 20260914-100000-aaaa"))

        let after = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(after["resolved"] as? Bool, true)
        var expected = before ?? [:]
        expected["resolved"] = true
        XCTAssertEqual(after as NSDictionary, expected as NSDictionary)
        XCTAssertEqual(try JSONDecoder().decode(Capture.self, from: Data(contentsOf: url)).note, "keep me")
        XCTAssertTrue(text(call("list_captures")).contains("· resolved"))
    }

    // 7
    func testUnknownIdIsAToolError() throws {
        _ = try write(id: "20260914-100000-aaaa", createdAt: "2026-09-14T10:00:00-07:00")
        for name in ["get_capture", "resolve_capture"] {
            let result = call(name, ["id": "20260101-000000-zzzz"])
            XCTAssertEqual(result["isError"] as? Bool, true, name)
            XCTAssertTrue(text(result).contains("No capture with id 20260101-000000-zzzz"), name)
        }
        XCTAssertEqual(call("get_capture")["isError"] as? Bool, true)
    }

    // 8
    func testProtocolErrorsAndNotifications() throws {
        let unknown = try XCTUnwrap(server.handle(request(1, "resources/list")))
        XCTAssertEqual((unknown["error"] as? [String: Any])?["code"] as? Int, -32601)
        XCTAssertNil(server.handle(["jsonrpc": "2.0", "method": "notifications/initialized"]))
        let bad = try XCTUnwrap(server.handle(line: "{not json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bad) as? [String: Any])
        XCTAssertEqual((object["error"] as? [String: Any])?["code"] as? Int, -32700)
        XCTAssertTrue(object["id"] is NSNull)
        let badTool = try XCTUnwrap(server.handle(request(2, "tools/call", ["name": "delete_everything"])))
        XCTAssertEqual((badTool["error"] as? [String: Any])?["code"] as? Int, -32602)
        // One line out, no newline inside.
        let line = try XCTUnwrap(server.handle(line: #"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#))
        XCTAssertFalse(String(decoding: line, as: UTF8.self).contains("\n"))
        XCTAssertNil(MCPServer.Options(arguments: ["Locant"]))
        XCTAssertEqual(MCPServer.Options(arguments: ["Locant", "--mcp", "--folder", "/tmp/x"])?.folder?.path(percentEncoded: false), "/tmp/x/")
    }

    // 9
    func testEmptyFolderAnswersWithASentence() throws {
        for name in ["latest_capture", "list_captures"] {
            let result = call(name)
            XCTAssertEqual(result["isError"] as? Bool, false, name)
            XCTAssertTrue(text(result).hasPrefix("No captures in "), name)
            XCTAssertTrue(text(result).contains("⌃⌃"), name)
        }
        _ = try write(id: "20260914-100000-aaaa", createdAt: "2026-09-14T10:00:00-07:00", resolved: true)
        XCTAssertTrue(text(call("latest_capture", ["unresolved_only": true])).hasPrefix("Every capture in "))
    }

    // 10: sidecars from before the rename and in subfolders count too.
    func testFindsPreRenameAndNestedSidecars() throws {
        let nested = try write(id: "20260914-100000-aaaa", createdAt: "2026-09-14T10:00:00-07:00")
        let sub = dir.appending(path: "old", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let old = sub.appending(path: "deixis-finder-20260913-090000-zzzz.json")
        let text = try String(contentsOf: URL(filePath: nested.image.path).deletingPathExtension().appendingPathExtension("json"), encoding: .utf8)
            .replacing("20260914-100000-aaaa", with: "20260913-090000-zzzz")
            .replacing("2026-09-14T10:00:00-07:00", with: "2026-09-13T09:00:00-07:00")
        try text.write(to: old, atomically: true, encoding: .utf8)
        try "not a capture".write(to: sub.appending(path: "locant-notes.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(server.index.entries().map(\.capture.id), ["20260914-100000-aaaa", "20260913-090000-zzzz"])
    }

    // MARK: Sidecars as the schema allows them (the same fixtures CI validates against schema/capture.schema.json)

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"), "fixture \(name)"))
    }

    // 11: a sidecar with only the keys the schema requires is read. `iterations` and the rest are optional there,
    // whatever the model defaults to; the synthesized decoder wanted them, so such a sidecar reached no tool.
    func testASidecarWithOnlyTheRequiredKeysIsRead() throws {
        let data = try fixture("sidecar-minimal")
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys.sorted()
        XCTAssertEqual(keys, ["createdAt", "element", "id", "image", "mode", "note", "resolved", "schemaVersion", "source"], "the schema's required list, nothing more")
        let capture = try JSONDecoder().decode(Capture.self, from: data)
        XCTAssertEqual(capture.id, "20261102-093000-r3qd")
        XCTAssertEqual(capture.element?.identifier, "Eight")
        XCTAssertEqual(capture.iterations, [])
        XCTAssertNil(capture.ocr)
        XCTAssertNil(capture.image.crop)
        XCTAssertNil(capture.elements)
        XCTAssertNil(capture.nearby)
        XCTAssertNil(capture.targets)

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appending(path: "locant-calculator-20261102-093000-r3qd.json"))
        XCTAssertEqual(server.index.entries().map(\.capture.id), ["20261102-093000-r3qd"])
        XCTAssertTrue(text(call("list_captures")).contains("20261102-093000-r3qd · 2026-11-02T09:30:00-08:00 · reference · Calculator · button id=Eight"))
        let payload = text(call("get_capture", ["id": "20261102-093000-r3qd"]))
        XCTAssertTrue(payload.hasPrefix("## Locant capture (reference)\nImage: /Users/malik/Pictures/Locant/locant-calculator-20261102-093000-r3qd.png\n"), payload)
    }

    // 12: the richer sidecars the app writes (a Shift set with an iteration, a drawn frame) decode and round-trip.
    func testSidecarFixturesRoundTrip() throws {
        for name in ["sidecar-shift-set", "sidecar-drawn-frame"] {
            let data = try fixture(name)
            let capture = try JSONDecoder().decode(Capture.self, from: data)
            let written = try JSONEncoder().encode(capture)
            XCTAssertEqual(try JSONDecoder().decode(Capture.self, from: written), capture, name)
            let readKeys = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys.sorted()
            let writtenKeys = try XCTUnwrap(JSONSerialization.jsonObject(with: written) as? [String: Any]).keys.sorted()
            XCTAssertEqual(writtenKeys, readKeys, "\(name): every key read is written back, none invented")
        }
        let set = try JSONDecoder().decode(Capture.self, from: try fixture("sidecar-shift-set"))
        XCTAssertEqual(set.targets?.count, 2)
        XCTAssertEqual(set.targets?[1].element.dom?.classes, ["pill", "pill-primary"])
        XCTAssertEqual(set.targets?[1].element.path.last?.dom, ".pill")
        XCTAssertEqual(set.targets?[1].imagePath, "/Users/malik/Pictures/Locant/locant-simulator-20261102-093512-q7xk-2.png")
        XCTAssertEqual(set.iterations.first?.frame, Frame(x: 43, y: 893.7, w: 370, h: 50.3))
        XCTAssertEqual(set.source.projectRoot, "/Users/malik/Documents/Oryne")
        let frame = try JSONDecoder().decode(Capture.self, from: try fixture("sidecar-drawn-frame"))
        XCTAssertEqual(frame.elements?.count, 2)
        XCTAssertEqual(frame.element?.members?.count, 2)
        XCTAssertEqual(frame.ocr, "Shortcut\nAction Button")
        XCTAssertTrue(frame.resolved)
    }
}
