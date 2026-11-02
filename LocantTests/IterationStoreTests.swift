import XCTest
@testable import Locant

final class IterationStoreTests: XCTestCase {
    func testAppendRoundTripsAndNamesAfterImages() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "LocantVerify-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let sidecar = dir.appending(path: "locant-simulator-20260913-180000-ab12.json")
        var capture = Capture(
            id: "20260913-180000-ab12", createdAt: "2026-09-13T18:00:00-07:00", mode: .fix,
            image: ImageInfo(path: dir.appending(path: "locant-simulator-20260913-180000-ab12.png").path(percentEncoded: false), widthPt: 10, heightPt: 10, scale: 2, crop: nil),
            source: SourceInfo(app: AppInfo(bundleId: "com.apple.iphonesimulator", name: "Simulator"), window: nil, url: nil, simulator: nil, projectRoot: "/tmp/x", gitCommit: "abc123"),
            element: nil, note: "round it", resolved: true
        )
        let encoder = JSONEncoder()
        try encoder.encode(capture).write(to: sidecar)
        FileStore.setFinderTags(["Locant", "Simulator", "fix"], on: sidecar)
        Lifecycle.pin([sidecar])

        XCTAssertEqual(IterationStore.afterImageURL(for: sidecar, index: 1).lastPathComponent, "locant-simulator-20260913-180000-ab12-after-1.png")
        XCTAssertEqual(IterationStore.sidecarURL(forImage: URL(filePath: capture.image.path)), sidecar)

        let first = Iteration(capturedAt: "2026-09-13T18:05:00-07:00", imagePath: "/tmp/after-1.png", gitBefore: "abc123", gitAfter: "def456", diffStat: " 1 file changed", files: ["Oryne/View.swift"], frame: Frame(x: 1, y: 2, w: 3, h: 4))
        let updated = try IterationStore.append(first, to: sidecar)
        XCTAssertEqual(updated.iterations, [first])
        XCTAssertTrue(updated.resolved)

        let second = Iteration(capturedAt: "2026-09-13T18:10:00-07:00", imagePath: "/tmp/after-2.png", gitBefore: "def456", gitAfter: "def456", diffStat: nil, files: [])
        let again = try IterationStore.append(second, to: sidecar)
        XCTAssertEqual(again.iterations.count, 2)
        capture.iterations = [first, second]
        XCTAssertEqual(try IterationStore.load(sidecar), capture)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: sidecar)) as? [String: Any])
        XCTAssertEqual((json["source"] as? [String: Any])?["gitCommit"] as? String, "abc123")
        // The rewrite kept the sidecar's Finder tags and its pin (Nov 2 2026; the atomic write dropped them).
        XCTAssertEqual(try sidecar.resourceValues(forKeys: [.tagNamesKey]).tagNames, ["Locant", "Simulator", "fix"])
        XCTAssertTrue(Lifecycle.isPinned(sidecar))
    }
}
