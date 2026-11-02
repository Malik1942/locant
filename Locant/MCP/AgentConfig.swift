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

    /// The command-line tool that owns the file, when only it should do the editing. Claude Code's
    /// `~/.claude.json` is its private state, rewritten while Claude Code runs, so its CLI writes
    /// there and Locant never does (Nov 2 2026): without the CLI the row shows the command instead.
    /// Codex's config.toml is the user's own file, and `codex mcp add` re-serializes all of it; one
    /// appended table is gentler.
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
        /// The TOML defines `locant` in a form Locant cannot cut out line by line (a value that
        /// runs on past its line, an array of tables): the user edits it.
        case configuredByHand
    }

    /// A path that stops working on its own: a mounted disk image (`/Volumes/…`, gone at the
    /// eject after the drag) or Gatekeeper's translocation folder, where a downloaded app runs
    /// until it is moved. Written into an agent's config, it would break at the next start.
    static func isTemporaryLocation(_ executable: String) -> Bool {
        executable.hasPrefix("/Volumes/") || executable.contains("/AppTranslocation/")
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

    /// The `[mcp_servers.locant]` table appended after everything else; an older definition
    /// removed first, in whichever form the file wrote it. Throws `configuredByHand` when that
    /// form cannot be removed safely, so the file is left alone rather than given a second
    /// `locant`, which Codex refuses to parse.
    static func tomlAdding(_ text: String?, executable: String) throws -> String {
        var body = try tomlRemoving(text) ?? (text ?? "")
        if !body.isEmpty, !body.hasSuffix("\n") { body += "\n" }
        if !body.isEmpty, !body.hasSuffix("\n\n") { body += "\n" }
        let args = arguments.map { tomlString($0) }.joined(separator: ", ")
        return body + "\(tomlHeader)\ncommand = \(tomlString(executable))\nargs = [\(args)]\n"
    }

    /// Every line that defines the server removed: its table and sub-tables, under any spelling of
    /// the header, or an inline table or dotted keys under `[mcp_servers]`. Nil when there was none;
    /// `configuredByHand` when a line's value runs on past it or the server is an array of tables.
    static func tomlRemoving(_ text: String?) throws -> String? {
        guard let text, let entry = tomlEntry(text) else { return nil }
        guard entry.removable else { throw Failure.configuredByHand }
        var lines = text.components(separatedBy: "\n")
        // Each run of lines, from the last: cut it, then one of the two blank lines it leaves touching.
        for run in runs(entry.lines).reversed() {
            lines.removeSubrange(run)
            if run.lowerBound > 0, run.lowerBound < lines.count,
               lines[run.lowerBound - 1].trimmingCharacters(in: .whitespaces).isEmpty,
               lines[run.lowerBound].trimmingCharacters(in: .whitespaces).isEmpty {
                lines.remove(at: run.lowerBound)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// The executable the `locant` server runs, in whichever form the file defines it. Nil when
    /// there is no server, and when it names no `command`: neither is a connection.
    static func tomlExecutable(_ text: String?) -> String? {
        guard let text else { return nil }
        return tomlEntry(text)?.command
    }

    /// Where a file defines the server. Line-based: Codex's file is the user's own, so the rewrite
    /// cuts whole lines and appends, and never re-serializes.
    private struct TOMLEntry {
        /// The lines of its table and sub-tables, and of an inline table or dotted keys under
        /// `[mcp_servers]` (or dotted from the root).
        var lines: [Int] = []
        /// False when cutting those lines would break the file: a value that runs on past its line
        /// (a multi-line array or string), or an `[[array]]` of tables.
        var removable = true
        var command: String?
    }

    private static func tomlEntry(_ text: String) -> TOMLEntry? {
        var entry = TOMLEntry()
        var table: [String] = []
        var inTable = false
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            if let header = tomlHeader(line) {
                table = header.path
                inTable = isServer(header.path)
                if inTable {
                    entry.lines.append(index)
                    if header.array { entry.removable = false }
                }
                continue
            }
            if inTable { entry.lines.append(index) }
            guard let pair = tomlKeyValue(line) else { continue }
            let path = table + pair.path
            guard isServer(path) else { continue }
            if entry.command == nil {
                if path.count == 3, path[2] == "command" { entry.command = tomlUnquote(pair.value) }
                if path.count == 2 { entry.command = tomlInlineCommand(pair.value) }
            }
            if !inTable {
                entry.lines.append(index)
                if !tomlScan(Substring(pair.value)) { entry.removable = false }
            }
        }
        return entry.lines.isEmpty ? nil : entry
    }

    private static func isServer(_ path: [String]) -> Bool {
        path.count >= 2 && path[0] == "mcp_servers" && path[1] == serverName
    }

    private static func runs(_ indices: [Int]) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        for index in indices.sorted() {
            if let last = runs.last, last.upperBound == index {
                runs[runs.count - 1] = last.lowerBound..<(index + 1)
            } else {
                runs.append(index..<(index + 1))
            }
        }
        return runs
    }

    /// A `[header]` or `[[header]]` line's key path, quotes and spaces dropped and a trailing
    /// comment allowed: `[mcp_servers."locant"] # mine` is `["mcp_servers", "locant"]`. Nil for any other line.
    private static func tomlHeader(_ line: String) -> (path: [String], array: Bool)? {
        let trimmed = Substring(line.trimmingCharacters(in: .whitespaces))
        guard trimmed.hasPrefix("[") else { return nil }
        let array = trimmed.hasPrefix("[[")
        let close = array ? "]]" : "]"
        guard let parsed = tomlKeyPath(trimmed.dropFirst(close.count)), parsed.rest.hasPrefix(close) else { return nil }
        let after = parsed.rest.dropFirst(close.count).drop { $0 == " " || $0 == "\t" }
        guard after.isEmpty || after.hasPrefix("#") else { return nil }
        return (parsed.path, array)
    }

    /// A `key = value` line's key path and the text of its value, comment and all.
    private static func tomlKeyValue(_ line: String) -> (path: [String], value: String)? {
        let trimmed = Substring(line.trimmingCharacters(in: .whitespaces))
        guard let first = trimmed.first, first != "[", first != "#" else { return nil }
        guard let parsed = tomlKeyPath(trimmed), parsed.rest.hasPrefix("=") else { return nil }
        return (parsed.path, parsed.rest.dropFirst().trimmingCharacters(in: .whitespaces))
    }

    /// The dotted keys at the start of `s`, bare or quoted, and what follows them. Nil without one.
    private static func tomlKeyPath(_ s: Substring) -> (path: [String], rest: Substring)? {
        var path: [String] = []
        var cursor = s
        while true {
            cursor = cursor.drop { $0 == " " || $0 == "\t" }
            guard let first = cursor.first else { break }
            if first == "\"" || first == "'" {
                var key = ""
                var index = cursor.index(after: cursor.startIndex)
                var closed = false
                while index < cursor.endIndex {
                    let ch = cursor[index]
                    if first == "\"", ch == "\\", cursor.index(after: index) < cursor.endIndex {
                        key.append(cursor[cursor.index(after: index)])
                        index = cursor.index(index, offsetBy: 2)
                        continue
                    }
                    index = cursor.index(after: index)
                    if ch == first { closed = true; break }
                    key.append(ch)
                }
                guard closed else { return nil }
                path.append(key)
                cursor = cursor[index...]
            } else {
                let bare = cursor.prefix { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
                guard !bare.isEmpty else { break }
                path.append(String(bare))
                cursor = cursor[bare.endIndex...]
            }
            let next = cursor.drop { $0 == " " || $0 == "\t" }
            guard next.first == "." else { cursor = next; break }
            cursor = next.dropFirst()
        }
        guard !path.isEmpty else { return nil }
        return (path, cursor)
    }

    /// The `command` of an inline table, `{ command = "…", args = […] }`, read from what is on
    /// its line whether or not the table closes there, so a table that runs on still reports the
    /// command it names. Nil when the value is not one or names no whole command.
    private static func tomlInlineCommand(_ value: String) -> String? {
        let whole = Substring(value)
        guard whole.hasPrefix("{") else { return nil }
        var close: Substring.Index?
        _ = tomlScan(whole) { index, depth in if close == nil, depth == 0, whole[index] == "}" { close = index } }
        let inner = whole[whole.index(after: whole.startIndex)..<(close ?? whole.endIndex)]
        var cuts: [Substring.Index] = []
        _ = tomlScan(inner) { index, depth in if depth == 0, inner[index] == "," { cuts.append(index) } }
        var parts: [Substring] = []
        var start = inner.startIndex
        for cut in cuts {
            parts.append(inner[start..<cut])
            start = inner.index(after: cut)
        }
        parts.append(inner[start...])
        for part in parts {
            guard let pair = tomlKeyValue(String(part)), pair.path == ["command"], tomlScan(Substring(pair.value)) else { continue }
            return tomlUnquote(pair.value)
        }
        return nil
    }

    /// Walks the text of a value, `visit` seeing each character outside strings with the bracket
    /// depth at it. True when every string and bracket closes on the line: a `#` at depth zero
    /// ends it as a comment, one inside a bracket leaves the bracket open.
    private static func tomlScan(_ s: Substring, _ visit: (Substring.Index, Int) -> Void = { _, _ in }) -> Bool {
        var depth = 0
        var index = s.startIndex
        while index < s.endIndex {
            let ch = s[index]
            switch ch {
            case "\"", "'":
                let quote = s[index...].hasPrefix(String(repeating: ch, count: 3)) ? String(repeating: ch, count: 3) : String(ch)
                var cursor = s.index(index, offsetBy: quote.count)
                var closed = false
                while cursor < s.endIndex {
                    if ch == "\"", s[cursor] == "\\" {
                        cursor = s.index(cursor, offsetBy: 2, limitedBy: s.endIndex) ?? s.endIndex
                        continue
                    }
                    if s[cursor...].hasPrefix(quote) {
                        cursor = s.index(cursor, offsetBy: quote.count)
                        closed = true
                        break
                    }
                    cursor = s.index(after: cursor)
                }
                guard closed else { return false }
                index = cursor
                continue
            case "#":
                return depth == 0
            case "[", "{":
                depth += 1
            case "]", "}":
                depth -= 1
                guard depth >= 0 else { return false }
            default:
                break
            }
            visit(index, depth)
            index = s.index(after: index)
        }
        return depth == 0
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
        (try? tomlAdding(nil, executable: executable)) ?? ""
    }

    /// The path as a shell reads it: bare when it has only path characters, else single-quoted.
    static func shellQuoted(_ s: String) -> String {
        let bare = !s.isEmpty && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "/._-+:@%".contains($0)) }
        return bare ? s : "'" + s.replacing("'", with: "'\\''") + "'"
    }
}

/// R56: reads and writes the agents' files, through their CLIs when those exist. The CLI lookup
/// and the writes to the real files are not tested; the file editing is, on temporary files.
enum AgentConnector {
    enum Failure: Error, LocalizedError, Equatable {
        case cli(String)
        case file(String)
        /// The executable is on a mounted dmg or in Gatekeeper's translocation folder (Nov 2 2026):
        /// written into an agent's config, that path breaks at the eject or the move.
        case temporaryLocation

        var errorDescription: String? {
            switch self {
            case .cli(let message), .file(let message): message
            case .temporaryLocation: "Move Locant to Applications first."
            }
        }
    }

    /// What Connect or Disconnect did: the agent's file written or its CLI run; or, for Claude
    /// Code without a `claude` on this Mac, nothing, and the command the user runs in its place.
    enum Outcome: Equatable, Sendable {
        case done
        case command(String)
    }

    /// This copy of Locant, as the agents will start it.
    static var executable: String {
        (Bundle.main.executableURL ?? URL(filePath: CommandLine.arguments[0])).resolvingSymlinksInPath().path(percentEncoded: false)
    }

    static func status(_ agent: Agent) -> AgentStatus {
        status(agent, at: agent.configURL)
    }

    static func status(_ agent: Agent, at url: URL) -> AgentStatus {
        let text = try? String(contentsOf: url, encoding: .utf8)
        let found = agent == .codex ? AgentConfig.tomlExecutable(text) : AgentConfig.jsonExecutable(text)
        return found.map { .connected(executable: $0) } ?? .notConnected
    }

    static func connect(_ agent: Agent) throws -> Outcome {
        try connect(agent, at: agent.configURL, executable: executable, cli: agent.cli.flatMap(cliURL))
    }

    static func disconnect(_ agent: Agent) throws -> Outcome {
        try disconnect(agent, at: agent.configURL, cli: agent.cli.flatMap(cliURL))
    }

    /// `url` is the agent's file and `cli` its tool when found; both are parameters so tests run on
    /// temporary files with no tool.
    static func connect(_ agent: Agent, at url: URL, executable: String, cli: URL?) throws -> Outcome {
        guard !AgentConfig.isTemporaryLocation(executable) else { throw Failure.temporaryLocation }
        if let name = agent.cli {
            guard let cli else { return .command(commandLine(name, addArguments(agent, executable: executable))) }
            _ = try? run(cli, removeArguments(agent))
            try run(cli, addArguments(agent, executable: executable))
            return .done
        }
        let text = try? String(contentsOf: url, encoding: .utf8)
        let updated: String
        do {
            updated = agent == .codex ? try AgentConfig.tomlAdding(text, executable: executable) : try AgentConfig.jsonAdding(text, executable: executable)
        } catch AgentConfig.Failure.configuredByHand {
            throw Failure.file("\(AgentConfig.serverName) is already configured by hand in \(url.path(percentEncoded: false)); edit it there.")
        } catch {
            throw Failure.file("\(url.path(percentEncoded: false)) is not JSON; add the server by hand.")
        }
        try write(updated, to: url)
        return .done
    }

    static func disconnect(_ agent: Agent, at url: URL, cli: URL?) throws -> Outcome {
        if let name = agent.cli {
            guard let cli else { return .command(commandLine(name, removeArguments(agent))) }
            try run(cli, removeArguments(agent))
            return .done
        }
        let text = try? String(contentsOf: url, encoding: .utf8)
        let updated: String?
        do {
            updated = agent == .codex ? try AgentConfig.tomlRemoving(text) : try AgentConfig.jsonRemoving(text)
        } catch AgentConfig.Failure.configuredByHand {
            throw Failure.file("\(AgentConfig.serverName) is already configured by hand in \(url.path(percentEncoded: false)); edit it there.")
        } catch {
            throw Failure.file("\(url.path(percentEncoded: false)) is not JSON; remove the server by hand.")
        }
        if let updated { try write(updated, to: url) }
        return .done
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

    /// The command as the user pastes it in a terminal.
    private static func commandLine(_ name: String, _ arguments: [String]) -> String {
        ([name] + arguments).map(AgentConfig.shellQuoted).joined(separator: " ")
    }

    /// The agent's command-line tool: in the places installers put it, else where the user's login
    /// shell finds it, since nvm, fnm, volta and the like put it on a PATH only the shell's rc files
    /// set and the app's own PATH is empty. Nil when neither knows it.
    static func cliURL(_ name: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appending(path: ".local/bin/\(name)"),
            URL(filePath: "/opt/homebrew/bin/\(name)"),
            URL(filePath: "/usr/local/bin/\(name)"),
            home.appending(path: ".claude/local/\(name)"),
            home.appending(path: ".npm-global/bin/\(name)"),
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path(percentEncoded: false)) }) { return found }
        return shellLookup(name)
    }

    /// `command -v <name>` in the user's login shell, interactive so its rc files run, under a
    /// deadline: an rc file that waits on something (a prompt, a tmux) must not hold Settings.
    /// The output goes to a file, not a pipe, so a chatty rc file or a background job it starts
    /// cannot block the read. The answer is the last line that is an executable's path; an alias
    /// or a function is not one.
    static func shellLookup(_ name: String, timeout: TimeInterval = 5) -> URL? {
        guard !name.isEmpty, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") }) else { return nil }
        let output = FileManager.default.temporaryDirectory.appending(path: "locant-cli-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: output.path(percentEncoded: false), contents: nil),
              let handle = try? FileHandle(forWritingTo: output) else { return nil }
        defer { try? FileManager.default.removeItem(at: output) }
        let process = Process()
        process.executableURL = loginShell
        process.arguments = ["-lic", "command -v \(name)"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }
        try? handle.close()
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut { kill(process.processIdentifier, SIGKILL) }
            return nil
        }
        guard process.terminationStatus == 0, let data = try? Data(contentsOf: output) else { return nil }
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.last { $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0) }.map { URL(filePath: $0) }
    }

    /// The user's login shell from the directory, `/bin/zsh` when it names none that runs.
    private static var loginShell: URL {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell, let path = String(validatingCString: shell),
           FileManager.default.isExecutableFile(atPath: path) {
            return URL(filePath: path)
        }
        return URL(filePath: "/bin/zsh")
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

    /// The text written to the file the path leads to: through a symlink to the file it names (a
    /// dotfiles checkout, say) and into that file, never over the link and never as a new inode,
    /// so its hard links, mode, and attributes stay. One backup of what was there, `<name>.locant-backup`
    /// beside it, before each rewrite. Nov 2 2026; before, the atomic write replaced the link with a plain file.
    static func write(_ text: String, to url: URL) throws {
        let target = url.resolvingSymlinksInPath()
        let path = target.path(percentEncoded: false)
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard FileManager.default.fileExists(atPath: path) else {
                try Data(text.utf8).write(to: target, options: .atomic)
                return
            }
            let backup = target.appendingPathExtension("locant-backup")
            if FileManager.default.fileExists(atPath: backup.path(percentEncoded: false)) { try FileManager.default.removeItem(at: backup) }
            try FileManager.default.copyItem(at: target, to: backup)
            let handle = try FileHandle(forWritingTo: target)
            defer { try? handle.close() }
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: Data(text.utf8))
        } catch {
            throw Failure.file("Could not write \(path): \(error.localizedDescription)")
        }
    }
}
