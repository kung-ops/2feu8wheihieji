import Foundation

/// Arbitrary-precision integer with java.math.BigInteger's semantics
/// (division rounds toward zero, shifts and bit operations act on the
/// two's-complement form). Magnitude is little-endian 32-bit limbs.
struct BigInt: Equatable, Comparable, CustomStringConvertible {
    private(set) var negative: Bool
    private(set) var mag: [UInt32]   // no leading (high) zero limbs; zero is []

    static let zero = BigInt(negative: false, mag: [])
    static let one = BigInt(1)

    init(negative: Bool, mag: [UInt32]) {
        var m = mag
        while let last = m.last, last == 0 { m.removeLast() }
        self.mag = m
        self.negative = m.isEmpty ? false : negative
    }

    init(_ v: Int64) {
        let u = v < 0 ? UInt64(bitPattern: v).twosComplementNegated : UInt64(v)
        self.init(negative: v < 0, mag: [UInt32(truncatingIfNeeded: u), UInt32(truncatingIfNeeded: u >> 32)])
    }

    init(_ v: Int) { self.init(Int64(v)) }

    /// Parses Java-style text: optional sign, digits in `radix`.
    init?(_ text: String, radix: Int = 10) {
        guard (2...36).contains(radix) else { return nil }
        var s = Substring(text)
        var neg = false
        if s.first == "-" { neg = true; s = s.dropFirst() } else if s.first == "+" { s = s.dropFirst() }
        guard !s.isEmpty else { return nil }
        var mag: [UInt32] = []
        // Process in chunks that fit a UInt32 multiplier.
        var chunkDigits = 1
        var chunkBase = UInt64(radix)
        while chunkBase * UInt64(radix) <= UInt64(UInt32.max) { chunkBase *= UInt64(radix); chunkDigits += 1 }
        var digits = Array(s)
        var first = digits.count % chunkDigits
        if first == 0 { first = chunkDigits }
        var idx = 0
        var take = first
        while idx < digits.count {
            var chunk: UInt64 = 0
            var mult: UInt64 = 1
            for _ in 0..<take {
                guard let d = digits[idx].hexDigitValue ?? BigInt.digitValue(digits[idx]), d < radix else { return nil }
                chunk = chunk * UInt64(radix) + UInt64(d)
                mult *= UInt64(radix)
                idx += 1
            }
            mag = BigInt.mulSmallAdd(mag, UInt32(truncatingIfNeeded: mult), UInt32(truncatingIfNeeded: chunk))
            take = chunkDigits
        }
        digits.removeAll()
        self.init(negative: neg, mag: mag)
    }

    private static func digitValue(_ c: Character) -> Int? {
        guard let a = c.asciiValue else { return nil }
        if a >= 48 && a <= 57 { return Int(a - 48) }
        if a >= 97 && a <= 122 { return Int(a - 97 + 10) }
        if a >= 65 && a <= 90 { return Int(a - 65 + 10) }
        return nil
    }

    var isZero: Bool { return mag.isEmpty }
    var signum: Int { return isZero ? 0 : (negative ? -1 : 1) }
    var magnitude: BigInt { return BigInt(negative: false, mag: mag) }
    var negated: BigInt { return BigInt(negative: !negative, mag: mag) }

    // MARK: - Magnitude helpers

    static func cmpMag(_ a: [UInt32], _ b: [UInt32]) -> Int {
        if a.count != b.count { return a.count < b.count ? -1 : 1 }
        var i = a.count - 1
        while i >= 0 {
            if a[i] != b[i] { return a[i] < b[i] ? -1 : 1 }
            i -= 1
        }
        return 0
    }

    static func addMag(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
        let (l, s) = a.count >= b.count ? (a, b) : (b, a)
        var out = [UInt32](repeating: 0, count: l.count + 1)
        var carry: UInt64 = 0
        for i in 0..<l.count {
            let t = UInt64(l[i]) + (i < s.count ? UInt64(s[i]) : 0) + carry
            out[i] = UInt32(truncatingIfNeeded: t)
            carry = t >> 32
        }
        out[l.count] = UInt32(carry)
        return out
    }

    /// a - b, requires |a| >= |b|.
    static func subMag(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
        var out = a
        var borrow: Int64 = 0
        for i in 0..<a.count {
            var t = Int64(a[i]) - borrow - (i < b.count ? Int64(b[i]) : 0)
            if t < 0 { t += 1 << 32; borrow = 1 } else { borrow = 0 }
            out[i] = UInt32(t)
        }
        return out
    }

    static func mulMag(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
        if a.isEmpty || b.isEmpty { return [] }
        var out = [UInt32](repeating: 0, count: a.count + b.count)
        for i in 0..<a.count {
            var carry: UInt64 = 0
            let ai = UInt64(a[i])
            if ai == 0 { continue }
            for j in 0..<b.count {
                let t = ai * UInt64(b[j]) + UInt64(out[i + j]) + carry
                out[i + j] = UInt32(truncatingIfNeeded: t)
                carry = t >> 32
            }
            var k = i + b.count
            while carry != 0 {
                let t = UInt64(out[k]) + carry
                out[k] = UInt32(truncatingIfNeeded: t)
                carry = t >> 32
                k += 1
            }
        }
        return out
    }

    static func mulSmallAdd(_ a: [UInt32], _ m: UInt32, _ add: UInt32) -> [UInt32] {
        var out = [UInt32](repeating: 0, count: a.count + 1)
        var carry = UInt64(add)
        for i in 0..<a.count {
            let t = UInt64(a[i]) * UInt64(m) + carry
            out[i] = UInt32(truncatingIfNeeded: t)
            carry = t >> 32
        }
        out[a.count] = UInt32(carry)
        while let last = out.last, last == 0 { out.removeLast() }
        return out
    }

    static func shlMag(_ a: [UInt32], _ n: Int) -> [UInt32] {
        if a.isEmpty || n == 0 { return a }
        let limbs = n / 32, bits = n % 32
        var out = [UInt32](repeating: 0, count: a.count + limbs + 1)
        for i in 0..<a.count {
            let v = UInt64(a[i]) << UInt64(bits)
            out[i + limbs] |= UInt32(truncatingIfNeeded: v)
            out[i + limbs + 1] |= UInt32(truncatingIfNeeded: v >> 32)
        }
        while let last = out.last, last == 0 { out.removeLast() }
        return out
    }

    static func shrMag(_ a: [UInt32], _ n: Int) -> [UInt32] {
        let limbs = n / 32, bits = n % 32
        if limbs >= a.count { return [] }
        var out = [UInt32](repeating: 0, count: a.count - limbs)
        for i in 0..<out.count {
            let lo = UInt64(a[i + limbs]) >> UInt64(bits)
            let hi = i + limbs + 1 < a.count ? UInt64(a[i + limbs + 1]) << UInt64(32 - bits) : 0
            out[i] = UInt32(truncatingIfNeeded: bits == 0 ? lo : (lo | hi))
        }
        while let last = out.last, last == 0 { out.removeLast() }
        return out
    }

    /// Knuth's algorithm D (Hacker's Delight divmnu): quotient and remainder of magnitudes.
    static func divModMag(_ u: [UInt32], _ v: [UInt32]) -> ([UInt32], [UInt32]) {
        precondition(!v.isEmpty)
        if cmpMag(u, v) < 0 { return ([], u) }
        if v.count == 1 {
            let d = UInt64(v[0])
            var q = [UInt32](repeating: 0, count: u.count)
            var r: UInt64 = 0
            var i = u.count - 1
            while i >= 0 {
                let cur = (r << 32) | UInt64(u[i])
                q[i] = UInt32(cur / d)
                r = cur % d
                i -= 1
            }
            var qq = q
            while let last = qq.last, last == 0 { qq.removeLast() }
            return (qq, r == 0 ? [] : [UInt32(r)])
        }
        let b: UInt64 = 1 << 32
        let s = v.last!.leadingZeroBitCount
        let n = v.count, m = u.count - v.count
        var vn = [UInt32](repeating: 0, count: n)
        for i in stride(from: n - 1, to: 0, by: -1) {
            vn[i] = s == 0 ? v[i] : (v[i] << UInt32(s)) | (v[i - 1] >> UInt32(32 - s))
        }
        vn[0] = v[0] << UInt32(s)
        var un = [UInt32](repeating: 0, count: u.count + 1)
        un[u.count] = s == 0 ? 0 : u[u.count - 1] >> UInt32(32 - s)
        for i in stride(from: u.count - 1, to: 0, by: -1) {
            un[i] = s == 0 ? u[i] : (u[i] << UInt32(s)) | (u[i - 1] >> UInt32(32 - s))
        }
        un[0] = u[0] << UInt32(s)
        var q = [UInt32](repeating: 0, count: m + 1)
        var j = m
        while j >= 0 {
            let num = (UInt64(un[j + n]) << 32) | UInt64(un[j + n - 1])
            var qhat = num / UInt64(vn[n - 1])
            var rhat = num - qhat * UInt64(vn[n - 1])
            while qhat >= b || qhat * UInt64(vn[n - 2]) > (b &* rhat) + UInt64(un[j + n - 2]) {
                qhat -= 1
                rhat += UInt64(vn[n - 1])
                if rhat >= b { break }
            }
            var k: Int64 = 0
            var t: Int64 = 0
            for i in 0..<n {
                let p = qhat * UInt64(vn[i])
                t = Int64(un[i + j]) - k - Int64(p & 0xffffffff)
                un[i + j] = UInt32(truncatingIfNeeded: t)
                k = Int64(p >> 32) - (t >> 32)
            }
            t = Int64(un[j + n]) - k
            un[j + n] = UInt32(truncatingIfNeeded: t)
            q[j] = UInt32(truncatingIfNeeded: qhat)
            if t < 0 {
                q[j] = q[j] &- 1
                var c: UInt64 = 0
                for i in 0..<n {
                    let sum = UInt64(un[i + j]) + UInt64(vn[i]) + c
                    un[i + j] = UInt32(truncatingIfNeeded: sum)
                    c = sum >> 32
                }
                un[j + n] = un[j + n] &+ UInt32(truncatingIfNeeded: c)
            }
            j -= 1
        }
        var r = [UInt32](repeating: 0, count: n)
        for i in 0..<n {
            r[i] = s == 0 ? un[i] : (un[i] >> UInt32(s)) | (un[i + 1] << UInt32(32 - s))
        }
        while let last = q.last, last == 0 { q.removeLast() }
        while let last = r.last, last == 0 { r.removeLast() }
        return (q, r)
    }

    // MARK: - Arithmetic

    static func + (a: BigInt, b: BigInt) -> BigInt {
        if a.negative == b.negative { return BigInt(negative: a.negative, mag: addMag(a.mag, b.mag)) }
        let c = cmpMag(a.mag, b.mag)
        if c == 0 { return .zero }
        return c > 0 ? BigInt(negative: a.negative, mag: subMag(a.mag, b.mag))
                     : BigInt(negative: b.negative, mag: subMag(b.mag, a.mag))
    }

    static func - (a: BigInt, b: BigInt) -> BigInt { return a + b.negated }

    static func * (a: BigInt, b: BigInt) -> BigInt {
        return BigInt(negative: a.negative != b.negative, mag: mulMag(a.mag, b.mag))
    }

    /// Java division: quotient rounds toward zero, remainder has the dividend's sign.
    func quotientAndRemainder(_ d: BigInt) -> (BigInt, BigInt) {
        let (q, r) = BigInt.divModMag(mag, d.mag)
        return (BigInt(negative: negative != d.negative, mag: q), BigInt(negative: negative, mag: r))
    }

    static func < (a: BigInt, b: BigInt) -> Bool { return a.compare(b) < 0 }

    func compare(_ o: BigInt) -> Int {
        if negative != o.negative { return negative ? -1 : 1 }
        let c = BigInt.cmpMag(mag, o.mag)
        return negative ? -c : c
    }

    func pow(_ e: Int) -> BigInt {
        var result = BigInt.one, base = self, e = e
        while e > 0 {
            if e & 1 == 1 { result = result * base }
            e >>= 1
            if e > 0 { base = base * base }
        }
        return result
    }

    func gcd(_ o: BigInt) -> BigInt {
        var a = magnitude, b = o.magnitude
        while !b.isZero { (a, b) = (b, a.quotientAndRemainder(b).1) }
        return a
    }

    // MARK: - Shifts and bits (two's-complement view)

    func shiftLeft(_ n: Int) -> BigInt {
        if n < 0 { return shiftRight(-n) }
        return BigInt(negative: negative, mag: BigInt.shlMag(mag, n))
    }

    /// Arithmetic shift: rounds toward negative infinity, like Java.
    func shiftRight(_ n: Int) -> BigInt {
        if n < 0 { return shiftLeft(-n) }
        if !negative { return BigInt(negative: false, mag: BigInt.shrMag(mag, n)) }
        // -((|x| - 1) >> n) - 1
        let m1 = BigInt.subMag(mag, [1])
        let shifted = BigInt.shrMag(BigInt(negative: false, mag: m1).mag, n)
        return BigInt(negative: true, mag: BigInt.addMag(shifted, [1]))
    }

    /// Bits in the minimal two's-complement form, excluding the sign bit.
    var bitLength: Int {
        if isZero { return 0 }
        func len(_ m: [UInt32]) -> Int { return m.isEmpty ? 0 : (m.count - 1) * 32 + (32 - m.last!.leadingZeroBitCount) }
        if !negative { return len(mag) }
        return len(BigInt(negative: false, mag: BigInt.subMag(mag, [1])).mag)
    }

    var bitCount: Int {
        let m = negative ? BigInt(negative: false, mag: BigInt.subMag(mag, [1])).mag : mag
        return m.reduce(0) { $0 + $1.nonzeroBitCount }
    }

    /// Two's-complement limbs, at least `count` long.
    private func twos(_ count: Int) -> [UInt32] {
        var out = [UInt32](repeating: 0, count: count)
        for i in 0..<min(count, mag.count) { out[i] = mag[i] }
        if negative {
            var carry: UInt64 = 1
            for i in 0..<count {
                let t = UInt64(~out[i]) + carry
                out[i] = UInt32(truncatingIfNeeded: t)
                carry = t >> 32
            }
        }
        return out
    }

    private static func fromTwos(_ limbs: [UInt32]) -> BigInt {
        guard let top = limbs.last, top & 0x8000_0000 != 0 else { return BigInt(negative: false, mag: limbs) }
        var out = limbs
        var carry: UInt64 = 1
        for i in 0..<out.count {
            let t = UInt64(~out[i]) + carry
            out[i] = UInt32(truncatingIfNeeded: t)
            carry = t >> 32
        }
        return BigInt(negative: true, mag: out)
    }

    func bitwise(_ o: BigInt, _ op: (UInt32, UInt32) -> UInt32) -> BigInt {
        let n = max(mag.count, o.mag.count) + 1
        let a = twos(n), b = o.twos(n)
        return BigInt.fromTwos((0..<n).map { op(a[$0], b[$0]) })
    }

    var not: BigInt { return negated - .one }

    func testBit(_ n: Int) -> Bool {
        guard n >= 0 else { return false }
        let limbs = twos(n / 32 + 2)
        return limbs[n / 32] & (1 << UInt32(n % 32)) != 0
    }

    var lowestSetBit: Int {
        if isZero { return -1 }
        for (i, limb) in mag.enumerated() where limb != 0 { return i * 32 + limb.trailingZeroBitCount }
        return -1
    }

    // MARK: - Conversions

    /// Low 64 bits of the two's-complement value (Java's longValue()).
    var int64Value: Int64 {
        let lo = UInt64(mag.count > 0 ? mag[0] : 0) | (UInt64(mag.count > 1 ? mag[1] : 0) << 32)
        return negative ? Int64(bitPattern: lo.twosComplementNegated) : Int64(bitPattern: lo)
    }

    var doubleValue: Double {
        var d = 0.0
        for limb in mag.reversed() { d = d * 4294967296.0 + Double(limb) }
        return negative ? -d : d
    }

    func toString(radix: Int = 10) -> String {
        if isZero { return "0" }
        let r = UInt32(max(2, min(36, radix)))
        var chunkBase: UInt32 = r, chunkDigits = 1
        while UInt64(chunkBase) * UInt64(r) <= UInt64(UInt32.max) { chunkBase *= r; chunkDigits += 1 }
        var parts: [String] = []
        var cur = mag
        while !cur.isEmpty {
            let (q, rem) = BigInt.divModMag(cur, [chunkBase])
            parts.append(String(rem.first ?? 0, radix: Int(r)))
            cur = q
        }
        var s = parts.last ?? "0"
        for p in parts.dropLast().reversed() { s += String(repeating: "0", count: chunkDigits - p.count) + p }
        return (negative ? "-" : "") + s
    }

    var description: String { return toString() }

    /// Big-endian two's-complement bytes (Java's toByteArray()).
    var byteArray: [Int8] {
        let n = bitLength / 8 + 1
        let limbs = twos(n / 4 + 1)
        var out: [Int8] = []
        for i in stride(from: n - 1, through: 0, by: -1) {
            out.append(Int8(bitPattern: UInt8(truncatingIfNeeded: limbs[i / 4] >> UInt32(8 * (i % 4)))))
        }
        return out
    }

    init(twosComplementBytes bytes: [UInt8]) {
        guard !bytes.isEmpty else { self = .zero; return }
        let n = (bytes.count + 3) / 4
        var limbs = [UInt32](repeating: (bytes[0] & 0x80) != 0 ? 0xffff_ffff : 0, count: n + 1)
        for (k, byte) in bytes.reversed().enumerated() {
            let shift = UInt32(8 * (k % 4))
            limbs[k / 4] = (limbs[k / 4] & ~(0xff << shift)) | (UInt32(byte) << shift)
        }
        self = BigInt.fromTwos(limbs)
    }
}

private extension UInt64 {
    var twosComplementNegated: UInt64 { return (~self) &+ 1 }
}
