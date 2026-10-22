import XCTest
@testable import Locant

/// Small Mach-O files for tests: a 64-bit header, one `LC_SYMTAB`, symbols, and a string table, as ld
/// lays them out.
enum MachOFixture {
    static let nSO: UInt8 = 0x64
    static let nOSO: UInt8 = 0x66
    /// `N_SECT | N_EXT`: an ordinary exported symbol, not a stab.
    static let exported: UInt8 = 0x0f

    /// A thin arm64 dylib whose symbol table holds `symbols` in order; no load commands without `symtab`.
    static func thin(symbols: [(type: UInt8, name: String)], symtab: Bool = true) -> Data {
        var strings = Data([0x20, 0x00])
        var entries = Data()
        for symbol in symbols {
            entries += le32(UInt32(strings.count)) + Data([symbol.type, 0, 0, 0]) + le64(0)
            strings += Data(symbol.name.utf8) + Data([0])
        }
        let symoff = 32 + (symtab ? 24 : 0)
        let stroff = symoff + entries.count
        var data = le32(0xfeedfacf) + le32(0x0100000c) + le32(0) + le32(6)
        data += le32(symtab ? 1 : 0) + le32(symtab ? 24 : 0) + le32(0) + le32(0)
        if symtab {
            data += le32(2) + le32(24) + le32(UInt32(symoff)) + le32(UInt32(symbols.count)) + le32(UInt32(stroff)) + le32(UInt32(strings.count))
        }
        return data + entries + strings
    }

    /// A debug map: for each object file, the source folder (`N_SO`) and the object file (`N_OSO`).
    static func debugMap(_ objectFiles: [String]) -> Data {
        thin(symbols: objectFiles.flatMap { [(nSO, "/Users/me/Code/oryne/Oryne/"), (nOSO, $0)] })
    }

    /// `slices` in a universal wrapper (big-endian `fat_header`, one `fat_arch` each).
    static func universal(_ slices: [Data]) -> Data {
        var header = be32(0xcafebabe) + be32(UInt32(slices.count))
        var offset = 8 + 20 * slices.count
        var body = Data()
        for (index, slice) in slices.enumerated() {
            header += be32(index == 0 ? 0x01000007 : 0x0100000c) + be32(0) + be32(UInt32(offset)) + be32(UInt32(slice.count)) + be32(0)
            body += slice
            offset += slice.count
        }
        return header + body
    }

    /// An object file Xcode compiled into `buildFolder` (a DerivedData project folder).
    static func objectFile(in buildFolder: String, _ name: String) -> String {
        buildFolder + "/Build/Intermediates.noindex/Oryne.build/Debug-iphonesimulator/Oryne.build/Objects-normal/arm64/\(name).o"
    }

    private static func le32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
    private static func le64(_ value: UInt64) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
    private static func be32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.bigEndian) { Data($0) } }
}

/// specs/simulator-project-root.md R106: the build folder a binary's debug map names.
final class BuildProvenanceTests: XCTestCase {
    private let folder = "/Users/me/Library/Developer/Xcode/DerivedData/Oryne-redesign"

    func testDebugMapNamesTheBuildFolder() {
        let data = MachOFixture.debugMap([MachOFixture.objectFile(in: folder, "AppState"), MachOFixture.objectFile(in: folder, "NodeCard")])
        XCTAssertEqual(BuildProvenance.buildFolder(inMachO: data), folder)
    }

    func testUniversalBinaryGivesTheSameFolder() {
        let slice = MachOFixture.debugMap([MachOFixture.objectFile(in: folder, "AppState")])
        XCTAssertEqual(BuildProvenance.buildFolder(inMachO: MachOFixture.universal([slice, slice])), folder)
        XCTAssertEqual(BuildProvenance.buildFolder(inMachO: MachOFixture.universal([MachOFixture.thin(symbols: [], symtab: false), slice])), folder,
                       "a slice without a debug map is passed over")
    }

    /// Coverage builds also link the toolchain's own archives; those name no build folder.
    func testEntriesOutsideABuildFolderAreSkipped() {
        let data = MachOFixture.debugMap([
            "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/clang/21/lib/darwin/libclang_rt.profile_osx.a(InstrProfiling.c.o)",
            MachOFixture.objectFile(in: folder, "AppState"),
        ])
        XCTAssertEqual(BuildProvenance.buildFolder(inMachO: data), folder)
    }

    func testTheFolderMostEntriesNameWins() {
        let other = "/Users/me/Library/Developer/Xcode/DerivedData/Oryne-watch"
        let data = MachOFixture.debugMap([
            MachOFixture.objectFile(in: other, "Prebuilt"),
            MachOFixture.objectFile(in: folder, "AppState"),
            MachOFixture.objectFile(in: folder, "NodeCard"),
        ])
        XCTAssertEqual(BuildProvenance.buildFolder(inMachO: data), folder)
    }

    func testNothingToReadGivesNil() {
        let object = MachOFixture.objectFile(in: folder, "AppState")
        let whole = MachOFixture.debugMap([object])
        XCTAssertNil(BuildProvenance.buildFolder(inMachO: MachOFixture.thin(symbols: [], symtab: false)), "no LC_SYMTAB")
        XCTAssertNil(BuildProvenance.buildFolder(inMachO: MachOFixture.thin(symbols: [(MachOFixture.exported, "_main")])), "no stabs")
        XCTAssertNil(BuildProvenance.buildFolder(inMachO: MachOFixture.thin(symbols: [(MachOFixture.nSO, object)])), "a source stab is not an object file")
        XCTAssertNil(BuildProvenance.buildFolder(inMachO: Data()), "empty")
        for length in [3, 31, 40, 60, whole.count - 40] {
            XCTAssertNil(BuildProvenance.buildFolder(inMachO: whole.prefix(length)), "truncated to \(length) bytes")
        }
        var random = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let bytes = Data((0..<Int.random(in: 0..<512, using: &random)).map { _ in UInt8.random(in: 0...255, using: &random) })
            _ = BuildProvenance.buildFolder(inMachO: bytes)
            _ = BuildProvenance.buildFolder(inMachO: whole.prefix(8) + bytes)
            _ = BuildProvenance.buildFolder(inMachO: MachOFixture.universal([bytes]))
        }
    }

    func testCodeBinaryIsTheDebugDylibWhenThereIsOne() throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let app = tmp.appending(path: "Oryne.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleExecutable": "Oryne"], format: .xml, options: 0)
            .write(to: app.appending(path: "Info.plist"))
        try Data().write(to: app.appending(path: "Oryne"))
        XCTAssertEqual(BuildProvenance.codeBinary(ofBundleAt: app)?.lastPathComponent, "Oryne")
        try Data().write(to: app.appending(path: "Oryne.debug.dylib"))
        XCTAssertEqual(BuildProvenance.codeBinary(ofBundleAt: app)?.lastPathComponent, "Oryne.debug.dylib")
        XCTAssertNil(BuildProvenance.codeBinary(ofBundleAt: tmp.appending(path: "Missing.app")))
    }
}
