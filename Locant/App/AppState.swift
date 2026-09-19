import AppKit
import Observation

/// The five Settings tabs, in toolbar order.
enum SettingsTab: Hashable, Sendable {
    case general, hotkeys, captures, myApps, agents
}

/// The only shared object. Owns the system-resource objects (overlay, hotkey, toast, reader) and
/// runs one capture session at a time: hover → click → note → write.
@Observable
@MainActor
final class AppState {
    enum Phase: Equatable {
        case idle, hovering, resolving, noting, writing
    }

    /// R22: which action the overlay is open for.
    enum Action: Equatable {
        case point, snap, text, cut

        var overlayMode: OverlayMode {
            switch self {
            case .point: .point
            case .snap: .snap
            case .text: .text
            case .cut: .cut
            }
        }
    }

    private(set) var phase: Phase = .idle
    let preferences = Preferences()
    /// Which Settings tab shows next. The help page sets it before opening Settings, so a row
    /// there lands on the tab that owns it.
    var settingsTab: SettingsTab = .general

    @ObservationIgnored private let reader = AccessibilityReader()
    @ObservationIgnored private var userTeamIDs: Set<String> = []
    @ObservationIgnored private let overlay = SelectionOverlay()
    @ObservationIgnored private let toast = Toast()
    @ObservationIgnored private var hotkeys: HotkeyMonitor?
    @ObservationIgnored private var ball: FloatingBall?
    /// v0.8.1 R59, R60: taps and sounds; made in `start()`, before the ball that shares it.
    @ObservationIgnored private var feedback: Feedback?
    @ObservationIgnored private var context: CaptureContext?
    @ObservationIgnored private var windows: [Geometry.WindowRecord] = []
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var pendingHover: CGPoint?
    @ObservationIgnored private var lastHoverPoint: CGPoint = .zero
    @ObservationIgnored private var lastHoverSnapshot: ElementSnapshot?
    @ObservationIgnored private var lastHoverElement: ResolvedElement?
    /// What Option cycles through for the hovered spot (see `HitRefiner.selectionLevels`).
    @ObservationIgnored private var levels: [ResolvedElement?] = []
    @ObservationIgnored private var levelIndex = 0
    /// v0.8.1 R59: whether the drawn outline moved since the last redraw; reset with each session.
    @ObservationIgnored private var outlineMoves = OutlineMoves()
    @ObservationIgnored private var lockedElement: ResolvedElement?
    @ObservationIgnored private var lockedElements: [RegionElement]?
    @ObservationIgnored private var lockedNearby: [RegionElement]?
    /// v0.8 R58: the elements added with Shift so far, the context of the first, and the set locked
    /// at the final click with the crops for elements after the first.
    @ObservationIgnored private var pinned: [CaptureTarget] = []
    @ObservationIgnored private var pinnedContext: CaptureContext?
    @ObservationIgnored private var lockedTargets: [CaptureTarget]?
    @ObservationIgnored private var extraCropTasks: [Task<CroppedImage, any Error>] = []
    @ObservationIgnored private var action: Action = .point
    @ObservationIgnored private var colorSession: ColorPickerSession?
    @ObservationIgnored private var clipboardOnlyPreset = false
    @ObservationIgnored private var sweepTask: Task<Void, Never>?
    @ObservationIgnored private var updateTask: Task<Void, Never>?
    /// R52: NSWorkspace launch and activation observers, and whether an iteration is being collected.
    @ObservationIgnored private var appObservers: [any NSObjectProtocol] = []
    @ObservationIgnored private var collecting = false
    /// v0.8.1 R63: the agent app that came forward last, by pid; `lastAgent` checks it is still that app.
    @ObservationIgnored private var lastAgentPID: pid_t?
    /// v0.8.1 R63: a reader of its own for the target label, so a slow agent never holds up hover.
    @ObservationIgnored private let agentReader = AccessibilityReader()
    /// v0.8.1 R63: pastes under way; auto-verify ignores activations while any is. A count, since two
    /// quick Returns can overlap.
    @ObservationIgnored private var pastesInFlight = 0
    @ObservationIgnored private let beforeAfter = BeforeAfterWindow()
    @ObservationIgnored private let help = HelpWindow()
    /// R25: the last ten picked colors, in memory only.
    @ObservationIgnored private(set) var recentColors: [ColorValue] = []
    @ObservationIgnored private var clickPoint: CGPoint = .zero
    @ObservationIgnored private var cropTask: Task<CroppedImage, any Error>?
    @ObservationIgnored private var openedSettingsPanes: Set<String> = []
    @ObservationIgnored private let ownPID = ProcessInfo.processInfo.processIdentifier

    var captureDirectory: URL { preferences.captureFolderURL }

    func start() {
        feedback = Feedback(preferences: preferences)
        Task.detached { [weak self] in
            let teams = CodeSigning.userTeamIDs()
            await MainActor.run { self?.userTeamIDs = teams }
        }
        preferences.onHotkeyChange = { [weak self] in self?.restartHotkey() }
        preferences.onActionHotkeysChange = { [weak self] in self?.restartHotkey() }
        preferences.onBallEnabledChange = { [weak self] in self?.updateBall() }
        preferences.onBallAutoHideChange = { [weak self] in
            guard let self else { return }
            self.ball?.autoHide = self.preferences.ballAutoHide
        }
        updateBall()
        showHelpOnFirstLaunch()
        scheduleSweeps()
        scheduleUpdateChecks()
        watchAppsForIterations()
        watchAgentApps()
        overlay.onHover = { [weak self] point in self?.hover(point) }
        overlay.onClick = { [weak self] point, shift in self?.click(point, shift: shift) }
        overlay.onShiftPressed = { [weak self] in self?.showShiftHintIfNeeded() }
        overlay.onReturn = { [weak self] in self?.confirmSetIfAny() ?? false }
        overlay.onCancel = { [weak self] in self?.cancel() }
        overlay.onCommit = { [weak self] note in self?.commit(note: note) }
        overlay.onOptionPressed = { [weak self] in self?.optionPressed() }
        overlay.onRegion = { [weak self] rect, start in self?.region(rect, start: start) }
        restartHotkey()
    }

    /// One monitor for the capture hotkey and every action hotkey (R29).
    private func restartHotkey() {
        hotkeys?.stop()
        var bindings = [HotkeyMonitor.Binding(preferences.hotkey) { [weak self] in self?.beginCapture() }]
        for (name, key) in preferences.actionHotkeys {
            guard let fire = fire(forAction: name) else { continue }
            bindings.append(HotkeyMonitor.Binding(key, fire: fire))
        }
        let monitor = HotkeyMonitor(bindings: bindings)
        monitor.start()
        hotkeys = monitor
        ball?.ringHints = ringHints()
    }

    /// What an action hotkey starts, by the action's name in `Preferences.hotkeyActions`.
    private func fire(forAction name: String) -> (@MainActor () -> Void)? {
        switch name {
        case "point": return { [weak self] in self?.beginCapture() }
        case "snap": return { [weak self] in self?.beginAction(.snap) }
        case "text": return { [weak self] in self?.beginAction(.text) }
        case "color": return { [weak self] in self?.beginColorPick() }
        case "cut": return { [weak self] in self?.beginAction(.cut) }
        default: return nil
        }
    }

    /// The action hotkeys, shown on the ring beside each segment's name.
    private func ringHints() -> [Ring.Segment: String] {
        var hints: [Ring.Segment: String] = [:]
        for segment in Ring.Segment.allCases {
            if let hotkey = preferences.actionHotkeys[segment.actionName] { hints[segment] = hotkey.symbol }
        }
        return hints
    }

    /// v0.3 R20: the ball follows the Settings toggle; first launch places it at the lower right.
    private func updateBall() {
        if preferences.ballEnabled {
            guard ball == nil else { return }
            let firstLaunch = preferences.ballPosition == nil
            let newBall = FloatingBall(origin: preferences.ballPosition)
            newBall.autoHide = preferences.ballAutoHide
            newBall.onPoint = { [weak self] in self?.beginCapture() }
            newBall.onMoved = { [weak self] origin in self?.preferences.ballPosition = origin }
            newBall.onAction = { [weak self] segment, clipboardOnly in self?.beginRingAction(segment, clipboardOnly: clipboardOnly) }
            newBall.ringHints = ringHints()
            newBall.feedback = feedback
            newBall.show(firstLaunch: firstLaunch)
            ball = newBall
        } else {
            ball?.hide()
            ball = nil
        }
    }

    /// While the Settings recorder listens, the real hotkeys must not fire.
    func pauseHotkey() {
        hotkeys?.stop()
    }
    func resumeHotkey() { restartHotkey() }

    // MARK: Session

    /// R1/R5: collect context for the app the user was looking at, then show the overlay.
    func beginCapture() {
        beginAction(.point)
    }

    /// R27: a ring segment chosen on the ball.
    func beginRingAction(_ segment: Ring.Segment, clipboardOnly: Bool) {
        switch segment {
        case .snap: clipboardOnlyPreset = clipboardOnly; beginAction(.snap)
        case .text: beginAction(.text)
        case .color: beginColorPick()
        case .cut: clipboardOnlyPreset = clipboardOnly; beginAction(.cut)
        }
    }

    // MARK: Lifecycle (R28)

    /// Sweep on launch and every 24 hours; the folder is read recursively.
    private func scheduleSweeps() {
        sweepTask?.cancel()
        sweepTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let folder = self.preferences.captureFolderURL
                let days = self.preferences.retentionDays
                _ = await Task.detached { Lifecycle.sweep(folder: folder, retentionDays: days) }.value
                try? await Task.sleep(for: Lifecycle.sweepInterval)
            }
        }
    }

    // MARK: Iterations (v0.6 R52)

    /// The captured app launching or coming forward is the moment to look at the element again.
    private func watchAppsForIterations() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
            appObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let bundleId = app.bundleIdentifier else { return }
                let pid = app.processIdentifier
                MainActor.assumeIsolated { self?.appCameForward(bundleId: bundleId, pid: pid) }
            })
        }
    }

    // MARK: Paste into the agent (v0.8.1 R63)

    /// Remembers the agent app that came forward last. An observer of its own: `appCameForward`
    /// returns early while iterations are off or a capture runs, and would drop these.
    private func watchAgentApps() {
        let center = NSWorkspace.shared.notificationCenter
        appObservers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  AgentPaste.isAgent(bundleId: app.bundleIdentifier) else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated { self?.lastAgentPID = pid }
        })
    }

    /// The note field, and beside it where Return will paste when that option is on.
    private func showNoteField(anchoredTo frame: CGRect?, around point: CGPoint) {
        overlay.showNoteField(anchoredTo: frame, around: point)
        showPasteTarget()
    }

    /// The app at once; its window title when the agent's own reader answers, if the field is
    /// still open by then.
    private func showPasteTarget() {
        guard preferences.pastesIntoAgent else { return }
        guard let app = lastAgent else {
            overlay.setNoteTarget(HudText.pasteTarget(AgentPaste.label(appName: nil, windowTitle: nil)))
            return
        }
        let name = app.localizedName ?? "Agent"
        overlay.setNoteTarget(HudText.pasteTarget(AgentPaste.label(appName: name, windowTitle: nil)))
        let pid = app.processIdentifier
        Task { @MainActor in
            let title = await agentReader.agentWindowTitle(pid: pid)
            guard phase == .noting else { return }
            overlay.setNoteTarget(HudText.pasteTarget(AgentPaste.label(appName: name, windowTitle: title)))
        }
    }

    /// The last agent while it still runs as the same app; nil after it quits.
    private var lastAgent: NSRunningApplication? {
        guard let pid = lastAgentPID, let app = NSRunningApplication(processIdentifier: pid),
              !app.isTerminated, AgentPaste.isAgent(bundleId: app.bundleIdentifier) else { return nil }
        return app
    }

    /// After the clipboard: wait for the overlay to order out, so no Locant panel is key, then bring
    /// the last agent forward and paste into its message field. It never sends. A newer capture, or
    /// anything else written to the clipboard, cancels it at any step, silently. The toast speaks
    /// only when nothing was pasted.
    private func pasteIntoAgent(near anchor: CGRect) async {
        // Read first: commit(note:) calls this right after PasteboardWriter.write, reset(), and the
        // toast, with no other clipboard write between, so this is what Return itself wrote.
        let clipboard = NSPasteboard.general.changeCount
        let proceed: @MainActor @Sendable () -> Bool = { self.phase == .idle && NSPasteboard.general.changeCount == clipboard }
        try? await Task.sleep(for: .milliseconds(Int(DesignTokens.dismiss * 1000) + 40))
        guard proceed() else { return }
        let app = lastAgent
        pastesInFlight += 1
        let outcome = await AgentPaster.paste(into: app, reader: agentReader, proceed: proceed)
        pastesInFlight -= 1
        if let text = AgentPaste.toastText(outcome, appName: app?.localizedName) {
            toast.show(HudText.plain(text), near: anchor)
        }
    }

    // MARK: Updates (v0.6 R45)

    /// 10 s after launch, then every 24 hours while running; skipped when the last check, on any
    /// launch, is under 24 hours old or the switch is off. Failures are silent.
    private func scheduleUpdateChecks() {
        updateTask?.cancel()
        updateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: UpdateCheck.launchDelay)
            while !Task.isCancelled {
                guard let self else { return }
                if self.preferences.checksForUpdates, UpdateCheck.isDue(lastCheck: self.preferences.lastUpdateCheck) {
                    await self.checkForUpdates(manual: false)
                }
                try? await Task.sleep(for: .seconds(UpdateCheck.interval))
            }
        }
    }

    /// The daily check, or Settings › General "Check Now…" (`manual`), which ignores the daily
    /// limit and the skipped version and always answers with an alert (R47).
    func checkForUpdates(manual: Bool) async {
        guard let current = UpdateCheck.currentVersion else { return }
        preferences.lastUpdateCheck = .now
        let latest: GitHubRelease
        do {
            latest = try await UpdateCheck.fetch(current: current)
        } catch {
            if manual { inform("Locant could not reach GitHub.", detail: "Try again later. The check runs by itself once a day.") }
            return
        }
        switch UpdateCheck.outcome(latest: latest, current: current, skipped: manual ? nil : preferences.skippedUpdateVersion) {
        case .available(let release):
            // R48: never over the overlay; the daily check tries again tomorrow instead of waiting.
            guard manual || phase == .idle else { return }
            offerUpdate(release, current: current)
        case .upToDate:
            if manual { inform("Locant \(current) is up to date.", detail: "The newest release on GitHub is \(latest.tagName).") }
        case .skipped:
            break
        }
    }

    private func offerUpdate(_ release: GitHubRelease, current: AppVersion) {
        let newest = release.version.map(\.description) ?? release.tagName
        let alert = NSAlert()
        alert.messageText = "Locant \(newest) is available"
        alert.informativeText = "You have \(current). Download the dmg and drag Locant over the copy in Applications; the permissions carry over because every release is signed with the same Developer ID."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn: NSWorkspace.shared.open(release.downloadURL)
        case .alertThirdButtonReturn: preferences.skippedUpdateVersion = newest
        default: break
        }
    }

    private func inform(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }

    // MARK: Verify (v0.4)

    /// The newest Point capture: an image with a sidecar.
    private func newestSidecar() -> URL? {
        AutoVerify.newestSidecar(among: Lifecycle.entries(in: preferences.captureFolderURL))
    }

    /// R52: the app of the newest capture launched or came forward. If the capture is worth it
    /// (`AutoVerify.wants`), wait for the window to draw, find the element again, and keep an
    /// iteration when it looks different. Never a toast on failure: the next activation tries again.
    private func appCameForward(bundleId: String, pid: pid_t) {
        guard preferences.collectsIterations, phase == .idle, !collecting, pastesInFlight == 0 else { return }
        guard let sidecar = newestSidecar(), let capture = try? IterationStore.load(sidecar),
              AutoVerify.wants(capture, activated: bundleId), let element = capture.element else { return }
        collecting = true
        Task { @MainActor in
            defer { collecting = false }
            try? await Task.sleep(for: AutoVerify.settle)
            guard preferences.collectsIterations, phase == .idle, ScreenCapture.hasPermission() else { return }
            await collectIteration(sidecar: sidecar, capture: capture, element: element, pid: pid)
        }
    }

    /// R31–R34: find the element again in the running app (by identifier, then role and label, then
    /// the nearest frame), capture it, and when the pixels changed record the git facts and append
    /// the iteration. The Before & After window is not opened; "Show before & after" is in the menu.
    private func collectIteration(sidecar: URL, capture: Capture, element: ResolvedElement, pid: pid_t) async {
        // A set that shares one image is only comparable once every element is found again, and
        // only this app's are reachable here: a set spanning apps simply never collects.
        let companions = AutoVerify.companions(of: capture)
        var found: ResolvedElement?
        var others: [ResolvedElement] = []
        var windowBounds: CGRect?
        for attempt in 0..<ElementRefinder.retries {
            let windows = WindowList.onScreen().filter { $0.ownerPID == pid && $0.layer == 0 }
            let largest = windows.max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
            windowBounds = largest?.bounds
            let region = largest?.bounds ?? SelectionOverlay.displayFrameCG(containing: element.frame.cgRect.origin)
            let snapshots = await reader.elements(in: region, pid: pid)
            found = ElementRefinder.match(element, among: snapshots)
            others = companions.compactMap { ElementRefinder.match($0, among: snapshots) }
            if found != nil, others.count == companions.count { break }
            if attempt < ElementRefinder.retries - 1 { try? await Task.sleep(for: ElementRefinder.retryInterval) }
        }
        guard let found, others.count == companions.count, phase == .idle else { return }
        do {
            let center = CGPoint(x: found.frame.x + found.frame.w / 2, y: found.frame.y + found.frame.h / 2)
            let display = SelectionOverlay.displayFrameCG(containing: center)
            // The same crop the capture took, so the two images are comparable: the set's union
            // when they shared one, the element's own otherwise.
            let crop = companions.isEmpty
                ? Geometry.cropRect(element: found.frame.cgRect, clickPoint: center, window: windowBounds, display: display)
                : Geometry.cropRects(for: ([found] + others).map(\.frame.cgRect), display: display, displayFor: SelectionOverlay.displayFrameCG(containing:))[0]
            let image = try await ScreenCapture.crop(crop)
            let previous = try? Data(contentsOf: URL(filePath: AutoVerify.previousImagePath(of: capture)))
            let png = image.png
            let changed = await Task.detached { previous.map { ImageDiff.differs(png: $0, png: png) } ?? true }.value
            guard changed else { return }
            let index = capture.iterations.count + 1
            let afterURL = IterationStore.afterImageURL(for: sidecar, index: index)
            try png.write(to: afterURL, options: .atomic)
            FileStore.setFinderTags(FileStore.tags(for: capture) + ["after"], on: afterURL)
            let root = capture.source.projectRoot
            let before = capture.source.gitCommit
            let change: GitChange = await Task.detached {
                root.map { GitFacts.changes(at: $0, since: before) } ?? GitChange(before: before, after: nil, diffStat: nil, files: [])
            }.value
            let iteration = Iteration(
                capturedAt: FileStore.isoTimestamp(date: Date()),
                imagePath: afterURL.path(percentEncoded: false),
                gitBefore: change.before, gitAfter: change.after, diffStat: change.diffStat, files: change.files,
                frame: found.frame
            )
            _ = try IterationStore.append(iteration, to: sidecar)
            let summary = GitFacts.summaryLine(of: change.diffStat) ?? (root == nil ? "no project folder" : "no changes")
            toast.show(HudText.plain("After #\(index) · \(summary)"), near: found.frame.cgRect)
        } catch {
            // Silent (R52): the element was found but the capture or the write failed; try on the next activation.
        }
    }

    /// R35: the newest capture that has iterations.
    func showBeforeAfter() {
        let candidates = Lifecycle.entries(in: preferences.captureFolderURL)
            .filter { $0.urls.contains { $0.pathExtension == "json" } }
            .sorted { $0.modified > $1.modified }
        for entry in candidates {
            guard let sidecar = entry.urls.first(where: { $0.pathExtension == "json" }),
                  let capture = try? IterationStore.load(sidecar), !capture.iterations.isEmpty else { continue }
            beforeAfter.show(capture)
            return
        }
        toast.show(HudText.plain("No iterations yet · point in your app, then run it again"), near: Self.mainScreenCenterCG())
    }

    /// R25: the magnifier session. Click copies the pixel in the chosen format; Esc cancels.
    func beginColorPick() {
        guard phase == .idle, colorSession == nil else { return }
        guard ScreenCapture.hasPermission() else {
            fail(.noScreenRecordingPermission, nearRect: nil)
            return
        }
        phase = .writing
        let session = ColorPickerSession(space: preferences.colorSpace, format: preferences.colorFormat)
        session.onPick = { [weak self] color in
            guard let self else { return }
            let text = ColorPicker.format(color, as: self.preferences.colorFormat)
            PasteboardWriter.write(string: text)
            recentColors = Array(([color] + recentColors).prefix(10))
            endColorPick()
            let cursor = Geometry.cgPoint(fromAppKit: NSEvent.mouseLocation, primaryHeight: SelectionOverlay.currentPrimaryHeight())
            toast.show(HudText.copied(identifier: text), near: CGRect(origin: cursor, size: .zero))
            feedback?.play(.landed)
        }
        session.onCancel = { [weak self] in self?.endColorPick() }
        colorSession = session
        session.start()
        showHintIfNeeded(key: "color", text: "↩ copies · arrows nudge")
    }

    private func endColorPick() {
        toast.hide()
        colorSession?.stop()
        colorSession = nil
        phase = .idle
    }

    /// R22: Snap, Text, and Cut open the same overlay in their mode.
    func beginAction(_ requested: Action) {
        guard phase == .idle else { return }
        action = requested
        overlay.mode = requested.overlayMode
        overlay.adjustsRegion = preferences.adjustSelection
        guard AccessibilityReader.isTrusted(prompt: false) else {
            fail(.noAccessibilityPermission, nearRect: nil)
            return
        }
        phase = .hovering
        Task {
            guard let collected = await ContextCollector.collect(reader: reader) else {
                reset()
                return
            }
            guard phase == .hovering else { return }
            context = collected
            windows = WindowList.onScreen()
            overlay.show()
            showHintIfNeeded(key: Self.hintKey(for: requested), text: Self.hintText(for: requested))
        }
    }

    // MARK: Hints (v0.5 R40)

    private static let hintShowings = 3

    /// R43: the one-page guide, once, after the permission alerts. Waits for the ball's fade-in.
    private func showHelpOnFirstLaunch() {
        guard preferences.hintCount("help") == 0 else { return }
        preferences.markHintShown("help")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            self.showHelp()
        }
    }

    /// Settings › General "Locant Help": the same page, any time.
    func showHelp() {
        help.show(state: self)
    }

    /// "Try it now" on the help page: the page goes away and Point opens over whatever is on screen,
    /// so the first capture happens in seconds. The help window is closed first because Locant never
    /// appears in its own captures.
    func tryPoint() {
        help.close()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            self.beginAction(.point)
        }
    }

    /// Once per install, after the first Point capture lands on the clipboard and while no agent is
    /// connected: the payload can be fetched instead of pasted. Waits for the Copied toast to go.
    private func showAgentHintIfNeeded() {
        guard preferences.hintCount("agents") == 0 else { return }
        preferences.markHintShown("agents")
        guard Agent.allCases.allSatisfy({ AgentConnector.status($0) == .notConnected }) else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(DesignTokens.toastLife + 0.4))
            guard phase == .idle else { return }
            toast.show(HudText.plain("Your agent can fetch this itself · Settings › Agents"), atBottomOf: NSEvent.mouseLocation, life: DesignTokens.hintLife)
        }
    }

    /// v0.8 R58: once per install, the first time Shift is held over the Point overlay.
    private func showShiftHintIfNeeded() {
        guard phase == .hovering, action == .point, preferences.hintCount("shift") == 0 else { return }
        preferences.markHintShown("shift")
        toast.show(HudText.plain("⇧ click adds another element · from any app"), atBottomOf: NSEvent.mouseLocation, life: DesignTokens.hintLife)
    }

    /// The first three opens of a mode: the gestures, at the bottom of the display under the cursor.
    private func showHintIfNeeded(key: String, text: String) {
        guard preferences.hintCount(key) < Self.hintShowings else { return }
        preferences.markHintShown(key)
        toast.show(HudText.plain(text), atBottomOf: NSEvent.mouseLocation, life: DesignTokens.hintLife)
    }

    private static func hintKey(for action: Action) -> String {
        switch action {
        case .point: "overlay.point"
        case .snap: "overlay.snap"
        case .text: "overlay.text"
        case .cut: "overlay.cut"
        }
    }

    private static func hintText(for action: Action) -> String {
        switch action {
        case .point: "↩ picks · drag for a frame · ⌥ for the parent"
        case .snap, .cut: "↩ takes the window · drag for a frame"
        case .text: "↩ takes the text · drag for a frame"
        }
    }

    private func hover(_ point: CGPoint) {
        guard phase == .hovering else { return }
        pendingHover = point
        guard hoverTask == nil else { return }
        hoverTask = Task { await drainHover() }
    }

    /// One in-flight lookup at a time, latest point wins, at most ~30 Hz.
    /// R2 hover precision: the reader already refines container hits toward a real control; here the
    /// last small element sticks while the cursor stays near it, so gaps do not flip to the big group.
    private func drainHover() async {
        defer { hoverTask = nil }
        while phase == .hovering, !Task.isCancelled, let point = pendingHover {
            pendingHover = nil
            if action == .snap || action == .cut {
                // Window under the cursor, no accessibility needed.
                lastHoverPoint = point
                let window = Geometry.windowOwner(at: point, windows: windows, excludingPID: ownPID)
                let drawn: Bool
                if let window {
                    let name = NSRunningApplication(processIdentifier: window.ownerPID)?.localizedName ?? "window"
                    drawn = overlay.setHighlight(window.bounds, readout: Readout(role: "window", identifier: nil, suffix: name, isFallback: false), around: point)
                } else {
                    drawn = overlay.setHighlight(nil, readout: .describing(nil), around: point)
                }
                if drawn, outlineMoves.moved(to: window?.bounds) { feedback?.tap(.alignment) }
                try? await Task.sleep(for: .milliseconds(33))
                continue
            }
            let fresh = await reader.snapshot(at: point, candidates: windowCandidates(at: point), fallbackPID: context?.frontPID ?? 0)
            guard phase == .hovering, !Task.isCancelled else { return }
            let freshLevels = fresh.map { HitRefiner.selectionLevels(for: $0, at: point) } ?? []
            let freshElement = freshLevels.first ?? nil
            let freshIsVague = freshElement.map { ElementResolver.containerRoles.contains($0.role) } ?? true
            if freshIsVague, HitRefiner.sticks(lastHoverElement, to: point) {
                // Crossing padding: keep the small element and its Option level.
            } else {
                if freshElement?.frame != lastHoverElement?.frame { levelIndex = 0 }
                lastHoverSnapshot = fresh
                levels = freshLevels
                lastHoverElement = freshElement
            }
            lastHoverPoint = point
            renderHover()
            try? await Task.sleep(for: .milliseconds(33))
        }
    }

    /// The hovered selection at the current Option level.
    private func selectedElement() -> ResolvedElement? {
        levels.indices.contains(levelIndex) ? levels[levelIndex] : lastHoverElement
    }

    /// v0.8.1 R59: a drawn outline that moved taps `.alignment`. Option's `step` taps `.levelChange`
    /// instead, and the move it causes is not also a tap.
    private func renderHover(step: Bool = false) {
        let element = selectedElement()
        var readout = Readout.describing(element)
        if levelIndex > 0 {
            readout.suffix = [readout.suffix, "↑\(levelIndex)"].compactMap { $0 }.joined(separator: " · ")
        }
        guard overlay.setHighlight(element?.frame.cgRect, readout: readout, around: lastHoverPoint) else { return }
        let moved = outlineMoves.moved(to: element?.frame.cgRect)
        if step {
            feedback?.tap(.levelChange)
        } else if moved {
            feedback?.tap(.alignment)
        }
    }

    /// Option while hovering: cluster, parent, grandparent, … then back to the element.
    private func optionPressed() {
        guard phase == .hovering, levels.count > 1 else { return }
        levelIndex = (levelIndex + 1) % levels.count
        renderHover(step: true)
    }

    /// R3: the on-screen windows under the point, front to back, in every layer. The reader asks
    /// their owners in turn; the app frontmost at hotkey time is the fallback when none contains it.
    private func windowCandidates(at point: CGPoint) -> [Geometry.WindowRecord] {
        Geometry.windowCandidates(at: point, windows: windows, excludingPID: ownPID)
    }

    private func provider(at point: CGPoint) -> AppElementProvider {
        AppElementProvider(reader: reader, candidates: windowCandidates(at: point), fallbackPID: context?.frontPID ?? 0)
    }

    /// R5: the source is the app that owns what was clicked. A normal window keeps the hotkey-time
    /// context when it is the same app, and otherwise names the app's focused window. Anything else
    /// (a desktop icon, a widget, a status item, a Dock item) is described afresh, with the window the
    /// element itself sits in, if any: a widget says "Month", a desktop icon says none, rather than
    /// whichever Finder window happens to be focused.
    private func recollectContextIfNeeded(window: Geometry.WindowRecord?, snapshot: ElementSnapshot?) async {
        guard let context else { return }
        let pid = window?.ownerPID ?? context.frontPID
        let isNormalWindow = (window?.layer ?? 0) == 0
        guard !isNormalWindow || pid != context.frontPID else { return }
        let title: ContextCollector.WindowTitle = isNormalWindow ? .focused : .known(snapshot.flatMap(Self.windowTitle(in:)))
        if let clicked = await ContextCollector.collect(reader: reader, pid: pid, windowTitle: title), phase == .resolving {
            self.context = clicked
        }
    }

    private static func windowTitle(in snapshot: ElementSnapshot) -> String? {
        ([snapshot.element] + snapshot.ancestors)
            .first { ElementResolver.mapRole($0.role ?? "", subrole: $0.subrole) == "window" }
            .flatMap { ElementResolver.nonEmpty($0.title) }
    }

    /// What a click at `point` means: the hovered selection at its Option level when the click is on or
    /// near it, else a fresh read with the lazy-tree retry.
    private func resolveClicked(at point: CGPoint) async -> (element: ResolvedElement?, snapshot: ElementSnapshot?) {
        let slack = HitRefiner.stickiness
        let hoverIsCurrent = !levels.isEmpty
            && (lastHoverElement.map { $0.frame.cgRect.insetBy(dx: -slack, dy: -slack).contains(point) } ?? false)
        if hoverIsCurrent, let shown = selectedElement() {
            return (shown, lastHoverSnapshot)
        } else if levelIndex > 0, let shown = selectedElement() {
            return (shown, lastHoverSnapshot) // an Option level chosen on purpose
        }
        let snapshot = await ElementResolver.snapshotWithRetry(at: point, using: provider(at: point))
        return (snapshot.map { HitRefiner.selectionLevels(for: $0, at: point).first ?? nil } ?? nil, snapshot)
    }

    /// v0.8 R58: an element as one of a set, with the app and window that own it.
    private func describeTarget(_ element: ResolvedElement, snapshot: ElementSnapshot?, window: Geometry.WindowRecord?) async -> CaptureTarget {
        let pid = window?.ownerPID ?? context?.frontPID ?? 0
        let isNormalWindow = (window?.layer ?? 0) == 0
        let title: ContextCollector.WindowTitle = isNormalWindow ? .focused : .known(snapshot.flatMap(Self.windowTitle(in:)))
        let source = await ContextCollector.collect(reader: reader, pid: pid, windowTitle: title)?.source ?? context?.source
        return CaptureTarget(element: element, app: source?.app ?? AppInfo(bundleId: "unknown", name: "unknown"), window: source?.window, url: snapshot?.url)
    }

    /// v0.8 R58: Shift-click adds the element under the cursor to the set, or removes it again. The
    /// overlay stays open; the first element's app becomes the capture's source.
    private func pin(at point: CGPoint) {
        guard phase == .hovering, action == .point else { return }
        Task {
            let (element, snapshot) = await resolveClicked(at: point)
            guard phase == .hovering, let element else { return }
            let window = snapshot?.window ?? Geometry.windowOwner(at: point, windows: windows, excludingPID: ownPID)
            if let index = pinned.firstIndex(where: { $0.element.frame == element.frame }) {
                pinned.remove(at: index)
            } else {
                let target = await describeTarget(element, snapshot: snapshot, window: window)
                guard phase == .hovering else { return }
                if pinned.isEmpty, let context {
                    let pid = window?.ownerPID ?? context.frontPID
                    var first = await ContextCollector.collect(reader: reader, pid: pid, windowTitle: .focused) ?? context
                    first.source.url = snapshot?.url
                    pinnedContext = first
                }
                pinned.append(target)
            }
            guard phase == .hovering else { return }
            overlay.setPinned(pinned.map { $0.element.frame.cgRect })
        }
    }

    /// v0.8 R58: Return with a set in progress confirms the set as it stands, without adding
    /// whatever happens to be under the cursor. Returns false when there is no set, so Return
    /// keeps its plain meaning, a click at the cursor.
    private func confirmSetIfAny() -> Bool {
        guard phase == .hovering, action == .point, !pinned.isEmpty, context != nil else { return false }
        toast.hide()
        let last = pinned[pinned.count - 1].element.frame.cgRect
        let point = CGPoint(x: last.midX, y: last.midY)
        phase = .resolving
        pendingHover = nil
        clickPoint = point
        guard ScreenCapture.hasPermission() else {
            fail(.noScreenRecordingPermission, nearRect: last)
            return true
        }
        Task { await finishSet(clicked: nil, snapshot: nil, window: nil, point: point) }
        return true
    }

    private func click(_ point: CGPoint, shift: Bool) {
        guard phase == .hovering, context != nil else { return }
        toast.hide()
        feedback?.clicked() // v0.8.1 R59: the trackpad just clicked; nothing taps for 80 ms
        if shift, action == .point {
            pin(at: point)
            return
        }
        switch action {
        case .point:
            break
        case .snap, .cut:
            let rect = Geometry.windowOwner(at: point, windows: windows, excludingPID: ownPID)?.bounds
                ?? SelectionOverlay.displayFrameCG(containing: point)
            runOneShot(on: rect, at: point, fromRegion: false)
            return
        case .text:
            let rect = selectedElement()?.frame.cgRect.insetBy(dx: -HitRefiner.tolerance, dy: -HitRefiner.tolerance)
                ?? SelectionOverlay.fallbackRect(around: point)
            runOneShot(on: rect, at: point, fromRegion: false)
            return
        }
        phase = .resolving
        pendingHover = nil
        clickPoint = point
        guard ScreenCapture.hasPermission() else {
            fail(.noScreenRecordingPermission, nearRect: SelectionOverlay.fallbackRect(around: point))
            return
        }
        Task {
            // What the user saw is what they clicked: keep the hovered selection (and its Option
            // depth) when the click is on or near it; otherwise resolve fresh with the lazy-tree retry.
            let (element, snapshot) = await resolveClicked(at: point)
            guard phase == .resolving else { return }
            // The window that answered the hit test, else the normal window under the point.
            let window = snapshot?.window ?? Geometry.windowOwner(at: point, windows: windows, excludingPID: ownPID)
            if !pinned.isEmpty {
                await finishSet(clicked: element, snapshot: snapshot, window: window, point: point)
                return
            }
            lockedElement = element
            if element == nil, let snapshot = lastHoverSnapshot {
                // v0.2 R15: what sits around a point that has no element.
                let neighborhood = snapshot.children ?? snapshot.siblings ?? []
                lockedNearby = RegionResolver.nearby(point: point, among: neighborhood).map(\.element)
            }

            await recollectContextIfNeeded(window: window, snapshot: snapshot)
            guard phase == .resolving else { return }
            // v0.8: the page address of a web node; the localhost rule in mode inference reads it.
            if let url = snapshot?.url { context?.source.url = url }

            let display = SelectionOverlay.displayFrameCG(containing: point)
            let rect = Geometry.cropRect(element: element?.frame.cgRect, clickPoint: point, window: window?.bounds, display: display)
            cropTask = Task { try await ScreenCapture.crop(rect) }

            overlay.setHighlight(element?.frame.cgRect, readout: .describing(element), around: point)
            showNoteField(anchoredTo: element?.frame.cgRect, around: point)
            phase = .noting
        }
    }

    /// v0.8 R58: the final click on a set. The clicked element joins it unless it is already in;
    /// the first element's app is the source; one crop of the union when it fits, else one each.
    private func finishSet(clicked: ResolvedElement?, snapshot: ElementSnapshot?, window: Geometry.WindowRecord?, point: CGPoint) async {
        var targets = pinned
        if let clicked, !targets.contains(where: { $0.element.frame == clicked.frame }) {
            targets.append(await describeTarget(clicked, snapshot: snapshot, window: window))
        }
        guard phase == .resolving else { return }
        if let pinnedContext { context = pinnedContext }
        let last = targets.last!.element
        lockedElement = targets[0].element
        lockedTargets = targets.count > 1 ? targets : nil

        let frames = targets.map { $0.element.frame.cgRect }
        let display = SelectionOverlay.displayFrameCG(containing: CGPoint(x: frames[0].midX, y: frames[0].midY))
        let rects = Geometry.cropRects(for: frames, display: display, displayFor: SelectionOverlay.displayFrameCG(containing:))
        cropTask = Task { try await ScreenCapture.crop(rects[0]) }
        extraCropTasks = rects.dropFirst().map { rect in Task { try await ScreenCapture.crop(rect) } }

        overlay.setPinned(frames)
        overlay.setHighlight(last.frame.cgRect, readout: .describing(last), around: point)
        showNoteField(anchoredTo: last.frame.cgRect, around: point)
        phase = .noting
    }

    /// v0.2 R11–R13: a drawn frame. Everything at least half inside becomes `elements`, the best of
    /// it the primary `element`, and the frame itself is the crop.
    private func region(_ rect: CGRect, start: CGPoint) {
        guard phase == .hovering, let context else { return }
        toast.hide()
        // A drawn frame replaces a set in progress.
        pinned = []
        pinnedContext = nil
        overlay.setPinned([])
        if action != .point {
            runOneShot(on: rect, at: start, fromRegion: true)
            return
        }
        phase = .resolving
        pendingHover = nil
        clickPoint = CGPoint(x: rect.midX, y: rect.midY)
        guard ScreenCapture.hasPermission() else {
            fail(.noScreenRecordingPermission, nearRect: rect)
            return
        }
        Task {
            // The frame belongs to whoever answers at its first corner: a normal window, or the
            // desktop, a widget, or the menu bar behind an empty stretch of Dock or menu bar backdrop.
            let hit = await reader.snapshot(at: start, candidates: windowCandidates(at: start), fallbackPID: context.frontPID)
            guard phase == .resolving else { return }
            let window = hit?.window ?? Geometry.windowOwner(at: start, windows: windows, excludingPID: ownPID)
            let pid = window?.ownerPID ?? context.frontPID
            var snapshots = await reader.elements(in: rect, pid: pid)
            var retry = 0
            while snapshots.isEmpty, retry < 2 { // lazy tree
                retry += 1
                try? await Task.sleep(for: .milliseconds(100))
                snapshots = await reader.elements(in: rect, pid: pid)
            }
            guard phase == .resolving else { return }
            await recollectContextIfNeeded(window: window, snapshot: hit)
            guard phase == .resolving else { return }
            let elements = RegionResolver.elements(in: rect, among: snapshots)
            lockedElement = RegionResolver.primary(among: snapshots, in: rect)
            lockedElements = elements

            let display = SelectionOverlay.displayFrameCG(containing: clickPoint)
            let crop = Geometry.cropRect(element: rect, clickPoint: clickPoint, window: nil, display: display, padding: 0)
            cropTask = Task { try await ScreenCapture.crop(crop) }

            overlay.showMarks(elements.map { $0.frame.cgRect })
            showNoteField(anchoredTo: rect, around: clickPoint)
            phase = .noting
        }
    }

    // MARK: One-shot actions (R23, R24, R26)

    /// Snap, Text, Cut: the overlay closes at once, the pixels are read, and the result goes to the
    /// clipboard (and to disk for images unless ⌥ was held). Failures leave the clipboard untouched.
    private func runOneShot(on rect: CGRect, at point: CGPoint, fromRegion: Bool) {
        guard let context else { return }
        let which = action
        let optionHeld = NSEvent.modifierFlags.contains(.option) || clipboardOnlyPreset
        clipboardOnlyPreset = false
        let appName = Geometry.windowOwner(at: point, windows: windows, excludingPID: ownPID)
            .flatMap { NSRunningApplication(processIdentifier: $0.ownerPID)?.localizedName } ?? context.source.app.name
        let display = SelectionOverlay.displayFrameCG(containing: point)
        let crop = Geometry.cropRect(element: rect, clickPoint: point, window: nil, display: display, padding: 0)
        let store = FileStore(directory: preferences.captureFolderURL, organization: preferences.organization)
        guard ScreenCapture.hasPermission() else {
            fail(.noScreenRecordingPermission, nearRect: rect)
            return
        }
        phase = .writing
        overlay.dismiss()
        Task {
            do {
                let image = try await ScreenCapture.crop(crop)
                let id = FileStore.makeID(date: Date())
                switch which {
                case .snap:
                    if !optionHeld {
                        try store.writeImage(png: image.png, fileName: Screenshot.fileName(appName: appName, id: id), appName: appName, tag: "snap")
                    }
                    PasteboardWriter.write(png: image.png)
                    let size = "\(MarkdownBuilder.number(image.widthPt))×\(MarkdownBuilder.number(image.heightPt))"
                    finishOneShot(HudText.plain(optionHeld ? "Snapped · \(size) · clipboard only" : "Snapped · \(size)"), near: crop, sound: .landed)
                case .text:
                    let lines = try await OCR.text(inPNG: image.png)
                    guard !lines.isEmpty else {
                        finishOneShot(HudText.plain("No text found"), near: crop, sound: .missed)
                        return
                    }
                    PasteboardWriter.write(string: lines.joined(separator: "\n"))
                    finishOneShot(HudText.plain("Copied · \(lines.count) \(lines.count == 1 ? "line" : "lines")"), near: crop, sound: .landed)
                case .cut:
                    let normalized = CGPoint(x: (point.x - crop.minX) / crop.width, y: (point.y - crop.minY) / crop.height)
                    let subject = try await Cutout.subject(inPNG: image.png, at: normalized, wholeRegion: fromRegion)
                    guard let subject else {
                        finishOneShot(HudText.plain("No subject found"), near: crop, sound: .missed)
                        return
                    }
                    if !optionHeld {
                        try store.writeImage(png: subject, fileName: Cutout.fileName(appName: appName, id: id), appName: appName, tag: "cut")
                    }
                    PasteboardWriter.write(png: subject)
                    finishOneShot(HudText.plain(optionHeld ? "Cut · clipboard only" : "Cut"), near: crop, sound: .landed)
                case .point:
                    reset()
                }
            } catch {
                fail(.captureFailed(error), nearRect: crop)
            }
        }
    }

    private func finishOneShot(_ text: NSAttributedString, near rect: CGRect, sound: Feedback.Sound) {
        reset()
        toast.show(text, near: rect)
        feedback?.play(sound) // v0.8.1 R60
    }

    /// R6/R7/R8: only Enter writes. Files first, clipboard last.
    private func commit(note: String) {
        guard phase == .noting, let context, let cropTask else { return }
        phase = .writing
        let element = lockedElement
        let elements = lockedElements
        let nearby = lockedNearby
        var targets = lockedTargets
        let extraCrops = extraCropTasks
        let anchor = (targets?.last?.element ?? element)?.frame.cgRect ?? SelectionOverlay.fallbackRect(around: clickPoint)
        let signals = ModeClassifier.signals(for: context, myApps: preferences.myApps, userTeamIDs: userTeamIDs)
        let store = FileStore(directory: preferences.captureFolderURL, organization: preferences.organization)
        Task {
            do {
                let image = try await cropTask.value
                // v0.3 R17: fix or reference, and the project root, from signals; touches the disk.
                // v0.4 R33: remember HEAD so Verify can diff against it later.
                let (decision, head) = await Task.detached { () -> (ModeDecision, String?) in
                    let decision = ModeInference.infer(signals)
                    return (decision, decision.projectRoot.flatMap(GitFacts.head(at:)))
                }.value
                var source = context.source
                source.projectRoot = decision.projectRoot
                source.gitCommit = head
                let now = Date()
                var capture = Capture(
                    id: FileStore.makeID(date: now),
                    createdAt: FileStore.isoTimestamp(date: now),
                    mode: decision.mode,
                    image: ImageInfo(path: "", widthPt: image.widthPt, heightPt: image.heightPt, scale: image.scale, crop: Frame(image.crop)),
                    source: source,
                    element: element,
                    note: note,
                    elements: elements,
                    nearby: nearby
                )
                // v0.8 R58: elements that did not fit the one image get their own, written first so
                // the sidecar can name them.
                if targets != nil, !extraCrops.isEmpty {
                    for (offset, task) in extraCrops.enumerated() {
                        let extra = try await task.value
                        let url = try store.writeExtraImage(png: extra.png, capture: capture, index: offset + 2)
                        targets?[offset + 1].imagePath = url.path(percentEncoded: false)
                    }
                    capture.targets = targets
                } else {
                    capture.targets = targets
                }
                // v0.2 R14: text in the image when nothing has an identifier.
                let hasIdentifier = element?.identifier != nil || (elements?.contains { $0.identifier != nil } ?? false)
                    || (targets?.contains { $0.element.identifier != nil || $0.element.dom?.id != nil } ?? false)
                if !hasIdentifier, let lines = try? await TextRecognizer.lines(inPNG: image.png), !lines.isEmpty {
                    capture.ocr = lines.joined(separator: "\n")
                }
                let written = try store.write(png: image.png, capture: capture)
                PasteboardWriter.write(markdown: MarkdownBuilder.build(written), png: image.png)
                reset()
                if let count = targets?.count {
                    toast.show(HudText.plain("Copied · \(count) elements"), near: anchor)
                } else {
                    toast.show(HudText.copied(identifier: element?.identifier), near: anchor)
                }
                feedback?.play(.landed)
                // v0.8.1 R63: with the option on, the hint about fetching over MCP stays unspent.
                if preferences.pastesIntoAgent {
                    await pasteIntoAgent(near: anchor)
                } else {
                    showAgentHintIfNeeded()
                }
            } catch {
                fail(.captureFailed(error), nearRect: anchor)
            }
        }
    }

    /// Esc at any point: nothing on disk, clipboard untouched.
    func cancel() {
        guard phase != .idle else { return }
        toast.hide()
        cropTask?.cancel()
        extraCropTasks.forEach { $0.cancel() }
        reset()
    }

    private func reset() {
        phase = .idle
        action = .point
        clipboardOnlyPreset = false
        overlay.mode = .point
        hoverTask?.cancel()
        hoverTask = nil
        pendingHover = nil
        cropTask = nil
        extraCropTasks = []
        pinned = []
        pinnedContext = nil
        lockedTargets = nil
        lockedElement = nil
        lockedElements = nil
        lockedNearby = nil
        lastHoverSnapshot = nil
        lastHoverElement = nil
        levels = []
        levelIndex = 0
        outlineMoves = OutlineMoves()
        context = nil
        windows = []
        overlay.dismiss()
    }

    // MARK: Failure (R9)

    private func fail(_ error: CaptureError, nearRect anchor: CGRect?) {
        reset()
        let rect = anchor ?? Self.mainScreenCenterCG()
        toast.show(HudText.plain(error.message), near: rect)
        feedback?.play(.missed) // v0.8.1 R60
        switch error {
        case .noAccessibilityPermission: openSettingsOnce(pane: "Privacy_Accessibility")
        case .noScreenRecordingPermission: openSettingsOnce(pane: "Privacy_ScreenCapture")
        case .noElementUnderCursor, .captureFailed: break
        }
    }

    private func openSettingsOnce(pane: String) {
        guard !openedSettingsPanes.contains(pane) else { return }
        openedSettingsPanes.insert(pane)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func mainScreenCenterCG() -> CGRect {
        let frame = NSScreen.main?.frame ?? .zero
        let center = Geometry.cgPoint(fromAppKit: CGPoint(x: frame.midX, y: frame.midY), primaryHeight: SelectionOverlay.currentPrimaryHeight())
        return CGRect(x: center.x, y: center.y, width: 0, height: 0)
    }

    // MARK: Menu actions

    func openCaptureFolder() {
        let folder = preferences.captureFolderURL
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}
