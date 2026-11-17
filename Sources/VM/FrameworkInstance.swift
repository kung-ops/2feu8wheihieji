import UIKit

extension Framework {

    static func instanceCall(_ vm: VM, _ t: JObject, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        let n = ref.name
        if n == "<init>" { return try construct(vm, t, ref, a) }

        var r: Ret? = nil
        switch t.native {
        case let s as String: r = try stringMethod(vm, t, s, ref, a)
        case let sb as StringBuilderBox: r = try builderMethod(vm, t, sb, ref, a)
        case let b as Boxed: r = try boxedMethod(vm, t, b, ref, a)
        case let l as ListBox: r = try listMethod(vm, t, l, ref, a)
        case let m as MapBox: r = try mapMethod(vm, t, m, ref, a)
        case let it as IteratorBox:
            switch n {
            case "hasNext": r = B(it.index < it.items.count)
            case "next":
                guard it.index < it.items.count else { throw vm.throwable("Ljava/util/NoSuchElementException;") }
                it.index += 1
                r = .val(it.items[it.index - 1])
            case "remove": r = .void
            default: break
            }
        case let v as ViewBox: r = try viewMethod(vm, t, v, ref, a)
        case let ab as ActivityBox: r = try activityMethod(vm, t, ab.host, ref, a)
        case let tb as ToastBox:
            switch n {
            case "show":
                let text = tb.text
                let h = vm.host
                vm.log("Toast: " + text)
                DispatchQueue.main.async { h?.showToast(text) }
                r = .void
            case "setText": tb.text = try text(vm, a[0], ref.params[0]); r = .void
            default: break
            }
        case let ib as IntentBox: r = try intentMethod(vm, t, ib, ref, a)
        case is HandlerBox: r = handlerMethod(vm, ref, a)
        case is RandomBox: r = try randomMethod(vm, ref, a)
        case let ps as PrintStreamBox:
            switch n {
            case "println", "print":
                var s = ""
                if !ref.params.isEmpty { s = try vm.stringOf(a[0], type: ref.params[0]) }
                ps.pending += s
                if n == "println" {
                    vm.log((ps.isErr ? "System.err: " : "System.out: ") + ps.pending)
                    ps.pending = ""
                }
                r = .void
            case "printf", "format":
                let fmt = try vm.stringOf(a[0].o)
                ps.pending += try vm.javaFormat(fmt, varargs(a[1]))
                r = O(t)
            case "flush":
                if !ps.pending.isEmpty { vm.log("System.out: " + ps.pending); ps.pending = "" }
                r = .void
            default: break
            }
        case let c as ClassRef:
            switch n {
            case "getName", "getCanonicalName", "getTypeName": r = S(vm, VMClass.javaName(c.name))
            case "getSimpleName": r = S(vm, AndroidLayoutInflater.simpleName(VMClass.javaName(c.name)))
            default: break
            }
        case let th as ThreadBox:
            switch n {
            case "start":
                vm.post("thread") { [weak vm] in _ = try vm?.call(t, "run") }
                r = .void
            case "run":
                if let rn = th.runnable { try vm.call(rn, "run") }
                r = .void
            case "join", "interrupt", "setDaemon", "setName", "setPriority": r = .void
            case "isAlive", "isInterrupted": r = B(false)
            default: break
            }
        case let pb as PrefsBox: r = prefsMethod(vm, pb, ref, a)
        case let eb as PrefsEditorBox: r = editorMethod(vm, t, eb, ref, a)
        case let db as DialogBuilderBox: r = try dialogMethod(vm, t, db, ref, a)
        case is ResourcesBox:
            switch n {
            case "getString", "getText":
                let s = resString(vm, a[0])
                if ref.params.count > 1 { r = S(vm, try vm.javaFormat(s, varargs(a[1]))) } else { r = S(vm, s) }
            case "getColor": r = I(resColor(vm, a[0]))
            case "getInteger": r = I(Int32(truncatingIfNeeded: vm.apk.resources?.value(resId(a[0])).map { $0.data } ?? 0))
            case "getBoolean": r = B((vm.apk.resources?.value(resId(a[0]))?.data ?? 0) != 0)
            case "getDimension", "getDimensionPixelSize": r = ref.ret == "F" ? Ret.val(Value.float(0)) : I(0)
            default: break
            }
        case is InflaterBox:
            if n == "inflate" {
                let v = vm.inflateLayout(resId(a[0]), host: vm.currentActivity)
                let attach = ref.params.count < 3 || a[2].i != 0
                if attach, a.count > 1, let parent = a[1].o?.native as? ViewBox, let child = v?.native as? ViewBox {
                    onMain { parent.addChild(child) }
                }
                r = O(v)
            }
        case is ActionBarBox:
            switch n {
            case "setTitle", "setSubtitle":
                if n == "setTitle", let host = vm.currentActivity {
                    host.title = try text(vm, a[0], ref.params[0])
                    let screen = vm.host
                    onMain { screen?.titleChanged(host) }
                }
                r = .void
            case "hide", "show", "setDisplayHomeAsUpEnabled", "setHomeButtonEnabled", "setDisplayShowTitleEnabled": r = .void
            default: break
            }
        case let arr as JArray:
            if n == "clone" { r = O(vm.newObject(arr.type, native: JArray(type: arr.type, items: arr.items))) }
        default:
            break
        }
        if let r = r { return r }

        // Throwable
        if vm.isSubclass(t.cls, of: "Ljava/lang/Throwable;") {
            switch n {
            case "getMessage", "getLocalizedMessage": return O(t.fields["__message"]?.o)
            case "printStackTrace": vm.log("W/System.err: " + vm.describeThrowable(t)); return .void
            case "getCause": return O(t.fields["__cause"]?.o)
            case "getStackTrace":
                return O(vm.newObject("[Ljava/lang/StackTraceElement;", native: JArray(type: "[Ljava/lang/StackTraceElement;", items: [])))
            case "toString": return S(vm, vm.describeThrowable(t))
            case "initCause": t.fields["__cause"] = a[0]; return O(t)
            case "addSuppressed", "setStackTrace": return .void
            default: break
            }
        }

        // Runnable objects run directly (e.g. a framework Runnable stub)
        // Object
        // For app objects these are the java.lang.Object defaults (reached via super.x()),
        // so they must not dispatch back into the app's own overrides.
        let identity = Int32(truncatingIfNeeded: ObjectIdentifier(t).hashValue)
        switch n {
        case "toString":
            if t.cls.isApp { return S(vm, t.cls.javaName + "@" + String(UInt32(bitPattern: identity), radix: 16)) }
            return S(vm, try vm.stringOf(t))
        case "hashCode":
            if t.cls.isApp { return I(identity) }
            return I(try vm.javaHash(t))
        case "equals":
            if t.cls.isApp { return B(t === a.first?.o) }
            return B(try vm.javaEquals(t, a.first?.o))
        case "getClass": return O(vm.newObject("Ljava/lang/Class;", native: ClassRef(name: t.cls.name)))
        case "notify", "notifyAll", "wait": return .void
        default: return nil
        }
    }

    // MARK: - Constructors

    static func construct(_ vm: VM, _ t: JObject, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        let c = ref.classDesc
        let p = ref.params
        if t.native != nil { return .void }
        switch c {
        case "Ljava/lang/Object;":
            return .void
        case "Ljava/lang/StringBuilder;", "Ljava/lang/StringBuffer;":
            var s = ""
            if let f = p.first, f != "I", let o = a[0].o { s = try vm.stringOf(o) }
            t.native = StringBuilderBox(s)
        case "Ljava/lang/String;":
            if p.isEmpty { t.native = "" }
            else if p[0] == "[C" {
                let items = (a[0].o?.native as? JArray)?.items ?? []
                if p.count == 3 {
                    let off = max(0, Int(a[1].i)), cnt = max(0, Int(a[2].i))
                    t.native = vm.charsToString(Array(items.dropFirst(off).prefix(cnt)))
                } else {
                    t.native = vm.charsToString(items)
                }
            } else if p[0] == "[B" {
                let items = (a[0].o?.native as? JArray)?.items ?? []
                t.native = String(decoding: items.map { UInt8(truncatingIfNeeded: $0.i) }, as: UTF8.self)
            } else {
                t.native = try vm.stringOf(a[0].o)
            }
        case "Ljava/util/ArrayList;", "Ljava/util/LinkedList;", "Ljava/util/Vector;", "Ljava/util/Stack;",
             "Ljava/util/ArrayDeque;", "Ljava/util/concurrent/CopyOnWriteArrayList;", "Ljava/util/PriorityQueue;",
             "Ljava/util/HashSet;", "Ljava/util/LinkedHashSet;", "Ljava/util/TreeSet;":
            let l = ListBox(isSet: c.contains("Set"))
            if let src = a.first?.o?.native as? ListBox { l.items = src.items }
            t.native = l
        case "Ljava/util/HashMap;", "Ljava/util/LinkedHashMap;", "Ljava/util/TreeMap;", "Ljava/util/Hashtable;",
             "Ljava/util/concurrent/ConcurrentHashMap;":
            let m = MapBox()
            if let src = a.first?.o?.native as? MapBox { m.keys = src.keys; m.values = src.values }
            t.native = m
        case "Ljava/util/Random;":
            t.native = RandomBox()
        case "Landroid/content/Intent;":
            let ib = IntentBox()
            if p.count >= 2, p[1] == "Ljava/lang/Class;", let cr = a[1].o?.native as? ClassRef { ib.target = cr.name }
            else if p.first == "Ljava/lang/String;" { ib.action = try vm.stringOf(a[0].o) }
            else if let src = a.first?.o?.native as? IntentBox { ib.target = src.target; ib.extras = src.extras; ib.action = src.action }
            t.native = ib
        case "Landroid/os/Bundle;":
            t.native = IntentBox()
        case "Landroid/os/Handler;":
            t.native = HandlerBox()
        case "Landroid/app/AlertDialog$Builder;", "Landroidx/appcompat/app/AlertDialog$Builder;",
             "Lcom/google/android/material/dialog/MaterialAlertDialogBuilder;":
            t.native = DialogBuilderBox()
        case "Ljava/lang/Thread;":
            let th = ThreadBox()
            if let f = p.first, f == "Ljava/lang/Runnable;" { th.runnable = a[0].o }
            t.native = th
        case "Ljava/lang/Integer;": t.native = Boxed(.int, a[0])
        case "Ljava/lang/Long;": t.native = Boxed(.long, a[0])
        case "Ljava/lang/Double;": t.native = Boxed(.double, a[0])
        case "Ljava/lang/Float;": t.native = Boxed(.float, a[0])
        case "Ljava/lang/Boolean;": t.native = Boxed(.bool, a[0])
        default:
            if isViewClass(vm, c) {
                vm.createView(c, for: t, context: a.first?.o)
                return .void
            }
            if vm.isSubclass(vm.classFor(c), of: "Ljava/lang/Throwable;") || vm.isSubclass(t.cls, of: "Ljava/lang/Throwable;") {
                if let f = p.first, f == "Ljava/lang/String;" { t.fields["__message"] = a[0] }
                else if let f = p.first, f == "Ljava/lang/Throwable;", let cause = a[0].o {
                    t.fields["__cause"] = a[0]
                    t.fields["__message"] = .obj(vm.str(vm.describeThrowable(cause)))
                }
                if p.count > 1, p[1] == "Ljava/lang/Throwable;" { t.fields["__cause"] = a[1] }
                return .void
            }
            return .void
        }
        return .void
    }

    // MARK: - java.lang.String

    static func stringMethod(_ vm: VM, _ t: JObject, _ s: String, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        let p = ref.params
        func argS(_ i: Int) throws -> String { return try vm.stringOf(a[i].o) }
        switch ref.name {
        case "length": return I(Int32(s.utf16.count))
        case "isEmpty": return B(s.isEmpty)
        case "isBlank": return B(s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        case "toString", "intern": return O(t)
        case "charAt", "codePointAt":
            let u = units(s)
            let i = Int(a[0].i)
            guard i >= 0 && i < u.count else {
                throw vm.throwable("Ljava/lang/StringIndexOutOfBoundsException;", "index \(i), length \(u.count)")
            }
            return I(Int32(u[i]))
        case "equals", "contentEquals":
            if let o = a[0].o {
                if let x = o.native as? String { return B(x == s) }
                if ref.name == "contentEquals" { return B(try vm.stringOf(o) == s) }
            }
            return B(false)
        case "equalsIgnoreCase":
            guard let x = a[0].o?.native as? String else { return B(false) }
            return B(x.lowercased() == s.lowercased())
        case "hashCode": return I(try vm.javaHash(t))
        case "concat":
            let x = try argS(0)
            return S(vm, s + x)
        case "substring", "subSequence":
            let u = units(s)
            let b = Int(a[0].i)
            let e = p.count > 1 ? Int(a[1].i) : u.count
            guard b >= 0, e <= u.count, b <= e else {
                throw vm.throwable("Ljava/lang/StringIndexOutOfBoundsException;", "begin \(b), end \(e), length \(u.count)")
            }
            return S(vm, fromUnits(u[b..<e]))
        case "indexOf", "lastIndexOf":
            let u = units(s)
            var needle: [UInt16] = [UInt16(truncatingIfNeeded: a[0].i)]
            if p[0] != "I" { needle = units(try argS(0)) }
            let last = ref.name == "lastIndexOf"
            var from = p.count > 1 ? Int(a[1].i) : (last ? u.count : 0)
            if needle.isEmpty { return I(Int32(max(0, min(from, u.count)))) }
            if u.count < needle.count { return I(-1) }
            if last {
                from = min(from, u.count - needle.count)
                var i = from
                while i >= 0 {
                    if Array(u[i..<(i + needle.count)]) == needle { return I(Int32(i)) }
                    i -= 1
                }
            } else {
                var i = max(0, from)
                while i + needle.count <= u.count {
                    if Array(u[i..<(i + needle.count)]) == needle { return I(Int32(i)) }
                    i += 1
                }
            }
            return I(-1)
        case "contains":
            let x = try argS(0)
            return B(x.isEmpty || s.contains(x))
        case "startsWith":
            if p.count > 1 {
                let off = Int(a[1].i)
                let u = units(s)
                guard off >= 0, off <= u.count else { return B(false) }
                return B(fromUnits(u[off...]).hasPrefix(try argS(0)))
            }
            return B(s.hasPrefix(try argS(0)))
        case "endsWith": return B(s.hasSuffix(try argS(0)))
        case "trim", "strip": return S(vm, s.trimmingCharacters(in: .whitespacesAndNewlines))
        case "toUpperCase": return S(vm, s.uppercased())
        case "toLowerCase": return S(vm, s.lowercased())
        case "replace":
            if p[0] == "C" {
                let from = fromUnits([UInt16(truncatingIfNeeded: a[0].i)])
                let to = fromUnits([UInt16(truncatingIfNeeded: a[1].i)])
                return S(vm, s.replacingOccurrences(of: from, with: to))
            }
            return S(vm, s.replacingOccurrences(of: try argS(0), with: try argS(1)))
        case "replaceAll", "replaceFirst":
            let pattern = try argS(0)
            var repl = try argS(1)
            repl = repl.replacingOccurrences(of: "\\$", with: "\\\\$")
            guard let re = try? NSRegularExpression(pattern: pattern) else { return O(t) }
            let ns = s as NSString
            var range = NSRange(location: 0, length: ns.length)
            if ref.name == "replaceFirst" {
                guard let m = re.firstMatch(in: s, range: range) else { return O(t) }
                range = m.range
            }
            return S(vm, re.stringByReplacingMatches(in: s, range: range, withTemplate: repl))
        case "matches":
            let x = try argS(0)
            let pattern = "^(?:" + x + ")$"
            return B(s.range(of: pattern, options: .regularExpression) != nil)
        case "split":
            let parts = javaSplit(s, try argS(0), limit: p.count > 1 ? Int(a[1].i) : 0)
            let items = parts.map { Value.obj(vm.str($0)) }
            return O(vm.newObject("[Ljava/lang/String;", native: JArray(type: "[Ljava/lang/String;", items: items)))
        case "compareTo", "compareToIgnoreCase":
            let other = try argS(0)
            var x = units(s), y = units(other)
            if ref.name == "compareToIgnoreCase" { x = units(s.lowercased()); y = units(other.lowercased()) }
            for k in 0..<min(x.count, y.count) where x[k] != y[k] { return I(Int32(x[k]) - Int32(y[k])) }
            return I(Int32(x.count - y.count))
        case "toCharArray":
            let items = units(s).map { Value.int(Int32($0)) }
            return O(vm.newObject("[C", native: JArray(type: "[C", items: items)))
        case "getBytes":
            let items = Array(s.utf8).map { Value.int(Int32(Int8(bitPattern: $0))) }
            return O(vm.newObject("[B", native: JArray(type: "[B", items: items)))
        case "repeat":
            return S(vm, String(repeating: s, count: max(0, Int(a[0].i))))
        default:
            return nil
        }
    }

    // MARK: - StringBuilder

    static func builderMethod(_ vm: VM, _ t: JObject, _ sb: StringBuilderBox, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        let p = ref.params
        switch ref.name {
        case "append":
            if p.count == 3, p[0] == "[C" {
                let items = (a[0].o?.native as? JArray)?.items ?? []
                sb.s += vm.charsToString(Array(items.dropFirst(Int(a[1].i)).prefix(Int(a[2].i))))
            } else if p.count == 3 {
                let u = units(try vm.stringOf(a[0].o))
                let b = max(0, Int(a[1].i)), e = min(u.count, Int(a[2].i))
                if b < e { sb.s += fromUnits(u[b..<e]) }
            } else if let f = p.first {
                sb.s += try vm.stringOf(a[0], type: f)
            }
            return O(t)
        case "toString": return S(vm, sb.s)
        case "length": return I(Int32(sb.s.utf16.count))
        case "isEmpty": return B(sb.s.isEmpty)
        case "charAt":
            let u = units(sb.s)
            let i = Int(a[0].i)
            guard i >= 0 && i < u.count else { throw vm.throwable("Ljava/lang/StringIndexOutOfBoundsException;", "index \(i)") }
            return I(Int32(u[i]))
        case "reverse": sb.s = String(sb.s.reversed()); return O(t)
        case "insert":
            var u = units(sb.s)
            let i = max(0, min(u.count, Int(a[0].i)))
            let ins = units(try vm.stringOf(a[1], type: p.count > 1 ? p[1] : "Ljava/lang/Object;"))
            u.insert(contentsOf: ins, at: i)
            sb.s = fromUnits(u)
            return O(t)
        case "deleteCharAt":
            var u = units(sb.s)
            let i = Int(a[0].i)
            guard i >= 0 && i < u.count else { throw vm.throwable("Ljava/lang/StringIndexOutOfBoundsException;", "index \(i)") }
            u.remove(at: i)
            sb.s = fromUnits(u)
            return O(t)
        case "delete", "replace":
            var u = units(sb.s)
            let b = max(0, min(u.count, Int(a[0].i)))
            let e = max(b, min(u.count, Int(a[1].i)))
            var repl: [UInt16] = []
            if ref.name == "replace" { repl = units(try vm.stringOf(a[2].o)) }
            u.replaceSubrange(b..<e, with: repl)
            sb.s = fromUnits(u)
            return O(t)
        case "setLength":
            var u = units(sb.s)
            let len = max(0, Int(a[0].i))
            if len < u.count { u = Array(u.prefix(len)) } else { u += [UInt16](repeating: 0, count: len - u.count) }
            sb.s = fromUnits(u)
            return .void
        case "setCharAt":
            var u = units(sb.s)
            let i = Int(a[0].i)
            if i >= 0 && i < u.count { u[i] = UInt16(truncatingIfNeeded: a[1].i) }
            sb.s = fromUnits(u)
            return .void
        case "indexOf", "lastIndexOf", "substring", "contains", "startsWith", "endsWith":
            return try stringMethod(vm, vm.str(sb.s), sb.s, ref, a)
        case "capacity": return I(Int32(sb.s.utf16.count + 16))
        default: return nil
        }
    }

    // MARK: - Boxed numbers

    static func boxedMethod(_ vm: VM, _ t: JObject, _ b: Boxed, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        switch ref.name {
        case "intValue", "shortValue", "byteValue", "charValue", "booleanValue":
            if b.kind == .double || b.kind == .float { return I(VM.f2i(b.asDouble)) }
            if b.kind == .long { return I(Int32(truncatingIfNeeded: b.value.j)) }
            return I(b.value.i)
        case "longValue":
            if b.kind == .double || b.kind == .float { return .val(.wide(VM.f2l(b.asDouble))) }
            return .val(.wide(b.kind == .long ? b.value.j : Int64(b.value.i)))
        case "doubleValue": return .val(.double(b.asDouble))
        case "floatValue": return .val(.float(Float(b.asDouble)))
        case "toString": return S(vm, b.text)
        case "compareTo":
            let o = (a[0].o?.native as? Boxed)?.asDouble ?? 0
            let x = b.asDouble
            return I(x < o ? -1 : (x > o ? 1 : 0))
        case "isNaN": return B(b.asDouble.isNaN)
        default: return nil
        }
    }

    // MARK: - Collections

    static func listMethod(_ vm: VM, _ t: JObject, _ l: ListBox, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        let p = ref.params
        func index(of v: Value) throws -> Int {
            for (k, x) in l.items.enumerated() {
                if try vm.javaEquals(x.o, v.o) { return k }
            }
            return -1
        }
        func checkIndex(_ i: Int, _ size: Int) throws {
            if i < 0 || i >= size {
                throw vm.throwable("Ljava/lang/IndexOutOfBoundsException;", "Index: \(i), Size: \(size)")
            }
        }
        switch ref.name {
        case "add", "offer", "addLast", "offerLast", "push", "addFirst", "offerFirst":
            if p.count == 2 {
                let i = Int(a[0].i)
                if i < 0 || i > l.items.count { try checkIndex(i, l.items.count) }
                l.items.insert(a[1], at: i)
                return .void
            }
            if l.isSet {
                let found = try index(of: a[0])
                if found >= 0 { return B(false) }
            }
            if ref.name == "addFirst" || ref.name == "offerFirst" || (ref.name == "push" && !t.cls.name.contains("Stack")) {
                l.items.insert(a[0], at: 0)
            } else {
                l.items.append(a[0])
            }
            if ref.name == "push" { return O(a[0].o) }
            return ref.ret == "V" ? .void : B(true)
        case "get", "elementAt":
            let i = Int(a[0].i)
            try checkIndex(i, l.items.count)
            return .val(l.items[i])
        case "set":
            let i = Int(a[0].i)
            try checkIndex(i, l.items.count)
            let old = l.items[i]
            l.items[i] = a[1]
            return .val(old)
        case "size": return I(Int32(l.items.count))
        case "isEmpty", "empty": return B(l.items.isEmpty)
        case "clear": l.items.removeAll(); return .void
        case "contains": return B(try index(of: a[0]) >= 0)
        case "indexOf": return I(Int32(try index(of: a[0])))
        case "lastIndexOf":
            for k in stride(from: l.items.count - 1, through: 0, by: -1) {
                if try vm.javaEquals(l.items[k].o, a[0].o) { return I(Int32(k)) }
            }
            return I(-1)
        case "remove":
            if p.first == "I" {
                let i = Int(a[0].i)
                try checkIndex(i, l.items.count)
                return .val(l.items.remove(at: i))
            }
            if p.isEmpty {
                guard !l.items.isEmpty else { throw vm.throwable("Ljava/util/NoSuchElementException;") }
                return .val(l.items.removeFirst())
            }
            let k = try index(of: a[0])
            if k >= 0 { l.items.remove(at: k) }
            return B(k >= 0)
        case "pop", "removeLast", "pollLast":
            if l.items.isEmpty {
                if ref.name.hasPrefix("poll") { return O(nil) }
                throw vm.throwable(t.cls.name.contains("Stack") ? "Ljava/util/EmptyStackException;" : "Ljava/util/NoSuchElementException;")
            }
            if ref.name == "pop" && !t.cls.name.contains("Stack") { return .val(l.items.removeFirst()) }
            return .val(l.items.removeLast())
        case "poll", "pollFirst", "removeFirst":
            if l.items.isEmpty {
                if ref.name.hasPrefix("poll") { return O(nil) }
                throw vm.throwable("Ljava/util/NoSuchElementException;")
            }
            return .val(l.items.removeFirst())
        case "peek", "peekFirst", "getFirst", "element", "first", "firstElement":
            if l.items.isEmpty {
                if ref.name.hasPrefix("peek") { return O(nil) }
                throw vm.throwable("Ljava/util/NoSuchElementException;")
            }
            if ref.name == "peek" && t.cls.name.contains("Stack") { return .val(l.items[l.items.count - 1]) }
            return .val(l.items[0])
        case "peekLast", "getLast", "last", "lastElement":
            if l.items.isEmpty {
                if ref.name.hasPrefix("peek") { return O(nil) }
                throw vm.throwable("Ljava/util/NoSuchElementException;")
            }
            return .val(l.items[l.items.count - 1])
        case "addAll":
            let src: [Value]
            if p.count == 2 { src = (a[1].o?.native as? ListBox)?.items ?? [] } else { src = (a[0].o?.native as? ListBox)?.items ?? [] }
            if p.count == 2 {
                let i = max(0, min(l.items.count, Int(a[0].i)))
                l.items.insert(contentsOf: src, at: i)
            } else {
                for v in src {
                    if l.isSet {
                        let found = try index(of: v)
                        if found >= 0 { continue }
                    }
                    l.items.append(v)
                }
            }
            return B(!src.isEmpty)
        case "iterator", "listIterator", "descendingIterator":
            let items = ref.name == "descendingIterator" ? Array(l.items.reversed()) : l.items
            return O(vm.newObject("Ljava/util/Iterator;", native: IteratorBox(items)))
        case "toArray":
            let type = "[Ljava/lang/Object;"
            return O(vm.newObject(type, native: JArray(type: type, items: l.items)))
        case "sort":
            try sortValues(vm, &l.items, comparator: a.first?.o)
            return .void
        case "forEach":
            guard let fn = a[0].o else { throw vm.npe("forEach") }
            for v in l.items { try vm.call(fn, "accept", params: ["Ljava/lang/Object;"], args: [v]) }
            return .void
        case "subList":
            let b = max(0, Int(a[0].i)), e = min(l.items.count, Int(a[1].i))
            return O(vm.newObject("Ljava/util/ArrayList;", native: ListBox(items: b < e ? Array(l.items[b..<e]) : [])))
        case "search":
            for k in stride(from: l.items.count - 1, through: 0, by: -1) {
                if try vm.javaEquals(l.items[k].o, a[0].o) { return I(Int32(l.items.count - k)) }
            }
            return I(-1)
        default: return nil
        }
    }

    static func mapMethod(_ vm: VM, _ t: JObject, _ m: MapBox, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        func find(_ k: Value) throws -> Int {
            for (i, x) in m.keys.enumerated() {
                if try vm.javaEquals(x.o, k.o) { return i }
            }
            return -1
        }
        switch ref.name {
        case "put":
            let i = try find(a[0])
            if i >= 0 { let old = m.values[i]; m.values[i] = a[1]; return .val(old) }
            m.keys.append(a[0]); m.values.append(a[1])
            return O(nil)
        case "putIfAbsent":
            let i = try find(a[0])
            if i >= 0 { return .val(m.values[i]) }
            m.keys.append(a[0]); m.values.append(a[1])
            return O(nil)
        case "get":
            let i = try find(a[0])
            return i >= 0 ? .val(m.values[i]) : O(nil)
        case "getOrDefault":
            let i = try find(a[0])
            return i >= 0 ? .val(m.values[i]) : .val(a[1])
        case "containsKey": return B(try find(a[0]) >= 0)
        case "containsValue":
            for v in m.values {
                if try vm.javaEquals(v.o, a[0].o) { return B(true) }
            }
            return B(false)
        case "remove":
            let i = try find(a[0])
            if i < 0 { return O(nil) }
            m.keys.remove(at: i)
            return .val(m.values.remove(at: i))
        case "size": return I(Int32(m.keys.count))
        case "isEmpty": return B(m.keys.isEmpty)
        case "clear": m.keys.removeAll(); m.values.removeAll(); return .void
        case "keySet": return O(vm.newObject("Ljava/util/HashSet;", native: ListBox(isSet: true, items: m.keys)))
        case "values": return O(vm.newObject("Ljava/util/ArrayList;", native: ListBox(items: m.values)))
        case "putAll":
            if let src = a[0].o?.native as? MapBox {
                for (k, v) in zip(src.keys, src.values) {
                    let i = try find(k)
                    if i >= 0 { m.values[i] = v } else { m.keys.append(k); m.values.append(v) }
                }
            }
            return .void
        case "entrySet":
            var entries: [Value] = []
            for (k, v) in zip(m.keys, m.values) {
                let e = vm.newObject("Ljava/util/Map$Entry;")
                e.fields["__key"] = k
                e.fields["__value"] = v
                entries.append(.obj(e))
            }
            return O(vm.newObject("Ljava/util/HashSet;", native: ListBox(isSet: true, items: entries)))
        default: return nil
        }
    }

    // MARK: - Intent / Bundle

    static func intentMethod(_ vm: VM, _ t: JObject, _ ib: IntentBox, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        let p = ref.params
        let n = ref.name
        if n == "putExtra" || (n.hasPrefix("put") && p.count == 2) {
            let key = try vm.stringOf(a[0].o)
            let t1 = p[1]
            ib.extras[key] = t1.hasPrefix("L") || t1.hasPrefix("[") ? a[1] : .obj(vm.box(a[1], type: t1))
            return ref.ret == "V" ? .void : O(t)
        }
        if n.hasPrefix("get") && n != "getExtras" && n != "getAction" && n != "getComponent" && p.first == "Ljava/lang/String;" {
            let key = try vm.stringOf(a[0].o)
            let v = ib.extras[key]
            let def: Value = p.count > 1 ? a[1] : Value.defaultFor(ref.ret)
            guard let val = v else { return .val(def) }
            if ref.ret.hasPrefix("L") || ref.ret.hasPrefix("[") {
                if ref.ret == "Ljava/lang/String;", let b = val.o?.native as? Boxed { return S(vm, b.text) }
                return .val(val)
            }
            if let b = val.o?.native as? Boxed {
                switch ref.ret {
                case "J": return .val(.wide(b.kind == .long ? b.value.j : Int64(b.value.i)))
                case "D": return .val(.double(b.asDouble))
                case "F": return .val(.float(Float(b.asDouble)))
                default: return I(b.value.i)
                }
            }
            return .val(def)
        }
        switch n {
        case "getExtras": return O(t)
        case "hasExtra", "containsKey":
            let key = try vm.stringOf(a[0].o)
            return B(ib.extras[key] != nil)
        case "setClass":
            if let cr = a[1].o?.native as? ClassRef { ib.target = cr.name }
            return O(t)
        case "setClassName":
            ib.target = VMClass.descriptor(try vm.stringOf(a[1].o))
            return O(t)
        case "setAction": ib.action = try vm.stringOf(a[0].o); return O(t)
        case "getAction": return ib.action.map { S(vm, $0) } ?? O(nil)
        case "addFlags", "setFlags", "setData", "setType", "addCategory", "setPackage": return O(t)
        case "putExtras":
            if let src = a[0].o?.native as? IntentBox { for (k, v) in src.extras { ib.extras[k] = v } }
            return O(t)
        case "remove":
            let key = try vm.stringOf(a[0].o)
            ib.extras[key] = nil
            return .void
        case "keySet":
            return O(vm.newObject("Ljava/util/HashSet;", native: ListBox(isSet: true, items: ib.extras.keys.map { Value.obj(vm.str($0)) })))
        default: return nil
        }
    }

    // MARK: - Handler / Random

    static func handlerMethod(_ vm: VM, _ ref: DexMethodRef, _ a: [Value]) -> Ret? {
        switch ref.name {
        case "post", "postAtFrontOfQueue":
            if let r = a[0].o { schedule(vm, r, delayMs: 0) }
            return B(true)
        case "postDelayed":
            if let r = a[0].o { schedule(vm, r, delayMs: a.count > 1 ? a[a.count - 1].j : 0) }
            return B(true)
        case "removeCallbacks": cancel(vm, a.first?.o); return .void
        case "removeCallbacksAndMessages": cancel(vm, nil); return .void
        case "getLooper": return O(vm.newObject("Landroid/os/Looper;"))
        default: return nil
        }
    }

    static func randomMethod(_ vm: VM, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        switch ref.name {
        case "nextInt":
            if ref.params.count == 1 {
                let bound = a[0].i
                if bound <= 0 { throw vm.throwable("Ljava/lang/IllegalArgumentException;", "bound must be positive") }
                return I(Int32.random(in: 0..<bound))
            }
            if ref.params.count == 2 {
                let lo = a[0].i, hi = a[1].i
                if hi <= lo { throw vm.throwable("Ljava/lang/IllegalArgumentException;", "bound must be greater than origin") }
                return I(Int32.random(in: lo..<hi))
            }
            return I(Int32.random(in: Int32.min...Int32.max))
        case "nextLong": return .val(.wide(Int64.random(in: Int64.min...Int64.max)))
        case "nextDouble": return .val(.double(Double.random(in: 0..<1)))
        case "nextFloat": return .val(.float(Float.random(in: 0..<1)))
        case "nextBoolean": return B(Bool.random())
        case "nextGaussian":
            let u1 = Double.random(in: Double.leastNonzeroMagnitude..<1), u2 = Double.random(in: 0..<1)
            return .val(.double(sqrt(-2 * log(u1)) * cos(2 * .pi * u2)))
        case "setSeed": return .void
        default: return nil
        }
    }

    // MARK: - SharedPreferences (stored in UserDefaults)

    static func prefsMethod(_ vm: VM, _ pb: PrefsBox, _ ref: DexMethodRef, _ a: [Value]) -> Ret? {
        let dict = UserDefaults.standard.dictionary(forKey: pb.key) ?? [:]
        let key = (a.first?.o?.native as? String) ?? ""
        switch ref.name {
        case "getString":
            if let s = dict[key] as? String { return S(vm, s) }
            return a.count > 1 ? .val(a[1]) : O(nil)
        case "getInt":
            if let v = dict[key] as? Int { return I(Int32(truncatingIfNeeded: v)) }
            return a.count > 1 ? .val(a[1]) : I(0)
        case "getLong":
            if let v = dict[key] as? Int64 { return .val(.wide(v)) }
            if let v = dict[key] as? Int { return .val(.wide(Int64(v))) }
            return a.count > 1 ? .val(a[1]) : .val(.wide(0))
        case "getBoolean":
            if let v = dict[key] as? Bool { return B(v) }
            return a.count > 1 ? .val(a[1]) : B(false)
        case "getFloat":
            if let v = dict[key] as? Double { return .val(.float(Float(v))) }
            return a.count > 1 ? .val(a[1]) : .val(.float(0))
        case "contains": return B(dict[key] != nil)
        case "edit": return O(vm.newObject("Landroid/content/SharedPreferences$Editor;", native: PrefsEditorBox(key: pb.key)))
        case "registerOnSharedPreferenceChangeListener", "unregisterOnSharedPreferenceChangeListener": return .void
        default: return nil
        }
    }

    static func editorMethod(_ vm: VM, _ t: JObject, _ eb: PrefsEditorBox, _ ref: DexMethodRef, _ a: [Value]) -> Ret? {
        let key = (a.first?.o?.native as? String) ?? ""
        switch ref.name {
        case "putString": eb.pending[key] = (a[1].o?.native as? String) ?? ""; eb.removed.remove(key); return O(t)
        case "putInt": eb.pending[key] = Int(a[1].i); eb.removed.remove(key); return O(t)
        case "putLong": eb.pending[key] = a[1].j; eb.removed.remove(key); return O(t)
        case "putBoolean": eb.pending[key] = a[1].i != 0; eb.removed.remove(key); return O(t)
        case "putFloat": eb.pending[key] = Double(a[1].f); eb.removed.remove(key); return O(t)
        case "remove": eb.removed.insert(key); eb.pending[key] = nil; return O(t)
        case "clear": eb.clear = true; return O(t)
        case "apply", "commit":
            var dict = eb.clear ? [:] : (UserDefaults.standard.dictionary(forKey: eb.key) ?? [:])
            for k in eb.removed { dict[k] = nil }
            for (k, v) in eb.pending { dict[k] = v }
            UserDefaults.standard.set(dict, forKey: eb.key)
            return ref.name == "commit" ? B(true) : .void
        default: return nil
        }
    }

    // MARK: - AlertDialog

    static func dialogMethod(_ vm: VM, _ t: JObject, _ db: DialogBuilderBox, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        let p = ref.params
        switch ref.name {
        case "setTitle": db.title = try text(vm, a[0], p[0]); return O(t)
        case "setMessage": db.message = try text(vm, a[0], p[0]); return O(t)
        case "setPositiveButton", "setNegativeButton", "setNeutralButton":
            let which: Int32 = ref.name == "setPositiveButton" ? -1 : (ref.name == "setNegativeButton" ? -2 : -3)
            let label = try text(vm, a[0], p[0])
            db.buttons.removeAll { $0.which == which }
            db.buttons.append((which, label, a.count > 1 ? a[1].o : nil))
            return O(t)
        case "setItems":
            if p[0] == "I" {
                db.items = []
            } else {
                db.items = try varargs(a[0]).map { try vm.stringOf($0) }
            }
            db.itemsListener = a.count > 1 ? a[1].o : nil
            return O(t)
        case "create": return O(t)
        case "show":
            let dialogObj = t
            let buttons: [(text: String, style: UIAlertAction.Style, action: () -> Void)] = db.buttons.map { b -> (text: String, style: UIAlertAction.Style, action: () -> Void) in
                let listener = b.listener
                let which = b.which
                return (text: b.text, style: which == -2 ? .cancel : .default, action: {
                    if let l = listener {
                        vm.postCall(l, "onClick", params: ["Landroid/content/DialogInterface;", "I"], args: [.obj(dialogObj), .int(which)])
                    }
                })
            }
            let itemsListener = db.itemsListener
            let itemTapped: ((Int) -> Void)? = db.items.isEmpty ? nil : { idx in
                if let l = itemsListener {
                    vm.postCall(l, "onClick", params: ["Landroid/content/DialogInterface;", "I"], args: [.obj(dialogObj), .int(Int32(idx))])
                }
            }
            let title = db.title, message = db.message, items = db.items
            let h = vm.host
            DispatchQueue.main.async {
                h?.showDialog(title: title, message: message, items: items, buttons: buttons, itemTapped: itemTapped)
            }
            return ref.ret == "V" ? .void : O(t)
        case "setCancelable", "setIcon", "setView", "setOnDismissListener", "setOnCancelListener": return O(t)
        default: return nil
        }
    }
}
