import Foundation
import Compression

/// Minimal read-only ZIP reader (APKs are ZIP files). Supports stored and
/// deflated entries, which is everything Android build tools produce.
///
/// The archive stays memory-mapped: only the entries you `read` are ever
/// copied into RAM, so even a 150 MB APK costs almost nothing to open.
final class ZipArchive {
    struct Entry {
        let name: String
        let method: Int
        let compressedSize: Int
        let size: Int
        let localOffset: Int
    }

    private let data: Data
    private let count: Int
    private(set) var entries: [String: Entry] = [:]
    private(set) var names: [String] = []

    init?(data: Data) {
        // Re-base so indices start at 0 no matter how the Data was made.
        self.data = data.startIndex == 0 ? data : Data(data)
        count = self.data.count
        guard count >= 22 else { return nil }

        // Find the End Of Central Directory record.
        var eocd = -1
        var i = count - 22
        let stop = max(0, count - 22 - 65_535)
        while i >= stop {
            if u32(i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { return nil }

        let total = u16(eocd + 10)
        var p = u32(eocd + 16)
        for _ in 0..<total {
            guard u32(p) == 0x02014b50 else { break }
            let method = u16(p + 10)
            let csize = u32(p + 20)
            let usize = u32(p + 24)
            let nameLen = u16(p + 28)
            let extraLen = u16(p + 30)
            let commentLen = u16(p + 32)
            let local = u32(p + 42)
            let name = String(decoding: bytes(p + 46, nameLen), as: UTF8.self)
            let e = Entry(name: name, method: method, compressedSize: csize, size: usize, localOffset: local)
            if entries[name] == nil { names.append(name) }
            entries[name] = e
            p += 46 + nameLen + extraLen + commentLen
        }
        if entries.isEmpty { return nil }
    }

    // MARK: - Raw access

    private func u8(_ o: Int) -> Int {
        return (o >= 0 && o < count) ? Int(data[o]) : 0
    }
    private func u16(_ o: Int) -> Int { return u8(o) | (u8(o + 1) << 8) }
    private func u32(_ o: Int) -> Int { return u16(o) | (u16(o + 2) << 16) }

    private func bytes(_ o: Int, _ n: Int) -> [UInt8] {
        guard o >= 0, n >= 0, o + n <= count else { return [] }
        return [UInt8](data[o..<(o + n)])
    }

    // MARK: - Entries

    func contains(_ name: String) -> Bool { return entries[name] != nil }

    func size(of name: String) -> Int { return entries[name]?.size ?? 0 }

    func read(_ name: String) -> [UInt8]? {
        guard let e = entries[name] else { return nil }
        let lo = e.localOffset
        guard u32(lo) == 0x04034b50 else { return nil }
        let start = lo + 30 + u16(lo + 26) + u16(lo + 28)
        guard start >= 0, start + e.compressedSize <= count else { return nil }

        if e.method == 0 {
            return bytes(start, e.compressedSize)
        }
        guard e.method == 8 else { return nil }
        if e.size == 0 { return [] }
        guard e.size < 256 * 1024 * 1024 else { return nil }

        var out = [UInt8](repeating: 0, count: e.size)
        let csize = e.compressedSize
        let usize = e.size
        let written: Int = data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int in
            guard let base = raw.baseAddress else { return 0 }
            let src = base.assumingMemoryBound(to: UInt8.self) + start
            return out.withUnsafeMutableBufferPointer { o -> Int in
                guard let ob = o.baseAddress else { return 0 }
                // COMPRESSION_ZLIB is raw DEFLATE (RFC 1951), exactly what ZIP uses.
                return compression_decode_buffer(ob, usize, src, csize, nil, COMPRESSION_ZLIB)
            }
        }
        if written <= 0 { return nil }
        if written < usize { return Array(out[0..<written]) }
        return out
    }
}
