import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Read-only bytes that are either copied into our own buffer or
/// memory-mapped from a file. Mapped bytes (installed apps' .dex files) are
/// "clean" memory: iOS can drop and re-read those pages under pressure
/// instead of counting them against the app, which matters on 1 GB iPhones.
final class ByteStore {
    let base: UnsafePointer<UInt8>
    let count: Int
    private let mapped: Bool

    init(copying bytes: [UInt8]) {
        let p = UnsafeMutablePointer<UInt8>.allocate(capacity: max(1, bytes.count))
        if bytes.isEmpty {
            p.initialize(to: 0)
        } else {
            bytes.withUnsafeBufferPointer { p.initialize(from: $0.baseAddress!, count: bytes.count) }
        }
        base = UnsafePointer(p)
        count = bytes.count
        mapped = false
    }

    /// Maps a whole file read-only. Returns nil if it can't be opened.
    init?(mapping path: String) {
        let fd = open(path, O_RDONLY)
        if fd < 0 { return nil }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, st.st_size > 0 else { return nil }
        let size = Int(st.st_size)
        guard let m = mmap(nil, size, PROT_READ, MAP_PRIVATE, fd, 0),
              m != UnsafeMutableRawPointer(bitPattern: -1) else { return nil }
        base = UnsafePointer(m.assumingMemoryBound(to: UInt8.self))
        count = size
        mapped = true
    }

    deinit {
        if mapped {
            munmap(UnsafeMutableRawPointer(mutating: base), count)
        } else {
            UnsafeMutablePointer(mutating: base).deallocate()
        }
    }
}

/// Bounds-checked little-endian reader. Out-of-range reads return 0 so a
/// malformed APK can never crash the app.
struct Bytes {
    let store: ByteStore
    private let p: UnsafePointer<UInt8>
    let count: Int

    init(_ b: [UInt8]) { self.init(store: ByteStore(copying: b)) }

    init(store: ByteStore) {
        self.store = store
        p = store.base
        count = store.count
    }

    @inline(__always) func u8(_ o: Int) -> Int {
        return (o >= 0 && o < count) ? Int(p[o]) : 0
    }
    @inline(__always) func u16(_ o: Int) -> Int {
        return u8(o) | (u8(o + 1) << 8)
    }
    @inline(__always) func u32(_ o: Int) -> Int {
        return u16(o) | (u16(o + 2) << 16)
    }
    @inline(__always) func s32(_ o: Int) -> Int32 {
        return Int32(truncatingIfNeeded: u32(o))
    }
    func slice(_ o: Int, _ n: Int) -> [UInt8] {
        guard o >= 0, n >= 0, o + n <= count else { return [] }
        return Array(UnsafeBufferPointer(start: p + o, count: n))
    }

    /// Reads an unsigned LEB128 value, advancing `o`.
    func uleb(_ o: inout Int) -> Int {
        var result = 0
        var shift = 0
        while shift < 35 {
            let byte = u8(o)
            o += 1
            result |= (byte & 0x7f) << shift
            if byte & 0x80 == 0 { break }
            shift += 7
        }
        return result
    }

    /// Reads a signed LEB128 value, advancing `o`.
    func sleb(_ o: inout Int) -> Int {
        var result = 0
        var shift = 0
        var byte = 0
        repeat {
            byte = u8(o)
            o += 1
            result |= (byte & 0x7f) << shift
            shift += 7
        } while byte & 0x80 != 0 && shift < 35
        if shift < 64 && (byte & 0x40) != 0 {
            result |= -(1 << shift)
        }
        return Int(Int32(truncatingIfNeeded: result))
    }
}

/// Resource string pool (shared by binary XML and resources.arsc).
struct StringPool {
    var strings: [String] = []

    init() {}

    init(_ d: Bytes, at start: Int) {
        let headerSize = d.u16(start + 2)
        let count = d.u32(start + 8)
        let flags = d.u32(start + 16)
        let stringsStart = d.u32(start + 20)
        let utf8 = (flags & 0x100) != 0
        guard count < 2_000_000 else { return }
        strings.reserveCapacity(count)
        for i in 0..<count {
            let off = d.u32(start + headerSize + i * 4)
            var p = start + stringsStart + off
            if utf8 {
                // utf16 length (skip), then utf8 byte length
                if d.u8(p) & 0x80 != 0 { p += 2 } else { p += 1 }
                var len = d.u8(p)
                if len & 0x80 != 0 {
                    len = ((len & 0x7f) << 8) | d.u8(p + 1)
                    p += 2
                } else {
                    p += 1
                }
                let bytes = d.slice(p, len)
                strings.append(String(decoding: bytes, as: UTF8.self))
            } else {
                var len = d.u16(p)
                if len & 0x8000 != 0 {
                    len = ((len & 0x7fff) << 16) | d.u16(p + 2)
                    p += 4
                } else {
                    p += 2
                }
                len = max(0, min(len, (d.count - p) / 2))
                var units = [UInt16]()
                units.reserveCapacity(len)
                for k in 0..<len { units.append(UInt16(d.u16(p + k * 2))) }
                strings.append(String(decoding: units, as: UTF16.self))
            }
        }
    }

    subscript(i: Int) -> String? {
        return (i >= 0 && i < strings.count) ? strings[i] : nil
    }
}
