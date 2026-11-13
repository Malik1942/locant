import AppKit
import ApplicationServices
import os

/// A browser Locant can ask to run a script in a page (specs/web-source.md R153). Every entry was read
/// from a real install: the words it refuses with, and that it answers Chromium's Apple Event,
/// `execute <tab> javascript`. Safari's is another (`do JavaScript`), not read yet, and not here.
struct WebBrowser: Sendable, Equatable, Identifiable {
    /// What the user turns on in the browser itself.
    enum Door: Sendable, Equatable {
        /// A menu item, by its path.
        case menu(String)
        /// An argument the browser must be opened with; it has no switch.
        case launchFlag(String)
    }

    var name: String
    var bundleIds: [String]
    var door: Door
    /// A phrase only this browser's refusal has, when its door is closed.
    var refusal: String
    /// The browser runs Apple Event scripts in a world of their own, where React's properties on the
    /// DOM are not visible; the script then goes through a script element (R148).
    var isolates: Bool

    var id: String { name }

    /// How to open the door, as Settings says it.
    var instruction: String {
        switch door {
        case .menu(let path): "Turn on \(path) in \(name)"
        case .launchFlag: "\(name) has to be opened from here"
        }
    }

    /// The copy of this browser that is installed, running first.
    var installedBundleId: String? {
        bundleIds.first { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
            ?? bundleIds.first { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
    }
}

/// The component, props and source lines of a web node, the way Claude's Browser picker shows them.
/// Accessibility stops at the DOM's id and classes; React keeps the rest on the node in development
/// builds, readable only by a script in the page. The browsers in `browsers` run one for Locant
/// through an Apple Event once the user has allowed it. The script reads and returns; the source maps
/// are read here. Every failure leaves the capture as accessibility gave it.
enum WebSourceLocator {
    private static let chromiumRefusal = "Executing JavaScript through AppleScript is turned off"
    private static let chromiumMenu = "View › Developer › Allow JavaScript from Apple Events"

    /// Read from real installs on Nov 13, 2026: Chrome 157, Edge 157, Brave 1.99, Dia 1.57.1. Arc has
    /// the command but opens only to a sign-in, and Firefox has no command at all; neither is here.
    static let browsers: [WebBrowser] = [
        WebBrowser(name: "Google Chrome",
                   bundleIds: ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary"],
                   door: .menu(chromiumMenu), refusal: chromiumRefusal, isolates: true),
        WebBrowser(name: "Dia", bundleIds: ["company.thebrowser.dia"],
                   door: .launchFlag("--enable-applescript-javascript"),
                   refusal: "--enable-applescript-javascript", isolates: true),
        WebBrowser(name: "Microsoft Edge",
                   bundleIds: ["com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Dev", "com.microsoft.edgemac.Canary"],
                   door: .menu(chromiumMenu), refusal: chromiumRefusal, isolates: true),
        WebBrowser(name: "Brave",
                   bundleIds: ["com.brave.Browser", "com.brave.Browser.beta", "com.brave.Browser.nightly"],
                   door: .menu(chromiumMenu), refusal: chromiumRefusal, isolates: true),
    ]

    static func browser(bundleId: String?) -> WebBrowser? {
        guard let bundleId else { return nil }
        return browsers.first { $0.bundleIds.contains(bundleId) }
    }

    /// R151: only a page a dev server on this Mac serves is asked. A page from anywhere else is
    /// someone's production build, with nothing to read but shortened names.
    static func asks(bundleId: String?, url: String?) -> Bool {
        guard browser(bundleId: bundleId) != nil, let url, let page = URL(string: url) else { return false }
        return WebSourceMaps.isLocal(page)
    }

    /// How long a capture waits for the answer at Enter. The lookup starts at the click, so the note
    /// usually covers it.
    static let commitWait: Duration = .milliseconds(1500)
    /// How long the Apple Event may run before it is abandoned.
    static let processTimeout: TimeInterval = 10

    // MARK: The lookup

    /// Why a lookup gave no component.
    enum Failure: Sendable, Equatable {
        /// macOS has not been asked yet whether Locant may script this browser. Never asked during a capture (R154).
        case notAsked
        /// The user said no to that.
        case denied
        /// The browser's own door is closed: its menu switch is off, or it was opened without its flag.
        case doorClosed
        /// No window's front tab shows the captured page.
        case noWindow
        /// The page answered, with nothing to say: not React, a production build, or it refused the script.
        case nothing(String)
        /// The browser did not answer, or answered with something else.
        case noAnswer(String)

        /// Whether a line in Settings would fix it.
        var needsSetup: Bool {
            switch self {
            case .notAsked, .denied, .doorClosed: true
            case .noWindow, .nothing, .noAnswer: false
            }
        }

        func reason(for browser: WebBrowser) -> String {
            switch self {
            case .notAsked: "Locant has not been allowed to ask \(browser.name) yet"
            case .denied: "Locant is not allowed to ask \(browser.name) (Privacy & Security › Automation)"
            case .doorClosed:
                if case .launchFlag(let flag) = browser.door { "\(browser.name) was opened without \(flag)" }
                else { "JavaScript from Apple Events is off in \(browser.name)" }
            case .noWindow: "no \(browser.name) window showed the page"
            case .nothing(let why): why
            case .noAnswer(let why): "\(browser.name) did not answer: \(why)"
            }
        }
    }

    enum Outcome: Sendable, Equatable {
        case found(ComponentInfo)
        case failed(Failure)
    }

    /// Looks the element up in the page the capture came from. `point` and `pid` find the page's
    /// viewport on screen through accessibility, so an element without an id is found by its place.
    static func locate(element: ResolvedElement, bundleId: String, url: String, point: CGPoint? = nil, pid: pid_t? = nil) async -> Outcome {
        guard let browser = browser(bundleId: bundleId), let page = URL(string: url), WebSourceMaps.isLocal(page) else {
            return .failed(.nothing("not a local page in a browser Locant can ask"))
        }
        let outcome = await lookUp(element: element, browser: browser, bundleId: bundleId, page: page, url: url, point: point, pid: pid)
        if case .failed(let failure) = outcome {
            log.notice("web source: \(failure.reason(for: browser), privacy: .public)")
        }
        return outcome
    }

    private static func lookUp(element: ResolvedElement, browser: WebBrowser, bundleId: String, page: URL, url: String,
                               point: CGPoint?, pid: pid_t?) async -> Outcome {
        switch permission(bundleId: bundleId, ask: false) {
        case .granted: break
        case .notAsked: return .failed(.notAsked)
        case .denied: return .failed(.denied)
        case .notRunning: return .failed(.noAnswer("it is not running"))
        }
        let area: CGRect? = if let point, let pid { viewport(at: point, pid: pid) } else { nil }
        guard let main = pageScript(for: element, area: area) else { return .failed(.noAnswer("the script is missing from the app")) }
        let script = browser.isolates
            ? pageWorldScript(main, event: "locant-web-source-" + UUID().uuidString.prefix(8).lowercased())
            : main
        let reply: String
        switch await runAppleScript(pageCommand(bundleId: bundleId), arguments: [script, matchURL(url)]) {
        case .success(let text): reply = unquoted(text)
        case .failure(let refusal): return .failed(failure(from: refusal.text, browser: browser))
        }
        guard let answer = decode(reply) else { return .failed(.noAnswer(String(reply.prefix(200)))) }
        if let error = answer.error {
            return .failed(error == noWindowError ? .noWindow : .nothing(error))
        }
        let components = answer.components ?? []
        guard let framework = answer.framework, !components.isEmpty || answer.source != nil else {
            return .failed(.nothing("the page named no component"))
        }
        let maps = WebSourceMaps(page: page, scripts: answer.scripts ?? [])
        let root = devServerRoot(for: url)
        func place(_ where: Answer.Where?) async -> SourceLocation? {
            guard let `where` else { return nil }
            var location: SourceLocation?
            if let file = `where`.file, let line = `where`.line {
                location = SourceLocation(file: file, line: line, column: `where`.column)
            } else if let stack = `where`.stack {
                location = await maps.location(of: stack)
            }
            guard let location else { return nil }
            return root.map { absolutize(location, root: $0) } ?? location
        }
        return .found(ComponentInfo(
            framework: framework,
            name: components.first,
            ancestors: Array(components.dropFirst()),
            props: (answer.props ?? []).map { ComponentProp(name: $0.name, value: $0.value) },
            source: await place(answer.source),
            renderedAt: await place(answer.renderedAt)
        ))
    }

    /// The task's answer if it comes within `limit`, else nil. The task keeps running either way.
    static func answer<T: Sendable>(of task: Task<T, Never>, within limit: Duration) async -> T? {
        let once = ResumeOnce<T?>()
        return await withCheckedContinuation { continuation in
            once.set(continuation)
            Task { once.resume(await task.value) }
            Task { try? await Task.sleep(for: limit); once.resume(nil) }
        }
    }

    // MARK: Permission

    enum Permission: Sendable, Equatable {
        case granted, notAsked, denied, notRunning
    }

    /// Whether macOS lets Locant send Apple Events to the browser. With `ask`, macOS shows its prompt
    /// when the user has not answered yet, and this waits for the answer: never on the main thread,
    /// and never during a capture (R154).
    static func permission(bundleId: String, ask: Bool) -> Permission {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty else { return .notRunning }
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleId)
        var status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask)
        if Int(status) == procNotFound {
            // Seen once for a browser that was running (Dia, Nov 13 2026): ask again before believing it.
            Thread.sleep(forTimeInterval: 0.1)
            status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask)
        }
        switch Int(status) {
        case Int(noErr): return .granted
        case errAEEventWouldRequireUserConsent: return .notAsked
        case procNotFound: return .notRunning
        default: return .denied
        }
    }

    // MARK: Settings

    /// Where a browser stands, for its row in Settings › Captures › Web pages (R155).
    enum Status: Sendable, Equatable {
        case notRunning
        case notAsked
        case denied
        case doorClosed
        /// Allowed and open, or allowed with no page open to try it on.
        case ready
    }

    /// Asks the browser to work out `0` in its front tab: enough to hear a refusal, and nothing a page can see.
    static func status(of browser: WebBrowser) async -> Status {
        guard let bundleId = browser.installedBundleId else { return .notRunning }
        switch permission(bundleId: bundleId, ask: false) {
        case .notRunning: return .notRunning
        case .notAsked: return .notAsked
        case .denied: return .denied
        case .granted: break
        }
        switch await runAppleScript(probeCommand(bundleId: bundleId), arguments: []) {
        case .success: return .ready
        case .failure(let refusal): return failure(from: refusal.text, browser: browser) == .doorClosed ? .doorClosed : .ready
        }
    }

    /// Shows macOS's own prompt for this browser and waits for the answer.
    static func requestPermission(for browser: WebBrowser) async -> Permission {
        guard let bundleId = browser.installedBundleId else { return .notRunning }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: permission(bundleId: bundleId, ask: true))
            }
        }
    }

    /// Opens a browser whose door is a launch argument, quitting it first when it runs without one.
    /// False when it would not quit; the user's tabs are the browser's own to restore.
    @MainActor
    static func open(_ browser: WebBrowser) async -> Bool {
        guard case .launchFlag(let flag) = browser.door, let bundleId = browser.installedBundleId,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return false }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleId) {
            app.terminate()
        }
        for _ in 0..<60 where !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty {
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = [flag]
        return (try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)) != nil
    }

    // MARK: Scripts

    /// The in-page script with this element's handles filled in. Nil when the resource is missing.
    static func pageScript(for element: ResolvedElement, area: CGRect? = nil) -> String? {
        guard let url = Bundle.main.url(forResource: "web-source", withExtension: "js"),
              let template = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let f = element.frame
        var args: [String: Any] = [
            "id": element.dom?.id ?? NSNull(),
            "classes": element.dom?.classes ?? [],
            "frame": ["x": f.x, "y": f.y, "w": f.w, "h": f.h],
        ]
        if let area, area.width > 0, area.height > 0 {
            args["area"] = ["x": area.minX, "y": area.minY, "w": area.width, "h": area.height]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: args),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return template.replacingOccurrences(of: "__LOCANT_ARGS__", with: json)
    }

    /// Chromium runs Apple Event JavaScript in an isolated world: the DOM is shared, the properties
    /// React sets on its nodes are not. A script element runs in the page's own world, synchronously,
    /// and hands its answer back in a DOM event both worlds see. A page whose Content-Security-Policy
    /// forbids inline scripts never runs it.
    static func pageWorldScript(_ main: String, event: String) -> String {
        let ev = jsString(event)
        let inner = "document.dispatchEvent(new CustomEvent(" + ev + ",{detail:" + main + "}))"
        return "(function(){var out=null;function h(e){out=e.detail}"
            + "document.addEventListener(\(ev),h);var s=document.createElement('script');"
            + "s.textContent=\(jsString(inner));(document.head||document.documentElement).appendChild(s);s.remove();"
            + "document.removeEventListener(\(ev),h);"
            + "return out||JSON.stringify({v:2,error:'the page did not run the script (Content-Security-Policy?)'})})()"
    }

    static let noWindowError = "no window shows the captured page"

    /// Finds the window whose front tab shows the captured page and runs the script there. A window
    /// without a tab is passed over; the browser's refusal to run the script is not.
    static func pageCommand(bundleId: String) -> String {
        """
        on run argv
            set js to item 1 of argv
            set wanted to item 2 of argv
            tell application id "\(bundleId)"
                repeat with w in windows
                    set t to missing value
                    set shown to ""
                    try
                        set t to active tab of w
                        set shown to (URL of t) as text
                    end try
                    if t is not missing value and shown starts with wanted then return execute t javascript js
                end repeat
            end tell
            return "{\\"v\\":2,\\"error\\":\\"\(noWindowError)\\"}"
        end run
        """
    }

    static func probeCommand(bundleId: String) -> String {
        """
        tell application id "\(bundleId)"
            if (count of windows) is 0 then return "no window"
            return execute (active tab of window 1) javascript "0"
        end tell
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

    /// What `web-source.js` returns.
    struct Answer: Decodable, Sendable {
        struct Where: Decodable, Sendable {
            var file: String?
            var line: Int?
            var column: Int?
            var stack: [StackFrame]?
        }
        struct Prop: Decodable, Sendable { var name: String; var value: String }
        var framework: String?
        var components: [String]?
        var props: [Prop]?
        var source: Where?
        var renderedAt: Where?
        var scripts: [String]?
        var error: String?
    }

    static func decode(_ json: String) -> Answer? {
        try? JSONDecoder().decode(Answer.self, from: Data(json.utf8))
    }

    /// Dia hands the script's string back as a JSON string, quotes and escapes included.
    static func unquoted(_ reply: String) -> String {
        guard reply.hasPrefix("\""), let list = try? JSONDecoder().decode([String].self, from: Data("[\(reply)]".utf8)),
              let inner = list.first else { return reply }
        return inner
    }

    /// What osascript's complaint means. The words are each browser's own, read from a real install.
    static func failure(from complaint: String, browser: WebBrowser) -> Failure {
        if complaint.contains(browser.refusal) { return .doorClosed }
        if complaint.contains("(-1743)") || complaint.contains("Not authorized to send Apple events") { return .denied }
        let line = complaint.split(separator: "\n").last.map(String.init) ?? complaint
        return .noAnswer(line.isEmpty ? "no reply in \(Int(processTimeout)) s" : String(line.prefix(200)))
    }

    // MARK: The page on screen

    /// The page's viewport in screen points: the scroll area that holds the outermost web area under
    /// `point`, as accessibility reports it. Chrome, Edge, Brave and Dia agree on it to a point, where
    /// the window's own numbers do not (a sidebar, an inset page, Brave's randomised window).
    static func viewport(at point: CGPoint, pid: pid_t) -> CGRect? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit) == .success, var node = hit else { return nil }
        var area: AXUIElement?
        for _ in 0..<80 {
            if role(of: node) == "AXWebArea" { area = node }
            guard let parent = parent(of: node) else { break }
            node = parent
        }
        guard let area else { return nil }
        if let holder = parent(of: area), role(of: holder) == "AXScrollArea", let frame = frame(of: holder) { return frame }
        return frame(of: area)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func role(of element: AXUIElement) -> String? {
        attribute(element, kAXRoleAttribute) as? String
    }

    private static func parent(of element: AXUIElement) -> AXUIElement? {
        guard let value = attribute(element, kAXParentAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), let size = attribute(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    // MARK: Files on this Mac

    /// For a localhost page, the folder the dev server runs in: the server's paths (`/src/Library.tsx`)
    /// are relative to it.
    static func devServerRoot(for url: String) -> String? {
        guard let parsed = URL(string: url), let host = parsed.host(), ModeInference.isLocalhost(host),
              let port = parsed.port else { return nil }
        guard let pid = run("/usr/sbin/lsof", ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"]).output?
            .split(separator: "\n").first.map(String.init) else { return nil }
        let cwd = run("/usr/sbin/lsof", ["-a", "-p", pid, "-d", "cwd", "-Fn"]).output?
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

    struct Refusal: Error, Sendable { var text: String }

    private static func runAppleScript(_ script: String, arguments: [String]) async -> Result<String, Refusal> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = run("/usr/bin/osascript", ["-"] + arguments, stdin: script, timeout: processTimeout)
                if let output = result.output {
                    continuation.resume(returning: .success(output))
                } else {
                    continuation.resume(returning: .failure(Refusal(text: result.complaint)))
                }
            }
        }
    }

    /// A short-lived tool's standard output, or what it complained of when it failed or ran past `timeout`.
    private static func run(_ tool: String, _ arguments: [String], stdin: String? = nil, timeout: TimeInterval = 3) -> (output: String?, complaint: String) {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        let output = Pipe(), errors = Pipe(), input = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = stdin == nil ? FileHandle.nullDevice : input
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return (nil, "could not start \(tool)") }
        if let stdin {
            input.fileHandleForWriting.write(Data(stdin.utf8))
            try? input.fileHandleForWriting.close()
        }
        // The answers here are a few kilobytes, well under a pipe's buffer, so waiting before reading
        // cannot stall the tool, and the timeout holds.
        if done.wait(timeout: .now() + timeout) == .timedOut { process.terminate(); return (nil, "") }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else { return (nil, errorText.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return (String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), "")
    }

    /// specs/first-run.md R144: public, under the app's subsystem, so `log show` reads it.
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.malikzhang.deixis", category: "web-source")
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
