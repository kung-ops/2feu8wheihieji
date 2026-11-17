import UIKit

/// BigDecimal / BigInteger, NumberFormat / DecimalFormat, Locale,
/// Settings, and the editable text of EditText (Editable, selection).
extension Framework {

    // MARK: - Decimal helpers

    static func decimal(_ v: Value) -> Decimal {
        guard let o = v.o else { return 0 }
        switch o.native {
        case let d as DecimalBox: return d.value
        case let b as Boxed:
            if b.kind == .long { return Decimal(b.value.j) }
            if b.kind == .double || b.kind == .float { return Decimal(string: Boxed.javaDouble(b.asDouble)) ?? 0 }
            return Decimal(Int(b.value.i))
        case let s as String: return Decimal(string: s) ?? 0
        default: return 0
        }
    }

    static func newDecimal(_ vm: VM, _ d: Decimal, integer: Bool = false, scale: Int? = nil) -> JObject {
        let box = DecimalBox(integer ? truncate(d) : d, integer: integer)
        let o = vm.newObject(integer ? "Ljava/math/BigInteger;" : "Ljava/math/BigDecimal;", native: box)
        if let s = scale { o.fields["__scale"] = .int(Int32(s)) }
        return o
    }

    static func round(_ d: Decimal, _ scale: Int, _ mode: NSDecimalNumber.RoundingMode) -> Decimal {
        var x = d
        var r = Decimal()
        NSDecimalRound(&r, &x, scale, mode)
        return r
    }

    static func truncate(_ d: Decimal) -> Decimal {
        return round(d, 0, d < 0 ? .up : .down)
    }

    /// Java RoundingMode (enum placeholder with __name, or legacy int) → Foundation mode.
    static func roundingMode(_ v: Value?, for d: Decimal) -> NSDecimalNumber.RoundingMode {
        var name = "HALF_UP"
        if let o = v?.o, let n = o.fields["__name"]?.o?.string { name = n }
        else if let v = v, case .int(let i) = v {
            name = ["UP", "DOWN", "CEILING", "FLOOR", "HALF_UP", "HALF_DOWN", "HALF_EVEN", "UNNECESSARY"][Int(max(0, min(7, i)))]
        }
        switch name {
        case "HALF_EVEN": return .bankers
        case "DOWN": return d < 0 ? .up : .down
        case "UP": return d < 0 ? .down : .up
        case "FLOOR": return .down
        case "CEILING": return .up
        default: return .plain
        }
    }

    static func plainString(_ d: Decimal, scale: Int? = nil) -> String {
        var s = NSDecimalNumber(decimal: d).stringValue
        if s == "NaN" { s = "0" }
        if let sc = scale, sc > 0 {
            let parts = s.split(separator: ".", omittingEmptySubsequences: false)
            let frac = parts.count > 1 ? String(parts[1]) : ""
            if frac.count < sc { s = String(parts[0]) + "." + frac + String(repeating: "0", count: sc - frac.count) }
        }
        return s
    }

    static func decimalScale(_ o: JObject, _ d: Decimal) -> Int {
        if let s = o.fields["__scale"] { return Int(s.i) }
        return max(0, -Int(d.exponent))
    }

    // MARK: - Static calls

    static func moreStatic(_ vm: VM, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        if let r = animationStatic(vm, ref, a) { return r }
        let n = ref.name
        let p = ref.params
        switch ref.classDesc {
        case "Ljava/math/BigDecimal;", "Ljava/math/BigInteger;":
            let isInt = ref.classDesc == "Ljava/math/BigInteger;"
            guard n == "valueOf" else { return nil }
            switch p.first {
            case "D":
                return O(newDecimal(vm, Decimal(string: Boxed.javaDouble(a[0].d)) ?? 0))
            case "J":
                var d = Decimal(a[0].j)
                if p.count == 2 { d = d * pow(Decimal(10), -Int(a[1].i)) }
                return O(newDecimal(vm, d, integer: isInt, scale: p.count == 2 ? Int(a[1].i) : nil))
            default:
                return nil
            }

        case "Ljava/text/NumberFormat;", "Ljava/text/DecimalFormat;":
            if n.hasPrefix("get") && n.hasSuffix("Instance") {
                let f = NumberFormatBox()
                if n == "getIntegerInstance" { f.maxFraction = 0 }
                return O(vm.newObject("Ljava/text/DecimalFormat;", native: f))
            }
            return nil

        case "Ljava/text/DecimalFormatSymbols;":
            if n == "getInstance" { return O(vm.newObject("Ljava/text/DecimalFormatSymbols;")) }
            return nil

        case "Ljava/util/Locale;":
            switch n {
            case "getDefault", "forLanguageTag": return O(locale(vm, "en", "US"))
            case "setDefault": return .void
            default: return nil
            }

        case "Landroid/provider/Settings$Secure;", "Landroid/provider/Settings$System;", "Landroid/provider/Settings$Global;":
            switch n {
            case "getInt", "getLong", "getFloat":
                if a.count > 2 { return .val(a[2]) }
                return ref.ret == "J" ? .val(.wide(0)) : (ref.ret == "F" ? .val(.float(0)) : I(0))
            case "getString": return O(nil)
            case "putInt", "putString", "putLong", "putFloat": return B(true)
            case "getUriFor": return O(vm.newObject("Landroid/net/Uri;"))
            default: return nil
            }

        default:
            return nil
        }
    }

    static func locale(_ vm: VM, _ lang: String, _ country: String) -> JObject {
        let o = vm.newObject("Ljava/util/Locale;")
        o.fields["__lang"] = .obj(vm.str(lang))
        o.fields["__country"] = .obj(vm.str(country))
        return o
    }

    // MARK: - Constructors

    static func moreConstruct(_ vm: VM, _ t: JObject, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        if let r = animationConstruct(t, ref) { return r }
        let p = ref.params
        switch ref.classDesc {
        case "Ljava/math/BigDecimal;", "Ljava/math/BigInteger;":
            let isInt = ref.classDesc == "Ljava/math/BigInteger;"
            var d: Decimal = 0
            switch p.first {
            case "Ljava/lang/String;":
                let s = try vm.stringOf(a[0].o).trimmingCharacters(in: .whitespaces)
                guard let v = Decimal(string: s), !s.isEmpty else { throw numberFormat(vm, s) }
                d = v
                if !isInt, let dot = s.firstIndex(of: ".") {
                    t.fields["__scale"] = .int(Int32(s.distance(from: s.index(after: dot), to: s.endIndex)))
                }
            case "D": d = Decimal(a[0].d)
            case "J": d = Decimal(a[0].j)
            case "I": d = Decimal(Int(a[0].i))
            case "Ljava/math/BigInteger;": d = decimal(a[0])
            default: d = 0
            }
            t.native = DecimalBox(isInt ? truncate(d) : d, integer: isInt)
            return .void
        case "Ljava/math/MathContext;":
            t.fields["__precision"] = a.first ?? .zero
            return .void
        case "Ljava/text/DecimalFormat;":
            let f = NumberFormatBox()
            if p.first == "Ljava/lang/String;" { applyPattern(f, try vm.stringOf(a[0].o)) }
            t.native = f
            return .void
        case "Landroid/text/SpannableStringBuilder;", "Landroid/text/SpannableString;", "Landroid/text/SpannedString;":
            var s = ""
            if let f = p.first, f != "I", let o = a[0].o { s = try vm.stringOf(o) }
            t.native = StringBuilderBox(s)
            return .void
        case "Ljava/util/Locale;":
            t.fields["__lang"] = a.count > 0 ? a[0] : .obj(vm.str("en"))
            t.fields["__country"] = a.count > 1 ? a[1] : .obj(vm.str(""))
            return .void
        default:
            return nil
        }
    }

    static func applyPattern(_ f: NumberFormatBox, _ pattern: String) {
        let main = pattern.split(separator: ";").first.map(String.init) ?? pattern
        f.grouping = main.contains(",")
        if let dot = main.firstIndex(of: ".") {
            let frac = main[main.index(after: dot)...].filter { $0 == "0" || $0 == "#" }
            f.maxFraction = frac.count
            f.minFraction = frac.filter { $0 == "0" }.count
        } else {
            f.maxFraction = 0
            f.minFraction = 0
        }
        let intPart = main.split(separator: ".").first.map(String.init) ?? main
        f.minInteger = max(1, intPart.filter { $0 == "0" }.count)
    }

    /// Formats like java.text.DecimalFormat: HALF_EVEN rounding, ',' grouping, '.' decimals.
    static func format(_ f: NumberFormatBox, _ d: Decimal) -> String {
        let r = round(d, f.maxFraction, .bankers)
        var s = plainString(abs(r))
        var intPart = s
        var frac = ""
        if let dot = s.firstIndex(of: ".") {
            intPart = String(s[..<dot])
            frac = String(s[s.index(after: dot)...])
        }
        while frac.count < f.minFraction { frac += "0" }
        while frac.count > f.minFraction, frac.hasSuffix("0") { frac.removeLast() }
        while intPart.count < f.minInteger { intPart = "0" + intPart }
        if f.grouping && intPart.count > 3 {
            var out = ""
            for (i, ch) in intPart.reversed().enumerated() {
                if i > 0 && i % 3 == 0 { out.append(",") }
                out.append(ch)
            }
            intPart = String(out.reversed())
        }
        s = intPart + (frac.isEmpty ? "" : "." + frac)
        return (r < 0 ? "-" : "") + s
    }

    // MARK: - Instance methods

    static func decimalMethod(_ vm: VM, _ t: JObject, _ db: DecimalBox, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        let d = db.value
        let isInt = db.isInteger
        let p = ref.params
        func other() -> Decimal { return decimal(a[0]) }
        func result(_ x: Decimal, scale: Int? = nil) -> Ret { return O(newDecimal(vm, x, integer: isInt, scale: scale)) }
        switch ref.name {
        case "add": return result(d + other())
        case "subtract": return result(d - other())
        case "multiply": return result(d * other())
        case "divide", "divideToIntegralValue":
            let o = other()
            if o == 0 { throw vm.throwable("Ljava/lang/ArithmeticException;", isInt ? "BigInteger divide by zero" : "Division by zero") }
            var q = d / o
            if isInt || ref.name == "divideToIntegralValue" { q = truncate(q) }
            if p.count >= 2, p[1] == "I" {
                let mode = p.count > 2 ? a[2] : nil
                return result(round(q, Int(a[1].i), roundingMode(mode, for: q)), scale: Int(a[1].i))
            }
            if p.count == 2, p[1] == "Ljava/math/RoundingMode;" {
                let sc = decimalScale(t, d)
                return result(round(q, sc, roundingMode(a[1], for: q)), scale: sc)
            }
            return result(q)
        case "remainder", "mod":
            let o = other()
            if o == 0 { throw vm.throwable("Ljava/lang/ArithmeticException;", "Division by zero") }
            var r = d - truncate(d / o) * o
            if ref.name == "mod", r < 0 { r += abs(o) }
            return result(r)
        case "negate": return result(-d)
        case "abs": return result(abs(d))
        case "pow":
            var r: Decimal = 1
            let e = Int(a[0].i)
            if e >= 0 && e < 10_000 { r = pow(d, e) }
            return result(r)
        case "signum": return I(d > 0 ? 1 : (d < 0 ? -1 : 0))
        case "compareTo":
            let o = other()
            return I(d < o ? -1 : (d > o ? 1 : 0))
        case "equals": return B(decimal(a[0]) == d && (a[0].o?.native as? DecimalBox)?.isInteger == isInt)
        case "hashCode": return I(Int32(truncatingIfNeeded: NSDecimalNumber(decimal: d).hashValue))
        case "max": return O(other() > d ? a[0].o : t)
        case "min": return O(other() < d ? a[0].o : t)
        case "setScale":
            let sc = Int(a[0].i)
            let mode = p.count > 1 ? a[1] : nil
            return result(round(d, sc, roundingMode(mode, for: d)), scale: sc)
        case "round":
            if let prec = a.first?.o?.fields["__precision"]?.i, prec > 0 {
                let digits = d == 0 ? 1 : Int(log10(Double(truncating: NSDecimalNumber(decimal: abs(d))))) + 1
                return result(round(d, max(0, Int(prec) - digits), .plain))
            }
            return O(t)
        case "scale": return I(Int32(decimalScale(t, d)))
        case "precision":
            return I(Int32(plainString(abs(d)).filter { $0.isNumber }.drop { $0 == "0" }.count))
        case "stripTrailingZeros": return O(newDecimal(vm, d, integer: isInt))
        case "toPlainString", "toString", "toEngineeringString":
            if p.first == "I" { // BigInteger.toString(radix)
                return S(vm, String(NSDecimalNumber(decimal: d).int64Value, radix: Int(max(2, min(36, a[0].i)))))
            }
            return S(vm, plainString(d, scale: isInt ? nil : t.fields["__scale"].map { Int($0.i) }))
        case "doubleValue": return .val(.double(NSDecimalNumber(decimal: d).doubleValue))
        case "floatValue": return .val(.float(NSDecimalNumber(decimal: d).floatValue))
        case "intValue", "intValueExact", "shortValue", "byteValue":
            return I(Int32(truncatingIfNeeded: NSDecimalNumber(decimal: truncate(d)).int64Value))
        case "longValue", "longValueExact":
            return .val(.wide(NSDecimalNumber(decimal: truncate(d)).int64Value))
        case "toBigInteger", "toBigIntegerExact", "unscaledValue":
            return O(newDecimal(vm, truncate(d), integer: true))
        case "movePointLeft", "movePointRight", "scaleByPowerOfTen":
            let k = Int(a[0].i) * (ref.name == "movePointLeft" ? -1 : 1)
            return result(d * pow(Decimal(10), k))
        case "ulp": return result(pow(Decimal(10), -decimalScale(t, d)))
        case "isProbablePrime", "testBit": return B(false)
        default: return nil
        }
    }

    static func numberFormatMethod(_ vm: VM, _ t: JObject, _ f: NumberFormatBox, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        let p = ref.params
        switch ref.name {
        case "format":
            var d: Decimal = 0
            switch p.first {
            case "D": d = Decimal(string: Boxed.javaDouble(a[0].d)) ?? Decimal(a[0].d)
            case "J": d = Decimal(a[0].j)
            default: d = decimal(a[0])
            }
            if a[0].o == nil, p.first?.hasPrefix("L") == true { return S(vm, "") }
            return S(vm, format(f, d))
        case "setMaximumFractionDigits": f.maxFraction = max(0, Int(a[0].i)); f.minFraction = min(f.minFraction, f.maxFraction); return .void
        case "setMinimumFractionDigits": f.minFraction = max(0, Int(a[0].i)); f.maxFraction = max(f.maxFraction, f.minFraction); return .void
        case "setMinimumIntegerDigits": f.minInteger = max(0, Int(a[0].i)); return .void
        case "setGroupingUsed": f.grouping = a[0].i != 0; return .void
        case "isGroupingUsed": return B(f.grouping)
        case "getMaximumFractionDigits": return I(Int32(f.maxFraction))
        case "getMinimumFractionDigits": return I(Int32(f.minFraction))
        case "applyPattern", "applyLocalizedPattern": applyPattern(f, try vm.stringOf(a[0].o)); return .void
        case "parse":
            let s = try vm.stringOf(a[0].o).replacingOccurrences(of: ",", with: "")
            guard let v = Double(s) else { throw vm.throwable("Ljava/text/ParseException;", "Unparseable number: \"\(s)\"") }
            return O(vm.box(.double(v), type: "D"))
        case "toPattern":
            return S(vm, (f.grouping ? "#,##0" : "0") + (f.maxFraction > 0 ? "." + String(repeating: "0", count: f.minFraction) + String(repeating: "#", count: f.maxFraction - f.minFraction) : ""))
        case "setMaximumIntegerDigits", "setRoundingMode", "setParseBigDecimal", "setDecimalFormatSymbols",
             "setPositivePrefix", "setNegativePrefix", "setPositiveSuffix", "setNegativeSuffix", "setDecimalSeparatorAlwaysShown",
             "setParseIntegerOnly", "setGroupingSize", "setCurrency":
            return .void
        case "getDecimalFormatSymbols": return O(vm.newObject("Ljava/text/DecimalFormatSymbols;"))
        default: return nil
        }
    }

    /// DecimalFormatSymbols / Locale placeholders (no native part; matched by class).
    static func plainObjectMethod(_ vm: VM, _ t: JObject, _ ref: DexMethodRef, _ a: [Value]) -> Ret? {
        switch t.cls.name {
        case "Ljava/text/DecimalFormatSymbols;":
            switch ref.name {
            case "getDecimalSeparator", "getMonetaryDecimalSeparator": return I(46)   // '.'
            case "getGroupingSeparator", "getMonetaryGroupingSeparator": return I(44) // ','
            case "getMinusSign": return I(45)
            case "getZeroDigit": return I(48)
            case "getPercent": return I(37)
            case "getExponentSeparator": return S(vm, "E")
            case "getInfinity": return S(vm, "∞")
            case "getNaN": return S(vm, "NaN")
            default: return nil
            }
        case "Ljava/util/Locale;":
            let lang = t.fields["__lang"]?.o?.string ?? "en"
            let country = t.fields["__country"]?.o?.string ?? "US"
            switch ref.name {
            case "getLanguage": return S(vm, lang)
            case "getCountry": return S(vm, country)
            case "toString": return S(vm, country.isEmpty ? lang : lang + "_" + country)
            case "toLanguageTag": return S(vm, country.isEmpty ? lang : lang + "-" + country)
            case "getDisplayName", "getDisplayLanguage": return S(vm, lang == "en" ? "English" : lang)
            case "getDisplayCountry": return S(vm, country)
            case "getScript", "getVariant": return S(vm, "")
            default: return nil
            }
        default:
            return nil
        }
    }

    /// android.text.Editable backed by an EditText's UIKit text field.
    static func editableMethod(_ vm: VM, _ t: JObject, _ eb: EditableBox, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        let box = eb.box
        let p = ref.params
        func current() -> [UInt16] { return units(onMain { box.text }) }
        func store(_ u: [UInt16]) {
            let s = fromUnits(u)
            onMain { box.text = s }
        }
        func clamp(_ i: Int32, _ count: Int) -> Int { return max(0, min(count, Int(i))) }
        func sub(_ v: Value, _ startIdx: Int?) throws -> [UInt16] {
            var u = units(try vm.stringOf(v.o))
            if let s = startIdx, p.count > s + 1 {
                let b = clamp(a[s].i, u.count), e = max(b, clamp(a[s + 1].i, u.count))
                u = Array(u[b..<e])
            }
            return u
        }
        switch ref.name {
        case "toString": return S(vm, onMain { box.text })
        case "length": return I(Int32(current().count))
        case "charAt":
            let u = current()
            let i = Int(a[0].i)
            guard i >= 0 && i < u.count else { throw vm.throwable("Ljava/lang/IndexOutOfBoundsException;", "index \(i)") }
            return I(Int32(u[i]))
        case "subSequence":
            let u = current()
            let b = clamp(a[0].i, u.count), e = max(b, clamp(a[1].i, u.count))
            return S(vm, fromUnits(u[b..<e]))
        case "insert":
            var u = current()
            let at = clamp(a[0].i, u.count)
            u.insert(contentsOf: try sub(a[1], 2), at: at)
            store(u)
            return O(t)
        case "replace":
            var u = current()
            let b = clamp(a[0].i, u.count), e = max(b, clamp(a[1].i, u.count))
            u.replaceSubrange(b..<e, with: try sub(a[2], 3))
            store(u)
            return O(t)
        case "append":
            var u = current()
            if p.first == "C" { u.append(UInt16(truncatingIfNeeded: a[0].i)) } else { u += try sub(a[0], 1) }
            store(u)
            return O(t)
        case "delete":
            var u = current()
            let b = clamp(a[0].i, u.count), e = max(b, clamp(a[1].i, u.count))
            u.removeSubrange(b..<e)
            store(u)
            return O(t)
        case "clear":
            store([])
            return .void
        case "getSpans":
            let type = ref.ret
            return O(vm.newObject(type, native: JArray(type: type, items: [])))
        case "getSpanStart", "getSpanEnd": return I(-1)
        case "getSpanFlags": return I(0)
        case "nextSpanTransition": return I(a.count > 1 ? a[1].i : 0)
        case "setSpan", "removeSpan", "clearSpans", "setFilters", "clearComposingText": return .void
        case "getFilters":
            return O(vm.newObject("[Landroid/text/InputFilter;", native: JArray(type: "[Landroid/text/InputFilter;", items: [])))
        case "equals": return B(t === a.first?.o)
        case "hashCode": return I(Int32(truncatingIfNeeded: ObjectIdentifier(t).hashValue))
        default: return nil
        }
    }
}
