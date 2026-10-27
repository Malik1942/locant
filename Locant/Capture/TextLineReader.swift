import CoreGraphics
import Foundation
import Vision

/// specs/capture-shapes.md R127: the lines of text inside an element that merges them (a SwiftUI list card,
/// Device Hub's floating tab bar), read from the screen sample with Vision. Hover never waits for them:
/// without lines for a rectangle's pixels it asks for them and goes on, and when they land `onUpdate` has
/// the spot read again. Memory only, dropped on `stop()`.
@MainActor
final class TextLineReader {
    /// The lines in `image`, which shows `frame` in global points. `cjk`: the element's label holds CJK
    /// characters, so a read that finds nothing is tried again for them.
    typealias Recognize = @Sendable (_ image: CGImage, _ frame: CGRect, _ cjk: Bool) async throws -> [TextLine]

    /// Rectangles whose lines are kept; past this the cache starts over.
    static let cacheLimit = 32

    /// Lines landed.
    var onUpdate: (() -> Void)?

    /// A rectangle and its pixels: lines read once stand while the pixels inside it do not change, so the
    /// sample's 1 s refresh does not read them again.
    private struct Key: Hashable, Sendable {
        var frame: Frame
        var scale: CGFloat
        var pixels: Int
        var cjk: Bool
    }

    private struct Request: Sendable {
        var key: Key
        var frame: CGRect
        var grid: PixelGrid
    }

    private let recognize: Recognize
    private var running = false
    private var cache: [Key: [TextLine]] = [:]
    private var inFlight: Key?
    /// The newest request that came while one was in flight; an older one waiting is dropped.
    private var waiting: Request?
    /// The last key worked out, so a sample's pixels are hashed once per rectangle, not at each hover step.
    /// A grid's generation names one sample (R119).
    private var lastKey: (generation: Int, key: Key)?
    /// Each `stop()` opens a new one; lines only land in the session that asked for them.
    private var session = 0

    init(recognize: @escaping Recognize = { image, frame, cjk in try TextLineReader.read(image, showing: frame, cjk: cjk) }) {
        self.recognize = recognize
    }

    /// Hover is on: lines are read when asked for.
    func start() {
        running = true
    }

    /// Hover is over: every line is dropped, and a read still running lands nowhere.
    func stop() {
        session += 1
        running = false
        cache = [:]
        inFlight = nil
        waiting = nil
        lastKey = nil
    }

    /// The lines read in `frame` (global points) of `grid`, when its pixels there have been read; else nil,
    /// and they are asked for. `label` is the element's, which says whether to try CJK.
    func lines(in frame: CGRect, of grid: PixelGrid, label: String? = nil) -> [TextLine]? {
        guard running, let key = key(for: frame, in: grid, cjk: Self.holdsCJK(label)) else { return nil }
        if let known = cache[key] { return known }
        ask(Request(key: key, frame: frame, grid: grid))
        return nil
    }

    private func key(for frame: CGRect, in grid: PixelGrid, cjk: Bool) -> Key? {
        let area = Frame(frame)
        if let last = lastKey, last.generation == grid.generation, last.key.frame == area, last.key.cjk == cjk { return last.key }
        guard let box = grid.box(of: frame) else { return nil }
        let key = Key(frame: area, scale: grid.scale, pixels: Self.hash(of: grid, in: box), cjk: cjk)
        lastKey = (grid.generation, key)
        return key
    }

    /// The bytes inside `box`, row by row.
    private static func hash(of grid: PixelGrid, in box: SampleBox) -> Int {
        var hasher = Hasher()
        grid.forEachRow(of: box) { hasher.combine(bytes: $0) }
        return hasher.finalize()
    }

    /// One read at a time; the newest of those that come meanwhile waits for it.
    private func ask(_ request: Request) {
        guard inFlight != request.key, waiting?.key != request.key else { return }
        if inFlight != nil {
            waiting = request
        } else {
            read(request)
        }
    }

    private func read(_ request: Request) {
        inFlight = request.key
        let session = session
        let recognize = recognize
        Task { [weak self] in
            let lines = await Task.detached(priority: .userInitiated) { () -> [TextLine]? in
                #if DEBUG
                let started = ContinuousClock.now
                defer { NSLog("Locant text lines: %.1f ms", (ContinuousClock.now - started) / .milliseconds(1)) }
                #endif
                guard let cut = request.grid.image(of: request.frame) else { return nil }
                return try? await recognize(cut.image, cut.frame, request.key.cjk)
            }.value
            guard let self, self.session == session else { return }
            self.inFlight = nil
            if self.cache.count >= Self.cacheLimit { self.cache.removeAll() }
            self.cache[request.key] = lines ?? [] // a failed read is not tried again on the same pixels
            if lines != nil { self.onUpdate?() }
            if let next = self.waiting {
                self.waiting = nil
                self.read(next)
            }
        }
    }

    // MARK: Vision

    /// Vision's lines in `image`, which shows `frame` in global points, top to bottom then left to right:
    /// `.fast`, en-US, no language correction. When that finds nothing and `cjk`, `.accurate` with the
    /// languages of Text in image (`TextRecognizer.languages`), since `.fast` reads none of them.
    nonisolated static func read(_ image: CGImage, showing frame: CGRect, cjk: Bool) throws -> [TextLine] {
        var found = try observations(in: image, level: .fast, languages: ["en-US"])
        if found.isEmpty, cjk {
            found = try observations(in: image, level: .accurate, languages: TextRecognizer.languages)
        }
        let lines = found.compactMap { observation -> TextLine? in
            guard let text = observation.topCandidates(1).first?.string.trimmingCharacters(in: .whitespaces),
                  !text.isEmpty else { return nil }
            return TextLine(text: text, frame: globalFrame(of: observation.boundingBox, in: frame))
        }
        return lines.sorted { a, b in abs(a.frame.y - b.frame.y) > 4 ? a.frame.y < b.frame.y : a.frame.x < b.frame.x }
    }

    private nonisolated static func observations(in image: CGImage, level: VNRequestTextRecognitionLevel,
                                                 languages: [String]) throws -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return request.results ?? []
    }

    /// Vision's box, normalized with its origin at the bottom left, in global points over `frame`.
    nonisolated static func globalFrame(of box: CGRect, in frame: CGRect) -> Frame {
        Frame(x: frame.minX + box.minX * frame.width, y: frame.minY + (1 - box.maxY) * frame.height,
              w: box.width * frame.width, h: box.height * frame.height)
    }

    /// Han, kana, or Hangul, which `.fast` does not read.
    nonisolated static func holdsCJK(_ text: String?) -> Bool {
        guard let text else { return false }
        return text.unicodeScalars.contains { scalar in
            scalar.properties.isIdeographic || (0x3040...0x30FF).contains(scalar.value) || (0xAC00...0xD7AF).contains(scalar.value)
        }
    }
}
