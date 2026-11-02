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
}
