import Foundation
import Compression

/// Minimal read-only ZIP reader (APKs are ZIP files). Supports stored and
/// deflated entries, which is everything Android build tools produce.
final class ZipArchive {
    struct Entry {
        let name: String
        let method: Int
        let compressedSize: Int
        let size: Int
        let localOffset: Int
    }

    private let d: Bytes
    private(set) var entries: [String: Entry] = [:]
    private(set) var names: [String] = []

    init?(bytes: [UInt8]) {
        d = Bytes(bytes)
        let n = bytes.count
        guard n >= 22 else { return nil }

        // Find the End Of Central Directory record.
        var eocd = -1
        var i = n - 22
        let stop = max(0, n - 22 - 65_535)
        while i >= stop {
            if d.u32(i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { return nil }

        let total = d.u16(eocd + 10)
        var p = d.u32(eocd + 16)
        for _ in 0..<total {
            guard d.u32(p) == 0x02014b50 else { break }
            let method = d.u16(p + 10)
            let csize = d.u32(p + 20)
            let usize = d.u32(p + 24)
            let nameLen = d.u16(p + 28)
            let extraLen = d.u16(p + 30)
            let commentLen = d.u16(p + 32)
            let local = d.u32(p + 42)
            let name = String(decoding: d.slice(p + 46, nameLen), as: UTF8.self)
            let e = Entry(name: name, method: method, compressedSize: csize, size: usize, localOffset: local)
            if entries[name] == nil { names.append(name) }
            entries[name] = e
            p += 46 + nameLen + extraLen + commentLen
        }
        if entries.isEmpty { return nil }
    }

    func contains(_ name: String) -> Bool { return entries[name] != nil }

    func read(_ name: String) -> [UInt8]? {
        guard let e = entries[name] else { return nil }
        let lo = e.localOffset
        guard d.u32(lo) == 0x04034b50 else { return nil }
        let start = lo + 30 + d.u16(lo + 26) + d.u16(lo + 28)
        guard start >= 0, start + e.compressedSize <= d.count else { return nil }

        if e.method == 0 {
            return d.slice(start, e.compressedSize)
        }
        guard e.method == 8 else { return nil }
        if e.size == 0 { return [] }
        guard e.size < 512 * 1024 * 1024 else { return nil }

        var out = [UInt8](repeating: 0, count: e.size)
        let src = d.b
        let csize = e.compressedSize
        let usize = e.size
        let written: Int = src.withUnsafeBufferPointer { s -> Int in
            out.withUnsafeMutableBufferPointer { o -> Int in
                guard let sb = s.baseAddress, let ob = o.baseAddress else { return 0 }
                // COMPRESSION_ZLIB is raw DEFLATE (RFC 1951), exactly what ZIP uses.
                return compression_decode_buffer(ob, usize, sb + start, csize, nil, COMPRESSION_ZLIB)
            }
        }
        if written <= 0 { return nil }
        if written < usize { return Array(out[0..<written]) }
        return out
    }
}
