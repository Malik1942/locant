import Foundation

/// specs/simulator-project-root.md R106: which build folder a binary came from. The linker writes a debug
/// map into the symbol table, one `N_OSO` stab per object file it linked, by absolute path; Xcode compiles
/// those under `<build folder>/Build/Intermediates.noindex/`. Pure, Foundation only: any input it cannot
/// read gives nil, never a crash.
enum BuildProvenance {
    static let intermediates = "/Build/Intermediates.noindex/"

    /// The binary that holds an iOS-style (flat) bundle's code. Xcode's Debug builds put it in
    /// `<executable>.debug.dylib` and leave the executable a stub, the same in every checkout.
    static func codeBinary(ofBundleAt bundle: URL) -> URL? {
        guard let data = try? Data(contentsOf: bundle.appending(path: "Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let executable = plist["CFBundleExecutable"] as? String, !executable.isEmpty
        else { return nil }
        let debug = bundle.appending(path: executable + ".debug.dylib")
        return FileManager.default.fileExists(atPath: debug.path(percentEncoded: false)) ? debug : bundle.appending(path: executable)
    }

    /// The build folder most of the debug map's object files sit in; entries elsewhere (the toolchain's own
    /// archives) are skipped. Nil without a debug map.
    static func buildFolder(inMachO data: Data) -> String? {
        var counts: [String: Int] = [:]
        for path in objectFiles(inMachO: data) {
            guard let range = path.range(of: intermediates), range.lowerBound > path.startIndex else { continue }
            counts[String(path[..<range.lowerBound]), default: 0] += 1
        }
        return counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
    }

    /// The `N_OSO` paths of a thin 64-bit Mach-O, or of the first slice of a universal one that has any.
    static func objectFiles(inMachO data: Data) -> [String] {
        let bytes = Bytes(data: data)
        switch bytes.u32(0, bigEndian: true) {
        case fatMagic, fatMagic64:
            let wide = bytes.u32(0, bigEndian: true) == fatMagic64
            guard let count = bytes.u32(4, bigEndian: true) else { return [] }
            for index in 0..<min(Int(count), maxSlices) {
                let arch = 8 + index * (wide ? 32 : 20)
                let offset = wide ? bytes.u64(arch + 8, bigEndian: true).flatMap { Int(exactly: $0) } : bytes.u32(arch + 8, bigEndian: true).map(Int.init)
                guard let offset else { return [] }
                let files = thinObjectFiles(bytes, at: offset)
                if !files.isEmpty { return files }
            }
            return []
        default:
            return thinObjectFiles(bytes, at: 0)
        }
    }

    private static let machMagic64: UInt32 = 0xfeedfacf
    private static let fatMagic: UInt32 = 0xcafebabe
    private static let fatMagic64: UInt32 = 0xcafebabf
    private static let lcSymtab: UInt32 = 0x2
    private static let nOSO: UInt8 = 0x66
    private static let maxSlices = 16

    /// One Mach-O starting `base` bytes in; symbol and string offsets count from there.
    private static func thinObjectFiles(_ bytes: Bytes, at base: Int) -> [String] {
        guard bytes.u32(base) == machMagic64, let commands = bytes.u32(base + 16) else { return [] }
        var cursor = base + 32
        for _ in 0..<commands {
            guard let command = bytes.u32(cursor), let size = bytes.u32(cursor + 4), size >= 8 else { return [] }
            if command == lcSymtab {
                guard let symbolOffset = bytes.u32(cursor + 8), let symbolCount = bytes.u32(cursor + 12),
                      let stringOffset = bytes.u32(cursor + 16), let stringSize = bytes.u32(cursor + 20) else { return [] }
                let strings = base + Int(stringOffset)
                let stringEnd = strings + Int(stringSize)
                var files: [String] = []
                for index in 0..<Int(symbolCount) {
                    let entry = base + Int(symbolOffset) + index * 16
                    guard let name = bytes.u32(entry), let type = bytes.u8(entry + 4) else { return [] }
                    guard type == nOSO else { continue }
                    guard let path = bytes.cString(at: strings + Int(name), before: stringEnd) else { return [] }
                    files.append(path)
                }
                return files
            }
            cursor += Int(size)
        }
        return []
    }

    /// Bounds-checked little- or big-endian reads.
    private struct Bytes {
        let data: Data

        func u8(_ offset: Int) -> UInt8? {
            guard offset >= 0, offset < data.count else { return nil }
            return data[data.startIndex + offset]
        }

        func u32(_ offset: Int, bigEndian: Bool = false) -> UInt32? {
            read(offset, width: 4, bigEndian: bigEndian).map { UInt32(truncatingIfNeeded: $0) }
        }

        func u64(_ offset: Int, bigEndian: Bool = false) -> UInt64? {
            read(offset, width: 8, bigEndian: bigEndian)
        }

        /// A NUL-terminated UTF-8 string that ends before `limit`; nil when it runs past it.
        func cString(at offset: Int, before limit: Int) -> String? {
            let end = min(limit, data.count)
            guard offset >= 0, offset < end else { return nil }
            let start = data.startIndex + offset
            guard let nul = data[start..<(data.startIndex + end)].firstIndex(of: 0) else { return nil }
            return String(bytes: data[start..<nul], encoding: .utf8)
        }

        private func read(_ offset: Int, width: Int, bigEndian: Bool) -> UInt64? {
            guard offset >= 0, offset <= data.count - width else { return nil }
            var value: UInt64 = 0
            for index in 0..<width {
                let byte = UInt64(data[data.startIndex + offset + index])
                value |= byte << (8 * UInt64(bigEndian ? width - 1 - index : index))
            }
            return value
        }
    }
}
