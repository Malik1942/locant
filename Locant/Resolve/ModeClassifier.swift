import Foundation

/// Section 4 of v0.1, now backed by v0.3 mode inference. Kept as the one call site for
/// "what mode is this source", so the rules live in `ModeInference`.
enum ModeClassifier {
    static let simulatorBundleId = ModeInference.simulatorBundleId

    static func signals(for context: CaptureContext, myApps: [String], userTeamIDs: Set<String>) -> ModeSignals {
        ModeSignals(
            bundleId: context.source.app.bundleId,
            // The simulator block is there exactly when the window shows a simulator (Device Hub also
            // shows physical devices).
            isSimulator: context.source.simulator != nil,
            simulatedBundleId: context.source.simulator?.appBundleId,
            bundlePath: context.bundlePath,
            urlHost: context.source.url.flatMap { URL(string: $0)?.host },
            teamID: context.teamID,
            userTeamIDs: userTeamIDs,
            myApps: myApps
        )
    }

    /// Mode from the source alone, without filesystem or keychain signals.
    static func classify(_ source: SourceInfo, myApps: [String] = []) -> CaptureMode {
        let context = CaptureContext(source: source, frontPID: 0)
        let environment = ModeEnvironment(directoryEntries: { _ in [] }, derivedDataWorkspacePath: { _ in nil })
        return ModeInference.infer(signals(for: context, myApps: myApps, userTeamIDs: []), environment: environment).mode
    }
}
