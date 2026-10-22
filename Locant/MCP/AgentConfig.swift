import Foundation

/// v0.7.1 R56: the three agents Settings can connect, in Malik's order.
enum Agent: String, CaseIterable, Identifiable, Sendable {
    case claudeCode, cursor, codex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .cursor: "Cursor"
        case .codex: "Codex"
        }
    }

    /// The agent's own user-level MCP configuration.
    var configURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .claudeCode: return home.appending(path: ".claude.json")
        case .cursor: return home.appending(path: ".cursor/mcp.json")
        case .codex: return home.appending(path: ".codex/config.toml")
        }
    }

    /// The command-line tool that owns the file, when it should do the editing. Claude Code's
    /// `~/.claude.json` is its private state, so its CLI writes there. Codex's config.toml is the
    /// user's own file, and `codex mcp add` re-serializes all of it; one appended table is gentler.
    var cli: String? {
        switch self {
        case .claudeCode: "claude"
        case .cursor, .codex: nil
        }
    }
}

enum AgentStatus: Equatable, Sendable {
    case notConnected
    /// The agent names a Locant executable; the view compares it with this copy's.
    case connected(executable: String)
}

/// The text of each agent's configuration with the `locant` server added or removed. Pure; the
/// files and the CLIs are `AgentConnector`'s.
enum AgentConfig {
    static let serverName = "locant"
    static let arguments = ["--mcp"]

    enum Failure: Error, Equatable {
        case notJSON
        case notAnObject
    }

    // MARK: JSON (Claude Code's ~/.claude.json, Cursor's mcp.json, any .mcp.json)

    /// `mcpServers.locant` set to this executable; every other key kept.
    static func jsonAdding(_ text: String?, executable: String) throws -> String {
        var root = try jsonObject(text)
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        servers[serverName] = ["command": executable, "args": arguments]
        root["mcpServers"] = servers
        return try jsonText(root)
    }

    /// `mcpServers.locant` removed. Nil when there was nothing to remove, so the file is left alone.
    static func jsonRemoving(_ text: String?) throws -> String? {
        var root = try jsonObject(text)
        guard var servers = root["mcpServers"] as? [String: Any], servers[serverName] != nil else { return nil }
        servers[serverName] = nil
        root["mcpServers"] = servers
        return try jsonText(root)
    }

    /// The executable the configured `locant` server runs, or nil when there is none.
    static func jsonExecutable(_ text: String?) -> String? {
        guard let root = try? jsonObject(text),
              let servers = root["mcpServers"] as? [String: Any],
              let server = servers[serverName] as? [String: Any] else { return nil }
        return server["command"] as? String ?? ""
    }

    private static func jsonObject(_ text: String?) throws -> [String: Any] {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [:] }
        guard let data = text.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) else { throw Failure.notJSON }
        guard let dictionary = object as? [String: Any] else { throw Failure.notAnObject }
        return dictionary
    }

    private static func jsonText(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    // MARK: TOML (Codex's config.toml)

    static let tomlHeader = "[mcp_servers.\(serverName)]"

    /// The `[mcp_servers.locant]` table appended after everything else; an older one removed first.
    static func tomlAdding(_ text: String?, executable: String) -> String {
        var body = tomlRemoving(text) ?? (text ?? "")
        if !body.isEmpty, !body.hasSuffix("\n") { body += "\n" }
        if !body.isEmpty, !body.hasSuffix("\n\n") { body += "\n" }
        let args = arguments.map { tomlString($0) }.joined(separator: ", ")
        return body + "\(tomlHeader)\ncommand = \(tomlString(executable))\nargs = [\(args)]\n"
    }

    /// The table and its sub-tables removed. Nil when there was none.
    static func tomlRemoving(_ text: String?) -> String? {
        guard let text, let range = tomlTableRange(text) else { return nil }
        var lines = text.components(separatedBy: "\n")
        lines.removeSubrange(range)
        // One blank line where the table was, not two.
        if range.lowerBound > 0, range.lowerBound < lines.count,
           lines[range.lowerBound - 1].trimmingCharacters(in: .whitespaces).isEmpty,
           lines[range.lowerBound].trimmingCharacters(in: .whitespaces).isEmpty {
            lines.remove(at: range.lowerBound)
        }
        return lines.joined(separator: "\n")
    }

    static func tomlExecutable(_ text: String?) -> String? {
        guard let text, let range = tomlTableRange(text) else { return nil }
        let lines = text.components(separatedBy: "\n")[range]
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("command") else { continue }
            let value = trimmed.drop { $0 != "=" }.dropFirst().trimmingCharacters(in: .whitespaces)
            return tomlUnquote(value)
        }
        return ""
    }

    /// Lines of the `[mcp_servers.locant]` table: its header through the line before the next
    /// header that is not one of its sub-tables, or the end.
    private static func tomlTableRange(_ text: String) -> Range<Int>? {
        let lines = text.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == tomlHeader }) else { return nil }
        var end = start + 1
        while end < lines.count {
            let trimmed = lines[end].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("["), !trimmed.hasPrefix("[mcp_servers.\(serverName).") { break }
            end += 1
        }
        return start..<end
    }

    private static func tomlString(_ s: String) -> String {
        "\"" + s.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"") + "\""
    }

    /// A basic or literal TOML string, or a bare value, with a trailing comment dropped.
    private static func tomlUnquote(_ s: String) -> String {
        let v = s.trimmingCharacters(in: .whitespaces)
        if v.hasPrefix("\"") {
            var out = ""
            var escaped = false
            for ch in v.dropFirst() {
                if escaped { out.append(ch); escaped = false; continue }
                if ch == "\\" { escaped = true; continue }
                if ch == "\"" { break }
                out.append(ch)
            }
            return out
        }
        if v.hasPrefix("'") {
            return String(v.dropFirst().prefix { $0 != "'" })
        }
        return String(v.prefix { $0 != "#" }).trimmingCharacters(in: .whitespaces)
    }

    // MARK: Snippets (README, Copy)

    /// What any MCP client that runs stdio servers needs.
    static func jsonSnippet(executable: String) -> String {
        (try? jsonText(["mcpServers": [serverName: ["command": executable, "args": arguments]]])) ?? ""
    }

    static func tomlSnippet(executable: String) -> String {
        tomlAdding(nil, executable: executable)
    }
}

/// R56: reads and writes the agents' files, through their CLIs when those exist. Not pure; not tested.
enum AgentConnector {
    enum Failure: Error, LocalizedError {
        case cli(String)
        case file(String)

        var errorDescription: String? {
            switch self {
            case .cli(let message), .file(let message): message
            }
        }
    }

    /// This copy of Locant, as the agents will start it.
    static var executable: String {
        (Bundle.main.executableURL ?? URL(filePath: CommandLine.arguments[0])).resolvingSymlinksInPath().path(percentEncoded: false)
    }

    static func status(_ agent: Agent) -> AgentStatus {
        let text = try? String(contentsOf: agent.configURL, encoding: .utf8)
        let found = agent == .codex ? AgentConfig.tomlExecutable(text) : AgentConfig.jsonExecutable(text)
        return found.map { .connected(executable: $0) } ?? .notConnected
    }

    static func connect(_ agent: Agent, executable: String = executable) throws {
        if let cli = agent.cli, let url = cliURL(cli) {
            _ = try? run(url, removeArguments(agent))
            try run(url, addArguments(agent, executable: executable))
            return
        }
        let text = try? String(contentsOf: agent.configURL, encoding: .utf8)
        let updated: String
        do {
            updated = agent == .codex ? AgentConfig.tomlAdding(text, executable: executable) : try AgentConfig.jsonAdding(text, executable: executable)
        } catch {
            throw Failure.file("\(agent.configURL.path(percentEncoded: false)) is not JSON; add the server by hand.")
        }
        try write(updated, to: agent.configURL)
    }

    static func disconnect(_ agent: Agent) throws {
        if let cli = agent.cli, let url = cliURL(cli) {
            try run(url, removeArguments(agent))
            return
        }
        let text = try? String(contentsOf: agent.configURL, encoding: .utf8)
        let updated: String?
        do {
            updated = agent == .codex ? AgentConfig.tomlRemoving(text) : try AgentConfig.jsonRemoving(text)
        } catch {
            throw Failure.file("\(agent.configURL.path(percentEncoded: false)) is not JSON; remove the server by hand.")
        }
        if let updated { try write(updated, to: agent.configURL) }
    }

    private static func addArguments(_ agent: Agent, executable: String) -> [String] {
        switch agent {
        case .claudeCode: ["mcp", "add", "--scope", "user", AgentConfig.serverName, "--", executable] + AgentConfig.arguments
        case .codex: ["mcp", "add", AgentConfig.serverName, "--", executable] + AgentConfig.arguments
        case .cursor: []
        }
    }

    private static func removeArguments(_ agent: Agent) -> [String] {
        switch agent {
        case .claudeCode: ["mcp", "remove", "--scope", "user", AgentConfig.serverName]
        case .codex: ["mcp", "remove", AgentConfig.serverName]
        case .cursor: []
        }
    }

    /// The agent's command-line tool, in the places installers put it; the app's PATH is empty.
    static func cliURL(_ name: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appending(path: ".local/bin/\(name)"),
            URL(filePath: "/opt/homebrew/bin/\(name)"),
            URL(filePath: "/usr/local/bin/\(name)"),
            home.appending(path: ".claude/local/\(name)"),
            home.appending(path: ".npm-global/bin/\(name)"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path(percentEncoded: false)) }
    }

    private static func run(_ url: URL, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = url
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", environment["PATH"] ?? ""].joined(separator: ":")
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
        } catch {
            throw Failure.cli("\(url.lastPathComponent) could not start: \(error.localizedDescription)")
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.cli("\(url.lastPathComponent) \(arguments.prefix(2).joined(separator: " ")) failed: \(text.split(separator: "\n").last.map(String.init) ?? "exit \(process.terminationStatus)")")
        }
    }

    private static func write(_ text: String, to url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw Failure.file("Could not write \(url.path(percentEncoded: false)): \(error.localizedDescription)")
        }
    }
}
