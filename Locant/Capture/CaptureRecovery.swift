import Foundation

/// specs/capture-recovery.md R112: restart replayd, the process behind ScreenCaptureKit, when it
/// lists no displays, then ask again until displays come back. replayd's name is not public API;
/// if Apple renames it, `killall` finds nothing, the re-check stays empty, and the user is told to
/// restart the Mac (R113).
enum CaptureRecovery {
    enum Outcome: Equatable, Sendable {
        case recovered, restartMac
    }

    static let recheckInterval: Duration = .milliseconds(250)
    static let recheckLimit: Duration = .seconds(3)

    static func outcome(displaysAfter: Int) -> Outcome {
        displaysAfter > 0 ? .recovered : .restartMac
    }

    /// Kills replayd, then asks ScreenCaptureKit every `recheckInterval` for up to `recheckLimit`.
    /// The asking is what makes launchd start a new replayd.
    static func restart() async -> Outcome {
        await killReplayd()
        #if DEBUG
        await StuckSimulation.noteRestart()
        #endif
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: recheckLimit)
        var displays = await ScreenCapture.capturableDisplayCount()
        while outcome(displaysAfter: displays) == .restartMac, clock.now < deadline {
            try? await Task.sleep(for: recheckInterval)
            displays = await ScreenCapture.capturableDisplayCount()
        }
        return outcome(displaysAfter: displays)
    }

    /// The signal comes from `killall`, an Apple binary running as the user, so Locant needs no
    /// entitlement and its hardened runtime does not apply. SIGKILL, because a hung replayd ignored
    /// SIGTERM. The exit status is not read: the re-check is the answer.
    private static func killReplayd() async {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/killall")
            process.arguments = ["-9", "replayd"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return }
            process.waitUntilExit()
        }.value
    }
}
