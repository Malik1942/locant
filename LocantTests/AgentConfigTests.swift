import XCTest
@testable import Locant

final class AgentConfigTests: XCTestCase {
    private let exe = "/Applications/Locant.app/Contents/MacOS/Locant"

    private func object(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    // 1
    func testJSONAddKeepsOtherServersAndReplacesAnOldLocant() throws {
        let existing = """
        {"mcpServers": {"agentation": {"command": "npx", "args": ["-y", "agentation-mcp", "server"]}, "locant": {"command": "/old/Locant", "args": ["--mcp"]}}, "numStartups": 12, "projects": {"/Users/me/x": {"allowedTools": []}}}
        """
        let updated = try object(try AgentConfig.jsonAdding(existing, executable: exe))
        let servers = try XCTUnwrap(updated["mcpServers"] as? [String: Any])
        XCTAssertEqual(servers.keys.sorted(), ["agentation", "locant"])
        XCTAssertEqual((servers["locant"] as? [String: Any])?["command"] as? String, exe)
        XCTAssertEqual((servers["locant"] as? [String: Any])?["args"] as? [String], ["--mcp"])
        XCTAssertEqual((servers["agentation"] as? [String: Any])?["args"] as? [String], ["-y", "agentation-mcp", "server"])
        XCTAssertEqual(updated["numStartups"] as? Int, 12)
        XCTAssertNotNil((updated["projects"] as? [String: Any])?["/Users/me/x"])

        let fresh = try object(try AgentConfig.jsonAdding(nil, executable: exe))
        XCTAssertEqual(((fresh["mcpServers"] as? [String: Any])?["locant"] as? [String: Any])?["command"] as? String, exe)
        XCTAssertEqual(try AgentConfig.jsonAdding("", executable: exe), try AgentConfig.jsonAdding(nil, executable: exe))
        XCTAssertTrue(try AgentConfig.jsonAdding(nil, executable: exe).hasSuffix("\n"))
        XCTAssertThrowsError(try AgentConfig.jsonAdding("{oops", executable: exe))
        XCTAssertThrowsError(try AgentConfig.jsonAdding("[1, 2]", executable: exe))
    }

    // 2
    func testJSONRemoveLeavesTheRest() throws {
        let existing = try AgentConfig.jsonAdding(#"{"mcpServers": {"agentation": {"command": "npx"}}, "theme": "dark"}"#, executable: exe)
        let removed = try object(try XCTUnwrap(try AgentConfig.jsonRemoving(existing)))
        XCTAssertEqual((removed["mcpServers"] as? [String: Any])?.keys.sorted(), ["agentation"])
        XCTAssertEqual(removed["theme"] as? String, "dark")
        XCTAssertNil(try AgentConfig.jsonRemoving(nil))
        XCTAssertNil(try AgentConfig.jsonRemoving(#"{"mcpServers": {}}"#))
        XCTAssertNil(try AgentConfig.jsonRemoving(#"{"theme": "dark"}"#))
    }

    // 3
    func testTOMLAddAppendsOneTable() throws {
        let existing = """
        model = "gpt-5"

        [mcp_servers.agentation]
        command = "npx"
        args = [ "-y", "agentation-mcp", "server" ]
        """
        let added = try AgentConfig.tomlAdding(existing, executable: exe)
        XCTAssertEqual(added, existing + "\n\n[mcp_servers.locant]\ncommand = \"\(exe)\"\nargs = [\"--mcp\"]\n")
        XCTAssertEqual(try AgentConfig.tomlAdding(nil, executable: exe), "[mcp_servers.locant]\ncommand = \"\(exe)\"\nargs = [\"--mcp\"]\n")
        // Adding twice replaces, never duplicates.
        let twice = try AgentConfig.tomlAdding(added, executable: "/elsewhere/Locant")
        XCTAssertEqual(twice.components(separatedBy: "[mcp_servers.locant]").count, 2)
        XCTAssertEqual(AgentConfig.tomlExecutable(twice), "/elsewhere/Locant")
        XCTAssertEqual(AgentConfig.tomlExecutable(try AgentConfig.tomlAdding(nil, executable: "/a \"quoted\"/Locant")), "/a \"quoted\"/Locant")
    }

    // 4
    func testTOMLRemoveTakesTheTableAndItsSubTables() throws {
        let existing = """
        model = "gpt-5"

        [mcp_servers.locant]
        command = "/old/Locant"
        args = ["--mcp"]

          [mcp_servers.locant.env]
          FOO = "bar"

        [mcp_servers.agentation]
        command = "npx"
        """
        XCTAssertEqual(try AgentConfig.tomlRemoving(existing), "model = \"gpt-5\"\n\n[mcp_servers.agentation]\ncommand = \"npx\"")
        XCTAssertNil(try AgentConfig.tomlRemoving(nil))
        XCTAssertNil(try AgentConfig.tomlRemoving("model = \"gpt-5\"\n"))
        // A table at the end of the file.
        let tail = "a = 1\n\n[mcp_servers.locant]\ncommand = \"/x\"\n"
        XCTAssertEqual(try AgentConfig.tomlRemoving(tail), "a = 1\n")
    }

    // 5
    func testDetectionReturnsTheConfiguredExecutable() throws {
        XCTAssertNil(AgentConfig.jsonExecutable(nil))
        XCTAssertNil(AgentConfig.jsonExecutable(#"{"mcpServers": {"other": {"command": "x"}}}"#))
        XCTAssertEqual(AgentConfig.jsonExecutable(try AgentConfig.jsonAdding(nil, executable: exe)), exe)
        XCTAssertNil(AgentConfig.tomlExecutable(nil))
        XCTAssertNil(AgentConfig.tomlExecutable("[mcp_servers.other]\ncommand = \"x\"\n"))
        XCTAssertEqual(AgentConfig.tomlExecutable("[mcp_servers.locant]\ncommand = \"/x/Locant\" # comment\nargs = []\n"), "/x/Locant")
        XCTAssertNil(AgentConfig.tomlExecutable("[mcp_servers.locant]\nargs = []\n"), "a table without a command is no connection")

        let snippet = try object(AgentConfig.jsonSnippet(executable: exe))
        XCTAssertEqual(((snippet["mcpServers"] as? [String: Any])?["locant"] as? [String: Any])?["args"] as? [String], ["--mcp"])
        XCTAssertEqual(Agent.allCases.map(\.title), ["Claude Code", "Cursor", "Codex"])
        XCTAssertEqual(Agent.claudeCode.configURL.lastPathComponent, ".claude.json")
        XCTAssertEqual(Agent.cursor.configURL.path(percentEncoded: false).hasSuffix("/.cursor/mcp.json"), true)
        XCTAssertEqual(Agent.codex.configURL.path(percentEncoded: false).hasSuffix("/.codex/config.toml"), true)
    }

    // 6: the spellings a hand writes into Codex's file (Nov 2 2026). Before, only the exact
    // `[mcp_servers.locant]` was seen, and Connect appended a second table Codex refused to parse.
    func testTOMLRecognisesTheFormsAHandWrites() throws {
        let quoted = "model = \"gpt-5\"\n\n[mcp_servers.\"locant\"] # mine\ncommand = \"/x/Locant\"\nargs = [\"--mcp\"]\n"
        XCTAssertEqual(AgentConfig.tomlExecutable(quoted), "/x/Locant")
        XCTAssertEqual(try AgentConfig.tomlRemoving(quoted), "model = \"gpt-5\"\n")
        let readded = try AgentConfig.tomlAdding(quoted, executable: exe)
        XCTAssertEqual(readded, "model = \"gpt-5\"\n\n[mcp_servers.locant]\ncommand = \"\(exe)\"\nargs = [\"--mcp\"]\n")
        XCTAssertEqual(AgentConfig.tomlExecutable("[ mcp_servers . 'locant' ]\ncommand = '/y/Locant'\n"), "/y/Locant")
        XCTAssertEqual(AgentConfig.tomlExecutable("[\"mcp_servers\".locant]\t# tab\ncommand = \"/t/Locant\"\n"), "/t/Locant")

        // Inline under [mcp_servers]: that one line goes, the neighbours stay, the table is appended.
        let inline = "[mcp_servers]\nagentation = { command = \"npx\" }\nlocant = { command = \"/z/Locant\", args = [\"--mcp\"] }\n\n[other]\na = 1\n"
        XCTAssertEqual(AgentConfig.tomlExecutable(inline), "/z/Locant")
        XCTAssertEqual(try AgentConfig.tomlRemoving(inline), "[mcp_servers]\nagentation = { command = \"npx\" }\n\n[other]\na = 1\n")
        XCTAssertEqual(try AgentConfig.tomlAdding(inline, executable: exe), "[mcp_servers]\nagentation = { command = \"npx\" }\n\n[other]\na = 1\n\n[mcp_servers.locant]\ncommand = \"\(exe)\"\nargs = [\"--mcp\"]\n")
        XCTAssertEqual(AgentConfig.tomlExecutable("[mcp_servers]\nlocant = { args = [\"--mcp\"], command = \"/c, d/Locant\" } # note\n"), "/c, d/Locant")

        // Dotted keys under [mcp_servers], and from the root.
        let dotted = "[mcp_servers]\nlocant.command = \"/d/Locant\"\nlocant.args = [\"--mcp\"]\n[other]\na = 1\n"
        XCTAssertEqual(AgentConfig.tomlExecutable(dotted), "/d/Locant")
        XCTAssertEqual(try AgentConfig.tomlRemoving(dotted), "[mcp_servers]\n[other]\na = 1\n")
        XCTAssertEqual(AgentConfig.tomlExecutable("mcp_servers.locant.command = \"/r/Locant\"\n"), "/r/Locant")

        // A value that runs on past its line, or an array of tables, cannot be cut out: by hand.
        let multiline = "[mcp_servers]\nlocant = { command = \"/m/Locant\", args = [\n  \"--mcp\"\n] }\n"
        XCTAssertEqual(AgentConfig.tomlExecutable(multiline), "/m/Locant")
        XCTAssertThrowsError(try AgentConfig.tomlRemoving(multiline)) { XCTAssertEqual($0 as? AgentConfig.Failure, .configuredByHand) }
        XCTAssertThrowsError(try AgentConfig.tomlAdding(multiline, executable: exe)) { XCTAssertEqual($0 as? AgentConfig.Failure, .configuredByHand) }
        XCTAssertThrowsError(try AgentConfig.tomlRemoving("[[mcp_servers.locant]]\ncommand = \"/a/Locant\"\n"))

        // No command is no connection, wherever the word appears.
        XCTAssertNil(AgentConfig.tomlExecutable("[mcp_servers.locant]\n[mcp_servers.locant.env]\ncommand = \"not ours\"\n"))
        XCTAssertNil(AgentConfig.tomlExecutable("[mcp_servers.locant]\ncommands = \"x\"\n"))
        XCTAssertNil(AgentConfig.tomlExecutable("[mcp_servers.locantx]\ncommand = \"x\"\n"))
        XCTAssertNil(AgentConfig.tomlExecutable("[mcp_servers]\nlocant = { args = [] }\n"))
        // A commented-out header is a comment.
        XCTAssertNil(AgentConfig.tomlExecutable("# [mcp_servers.locant]\n# command = \"x\"\n"))
        // And a table without a command is replaced, not duplicated.
        let bare = "[mcp_servers.locant]\nargs = []\n"
        XCTAssertEqual(try AgentConfig.tomlAdding(bare, executable: exe).components(separatedBy: "[mcp_servers.locant]").count, 2)
    }

    // 7: writes follow a symlink into the file it names and keep one backup beside it (Nov 2 2026).
    func testWriteFollowsASymlinkAndKeepsOneBackup() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "LocantAgents-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let real = dir.appending(path: "dotfiles/cursor/mcp.json")
        let link = dir.appending(path: "home/.cursor/mcp.json")
        try FileManager.default.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        let first = #"{"mcpServers": {"agentation": {"command": "npx"}}}"#
        try first.write(to: real, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let inode = try FileManager.default.attributesOfItem(atPath: real.path(percentEncoded: false))[.systemFileNumber] as? Int

        XCTAssertEqual(try AgentConnector.connect(.cursor, at: link, executable: exe, cli: nil), .done)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path(percentEncoded: false)), real.path(percentEncoded: false), "the link is still a link")
        let written = try object(try String(contentsOf: real, encoding: .utf8))
        XCTAssertEqual((written["mcpServers"] as? [String: Any])?.keys.sorted(), ["agentation", "locant"])
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: real.path(percentEncoded: false))[.systemFileNumber] as? Int, inode, "the file was edited in place")
        let backup = dir.appending(path: "dotfiles/cursor/mcp.json.locant-backup")
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), first)
        XCTAssertEqual(AgentConnector.status(.cursor, at: link), .connected(executable: exe))

        // The next write replaces the backup with what it found, so there is one backup, not a pile.
        XCTAssertEqual(try AgentConnector.disconnect(.cursor, at: link, cli: nil), .done)
        XCTAssertTrue(try String(contentsOf: backup, encoding: .utf8).contains("locant"), "the backup is the file before this write")
        XCTAssertFalse(try String(contentsOf: real, encoding: .utf8).contains("locant"))
        XCTAssertEqual(AgentConnector.status(.cursor, at: link), .notConnected)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: real.deletingLastPathComponent().path(percentEncoded: false)).sorted(), ["mcp.json", "mcp.json.locant-backup"])

        // A file that is not there yet is created, with no backup, and the folder with it.
        let fresh = dir.appending(path: "home2/.cursor/mcp.json")
        XCTAssertEqual(try AgentConnector.connect(.cursor, at: fresh, executable: exe, cli: nil), .done)
        XCTAssertEqual(AgentConnector.status(.cursor, at: fresh), .connected(executable: exe))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fresh.path(percentEncoded: false) + ".locant-backup"))

        // Codex's file, the same way.
        let toml = dir.appending(path: "home/.codex/config.toml")
        try FileManager.default.createDirectory(at: toml.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "model = \"gpt-5\"\n".write(to: toml, atomically: true, encoding: .utf8)
        XCTAssertEqual(try AgentConnector.connect(.codex, at: toml, executable: exe, cli: nil), .done)
        XCTAssertEqual(AgentConnector.status(.codex, at: toml), .connected(executable: exe))
        XCTAssertEqual(try String(contentsOf: toml.appendingPathExtension("locant-backup"), encoding: .utf8), "model = \"gpt-5\"\n")
        try "[mcp_servers]\nlocant = { command = \"/m\", args = [\n\"--mcp\"] }\n".write(to: toml, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try AgentConnector.connect(.codex, at: toml, executable: exe, cli: nil)) {
            XCTAssertTrue($0.localizedDescription.contains("already configured by hand"), $0.localizedDescription)
        }
        XCTAssertThrowsError(try AgentConnector.disconnect(.codex, at: toml, cli: nil))
        XCTAssertTrue(try String(contentsOf: toml, encoding: .utf8).hasPrefix("[mcp_servers]\nlocant = { command = \"/m\""), "left alone")
    }

    // 8: Claude Code without its CLI gets the command, and ~/.claude.json is never written (Nov 2 2026).
    func testClaudeCodeWithoutItsCLIShowsTheCommandAndLeavesTheFileAlone() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "LocantAgents-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: ".claude.json")
        let state = #"{"numStartups": 3, "mcpServers": {}}"#
        try state.write(to: url, atomically: true, encoding: .utf8)

        XCTAssertEqual(try AgentConnector.connect(.claudeCode, at: url, executable: exe, cli: nil), .command("claude mcp add --scope user locant -- \(exe) --mcp"))
        XCTAssertEqual(try AgentConnector.disconnect(.claudeCode, at: url, cli: nil), .command("claude mcp remove --scope user locant"))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), state)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false)), [".claude.json"])
        XCTAssertEqual(try AgentConnector.connect(.claudeCode, at: url, executable: "/Applications/My Apps/Locant.app/Contents/MacOS/Locant", cli: nil),
                       .command("claude mcp add --scope user locant -- '/Applications/My Apps/Locant.app/Contents/MacOS/Locant' --mcp"))
        XCTAssertEqual(AgentConfig.shellQuoted("it's"), "'it'\\''s'")

        // The login shell finds what the fixed folders do not; a name nobody has stays nil.
        XCTAssertEqual(AgentConnector.cliURL("uname")?.path(percentEncoded: false), "/usr/bin/uname")
        XCTAssertNil(AgentConnector.shellLookup("locant-no-such-tool-\(UUID().uuidString.prefix(6))"))
        XCTAssertNil(AgentConnector.shellLookup("ls; echo"), "only a name goes to the shell")
    }

    // 9: a path that dies with the eject or the move is refused before anything is written (Nov 2 2026).
    func testConnectRefusesAnExecutableThatWillStopWorking() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "LocantAgents-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: ".cursor/mcp.json")
        for executable in ["/Volumes/Locant/Locant.app/Contents/MacOS/Locant",
                           "/private/var/folders/x1/T/AppTranslocation/1B2C/d/Locant.app/Contents/MacOS/Locant"] {
            XCTAssertTrue(AgentConfig.isTemporaryLocation(executable))
            XCTAssertThrowsError(try AgentConnector.connect(.cursor, at: url, executable: executable, cli: nil)) {
                XCTAssertEqual($0 as? AgentConnector.Failure, .temporaryLocation)
                XCTAssertEqual($0.localizedDescription, "Move Locant to Applications first.")
            }
            XCTAssertThrowsError(try AgentConnector.connect(.claudeCode, at: url, executable: executable, cli: nil))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path(percentEncoded: false)))
        XCTAssertFalse(AgentConfig.isTemporaryLocation(exe))
        XCTAssertFalse(AgentConfig.isTemporaryLocation("/Users/me/Volumes/Locant"))
    }
}
