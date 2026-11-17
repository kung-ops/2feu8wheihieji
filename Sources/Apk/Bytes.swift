import Foundation

/// Bounds-checked little-endian reader. Out-of-range reads return 0 so a
/// malformed APK can never crash the app.
struct Bytes {
    let b: [UInt8]

    init(_ b: [UInt8]) { self.b = b }

    var count: Int { return b.count }

    @inline(__always) func u8(_ o: Int) -> Int {
        return (o >= 0 && o < b.count) ? Int(b[o]) : 0
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
        guard o >= 0, n >= 0, o + n <= b.count else { return [] }
        return Array(b[o..<(o + n)])
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
