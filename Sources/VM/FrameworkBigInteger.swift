import Foundation

/// java.math.BigInteger, backed by BigInt (any size, exact).
final class BigIntegerBox {
    let value: BigInt
    init(_ v: BigInt) { value = v }
}

extension Framework {

    static func bigInt(_ v: Value) -> BigInt? {
        guard let o = v.o else { return nil }
        switch o.native {
        case let b as BigIntegerBox: return b.value
        case let d as DecimalBox: return BigInt(plainString(truncate(d.value)))
        case let b as Boxed: return BigInt(b.kind == .long ? b.value.j : Int64(b.value.i))
        default: return nil
        }
    }

    static func newBigInteger(_ vm: VM, _ v: BigInt) -> JObject {
        return vm.newObject("Ljava/math/BigInteger;", native: BigIntegerBox(v))
    }

    static func bigIntegerConstruct(_ vm: VM, _ t: JObject, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        guard ref.classDesc == "Ljava/math/BigInteger;" else { return nil }
        let p = ref.params
        var v = BigInt.zero
        switch p.first {
        case "Ljava/lang/String;":
            let s = try vm.stringOf(a[0].o)
            let radix = p.count > 1 ? Int(a[1].i) : 10
            guard let parsed = BigInt(s, radix: radix) else { throw numberFormat(vm, s) }
            v = parsed
        case "[B":
            v = BigInt(twosComplementBytes: (a[0].o?.native as? JArray)?.byteValues ?? [])
        case "I":
            if p.count >= 2, p[1] == "[B" {
                // (signum, magnitude bytes)
                let bytes = (a[1].o?.native as? JArray)?.byteValues ?? []
                let mag = BigInt(twosComplementBytes: [0] + bytes)
                v = a[0].i < 0 ? mag.negated : mag
            } else if p.count >= 2 {
                // (numBits, Random): a random number below 2^numBits
                let bits = max(0, Int(a[0].i))
                var r = BigInt.zero
                for _ in 0..<((bits + 31) / 32) { r = r.shiftLeft(32) + BigInt(Int64(UInt32.random(in: 0...UInt32.max))) }
                v = bits == 0 ? .zero : BigInt(negative: false, mag: r.magnitude.shiftRight(((bits + 31) / 32) * 32 - bits).mag)
            }
        default:
            break
        }
        t.native = BigIntegerBox(v)
        return .void
    }

    static func bigIntegerStatic(_ vm: VM, _ ref: DexMethodRef, _ a: [Value]) -> Ret? {
        guard ref.classDesc == "Ljava/math/BigInteger;" else { return nil }
        switch ref.name {
        case "valueOf": return O(newBigInteger(vm, BigInt(a[0].j)))
        case "probablePrime": return O(newBigInteger(vm, BigInt(1_000_003)))
        default: return nil
        }
    }

    static func bigIntegerMethod(_ vm: VM, _ t: JObject, _ b: BigIntegerBox, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        let x = b.value
        func other() throws -> BigInt {
            guard let o = bigInt(a[0]) else { throw vm.npe("BigInteger." + ref.name) }
            return o
        }
        func big(_ v: BigInt) -> Ret { return O(newBigInteger(vm, v)) }
        func divisor() throws -> BigInt {
            let d = try other()
            if d.isZero { throw vm.throwable("Ljava/lang/ArithmeticException;", "BigInteger divide by zero") }
            return d
        }
        switch ref.name {
        case "add": return big(x + (try other()))
        case "subtract": return big(x - (try other()))
        case "multiply": return big(x * (try other()))
        case "divide": return big(x.quotientAndRemainder(try divisor()).0)
        case "remainder": return big(x.quotientAndRemainder(try divisor()).1)
        case "mod":
            let m = try divisor()
            if m.signum <= 0 { throw vm.throwable("Ljava/lang/ArithmeticException;", "BigInteger: modulus not positive") }
            var r = x.quotientAndRemainder(m).1
            if r.signum < 0 { r = r + m }
            return big(r)
        case "divideAndRemainder":
            let (q, r) = x.quotientAndRemainder(try divisor())
            let items: [Value] = [.obj(newBigInteger(vm, q)), .obj(newBigInteger(vm, r))]
            return O(vm.newObject("[Ljava/math/BigInteger;", native: JArray(type: "[Ljava/math/BigInteger;", items: items)))
        case "negate": return big(x.negated)
        case "abs": return big(x.magnitude)
        case "signum": return I(Int32(x.signum))
        case "pow":
            let e = Int(a[0].i)
            if e < 0 { throw vm.throwable("Ljava/lang/ArithmeticException;", "Negative exponent") }
            if x.bitLength * e > 4_000_000 { throw vm.throwable("Ljava/lang/ArithmeticException;", "BigInteger would overflow supported range") }
            return big(x.pow(e))
        case "gcd": return big(x.gcd(try other()))
        case "shiftLeft": return big(x.shiftLeft(Int(a[0].i)))
        case "shiftRight": return big(x.shiftRight(Int(a[0].i)))
        case "bitLength": return I(Int32(x.bitLength))
        case "bitCount": return I(Int32(x.bitCount))
        case "getLowestSetBit": return I(Int32(x.lowestSetBit))
        case "testBit":
            if a[0].i < 0 { throw vm.throwable("Ljava/lang/ArithmeticException;", "Negative bit address") }
            return B(x.testBit(Int(a[0].i)))
        case "setBit", "clearBit", "flipBit":
            let bit = BigInt.one.shiftLeft(Int(max(0, a[0].i)))
            switch ref.name {
            case "setBit": return big(x.bitwise(bit, |))
            case "clearBit": return big(x.bitwise(bit.not, &))
            default: return big(x.bitwise(bit, ^))
            }
        case "and": return big(x.bitwise(try other(), &))
        case "or": return big(x.bitwise(try other(), |))
        case "xor": return big(x.bitwise(try other(), ^))
        case "andNot": return big(x.bitwise((try other()).not, &))
        case "not": return big(x.not)
        case "compareTo": return I(Int32(x.compare(try other())))
        case "equals":
            guard let o = a[0].o?.native as? BigIntegerBox else { return B(false) }
            return B(o.value == x)
        case "hashCode":
            var h: Int32 = 0
            for limb in x.toString(radix: 16).utf8 { h = h &* 31 &+ Int32(limb) }
            return I(h)
        case "min": return O((try other()) < x ? a[0].o : t)
        case "max": return O((try other()) > x ? a[0].o : t)
        case "intValue", "intValueExact", "shortValue", "byteValue":
            return I(Int32(truncatingIfNeeded: x.int64Value))
        case "longValue", "longValueExact": return .val(.wide(x.int64Value))
        case "doubleValue": return .val(.double(x.doubleValue))
        case "floatValue": return .val(.float(Float(x.doubleValue)))
        case "toString":
            return S(vm, x.toString(radix: ref.params.first == "I" ? Int(a[0].i) : 10))
        case "toByteArray":
            return O(vm.newObject("[B", native: JArray(type: "[B", items: x.byteArray.map { .int(Int32($0)) })))
        case "modPow":
            guard let e = bigInt(a[0]), let m = bigInt(a[1]), m.signum > 0 else {
                throw vm.throwable("Ljava/lang/ArithmeticException;", "BigInteger: modulus not positive")
            }
            var result = BigInt.one, base = x.quotientAndRemainder(m).1, exp = e
            if base.signum < 0 { base = base + m }
            while exp.signum > 0 {
                if exp.testBit(0) { result = (result * base).quotientAndRemainder(m).1 }
                base = (base * base).quotientAndRemainder(m).1
                exp = exp.shiftRight(1)
            }
            return big(result)
        case "isProbablePrime":
            let n = x.magnitude
            if n.compare(BigInt(2)) < 0 { return B(false) }
            for p in [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37] {
                let pb = BigInt(Int64(p))
                if n == pb { return B(true) }
                if n.quotientAndRemainder(pb).1.isZero { return B(false) }
            }
            return B(true)
        case "sqrt":
            if x.signum < 0 { throw vm.throwable("Ljava/lang/ArithmeticException;", "Negative BigInteger") }
            var lo = BigInt.zero, hi = BigInt.one.shiftLeft(x.bitLength / 2 + 1)
            while lo < hi {
                let mid = (lo + hi + .one).shiftRight(1)
                if (mid * mid).compare(x) <= 0 { lo = mid } else { hi = mid - .one }
            }
            return big(lo)
        default:
            return nil
        }
    }
}
