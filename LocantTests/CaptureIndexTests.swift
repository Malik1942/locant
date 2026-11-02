import XCTest
@testable import Locant

final class CaptureIndexTests: XCTestCase {
    /// `resolve_capture` rewrites the sidecar; the Finder tags and the pin `FileStore.write` and
    /// Lifecycle put on it must still be there afterwards (Nov 2 2026; the atomic write dropped them).
    func testResolveKeepsTheSidecarsTagsAndPin() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "LocantIndex-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let capture = Capture(
            id: "20260914-100000-aaaa", createdAt: "2026-09-14T10:00:00-07:00", mode: .fix,
            image: ImageInfo(path: "", widthPt: 10, heightPt: 10, scale: 2, crop: nil),
            source: SourceInfo(app: AppInfo(bundleId: "com.apple.iphonesimulator", name: "Simulator"), window: nil, url: nil, simulator: nil, projectRoot: "/Users/me/Code/Oryne"),
            element: nil, note: "round it"
        )
        let written = try FileStore(directory: dir).write(png: Data([0x89, 0x50, 0x4E, 0x47]), capture: capture)
        let sidecar = IterationStore.sidecarURL(forImage: URL(filePath: written.image.path))
        Lifecycle.pin([sidecar])
        let tags = ["Locant", "Simulator", "fix", "Oryne"]
        XCTAssertEqual(try sidecar.resourceValues(forKeys: [.tagNamesKey]).tagNames, tags)

        let index = CaptureIndex(folder: dir)
        let resolved = try index.resolve(id: capture.id)
        XCTAssertTrue(resolved.capture.resolved)
        XCTAssertEqual(try IterationStore.load(sidecar).resolved, true)
        XCTAssertEqual(try sidecar.resourceValues(forKeys: [.tagNamesKey]).tagNames, tags, "the JSON keeps the tags its PNG has")
        XCTAssertEqual(try URL(filePath: written.image.path).resourceValues(forKeys: [.tagNamesKey]).tagNames, tags)
        XCTAssertTrue(Lifecycle.isPinned(sidecar))

        // The helper on its own: every attribute comes back, and a file without any is just written.
        let plain = dir.appending(path: "plain.json")
        try FileStore.rewrite(Data("{}".utf8), at: plain)
        XCTAssertEqual(try String(contentsOf: plain, encoding: .utf8), "{}")
        XCTAssertNil(FileStore.extendedAttributes(of: plain)["com.apple.metadata:_kMDItemUserTags"])
        XCTAssertTrue(Set(FileStore.extendedAttributes(of: sidecar).keys).isSuperset(of: ["com.apple.metadata:_kMDItemUserTags", Lifecycle.pinAttribute]))
    }
}
