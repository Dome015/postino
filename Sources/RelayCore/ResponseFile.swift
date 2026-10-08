import Foundation
public enum ResponseFile {
    public static let pageSize = 128 * 1024
    public static func copy(from input: FileHandle, to output: FileHandle) throws {
        var more = true
        while more { try autoreleasepool { guard let chunk = try input.read(upToCount: 262144), !chunk.isEmpty else { more = false; return }; try output.write(contentsOf: chunk) } }
    }
    public static func size(_ url: URL) -> Int64 { (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0 }
    public static func page(_ url: URL, index: Int) throws -> String {
        let h = try FileHandle(forReadingFrom: url); defer { try? h.close() }
        let start = UInt64(max(0, index) * pageSize); try h.seek(toOffset: start)
        let data = try h.read(upToCount: pageSize + 4) ?? Data(); var lo = 0; var hi = min(pageSize, data.count)
        if start > 0 { while lo < min(4, data.count) && (data[lo] & 0xC0) == 0x80 { lo += 1 } }
        while hi < data.count && (data[hi] & 0xC0) == 0x80 { hi += 1 }
        return String(decoding: data[lo..<hi], as: UTF8.self)
    }
    // A bounded-memory formatter. No object graph, no Double conversion, no loss of large integer precision.
    public static func pretty(_ source: URL, destination: URL, cancelled: () -> Bool = { false }) throws {
        let input = try FileHandle(forReadingFrom: source); defer { try? input.close() }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw RelayError.message("Cannot create formatted file.") }
        let output = try FileHandle(forWritingTo: destination); defer { try? output.close() }
        var buffer = Data(); buffer.reserveCapacity(70_000); var depth = 0; var inString = false; var escaped = false; var previous: UInt8 = 0
        func flush() throws { if buffer.count >= 65_536 { try output.write(contentsOf: buffer); buffer.removeAll(keepingCapacity: true) } }
        func newline() { buffer.append(10); buffer.append(contentsOf: repeatElement(UInt8(32), count: min(depth, 64) * 2)) }
        do {
            var hasMore = true
            while hasMore { try autoreleasepool {
                guard let chunk = try input.read(upToCount: 65_536), !chunk.isEmpty else { hasMore = false; return }
                if cancelled() { throw CancellationError() }
                for b in chunk {
                    if inString { buffer.append(b); if escaped { escaped = false } else if b == 92 { escaped = true } else if b == 34 { inString = false; previous = 34 }; try flush(); continue }
                    if [9, 10, 13, 32].contains(b) { continue }
                    if b == 34 { if previous == 123 || previous == 91 { newline() }; buffer.append(b); inString = true }
                    else if b == 123 || b == 91 { if previous == 123 || previous == 91 { newline() }; buffer.append(b); depth += 1 }
                    else if b == 125 || b == 93 { depth = max(0, depth - 1); if previous != 123 && previous != 91 { newline() }; buffer.append(b) }
                    else if b == 44 { buffer.append(b); newline() }
                    else if b == 58 { buffer.append(contentsOf: [58, 32]) }
                    else { if previous == 123 || previous == 91 { newline() }; buffer.append(b) }
                    previous = b; try flush()
                }
            } }
            try output.write(contentsOf: buffer)
        } catch { try? FileManager.default.removeItem(at: destination); throw error }
    }
    public static func search(_ url: URL, term: String, from offset: UInt64 = 0, cancelled: () -> Bool = { false }) throws -> UInt64? {
        guard !term.isEmpty else { return nil }; let needle = Data(term.utf8); let h = try FileHandle(forReadingFrom: url); defer { try? h.close() }; try h.seek(toOffset: offset)
        var carry = Data(); var position = offset
        var hasMore = true; var found: UInt64?
        while hasMore {
            try autoreleasepool {
                guard let chunk = try h.read(upToCount: 262_144), !chunk.isEmpty else { hasMore = false; return }
                if cancelled() { throw CancellationError() }; var combined = carry; combined.append(chunk)
                if let range = combined.range(of: needle) { found = position - UInt64(carry.count) + UInt64(range.lowerBound); return }
                carry = Data(combined.suffix(max(0, needle.count - 1))); position += UInt64(chunk.count)
            }
            if let found = found { return found }
        }
        return nil
    }
}
