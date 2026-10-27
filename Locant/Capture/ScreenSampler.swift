import CoreGraphics
import Foundation

/// specs/capture-shapes.md R126: one recent image of the area hover reads shapes in, while the overlay
/// is up. Hover never waits for it: without an image of the area it wants, hover runs without shapes,
/// and when one lands `onUpdate` has the spot read again. Memory only, dropped on `stop()`.
@MainActor
final class ScreenSampler {
    typealias Capture = @Sendable (CGRect) async throws -> (image: CGImage, frame: CGRect, scale: CGFloat)

    /// Larger areas are taken at a lower scale. Nonisolated: the default capture reads it off the main actor.
    nonisolated static let maxSamples = 4_000_000

    /// The area captured now through ScreenCaptureKit, Locant's own windows excluded.
    nonisolated static let live: Capture = { try await ScreenCapture.regionImage($0, maxSamples: ScreenSampler.maxSamples) }

    /// While the screen is frozen (specs/frozen-screen.md R119), the area cut from the frozen image: hover reads
    /// the pixels the user sees, the same ones the click crops (R120 there). `freeze` answers the session's
    /// freeze, waiting for one still being taken; without one, or with no frozen display holding the area's
    /// center, the area is captured by `live`. The cut runs where the capture runs, off the main actor.
    nonisolated static func frozenFirst(_ freeze: @escaping @Sendable () async -> FrozenScreen?,
                                        live capture: @escaping Capture = ScreenSampler.live) -> Capture {
        { area in
            if let cut = await freeze()?.sample(area, maxSamples: ScreenSampler.maxSamples) { return cut }
            return try await capture(area)
        }
    }

    /// A new image landed.
    var onUpdate: (() -> Void)?

    private let hasPermission: @MainActor () -> Bool
    private let capture: Capture
    private let refresh: Duration
    private var latest: PixelGrid?
    private var latestArea: CGRect?
    private var wanted: CGRect?
    /// The area the last capture failed on. `want` leaves it to the refresh: a wedged capture service
    /// throws at once, and hover wants an area about 30 times a second.
    private var failedArea: CGRect?
    private var inFlight = false
    private var generation = 0
    /// Each `start()` and `stop()` opens a new one; a capture only lands in the session that asked for it.
    private var session = 0
    private var loop: Task<Void, Never>?

    init(hasPermission: @escaping @MainActor () -> Bool = { ScreenCapture.hasPermission() },
         capture: @escaping Capture = ScreenSampler.live,
         refresh: Duration = .seconds(1)) {
        self.hasPermission = hasPermission
        self.capture = capture
        self.refresh = refresh
    }

    /// The overlay is up: the area hover wants is taken again every `refresh`.
    func start() {
        guard loop == nil else { return }
        session += 1
        let refresh = refresh
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: refresh)
                guard !Task.isCancelled, let self else { return }
                self.take()
            }
        }
    }

    /// The overlay is gone: no more captures, and the image is dropped. A capture still running may
    /// finish, but its image is discarded.
    func stop() {
        session += 1
        inFlight = false
        loop?.cancel()
        loop = nil
        latest = nil
        latestArea = nil
        wanted = nil
        failedArea = nil
    }

    /// The area hover reads shapes in now. Taken at once unless the newest image already shows it, or
    /// the last capture of it failed, which the next refresh takes again.
    func want(_ area: CGRect) {
        guard loop != nil, area.width > 0, area.height > 0 else { return }
        wanted = area
        if let latestArea, HitRefiner.matches(Frame(latestArea), Frame(area)) { return }
        if let failedArea, HitRefiner.matches(Frame(failedArea), Frame(area)) { return }
        take()
    }

    /// The newest image, when it shows `area`.
    func image(for area: CGRect) -> PixelGrid? {
        guard let latest, let latestArea, HitRefiner.matches(Frame(latestArea), Frame(area)) else { return nil }
        return latest
    }

    /// One capture at a time, never without Screen Recording permission, so it can never prompt.
    /// A failure leaves the previous image, or none, and says nothing.
    private func take() {
        guard !inFlight, let area = wanted, hasPermission() else { return }
        inFlight = true
        generation += 1
        let generation = generation
        let session = session
        let capture = capture
        Task { [weak self] in
            let grid = await Task.detached { () -> PixelGrid? in
                guard let taken = try? await capture(area), taken.frame.width > 0 else { return nil }
                return PixelGrid(image: taken.image, frame: taken.frame,
                                 scale: CGFloat(taken.image.width) / taken.frame.width, generation: generation)
            }.value
            guard let self, self.session == session else { return }
            self.inFlight = false
            self.failedArea = grid == nil ? area : nil
            if let grid {
                self.latest = grid
                self.latestArea = area
                self.onUpdate?()
            }
            // An area wanted while this one was in flight is taken now, not at the next refresh. It
            // cannot loop: only `want` moves `wanted`, and a failed capture of it matches itself.
            if let wanted = self.wanted, !HitRefiner.matches(Frame(wanted), Frame(area)) { self.take() }
        }
    }
}
