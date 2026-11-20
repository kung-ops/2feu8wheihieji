import UIKit

extension Framework {

    static func staticCall(_ vm: VM, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        let n = ref.name
        let p = ref.params
        func arg(_ i: Int) -> Value { return i < a.count ? a[i] : .zero }
        func str(_ i: Int) throws -> String? {
            guard let o = arg(i).o else { return nil }
            return try vm.stringOf(o)
        }

        switch ref.classDesc {

        case "Landroid/util/Log;":
            if n == "isLoggable" { return B(true) }
            let levels = ["v": "V", "d": "D", "i": "I", "w": "W", "e": "E", "wtf": "F"]
            let tag = try str(0) ?? ""
            var msg = ""
            if p.count > 1 { msg = try str(1) ?? "" }
            if p.count > 2, let ex = arg(2).o { msg += "\n" + vm.describeThrowable(ex) }
            vm.log("\(levels[n] ?? "I")/\(tag): \(msg)")
            return I(0)

        case "Ljava/lang/String;":
            switch n {
            case "valueOf", "copyValueOf":
                if p.first == "[C" {
                    let items = (arg(0).o?.native as? JArray)?.items ?? []
                    if p.count == 3 {
                        let off = Int(arg(1).i), cnt = Int(arg(2).i)
                        guard off >= 0, cnt >= 0, off + cnt <= items.count else { throw vm.throwable("Ljava/lang/StringIndexOutOfBoundsException;") }
                        return S(vm, vm.charsToString(Array(items[off..<(off + cnt)])))
                    }
                    return S(vm, vm.charsToString(items))
                }
                return S(vm, try vm.stringOf(arg(0), type: p.first ?? "Ljava/lang/Object;"))
            case "format":
                let shift = p.first == "Ljava/util/Locale;" ? 1 : 0
                let fmt = try str(shift) ?? ""
                return S(vm, try vm.javaFormat(fmt, varargs(arg(shift + 1))))
            case "join":
                let sep = try str(0) ?? ""
                var parts: [String] = []
                if let l = arg(1).o?.native as? ListBox { for x in l.items { parts.append(try vm.stringOf(x.o)) } }
                else { for x in varargs(arg(1)) { parts.append(try vm.stringOf(x)) } }
                return S(vm, parts.joined(separator: sep))
            default: return nil
            }

        case "Ljava/lang/Integer;", "Ljava/lang/Short;", "Ljava/lang/Byte;":
            switch n {
            case "parseInt", "parseShort", "parseByte":
                let s0 = try str(0)
                return I(try parseInt(vm, s0, radix: p.count > 1 ? Int(arg(1).i) : 10))
            case "valueOf":
                if p.first == "Ljava/lang/String;" {
                    let s0 = try str(0)
                    let v = try parseInt(vm, s0, radix: p.count > 1 ? Int(arg(1).i) : 10)
                    return O(vm.box(.int(v), type: "I"))
                }
                return O(vm.box(arg(0), type: ref.classDesc == "Ljava/lang/Integer;" ? "I" : (ref.classDesc == "Ljava/lang/Short;" ? "S" : "B")))
            case "toString":
                if p.count == 2, (2...36).contains(Int(arg(1).i)) { return S(vm, String(arg(0).i, radix: Int(arg(1).i))) }
                return S(vm, String(arg(0).i))
            case "toHexString": return S(vm, String(UInt32(bitPattern: arg(0).i), radix: 16))
            case "toBinaryString": return S(vm, String(UInt32(bitPattern: arg(0).i), radix: 2))
            case "toOctalString": return S(vm, String(UInt32(bitPattern: arg(0).i), radix: 8))
            case "max": return I(max(arg(0).i, arg(1).i))
            case "min": return I(min(arg(0).i, arg(1).i))
            case "sum": return I(arg(0).i &+ arg(1).i)
            case "compare": return I(arg(0).i < arg(1).i ? -1 : (arg(0).i > arg(1).i ? 1 : 0))
            case "signum": return I(arg(0).i.signum())
            case "hashCode": return I(arg(0).i)
            case "highestOneBit":
                let u = UInt32(bitPattern: arg(0).i)
                return I(u == 0 ? 0 : Int32(bitPattern: UInt32(1) << (31 - UInt32(u.leadingZeroBitCount))))
            case "lowestOneBit": return I(arg(0).i & (0 &- arg(0).i))
            case "numberOfLeadingZeros": return I(Int32(UInt32(bitPattern: arg(0).i).leadingZeroBitCount))
            case "numberOfTrailingZeros": return I(Int32(UInt32(bitPattern: arg(0).i).trailingZeroBitCount))
            case "bitCount": return I(Int32(UInt32(bitPattern: arg(0).i).nonzeroBitCount))
            case "reverse":
                var u = UInt32(bitPattern: arg(0).i), r: UInt32 = 0
                for _ in 0..<32 { r = (r << 1) | (u & 1); u >>= 1 }
                return I(Int32(bitPattern: r))
            case "reverseBytes": return I(Int32(bitPattern: UInt32(bitPattern: arg(0).i).byteSwapped))
            case "rotateLeft", "rotateRight":
                let u = UInt32(bitPattern: arg(0).i)
                var d = UInt32(bitPattern: arg(1).i) & 31
                if n == "rotateRight" { d = (32 - d) & 31 }
                return I(Int32(bitPattern: d == 0 ? u : (u << d) | (u >> (32 - d))))
            case "compareUnsigned":
                let x = UInt32(bitPattern: arg(0).i), y = UInt32(bitPattern: arg(1).i)
                return I(x < y ? -1 : (x > y ? 1 : 0))
            case "divideUnsigned", "remainderUnsigned":
                let x = UInt32(bitPattern: arg(0).i), y = UInt32(bitPattern: arg(1).i)
                if y == 0 { throw vm.throwable("Ljava/lang/ArithmeticException;", "/ by zero") }
                return I(Int32(bitPattern: n == "divideUnsigned" ? x / y : x % y))
            case "toUnsignedLong": return .val(.wide(Int64(UInt32(bitPattern: arg(0).i))))
            case "toUnsignedString": return S(vm, String(UInt32(bitPattern: arg(0).i)))
            case "parseUnsignedInt":
                let s0 = try str(0) ?? ""
                guard let v = UInt32(s0) else { throw numberFormat(vm, s0) }
                return I(Int32(bitPattern: v))
            case "decode":
                let s0 = try str(0) ?? ""
                var t = s0, neg = false
                if t.hasPrefix("-") { neg = true; t.removeFirst() } else if t.hasPrefix("+") { t.removeFirst() }
                var radix = 10
                if t.hasPrefix("0x") || t.hasPrefix("0X") { radix = 16; t.removeFirst(2) }
                else if t.hasPrefix("#") { radix = 16; t.removeFirst() }
                else if t.hasPrefix("0") && t.count > 1 { radix = 8; t.removeFirst() }
                guard let v = Int64(t, radix: radix) else { throw numberFormat(vm, s0) }
                return O(vm.box(.int(Int32(truncatingIfNeeded: neg ? -v : v)), type: "I"))
            default: return nil
            }

        case "Ljava/lang/Long;":
            switch n {
            case "parseLong":
                let s = try str(0)
                guard let ss = s, let v = Int64(ss) else { throw numberFormat(vm, s ?? "null") }
                return .val(.wide(v))
            case "valueOf":
                if p.first == "Ljava/lang/String;" {
                    guard let s = try str(0), let v = Int64(s) else { throw numberFormat(vm, "?") }
                    return O(vm.box(.wide(v), type: "J"))
                }
                return O(vm.box(.wide(arg(0).j), type: "J"))
            case "toString": return S(vm, String(arg(0).j))
            case "compare": return I(arg(0).j < arg(1).j ? -1 : (arg(0).j > arg(1).j ? 1 : 0))
            case "max": return .val(.wide(max(arg(0).j, arg(1).j)))
            case "min": return .val(.wide(min(arg(0).j, arg(1).j)))
            case "sum": return .val(.wide(arg(0).j &+ arg(1).j))
            case "signum": return I(Int32(arg(0).j.signum()))
            case "hashCode": return I(Int32(truncatingIfNeeded: arg(0).j ^ (arg(0).j >> 32)))
            case "highestOneBit":
                let u = UInt64(bitPattern: arg(0).j)
                return .val(.wide(u == 0 ? 0 : Int64(bitPattern: UInt64(1) << (63 - UInt64(u.leadingZeroBitCount)))))
            case "lowestOneBit": return .val(.wide(arg(0).j & (0 &- arg(0).j)))
            case "numberOfLeadingZeros": return I(Int32(UInt64(bitPattern: arg(0).j).leadingZeroBitCount))
            case "numberOfTrailingZeros": return I(Int32(UInt64(bitPattern: arg(0).j).trailingZeroBitCount))
            case "bitCount": return I(Int32(UInt64(bitPattern: arg(0).j).nonzeroBitCount))
            case "reverseBytes": return .val(.wide(Int64(bitPattern: UInt64(bitPattern: arg(0).j).byteSwapped)))
            case "rotateLeft", "rotateRight":
                let u = UInt64(bitPattern: arg(0).j)
                var d = UInt64(bitPattern: Int64(arg(1).i)) & 63
                if n == "rotateRight" { d = (64 - d) & 63 }
                return .val(.wide(Int64(bitPattern: d == 0 ? u : (u << d) | (u >> (64 - d)))))
            case "toHexString": return S(vm, String(UInt64(bitPattern: arg(0).j), radix: 16))
            case "toBinaryString": return S(vm, String(UInt64(bitPattern: arg(0).j), radix: 2))
            case "compareUnsigned":
                let x = UInt64(bitPattern: arg(0).j), y = UInt64(bitPattern: arg(1).j)
                return I(x < y ? -1 : (x > y ? 1 : 0))
            case "toUnsignedString": return S(vm, String(UInt64(bitPattern: arg(0).j)))
            default: return nil
            }

        case "Ljava/lang/Double;", "Ljava/lang/Float;":
            let isF = ref.classDesc == "Ljava/lang/Float;"
            switch n {
            case "parseDouble", "parseFloat":
                let s0 = try str(0)
                let d = try parseDouble(vm, s0)
                return .val(n == "parseFloat" ? .float(Float(d)) : .double(d))
            case "valueOf":
                if p.first == "Ljava/lang/String;" {
                    let s0 = try str(0)
                    let d = try parseDouble(vm, s0)
                    return O(isF ? vm.box(.float(Float(d)), type: "F") : vm.box(.double(d), type: "D"))
                }
                return O(vm.box(arg(0), type: isF ? "F" : "D"))
            case "toString": return S(vm, Boxed.javaDouble(isF ? Double(arg(0).f) : arg(0).d))
            case "isNaN": return B(isF ? arg(0).f.isNaN : arg(0).d.isNaN)
            case "isInfinite": return B(isF ? arg(0).f.isInfinite : arg(0).d.isInfinite)
            case "compare":
                let x = isF ? Double(arg(0).f) : arg(0).d
                let y = isF ? Double(arg(1).f) : arg(1).d   // doubles occupy one logical slot here
                return I(x < y ? -1 : (x > y ? 1 : 0))
            default: return nil
            }

        case "Ljava/lang/Boolean;":
            switch n {
            case "parseBoolean":
                let s0 = try str(0)
                return B(s0?.lowercased() == "true")
            case "valueOf":
                if p.first == "Ljava/lang/String;" {
                    let s0 = try str(0)
                    return O(vm.box(.int(s0?.lowercased() == "true" ? 1 : 0), type: "Z"))
                }
                return O(vm.box(arg(0), type: "Z"))
            case "toString": return S(vm, arg(0).i != 0 ? "true" : "false")
            default: return nil
            }

        case "Ljava/lang/Character;":
            let c = UInt16(truncatingIfNeeded: arg(0).i)
            let scalar = UnicodeScalar(c)
            let ch = scalar.map { Character($0) }
            switch n {
            case "valueOf": return O(vm.box(arg(0), type: "C"))
            case "toString": return S(vm, ch.map { String($0) } ?? "")
            case "isDigit": return B(ch?.isNumber ?? false)
            case "isLetter": return B(ch?.isLetter ?? false)
            case "isLetterOrDigit": return B((ch?.isLetter ?? false) || (ch?.isNumber ?? false))
            case "isUpperCase": return B(ch?.isUppercase ?? false)
            case "isLowerCase": return B(ch?.isLowercase ?? false)
            case "isWhitespace", "isSpaceChar": return B(ch?.isWhitespace ?? false)
            case "toUpperCase", "toLowerCase":
                guard let x = ch else { return I(arg(0).i) }
                let s = n == "toUpperCase" ? String(x).uppercased() : String(x).lowercased()
                return I(Int32(s.utf16.first ?? c))
            case "getNumericValue", "digit":
                if let x = ch, let v = Int(String(x), radix: 36) { return I(Int32(v)) }
                return I(-1)
            default: return nil
            }

        case "Ljava/lang/Math;", "Ljava/lang/StrictMath;", "Lkotlin/math/MathKt;":
            let t = p.first ?? "D"
            func dArg(_ i: Int) -> Double {
                let pt = i < p.count ? p[i] : "D"
                switch pt {
                case "D": return arg(i).d
                case "F": return Double(arg(i).f)
                case "J": return Double(arg(i).j)
                default: return Double(arg(i).i)
                }
            }
            func ret(_ d: Double) -> Ret {
                switch t {
                case "I": return I(VM.f2i(d))
                case "J": return .val(.wide(VM.f2l(d)))
                case "F": return .val(.float(Float(d)))
                default: return .val(.double(d))
                }
            }
            switch n {
            case "abs":
                if t == "I" { return I(arg(0).i == Int32.min ? Int32.min : abs(arg(0).i)) }
                if t == "J" { return .val(.wide(arg(0).j == Int64.min ? Int64.min : abs(arg(0).j))) }
                return ret(abs(dArg(0)))
            case "max":
                if t == "I" { return I(max(arg(0).i, arg(1).i)) }
                if t == "J" { return .val(.wide(max(arg(0).j, arg(1).j))) }
                return ret(max(dArg(0), dArg(1)))
            case "min":
                if t == "I" { return I(min(arg(0).i, arg(1).i)) }
                if t == "J" { return .val(.wide(min(arg(0).j, arg(1).j))) }
                return ret(min(dArg(0), dArg(1)))
            case "sqrt": return .val(.double(sqrt(dArg(0))))
            case "cbrt": return .val(.double(cbrt(dArg(0))))
            case "pow": return .val(.double(pow(dArg(0), dArg(1))))
            case "floor": return .val(.double(floor(dArg(0))))
            case "ceil": return .val(.double(ceil(dArg(0))))
            case "rint": return .val(.double(dArg(0).rounded(.toNearestOrEven)))
            case "round":
                if t == "F" { return I(VM.f2i(floor(dArg(0) + 0.5))) }
                return .val(.wide(VM.f2l(floor(dArg(0) + 0.5))))
            case "random": return .val(.double(Double.random(in: 0..<1)))
            case "sin": return .val(.double(sin(dArg(0))))
            case "cos": return .val(.double(cos(dArg(0))))
            case "tan": return .val(.double(tan(dArg(0))))
            case "asin": return .val(.double(asin(dArg(0))))
            case "acos": return .val(.double(acos(dArg(0))))
            case "atan": return .val(.double(atan(dArg(0))))
            case "atan2": return .val(.double(atan2(dArg(0), dArg(1))))
            case "hypot": return .val(.double(hypot(dArg(0), dArg(1))))
            case "log": return .val(.double(log(dArg(0))))
            case "log10": return .val(.double(log10(dArg(0))))
            case "exp": return .val(.double(exp(dArg(0))))
            case "signum": return ret(dArg(0) > 0 ? 1 : (dArg(0) < 0 ? -1 : 0))
            case "toRadians": return .val(.double(dArg(0) * .pi / 180))
            case "toDegrees": return .val(.double(dArg(0) * 180 / .pi))
            case "floorDiv":
                if t == "J" {
                    let x = arg(0).j, y = arg(1).j
                    if y == 0 { throw vm.throwable("Ljava/lang/ArithmeticException;", "/ by zero") }
                    var q = x.dividedReportingOverflow(by: y).partialValue
                    if x.remainderReportingOverflow(dividingBy: y).partialValue != 0 && ((x < 0) != (y < 0)) { q -= 1 }
                    return .val(.wide(q))
                }
                let x = arg(0).i, y = arg(1).i
                if y == 0 { throw vm.throwable("Ljava/lang/ArithmeticException;", "/ by zero") }
                var q = x.dividedReportingOverflow(by: y).partialValue
                if x.remainderReportingOverflow(dividingBy: y).partialValue != 0 && ((x < 0) != (y < 0)) { q -= 1 }
                return I(q)
            case "floorMod":
                let x = arg(0).i, y = arg(1).i
                if y == 0 { throw vm.throwable("Ljava/lang/ArithmeticException;", "/ by zero") }
                let m = x.remainderReportingOverflow(dividingBy: y).partialValue
                return I((m != 0 && ((m < 0) != (y < 0))) ? m + y : m)
            default: return nil
            }

        case "Ljava/lang/System;":
            switch n {
            case "currentTimeMillis": return .val(.wide(Int64(Date().timeIntervalSince1970 * 1000)))
            case "nanoTime": return .val(.wide(Int64(DispatchTime.now().uptimeNanoseconds)))
            case "arraycopy":
                guard let src = arg(0).o?.native as? JArray, let dst = arg(2).o?.native as? JArray else {
                    throw vm.npe("arraycopy")
                }
                let sp = Int(arg(1).i), dp = Int(arg(3).i), len = Int(arg(4).i)
                guard sp >= 0, dp >= 0, len >= 0, sp + len <= src.count, dp + len <= dst.count else {
                    throw vm.throwable("Ljava/lang/ArrayIndexOutOfBoundsException;",
                                       "src.length=\(src.count) srcPos=\(sp) dst.length=\(dst.count) dstPos=\(dp) length=\(len)")
                }
                dst.copy(from: src, sp, to: dp, count: len)
                return .void
            case "exit":
                let h = vm.host
                DispatchQueue.main.async { h?.finishAll() }
                throw VMError.stopped
            case "identityHashCode": return I(Int32(truncatingIfNeeded: arg(0).o.map { ObjectIdentifier($0).hashValue } ?? 0))
            case "lineSeparator": return S(vm, "\n")
            case "getProperty", "getenv": return O(nil)
            case "gc", "loadLibrary", "load":
                if n != "gc" {
                    let lib = try str(0) ?? ""
                    vm.warnOnce("native library '\(lib)' cannot be loaded on iOS")
                }
                return .void
            default: return nil
            }

        case "Ljava/lang/Thread;":
            switch n {
            case "sleep": return .void
            case "currentThread": return O(vm.mainThread)
            case "interrupted", "holdsLock": return B(false)
            default: return nil
            }

        case "Landroid/os/SystemClock;":
            let ms = Int64(ProcessInfo.processInfo.systemUptime * 1000)
            switch n {
            case "uptimeMillis", "elapsedRealtime": return .val(.wide(ms))
            case "sleep": return .void
            default: return nil
            }

        case "Landroid/widget/Toast;":
            if n == "makeText" {
                let t = try text(vm, arg(1), p.count > 1 ? p[1] : "I")
                return O(vm.newObject("Landroid/widget/Toast;", native: ToastBox(t)))
            }
            return nil

        case "Landroid/text/TextUtils;":
            switch n {
            case "isEmpty":
                guard let o = arg(0).o else { return B(true) }
                return B(try vm.stringOf(o).isEmpty)
            case "equals":
                let x = try vm.stringOf(arg(0).o)
                let y = try vm.stringOf(arg(1).o)
                return B(x == y)
            case "join":
                let sep = try str(0) ?? ""
                var parts: [String] = []
                if let l = arg(1).o?.native as? ListBox { for x in l.items { parts.append(try vm.stringOf(x.o)) } }
                else { for x in varargs(arg(1)) { parts.append(try vm.stringOf(x)) } }
                return S(vm, parts.joined(separator: sep))
            default: return nil
            }

        case "Landroid/graphics/Color;":
            switch n {
            case "rgb": return I(Int32(bitPattern: 0xff000000) | ((arg(0).i & 0xff) << 16) | ((arg(1).i & 0xff) << 8) | (arg(2).i & 0xff))
            case "argb": return I(((arg(0).i & 0xff) << 24) | ((arg(1).i & 0xff) << 16) | ((arg(2).i & 0xff) << 8) | (arg(3).i & 0xff))
            case "parseColor":
                var s = try str(0) ?? ""
                let named: [String: UInt32] = ["red": 0xffff0000, "blue": 0xff0000ff, "green": 0xff00ff00, "black": 0xff000000,
                                               "white": 0xffffffff, "gray": 0xff888888, "grey": 0xff888888, "yellow": 0xffffff00,
                                               "cyan": 0xff00ffff, "magenta": 0xffff00ff]
                if let c = named[s.lowercased()] { return I(Int32(bitPattern: c)) }
                guard s.hasPrefix("#") else { throw vm.throwable("Ljava/lang/IllegalArgumentException;", "Unknown color") }
                s.removeFirst()
                guard var v = UInt32(s, radix: 16) else { throw vm.throwable("Ljava/lang/IllegalArgumentException;", "Unknown color") }
                if s.count == 6 { v |= 0xff000000 }
                return I(Int32(bitPattern: v))
            case "red": return I((arg(0).i >> 16) & 0xff)
            case "green": return I((arg(0).i >> 8) & 0xff)
            case "blue": return I(arg(0).i & 0xff)
            case "alpha": return I((arg(0).i >> 24) & 0xff)
            default: return nil
            }

        case "Ljava/util/Objects;":
            switch n {
            case "equals": return B(try vm.javaEquals(arg(0).o, arg(1).o))
            case "hashCode": return I(try vm.javaHash(arg(0).o))
            case "hash":
                var h: Int32 = 1
                for x in varargs(arg(0)) {
                    let xh = try vm.javaHash(x)
                    h = h &* 31 &+ xh
                }
                return I(h)
            case "toString":
                if arg(0).o == nil && p.count > 1 { return O(arg(1).o) }
                return S(vm, try vm.stringOf(arg(0).o))
            case "isNull": return B(arg(0).o == nil)
            case "nonNull": return B(arg(0).o != nil)
            case "requireNonNull":
                if arg(0).o == nil {
                    var msg: String? = nil
                    if p.count > 1 { msg = try str(1) }
                    throw vm.throwable("Ljava/lang/NullPointerException;", msg)
                }
                return O(arg(0).o)
            case "requireNonNullElse": return O(arg(0).o ?? arg(1).o)
            default: return nil
            }

        case "Lkotlin/jvm/internal/Intrinsics;":
            switch n {
            case "areEqual":
                if p.first == "Ljava/lang/Object;" && p.count == 2 && p[1] == "Ljava/lang/Object;" {
                    return B(try vm.javaEquals(arg(0).o, arg(1).o))
                }
                return B(arg(0).j == arg(1).j)
            case "stringPlus":
                let left = try str(0) ?? "null"
                let right = try vm.stringOf(arg(1).o)
                return S(vm, left + right)
            case "compare":
                if p.first == "J" { return I(arg(0).j < arg(1).j ? -1 : (arg(0).j > arg(1).j ? 1 : 0)) }
                return I(arg(0).i < arg(1).i ? -1 : (arg(0).i > arg(1).i ? 1 : 0))
            case "throwUninitializedPropertyAccessException", "throwUninitializedProperty":
                let prop = try str(0) ?? ""
                throw vm.throwable("Lkotlin/UninitializedPropertyAccessException;", "lateinit property \(prop) has not been initialized")
            case "throwNpe", "throwJavaNpe":
                throw vm.throwable("Ljava/lang/NullPointerException;")
            default:
                if n.hasPrefix("check") { return .void }
                return nil
            }

        case "Ljava/util/Arrays;":
            switch n {
            case "asList":
                return O(vm.newObject("Ljava/util/ArrayList;", native: ListBox(items: (arg(0).o?.native as? JArray)?.items ?? [])))
            case "toString":
                guard let arr = arg(0).o?.native as? JArray else { return S(vm, "null") }
                let et = arr.elementType
                var parts: [String] = []
                for x in arr.items { parts.append(try vm.stringOf(x, type: et)) }
                return S(vm, "[" + parts.joined(separator: ", ") + "]")
            case "sort":
                guard let arr = arg(0).o?.native as? JArray else { throw vm.npe("sort") }
                let et = arr.elementType
                var from = 0, to = arr.count
                var cmp: JObject? = nil
                if p.count >= 3 && p[1] == "I" && p[2] == "I" {
                    from = max(0, Int(arg(1).i)); to = min(arr.count, Int(arg(2).i))
                    if p.count == 4 { cmp = arg(3).o }
                } else if p.count == 2 {
                    cmp = arg(1).o
                }
                guard from < to else { return .void }
                var items = arr.items
                var part = Array(items[from..<to])
                switch et {
                case "I", "S", "B", "C": part.sort { $0.i < $1.i }
                case "J": part.sort { $0.j < $1.j }
                case "D": part.sort { $0.d < $1.d }
                case "F": part.sort { $0.f < $1.f }
                default: try sortValues(vm, &part, comparator: cmp)
                }
                items.replaceSubrange(from..<to, with: part)
                arr.items = items
                return .void
            case "fill":
                guard let arr = arg(0).o?.native as? JArray else { throw vm.npe("fill") }
                let v = p.count == 2 ? arg(1) : arg(3)
                if p.count == 2 { arr.fill(v, from: 0, to: arr.count) }
                else { arr.fill(v, from: max(0, Int(arg(1).i)), to: min(arr.count, Int(arg(2).i))) }
                return .void
            case "copyOf":
                guard let arr = arg(0).o?.native as? JArray else { throw vm.npe("copyOf") }
                let len = Int(arg(1).i)
                if len < 0 { throw vm.throwable("Ljava/lang/NegativeArraySizeException;", "\(len)") }
                try vm.checkAllocation(type: arr.type, count: len)
                let out = JArray(type: arr.type, count: len)
                out.copy(from: arr, 0, to: 0, count: min(len, arr.count))
                return O(vm.newObject(arr.type, native: out))
            case "copyOfRange":
                guard let arr = arg(0).o?.native as? JArray else { throw vm.npe("copyOfRange") }
                let from = Int(arg(1).i), to = Int(arg(2).i)
                guard from >= 0, from <= arr.count else {
                    throw vm.throwable("Ljava/lang/ArrayIndexOutOfBoundsException;", "\(from)")
                }
                guard from <= to else { throw vm.throwable("Ljava/lang/IllegalArgumentException;", "\(from) > \(to)") }
                try vm.checkAllocation(type: arr.type, count: to - from)
                let out = JArray(type: arr.type, count: to - from)
                out.copy(from: arr, from, to: 0, count: min(to, arr.count) - from)
                return O(vm.newObject(arr.type, native: out))
            case "equals":
                guard let x = arg(0).o?.native as? JArray, let y = arg(1).o?.native as? JArray else { return B(arg(0).o == nil && arg(1).o == nil) }
                if x.count != y.count { return B(false) }
                let xs = x.items, ys = y.items
                for k in 0..<xs.count where !vm.sameValue(xs[k], ys[k]) {
                    if let a = xs[k].o, let b = ys[k].o {
                        let eq = try vm.javaEquals(a, b)
                        if eq { continue }
                    }
                    if xs[k].j == ys[k].j, xs[k].o == nil { continue }
                    return B(false)
                }
                return B(true)
            default: return nil
            }

        case "Ljava/util/Collections;":
            switch n {
            case "sort":
                guard let l = arg(0).o?.native as? ListBox else { throw vm.npe("sort") }
                try sortValues(vm, &l.items, comparator: p.count > 1 ? arg(1).o : nil)
                return .void
            case "reverse":
                (arg(0).o?.native as? ListBox)?.items.reverse()
                return .void
            case "shuffle":
                (arg(0).o?.native as? ListBox)?.items.shuffle()
                return .void
            case "emptyList", "emptySet":
                return O(vm.newObject("Ljava/util/ArrayList;", native: ListBox(isSet: n == "emptySet")))
            case "emptyMap":
                return O(vm.newObject("Ljava/util/HashMap;", native: MapBox()))
            case "singletonList", "singleton":
                return O(vm.newObject("Ljava/util/ArrayList;", native: ListBox(items: [arg(0)])))
            case "unmodifiableList", "unmodifiableSet", "unmodifiableCollection", "unmodifiableMap", "synchronizedList", "synchronizedMap":
                return O(arg(0).o)
            case "max", "min":
                guard let l = arg(0).o?.native as? ListBox, !l.items.isEmpty else {
                    throw vm.throwable("Ljava/util/NoSuchElementException;")
                }
                var items = l.items
                try sortValues(vm, &items, comparator: p.count > 1 ? arg(1).o : nil)
                return .val(n == "max" ? items[items.count - 1] : items[0])
            default: return nil
            }

        case "Ljava/util/UUID;":
            if n == "randomUUID" { return O(vm.newObject("Ljava/util/UUID;", native: UUID().uuidString.lowercased())) }
            return nil

        case "Ljava/util/concurrent/ThreadLocalRandom;":
            if n == "current" { return O(vm.newObject("Ljava/util/Random;", native: RandomBox())) }
            return nil

        case "Landroid/os/Looper;":
            switch n {
            case "getMainLooper", "myLooper": return O(vm.mainLooper)
            case "prepare", "prepareMainLooper", "loop": return .void
            default: return nil
            }

        case "Ljava/util/concurrent/Executors;":
            if n.hasPrefix("new") || n == "unconfigurableExecutorService" {
                return O(vm.newObject("Ljava/util/concurrent/ThreadPoolExecutor;", native: ExecutorBox()))
            }
            if n == "callable" { return O(arg(0).o) }
            return nil

        case "Ljava/util/concurrent/atomic/AtomicReferenceFieldUpdater;",
             "Ljava/util/concurrent/atomic/AtomicIntegerFieldUpdater;",
             "Ljava/util/concurrent/atomic/AtomicLongFieldUpdater;":
            if n == "newUpdater" {
                let field = try str(p.count - 1) ?? ""
                return O(vm.newObject(ref.classDesc, native: FieldUpdaterBox(field: field)))
            }
            return nil

        case "Ljava/lang/ThreadLocal;":
            if n == "withInitial" {
                let rb = RefBox(.null, threadLocal: true)
                rb.supplier = arg(0).o
                return O(vm.newObject("Ljava/lang/ThreadLocal;", native: rb))
            }
            return nil

        case "Ljava/lang/Enum;":
            if n == "valueOf", let cr = arg(0).o?.native as? ClassRef {
                let name = try str(1) ?? ""
                let c = vm.classFor(cr.name)
                try vm.ensureInit(c)
                for v in c.statics.values {
                    if let o = v.o, (o.fields["__name"]?.o?.native as? String) == name { return O(o) }
                }
                throw vm.throwable("Ljava/lang/IllegalArgumentException;", "No enum constant \(VMClass.javaName(cr.name)).\(name)")
            }
            return nil

        case "Landroidx/core/content/ContextCompat;", "Landroidx/core/content/res/ResourcesCompat;":
            switch n {
            case "getColor": return I(resColor(vm, arg(1)))
            case "getDrawable": return O(drawable(vm, resId(arg(1))))
            case "checkSelfPermission": return I(0)
            default: return nil
            }

        case "Landroid/view/LayoutInflater;":
            if n == "from" { return O(vm.newObject("Landroid/view/LayoutInflater;", native: InflaterBox())) }
            return nil

        case "Landroid/view/View;":
            if n == "inflate" {
                let v = vm.inflateLayout(resId(arg(1)), host: vm.activityHost(arg(0).o))
                if let parent = arg(2).o?.native as? ViewBox, let child = v?.native as? ViewBox {
                    onMain { parent.addChild(child) }
                    return O(arg(2).o)
                }
                return O(v)
            }
            if n == "generateViewId" { return I(Int32.random(in: 0x100000..<0x7000000)) }
            return nil

        case "Landroid/widget/Toast$Companion;":
            return nil

        default:
            if let r = try graphicsStatic(vm, ref, a) { return r }
            if let r = deviceStatic(vm, ref, a) { return r }
            return try moreStatic(vm, ref, a)
        }
    }
}
