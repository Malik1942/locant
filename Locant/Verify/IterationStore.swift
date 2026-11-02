import Foundation

/// R34: iterations live in the capture's own sidecar. The file is rewritten whole, keeping its
/// Finder tags and pin; last writer wins, and the app never caches sidecars.
enum IterationStore {
    static func load(_ sidecar: URL) throws -> Capture {
        try JSONDecoder().decode(Capture.self, from: Data(contentsOf: sidecar))
    }

    @discardableResult
    static func append(_ iteration: Iteration, to sidecar: URL) throws -> Capture {
        var capture = try load(sidecar)
        capture.iterations.append(iteration)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileStore.rewrite(encoder.encode(capture), at: sidecar)
        return capture
    }

    /// `locant-<slug>-<id>-after-<n>.png` beside the sidecar.
    static func afterImageURL(for sidecar: URL, index: Int) -> URL {
        let base = sidecar.deletingPathExtension().lastPathComponent
        return sidecar.deletingLastPathComponent().appending(path: "\(base)-after-\(index).png")
    }

    static func sidecarURL(forImage png: URL) -> URL {
        png.deletingPathExtension().appendingPathExtension("json")
    }
}
