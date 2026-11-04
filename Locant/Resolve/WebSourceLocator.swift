import Foundation

/// Prototype: the component, props and source lines of a web node, the way Claude's Browser picker
/// shows them. Accessibility stops at the DOM's id and classes; React keeps the rest on the node in
/// development builds, readable only by a script in the page. Chrome runs one for us through its
/// `execute javascript` Apple Event when the user has turned on View › Developer › Allow JavaScript
/// from Apple Events. Nothing here changes the page, and every failure is a nil: the capture goes on
/// with what accessibility gave it.
enum WebSourceLocator {
    /// Chrome first. Its sdef's `execute` command; Dia has the same one behind a launch flag, Safari
    /// a different one (`do JavaScript`).
    static let chromeBundleIds: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
    ]

    static func supports(bundleId: String?) -> Bool {
        bundleId.map(chromeBundleIds.contains) ?? false
    }

    /// How long a capture waits for the answer at Enter. The lookup starts at the click, so the note
    /// usually covers it; the first call in a session reads source maps and takes up to a second.
    static let commitWait: Duration = .milliseconds(1500)
    /// How long the Apple Event may run before it is abandoned. Long, so the first-use Automation
    /// prompt can be answered; the capture never waits this long.
    static let processTimeout: TimeInterval = 30

    /// Looks the element up in the page the capture came from. Nil when the browser is not supported,
    /// JavaScript from Apple Events is off, the page is not a React development build, or the tab
    /// that shows `url` cannot be found.
    static func locate(element: ResolvedElement, bundleId: String, url: String) async -> ComponentInfo? {
        guard supports(bundleId: bundleId), let main = pageScript(for: element) else { return nil }
        let wrapped = pageWorldScript(main, event: "locant-web-source-" + UUID().uuidString.prefix(8).lowercased())
        guard let reply = await runAppleScript(chromeScript(bundleId: bundleId), arguments: [wrapped, matchURL(url)]) else { return nil }
        guard var info = parse(reply) else {
            log("no component: \(reply.prefix(300))")
            return nil
        }
        if let root = devServerRoot(for: url) {
            info.source = info.source.map { absolutize($0, root: root) }
            info.renderedAt = info.renderedAt.map { absolutize($0, root: root) }
        }
        return info
    }

    /// The task's answer if it comes within `limit`, else nil. The task keeps running either way, so a
    /// first-use Automation prompt answered later still counts for the next capture.
    static func answer<T: Sendable>(of task: Task<T?, Never>, within limit: Duration) async -> T? {
        let once = ResumeOnce<T?>()
        return await withCheckedContinuation { continuation in
            once.set(continuation)
            Task { once.resume(await task.value) }
            Task { try? await Task.sleep(for: limit); once.resume(nil) }
        }
    }

    // MARK: Scripts

    /// The in-page script with this element's handles filled in. Nil when the resource is missing.
    static func pageScript(for element: ResolvedElement) -> String? {
        guard let url = Bundle.main.url(forResource: "web-source", withExtension: "js"),
              let template = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let f = element.frame
        let args: [String: Any] = [
            "id": element.dom?.id ?? NSNull(),
            "classes": element.dom?.classes ?? [],
            "frame": ["x": f.x, "y": f.y, "w": f.w, "h": f.h],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: args),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return template.replacingOccurrences(of: "__LOCANT_ARGS__", with: json)
    }

    /// Chrome runs Apple Event JavaScript in an isolated world: the DOM is shared, the properties React
    /// sets on its nodes are not. A script element runs in the page's own world, synchronously, and
    /// hands its answer back in a DOM event both worlds see. A page whose Content-Security-Policy
    /// forbids inline scripts never runs it.
    static func pageWorldScript(_ main: String, event: String) -> String {
        let ev = jsString(event)
        let inner = "document.dispatchEvent(new CustomEvent(" + ev + ",{detail:" + main + "}))"
        return "(function(){var out=null;function h(e){out=e.detail}"
            + "document.addEventListener(\(ev),h);var s=document.createElement('script');"
            + "s.textContent=\(jsString(inner));(document.head||document.documentElement).appendChild(s);s.remove();"
            + "document.removeEventListener(\(ev),h);"
            + "return out||JSON.stringify({v:1,error:'the page did not run the script (Content-Security-Policy?)'})})()"
    }

    /// Finds the frontmost window whose active tab shows the captured page and runs the script there.
    static func chromeScript(bundleId: String) -> String {
        """
        on run argv
            set js to item 1 of argv
            set wanted to item 2 of argv
            tell application id "\(bundleId)"
                repeat with w in windows
                    set t to active tab of w
                    if (URL of t) starts with wanted then return execute t javascript js
                end repeat
            end tell
            return "{\\"v\\":1,\\"error\\":\\"no window shows the captured page\\"}"
        end run
        """
    }

    /// The page address without its fragment: a hash route the page changed since is still the page.
    static func matchURL(_ url: String) -> String {
        url.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? url
    }

    private static func jsString(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [s]), let json = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(json.dropFirst().dropLast())
    }

    // MARK: The reply

    private struct Reply: Decodable {
        struct Location: Decodable { var file: String; var line: Int; var column: Int? }
        struct Prop: Decodable { var name: String; var value: String }
        var framework: String?
        var components: [String]?
        var props: [Prop]?
        var source: Location?
        var renderedAt: Location?
        var error: String?
    }

    /// The script's JSON as a component. Nil when the page named no framework or no component.
    static func parse(_ json: String) -> ComponentInfo? {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: Data(json.utf8)),
              let framework = reply.framework, reply.error == nil else { return nil }
        let components = reply.components ?? []
        guard !components.isEmpty || reply.source != nil else { return nil }
        let location = { (l: Reply.Location) in SourceLocation(file: l.file, line: l.line, column: l.column) }
        return ComponentInfo(
            framework: framework,
            name: components.first,
            ancestors: Array(components.dropFirst()),
            props: (reply.props ?? []).map { ComponentProp(name: $0.name, value: $0.value) },
            source: reply.source.map(location),
            renderedAt: reply.renderedAt.map(location)
        )
    }

    // MARK: Files on this Mac

    /// For a localhost page, the folder the dev server runs in: the server's paths (`/src/Library.tsx`)
    /// are relative to it.
    static func devServerRoot(for url: String) -> String? {
        guard let parsed = URL(string: url), let host = parsed.host(), ModeInference.isLocalhost(host),
              let port = parsed.port else { return nil }
        guard let pid = run("/usr/sbin/lsof", ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"])?
            .split(separator: "\n").first.map(String.init) else { return nil }
        let cwd = run("/usr/sbin/lsof", ["-a", "-p", pid, "-d", "cwd", "-Fn"])?
            .split(separator: "\n").first { $0.hasPrefix("n") }.map { String($0.dropFirst()) }
        return cwd.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The server path as a file under `root` when that file exists; otherwise unchanged.
    static func absolutize(_ location: SourceLocation, root: String, exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> SourceLocation {
        guard location.file.hasPrefix("/"), !exists(location.file) else { return location }
        let candidate = (root as NSString).appendingPathComponent(location.file)
        guard exists(candidate) else { return location }
        var copy = location
        copy.file = candidate
        return copy
    }

    // MARK: Processes

    private static func runAppleScript(_ script: String, arguments: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: run("/usr/bin/osascript", ["-"] + arguments, stdin: script, timeout: processTimeout))
            }
        }
    }

    /// A short-lived tool's standard output, or nil when it failed or ran past `timeout`.
    private static func run(_ tool: String, _ arguments: [String], stdin: String? = nil, timeout: TimeInterval = 3) -> String? {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        let output = Pipe(), errors = Pipe(), input = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = stdin == nil ? FileHandle.nullDevice : input
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return nil }
        if let stdin {
            input.fileHandleForWriting.write(Data(stdin.utf8))
            try? input.fileHandleForWriting.close()
        }
        // The answers here are a few kilobytes, well under a pipe's buffer, so waiting before reading
        // cannot stall the tool, and the timeout holds.
        if done.wait(timeout: .now() + timeout) == .timedOut { process.terminate(); return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            if tool.hasSuffix("osascript") { log("osascript failed: \(errorText.trimmingCharacters(in: .whitespacesAndNewlines))") }
            return nil
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Prototype diagnostics: a line in ~/Library/Logs/Locant/web-source.log (NSLog prints <private>).
    static func log(_ line: String) {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Locant")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "web-source.log")
        let stamped = ISO8601DateFormatter().string(from: Date()) + " " + line + "\n"
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data(stamped.utf8))
            try? handle.close()
        } else {
            try? Data(stamped.utf8).write(to: file)
        }
    }
}

/// Resumes a continuation once, whichever of two racers comes first.
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?
    private var early: T?
    private var done = false

    func set(_ c: CheckedContinuation<T, Never>) {
        lock.lock()
        if done, let early {
            lock.unlock()
            c.resume(returning: early)
            return
        }
        continuation = c
        lock.unlock()
    }

    func resume(_ value: T) {
        lock.lock()
        guard !done else { lock.unlock(); return }
        done = true
        if let c = continuation {
            continuation = nil
            lock.unlock()
            c.resume(returning: value)
        } else {
            early = value
            lock.unlock()
        }
    }
}
