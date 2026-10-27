import CoreGraphics
import Foundation
import Vision

/// specs/capture-shapes.md R127: the lines of text inside an element that merges them (a SwiftUI list card,
/// Device Hub's floating tab bar), read from the screen sample with Vision. Hover never waits for them:
/// without lines for a rectangle's pixels it asks for them and goes on with the lines last read there for the
/// same element, if any, and when they land `onUpdate` has the spot read again. Memory only, dropped on `stop()`.
@MainActor
final class TextLineReader {
    /// How an answer's lines are read, decided from its label before anything is read (`reading(for:)`).
    enum Reading: Hashable, Sendable {
        /// `.fast`, en-US.
        case latin
        /// One `.accurate` read in `hanLanguages`, Simplified Chinese first.
        case han
    }

    /// The lines in `image`, which shows `frame` in global points, read as `reading` says.
    typealias Recognize = @Sendable (_ image: CGImage, _ frame: CGRect, _ reading: Reading) async throws -> [TextLine]

    /// Rectangles whose lines are kept; past this the cache starts over.
    static let cacheLimit = 32

    /// Lines landed that can change the ladder: two or more, or fewer where two or more were known in the frame.
    var onUpdate: (() -> Void)?

    /// A rectangle and its pixels: lines read once stand while the pixels inside it do not change, so the
    /// sample's 1 s refresh does not read them again.
    private struct Key: Hashable, Sendable {
        var frame: Frame
        var scale: CGFloat
        var pixels: Int
        var reading: Reading
    }

    private struct Request: Sendable {
        var key: Key
        /// The label of the element the lines are read for.
        var label: String?
        var frame: CGRect
        var grid: PixelGrid
    }

    private let recognize: Recognize
    private var running = false
    private var cache: [Key: [TextLine]] = [:]
    /// The lines last read in each frame, whatever its pixels then, and the label of the element they were read
    /// for. They stand while the frame's changed pixels are read again, for an element whose label shares a part
    /// with that one (`HitRefiner.labelsSharePart`): a merged element's label ticks with the text it merges
    /// ("Random, 4 seconds ago" to "Random, 5 seconds ago"), while another element at the same frame (a pushed
    /// screen of the same layout, a reused cell, another tab under the tab bar) shares no part with it.
    private var latest: [Frame: (label: String?, lines: [TextLine])] = [:]
    private var inFlight: Key?
    /// The newest request that came while one was in flight; an older one waiting is dropped.
    private var waiting: Request?
    /// The last key worked out, so a sample's pixels are hashed once per rectangle, not at each hover step.
    /// A grid's generation names one sample (R119).
    private var lastKey: (generation: Int, key: Key)?
    /// Each `stop()` opens a new one; lines only land in the session that asked for them.
    private var session = 0

    init(recognize: @escaping Recognize = { image, frame, reading in try TextLineReader.read(image, showing: frame, reading: reading) }) {
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
        latest = [:]
        inFlight = nil
        waiting = nil
        lastKey = nil
    }

    /// The lines read in `frame` (global points) of `grid` for the element there with `label`, when its pixels
    /// there have been read. Else they are asked for, and meanwhile the lines last read in that frame stand when
    /// they were read for the same element as far as the labels tell (`latest`), or nil. The label also says how
    /// to read them (`reading(for:)`); one that gives no reading gives no lines, and nothing is read.
    func lines(in frame: CGRect, of grid: PixelGrid, label: String? = nil) -> [TextLine]? {
        guard running, let reading = Self.reading(for: label), let key = key(for: frame, in: grid, reading: reading) else { return nil }
        if let known = cache[key] {
            remember(known, in: key.frame, label: label)
            return known
        }
        ask(Request(key: key, label: label, frame: frame, grid: grid))
        guard let last = latest[key.frame], HitRefiner.labelsSharePart(last.label, label) else { return nil }
        return last.lines
    }

    private func remember(_ lines: [TextLine], in frame: Frame, label: String?) {
        if latest[frame] == nil, latest.count >= Self.cacheLimit { latest.removeAll() }
        latest[frame] = (label, lines)
    }

    private func key(for frame: CGRect, in grid: PixelGrid, reading: Reading) -> Key? {
        let area = Frame(frame)
        if let last = lastKey, last.generation == grid.generation, last.key.frame == area, last.key.reading == reading { return last.key }
        guard let box = grid.box(of: frame) else { return nil }
        let key = Key(frame: area, scale: grid.scale, pixels: Self.hash(of: grid, in: box), reading: reading)
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
                return try? await recognize(cut.image, cut.frame, request.key.reading)
            }.value
            guard let self, self.session == session else { return }
            self.inFlight = nil
            // A failed read caches no lines for these pixels: they are read again only once they change.
            let landed = lines ?? []
            let shown = self.latest[request.key.frame]?.lines.count ?? 0 // what hover may show in the frame meanwhile
            if self.cache.count >= Self.cacheLimit { self.cache.removeAll() }
            self.cache[request.key] = landed
            self.remember(landed, in: request.key.frame, label: request.label)
            // One line or none makes no rung (R127), so only a landing that can change the ladder reads the spot again.
            if landed.count >= 2 || shown >= 2 { self.onUpdate?() }
            if let next = self.waiting {
                self.waiting = nil
                self.read(next)
            }
        }
    }

    // MARK: Vision

    /// How to read the lines of an answer with `label`. Kana or Hangul anywhere: none, so no line rungs, until a
    /// real sample calibrates a reading for them (on Oct 26's synthetic renders `.fast` read 주말 국수 / 어제 as
    /// "xu" and "X41"). The katakana middle dot and long vowel mark (U+30FB, U+30FC) are not kana here: Chinese
    /// writes transliterated names with them (约翰・史密斯). Else, with Han: `.han`, since `.fast` reads no Han and
    /// returns junk for it rather than nothing ("4 秒前" as "4 1JBIJ"). Else `.latin`.
    nonisolated static func reading(for label: String?) -> Reading? {
        var han = false
        for scalar in (label ?? "").unicodeScalars {
            switch scalar.value {
            case 0x3040...0x30FA, 0x30FD...0x30FF, 0x31F0...0x31FF, 0xFF65...0xFF9F: return nil // kana
            case 0x1100...0x11FF, 0x3130...0x318F, 0xA960...0xA97F, 0xAC00...0xD7FF: return nil // Hangul
            default: if scalar.properties.isIdeographic { han = true }
            }
        }
        return han ? .han : .latin
    }

    /// Simplified Chinese first: `.accurate` with en-US first read 周末面条 / 昨天 as "BFE", and 周末面条 / 4 秒前 as
    /// nothing (Oct 26, synthetic renders); language correction made no difference.
    nonisolated static let hanLanguages = ["zh-Hans", "en-US"]

    /// Vision's lines in `image`, which shows `frame` in global points, top to bottom then left to right, with
    /// no language correction: `.latin` at `.fast` in en-US, `.han` at `.accurate` in `hanLanguages`.
    nonisolated static func read(_ image: CGImage, showing frame: CGRect, reading: Reading) throws -> [TextLine] {
        let found = switch reading {
        case .latin: try observations(in: image, level: .fast, languages: ["en-US"])
        case .han: try observations(in: image, level: .accurate, languages: hanLanguages)
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
}
