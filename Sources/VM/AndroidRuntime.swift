import UIKit

/// Android-level services built on the interpreter: launching activities,
/// wiring views to Java objects, and Java string semantics.
extension VM {

    // MARK: - Activities

    func launchActivity(_ desc: String, intent: JObject?) throws {
        guard hasAppClass(desc) else {
            throw VMError.unsupported("activity \(VMClass.javaName(desc)) was not found in the APK's code")
        }
        let c = classFor(desc)
        try ensureInit(c)
        let obj = JObject(cls: c)
        let label = apk.label
        let host: ActivityHost = onMain { ActivityHost(className: c.javaName, title: label) }
        obj.native = ActivityBox(host: host)
        host.activity = obj
        host.intent = intent
        activityStack.append(host)
        let screen = self.host
        onMain { screen?.push(host) }
        if let note = libraryNote {
            log(note)
            libraryNote = nil
        }
        log("▶︎ Starting \(c.javaName)")

        let initRef = DexMethodRef(classDesc: desc, name: "<init>", params: [], ret: "V", sig: "<init>()V")
        _ = try invoke(kind: 2, ref: initRef, args: [.obj(obj)])
        try call(obj, "onCreate", params: ["Landroid/os/Bundle;"], args: [.null])
        try call(obj, "onStart")
        try call(obj, "onPostCreate", params: ["Landroid/os/Bundle;"], args: [.null])
        try call(obj, "onResume")
        try call(obj, "onPostResume")
    }

    func finishActivity(_ host: ActivityHost) {
        guard !host.finished else { return }
        host.finished = true
        activityStack.removeAll { $0 === host }
        if let a = host.activity {
            _ = try? call(a, "onPause")
            _ = try? call(a, "onStop")
            _ = try? call(a, "onDestroy")
        }
        let screen = self.host
        DispatchQueue.main.async { screen?.finish(host) }
    }

    /// The user pressed Home: the visible activity is paused and stopped,
    /// like on Android. `then` runs on the main thread afterwards.
    func moveToBackground(then: (() -> Void)? = nil) {
        post("background") { [weak self] in
            defer { if let then = then { DispatchQueue.main.async(execute: then) } }
            guard let self = self, let a = self.currentActivity?.activity else { return }
            _ = try? self.call(a, "onPause")
            _ = try? self.call(a, "onStop")
            _ = try? self.call(a, "onTrimMemory", params: ["I"], args: [.int(20)])
        }
    }

    /// The user came back to the app.
    func moveToForeground() {
        post("foreground") { [weak self] in
            guard let self = self, let a = self.currentActivity?.activity else { return }
            try self.call(a, "onRestart")
            try self.call(a, "onStart")
            try self.call(a, "onResume")
        }
    }

    /// Frees caches that are rebuilt on demand (iOS memory warning).
    func trimMemory() {
        post("trim") { [weak self] in
            guard let self = self else { return }
            for d in self.apk.dexFiles { d.trimCaches() }
            for c in self.classes.values { c.vcache.removeAll(); c.vmiss.removeAll() }
            if let a = self.currentActivity?.activity {
                _ = try? self.call(a, "onLowMemory")
                _ = try? self.call(a, "onTrimMemory", params: ["I"], args: [.int(80)])
            }
        }
    }

    func activityHost(_ ctx: JObject?) -> ActivityHost? {
        if let b = ctx?.native as? ActivityBox { return b.host }
        return currentActivity
    }

    var currentActivity: ActivityHost? {
        return activityStack.last(where: { !$0.finished })
    }

    // MARK: - Views

    /// Descriptor used as the Java class of an inflated element.
    func classDescriptor(forElement element: String) -> String {
        if element.contains(".") {
            let d = VMClass.descriptor(element)
            return hasAppClass(d) ? "Landroid/view/View;" : d
        }
        switch element {
        case "View", "ViewGroup", "SurfaceView", "TextureView", "ViewStub":
            return "Landroid/view/\(element);"
        case "WebView":
            return "Landroid/webkit/WebView;"
        default:
            return "Landroid/widget/\(element);"
        }
    }

    /// Creates Java objects for a ViewBox tree and hooks up UI events.
    @discardableResult
    func wrap(_ box: ViewBox, in host: ActivityHost?, desc: String? = nil) -> JObject {
        if let existing = box.jobj { return existing }
        // A custom view from the app itself (e.g. <com.example.MyTextView>) becomes
        // a real instance of the app's class, so the app can cast to it and its
        // overridden methods run. Its native part is still the UIKit view.
        var appClass: VMClass? = nil
        if desc == nil, box.elementName.contains(".") {
            let d = VMClass.descriptor(box.elementName)
            if hasAppClass(d) { appClass = classFor(d) }
        }
        let obj = JObject(cls: appClass ?? classFor(desc ?? classDescriptor(forElement: box.elementName)), native: box)
        box.jobj = obj
        if let c = appClass { constructCustomView(obj, c, host: host) }
        host?.viewObjects.append(obj)
        if host == nil { orphanViews.append(obj) }
        box.handler = { [weak self, weak obj] b, event, value in
            guard let vm = self, let o = obj else { return }
            vm.post("ui-event") { try vm.dispatchEvent(b, o, event, value, host) }
        }
        for c in box.children { wrap(c, in: host) }
        return obj
    }

    /// Runs the app's View constructor: (Context, AttributeSet) or (Context).
    private func constructCustomView(_ obj: JObject, _ c: VMClass, host: ActivityHost?) {
        guard let dc = c.dex else { return }
        let ctx: Value = .obj(host?.activity ?? currentActivity?.activity)
        let attrs: Value = .obj(newObject("Landroid/util/AttributeSet;"))
        let candidates: [(String, [Value])] = [
            ("<init>(Landroid/content/Context;Landroid/util/AttributeSet;)V", [ctx, attrs]),
            ("<init>(Landroid/content/Context;Landroid/util/AttributeSet;I)V", [ctx, attrs, .zero]),
            ("<init>(Landroid/content/Context;)V", [ctx])
        ]
        do {
            try ensureInit(c)
            for (sig, args) in candidates {
                if let m = dc.methods[sig], m.code != nil {
                    _ = try execute(m, [.obj(obj)] + args)
                    return
                }
            }
        } catch let t as JavaThrow {
            warnOnce("custom view \(c.javaName) constructor failed: \(describeThrowable(t.obj))")
        } catch {
            warnOnce("custom view \(c.javaName) constructor failed: \(error)")
        }
    }

    private func dispatchEvent(_ b: ViewBox, _ o: JObject, _ event: String, _ value: Int32, _ host: ActivityHost?) throws {
        switch event {
        case "checked":
            if let l = b.checkedListener {
                try call(l, "onCheckedChanged", params: ["Landroid/widget/CompoundButton;", "Z"], args: [.obj(o), .int(value)])
            }
            fallthrough
        case "click":
            if let l = b.clickListener {
                try call(l, "onClick", params: ["Landroid/view/View;"], args: [.obj(o)])
            } else if let name = b.onClickAttr, let act = (host ?? currentActivity)?.activity {
                try callByName(act, name, args: [.obj(o)])
            } else {
                _ = try listItemClicked(b)
            }
        case "progress":
            if let l = b.seekListener {
                try call(l, "onProgressChanged", params: ["Landroid/widget/SeekBar;", "I", "Z"],
                         args: [.obj(o), .int(value), .int(1)])
            }
        default:
            break
        }
    }

    func inflateLayout(_ id: Int, host: ActivityHost?) -> JObject? {
        let apk = self.apk
        let box: ViewBox? = onMain {
            guard let node = apk.layout(id) else { return nil }
            return AndroidLayoutInflater(apk: apk).inflate(node)
        }
        guard let b = box else {
            warnOnce("layout 0x\(String(id, radix: 16)) could not be loaded")
            return nil
        }
        return wrap(b, in: host)
    }

    func setContent(_ host: ActivityHost, _ view: JObject) {
        guard let box = view.native as? ViewBox else { return }
        host.rootBox = box
        onMain { host.setContent(box.view) }
    }

    func createView(_ classDesc: String, for obj: JObject, context: JObject?) {
        let element = VMClass.javaName(classDesc)
        let simple = AndroidLayoutInflater.simpleName(element)
        let box: ViewBox = onMain {
            let inf = AndroidLayoutInflater(apk: self.apk)
            return inf.make(simple, orientation: nil, hasChildren: false)
        }
        obj.native = box
        box.jobj = obj
        let host = activityHost(context)
        if let h = host { h.viewObjects.append(obj) } else { orphanViews.append(obj) }
        box.handler = { [weak self, weak obj] b, event, value in
            guard let vm = self, let o = obj else { return }
            vm.post("ui-event") { try vm.dispatchEvent(b, o, event, value, host) }
        }
    }

    // MARK: - Java semantics

    /// String.valueOf / string concatenation for a value of the given type.
    func stringOf(_ v: Value, type: String) throws -> String {
        switch type {
        case "I", "S", "B": return String(v.i)
        case "J": return String(v.j)
        case "Z": return v.i != 0 ? "true" : "false"
        case "C": return String(UnicodeScalar(UInt16(truncatingIfNeeded: v.i)).map { Character($0) } ?? "?")
        case "F": return Boxed.javaDouble(Double(v.f))
        case "D": return Boxed.javaDouble(v.d)
        case "[C":
            if let a = v.o?.native as? JArray { return String(decoding: a.utf16, as: UTF16.self) }
            return "null"
        default: return try stringOf(v.o)
        }
    }

    func charsToString(_ items: [Value]) -> String {
        let units = items.map { UInt16(truncatingIfNeeded: $0.i) }
        return String(decoding: units, as: UTF16.self)
    }

    func stringOf(_ o: JObject?) throws -> String {
        guard let o = o else { return "null" }
        switch o.native {
        case let s as String: return s
        case let sb as StringBuilderBox: return sb.s
        case let b as Boxed: return b.text
        case let l as ListBox:
            var parts: [String] = []
            for item in l.items { parts.append(try stringOf(item.o)) }
            return "[" + parts.joined(separator: ", ") + "]"
        case let v as ViewBox:
            return onMain { v.text }
        case let e as EditableBox:
            return onMain { e.box.text }
        case let d as DecimalBox:
            return Framework.plainString(d.value, scale: d.isInteger ? nil : o.fields["__scale"].map { Int($0.i) })
        case let c as ClassRef:
            return "class " + VMClass.javaName(c.name)
        default:
            break
        }
        if o.cls.isApp, findVirtual(o.cls, "toString()Ljava/lang/String;") != nil {
            let r = try call(o, "toString", ret: "Ljava/lang/String;")
            return r?.o?.string ?? "null"
        }
        if isSubclass(o.cls, of: "Ljava/lang/Throwable;") { return describeThrowable(o) }
        if let name = o.fields["__name"]?.o?.native as? String, o.fields["__ordinal"] != nil { return name }
        return o.cls.javaName + "@" + String(UInt(bitPattern: ObjectIdentifier(o).hashValue) & 0xffffff, radix: 16)
    }

    func javaEquals(_ a: JObject?, _ b: JObject?) throws -> Bool {
        guard let a = a, let b = b else { return a == nil && b == nil }
        if a === b { return true }
        if let x = a.native as? String { return x == (b.native as? String) }
        if let x = a.native as? Boxed, let y = b.native as? Boxed {
            if x.kind == .long || y.kind == .long { return x.value.j == y.value.j }
            if x.kind == .double || x.kind == .float { return x.asDouble == y.asDouble }
            return x.value.i == y.value.i && x.kind == y.kind
        }
        if a.cls.isApp, findVirtual(a.cls, "equals(Ljava/lang/Object;)Z") != nil {
            let r = try call(a, "equals", params: ["Ljava/lang/Object;"], ret: "Z", args: [.obj(b)])
            return (r?.i ?? 0) != 0
        }
        return false
    }

    func javaHash(_ o: JObject?) throws -> Int32 {
        guard let o = o else { return 0 }
        if let s = o.native as? String {
            var h: Int32 = 0
            for u in s.utf16 { h = h &* 31 &+ Int32(u) }
            return h
        }
        if let b = o.native as? Boxed { return b.value.i }
        if o.cls.isApp, findVirtual(o.cls, "hashCode()I") != nil {
            return try call(o, "hashCode", ret: "I")?.i ?? 0
        }
        return Int32(truncatingIfNeeded: ObjectIdentifier(o).hashValue)
    }

    func box(_ v: Value, type: String) -> JObject {
        switch type {
        case "I": return newObject("Ljava/lang/Integer;", native: Boxed(.int, v))
        case "J": return newObject("Ljava/lang/Long;", native: Boxed(.long, v))
        case "Z": return newObject("Ljava/lang/Boolean;", native: Boxed(.bool, v))
        case "D": return newObject("Ljava/lang/Double;", native: Boxed(.double, v))
        case "F": return newObject("Ljava/lang/Float;", native: Boxed(.float, v))
        case "C": return newObject("Ljava/lang/Character;", native: Boxed(.char, v))
        case "S": return newObject("Ljava/lang/Short;", native: Boxed(.short, v))
        default: return newObject("Ljava/lang/Byte;", native: Boxed(.byte, v))
        }
    }

    /// Java's String.format for the common cases (%d %s %f %.2f %x %c %b %n %%).
    func javaFormat(_ fmt: String, _ args: [JObject?]) throws -> String {
        var out = ""
        var argIndex = 0
        let chars = Array(fmt)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch != "%" { out.append(ch); i += 1; continue }
            i += 1
            var spec = ""
            while i < chars.count, "-#+ 0,(.0123456789$".contains(chars[i]) { spec.append(chars[i]); i += 1 }
            guard i < chars.count else { break }
            let conv = chars[i]
            i += 1
            if conv == "%" { out.append("%"); continue }
            if conv == "n" { out.append("\n"); continue }
            if let dollar = spec.firstIndex(of: "$"), let n = Int(spec[spec.startIndex..<dollar]) {
                argIndex = n - 1
                spec = String(spec[spec.index(after: dollar)...])
            }
            let arg: JObject? = argIndex < args.count ? args[argIndex] : nil
            argIndex += 1
            let grouping = spec.contains(",")
            let cspec = spec.replacingOccurrences(of: ",", with: "")
            switch conv {
            case "d":
                var n: Int64 = 0
                if let b = arg?.native as? Boxed { n = b.kind == .long ? b.value.j : Int64(b.value.i) }
                var s = String(format: "%" + cspec + "lld", n)
                if grouping {
                    let nf = NumberFormatter()
                    nf.numberStyle = .decimal
                    nf.groupingSeparator = ","
                    s = nf.string(from: NSNumber(value: n)) ?? s
                }
                out += s
            case "f", "e", "g":
                var d = (arg?.native as? Boxed)?.asDouble ?? 0
                if let db = arg?.native as? DecimalBox { d = NSDecimalNumber(decimal: db.value).doubleValue }
                out += String(format: "%" + cspec + String(conv), d)
            case "x", "X", "o":
                var n: Int64 = 0
                if let b = arg?.native as? Boxed { n = b.kind == .long ? b.value.j : Int64(UInt32(bitPattern: b.value.i)) }
                out += String(format: "%" + cspec + "ll" + String(conv), n)
            case "c":
                if let b = arg?.native as? Boxed { out += b.kind == .char ? b.text : String(Character(UnicodeScalar(UInt8(truncatingIfNeeded: b.value.i)))) }
            case "b", "B":
                if let b = arg?.native as? Boxed, b.kind == .bool { out += b.text } else { out += arg == nil ? "false" : "true" }
            default:
                var s = try stringOf(arg)
                if conv == "S" { s = s.uppercased() }
                if let w = Int(cspec.replacingOccurrences(of: "-", with: "")), s.count < w {
                    let pad = String(repeating: " ", count: w - s.count)
                    s = cspec.hasPrefix("-") ? s + pad : pad + s
                }
                out += s
            }
        }
        return out
    }
}
