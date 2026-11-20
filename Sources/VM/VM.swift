import Foundation

/// Runs VM work on one background thread with a big stack, so deep Java
/// call chains don't overflow the 1 MB main-thread stack.
final class VMThread: Thread {
    private var jobs: [() -> Void] = []
    private let cond = NSCondition()
    /// Runs on this thread once it has been stopped (after the job in progress).
    var onExit: (() -> Void)?

    override init() {
        super.init()
        stackSize = 32 * 1024 * 1024
        name = "dalvik-vm"
    }

    func enqueue(_ job: @escaping () -> Void) {
        cond.lock()
        jobs.append(job)
        cond.signal()
        cond.unlock()
    }

    func stop() {
        cancel()
        cond.lock()
        cond.signal()
        cond.unlock()
    }

    override func main() {
        while true {
            cond.lock()
            while jobs.isEmpty && !isCancelled { cond.wait() }
            if isCancelled {
                jobs.removeAll()
                let exit = onExit
                onExit = nil
                cond.unlock()
                autoreleasepool { exit?() }
                return
            }
            let job = jobs.removeFirst()
            cond.unlock()
            autoreleasepool { job() }
        }
    }
}

/// Runs a block on the main thread and returns its result.
@discardableResult
func onMain<T>(_ f: () -> T) -> T {
    if Thread.isMainThread { return f() }
    return DispatchQueue.main.sync(execute: f)
}

/// A small Dalvik bytecode interpreter.
final class VM {
    let apk: ApkPackage
    weak var host: RunHost?
    private(set) var classes: [String: VMClass] = [:]
    private var foundClasses: [String: DexClass] = [:]
    private var missingClasses: Set<String> = []

    /// Library classes inside the APK that we treat like Android itself
    /// (e.g. AndroidX's AppCompatActivity after R8 renamed it to "Lo/xy;"),
    /// mapped to the real Android class they stand in for.
    private var libraryClasses: [String: String] = [:]
    var libraryNote: String?
    var internedStrings: [String: JObject] = [:]
    private var warned: Set<String> = []
    let thread = VMThread()
    /// The app's private folders on the virtual device.
    lazy var storage = AppStorage(packageName: apk.packageName)

    var steps = 0
    var stepLimit = 40_000_000
    /// Distinguish interpreted APK methods from Android API compatibility fallbacks.
    var interpretedMethodCount = 0
    var stubCallCount = 0
    var strictRealApkMode = true
    var depth = 0
    var stopped = false
    var log: (String) -> Void = { _ in }
    /// Methods currently running (for crash stack traces).
    private var frames: [DexMethod] = []

    // Android runtime state (VM thread only)
    var activityStack: [ActivityHost] = []
    var orphanViews: [JObject] = []
    var runnableGeneration: [ObjectIdentifier: Int] = [:]
    /// ListViews with an adapter (see FrameworkLists).
    var listViews: [ViewBox] = []
    /// Drawing views waiting for the next frame (see Graphics).
    var dirtyCanvases: [ViewBox] = []
    var frameScheduled = false
    var framesDrawn = 0

    /// The one main Looper and main Thread. Must be singletons, because apps
    /// check `Looper.getMainLooper().getThread() == Thread.currentThread()`.
    lazy var mainLooper: JObject = newObject("Landroid/os/Looper;", native: LooperBox())
    lazy var mainThread: JObject = newObject("Ljava/lang/Thread;", native: ThreadBox())

    /// Library code we don't interpret; calls into it go to Framework stubs.
    static let frameworkPrefixes = [
        "Landroid/", "Ljava/", "Ljavax/", "Landroidx/", "Ldalvik/", "Lsun/",
        "Lcom/google/android/material/", "Lcom/google/android/gms/", "Lorg/json/",
        "Lkotlin/jvm/internal/Intrinsics;", "Lorg/w3c/", "Lorg/xml/"
    ]

    init(apk: ApkPackage) {
        self.apk = apk
        findLibraryActivityParents()
        thread.start()
    }

    deinit {
        thread.stop()
    }

    func shutdown() {
        guard !stopped else { return }
        stopped = true
        // Once the job in progress has stopped, break the app's reference
        // cycles so all of its memory is given back (see releaseAll).
        thread.onExit = { [self] in self.releaseAll() }
        thread.stop()
    }

    func isFrameworkName(_ name: String) -> Bool {
        if name.hasPrefix("[") { return true }
        if libraryClasses[name] != nil { return true }
        for p in VM.frameworkPrefixes where name.hasPrefix(p) { return true }
        return false
    }

    /// The APK's own definition of a class (first dex wins), decoded on demand.
    func dexClass(_ name: String) -> DexClass? {
        if let c = foundClasses[name] { return c }
        if missingClasses.contains(name) { return nil }
        for dx in apk.dexFiles {
            if let c = dx.dexClass(name) {
                foundClasses[name] = c
                return c
            }
        }
        missingClasses.insert(name)
        return nil
    }

    /// Finds "bridge" library classes: superclasses that sit between the app's
    /// own classes and a real Android class (android.app.Activity,
    /// android.widget.EditText, …) but live outside the app's package —
    /// typically AndroidX AppCompat/Material classes renamed by R8 (e.g. "Lp/j;").
    /// They depend on Android internals (themes, windows, delegates), so they are
    /// handled by the built-in Android stand-ins instead of being interpreted.
    private func findLibraryActivityParents() {
        func pkg(_ desc: String) -> String {
            guard let slash = desc.lastIndex(of: "/") else { return "L" }
            return String(desc[...slash])
        }
        var own: Set<String> = [pkg(VMClass.descriptor(apk.packageName + ".X"))]
        for a in apk.activities { own.insert(pkg(VMClass.descriptor(a))) }
        if let app = apk.applicationClass { own.insert(pkg(VMClass.descriptor(app))) }
        own = own.filter { $0.count > 3 }
        func isOwn(_ desc: String) -> Bool {
            for p in own where desc.hasPrefix(p) { return true }
            return false
        }
        func superOf(_ desc: String) -> String? {
            for dx in apk.dexFiles where dx.hasClass(desc) { return dx.superclassOf(desc) }
            return nil
        }
        func inApk(_ desc: String) -> Bool {
            return apk.dexFiles.contains { $0.hasClass(desc) }
        }
        var done: Set<String> = []
        for dx in apk.dexFiles {
            for name in dx.classNames where isOwn(name) && !done.contains(name) {
                done.insert(name)
                // Walk up (through bundled AndroidX too) to the first class that
                // the real Android OS provides, e.g. android.app.Activity.
                var chain: [String] = []
                var cur = superOf(name)
                while let c = cur, chain.count < 30, inApk(c), !c.hasPrefix("Landroid/"), !c.hasPrefix("Ljava/") {
                    chain.append(c)
                    cur = superOf(c)
                }
                guard let terminal = cur, terminal.hasPrefix("Landroid/") else { continue }
                if terminal == "Landroid/app/Activity;" {
                    // Activities: R8 may rename the app's own base classes too (YouTube),
                    // so find AndroidX by the text it contains, e.g. "androidx:appcompat".
                    // That class and everything above it is library code.
                    if let k = chain.firstIndex(where: { isAndroidXActivity($0) }) {
                        for c in chain[k...] { libraryClasses[c] = terminal }
                    }
                    continue
                }
                var bridging = false
                for c in chain {
                    if !isOwn(c) { bridging = true }
                    if bridging { libraryClasses[c] = terminal }
                }
            }
        }
        if !libraryClasses.isEmpty {
            libraryNote = "ℹ︎ Treating \(libraryClasses.count) bundled library class(es) as Android, e.g. " +
                libraryClasses.keys.sorted().prefix(4).map { VMClass.javaName($0) + "→" + AndroidLayoutInflater.simpleName(libraryClasses[$0] ?? "") }.joined(separator: ", ")
        }
    }

    /// AndroidX's AppCompatActivity / FragmentActivity / ComponentActivity, even
    /// when renamed: recognised by their package name or the strings they use.
    private var androidXCache: [String: Bool] = [:]
    func isAndroidXActivity(_ desc: String) -> Bool {
        if desc.hasPrefix("Landroidx/") || desc.hasPrefix("Landroid/support/") { return true }
        if let v = androidXCache[desc] { return v }
        let markers = ["androidx:appcompat", "android:support:activity-result", "Local FragmentActivity",
                       "android:support:lifecycle", "androidx.activity.result.contract"]
        var found = false
        if let dc = dexClass(desc) {
            outer: for m in dc.methods.values {
                guard let code = m.code else { continue }
                for s in VM.constStrings(code, m.dex) where markers.contains(where: { s.hasPrefix($0) }) {
                    found = true
                    break outer
                }
            }
        }
        androidXCache[desc] = found
        return found
    }

    /// All const-string literals in a method.
    static func constStrings(_ code: DexCode, _ dex: DexFile) -> [String] {
        var out: [String] = []
        let u = code.insns
        var pc = 0
        while pc < u.count {
            let w = Int(u[pc])
            let op = w & 0xff
            if op == 0x1a, pc + 1 < u.count { out.append(dex.string(Int(u[pc + 1]))) }
            if op == 0x1b, pc + 2 < u.count { out.append(dex.string(Int(u[pc + 1]) | (Int(u[pc + 2]) << 16))) }
            pc += max(1, insnWidth(u, pc))
        }
        return out
    }

    /// Length in 16-bit code units of the instruction at pc (including switch / array payloads).
    static func insnWidth(_ u: [UInt16], _ pc: Int) -> Int {
        let w = Int(u[pc])
        let op = w & 0xff
        func at(_ i: Int) -> Int { return pc + i < u.count ? Int(u[pc + i]) : 0 }
        switch op {
        case 0x00:
            switch w {
            case 0x0100: return 4 + at(1) * 2
            case 0x0200: return 2 + at(1) * 4
            case 0x0300:
                let width = at(1), size = at(2) | (at(3) << 16)
                return 4 + (size * width + 1) / 2
            default: return 1
            }
        case 0x02, 0x05, 0x08, 0x13, 0x15, 0x16, 0x19, 0x1a, 0x1c, 0x1f, 0x20, 0x22, 0x23, 0x29, 0xfe, 0xff: return 2
        case 0x03, 0x06, 0x09, 0x14, 0x17, 0x1b, 0x24, 0x25, 0x26, 0x2a, 0x2b, 0x2c, 0xfc, 0xfd: return 3
        case 0x18: return 5
        case 0x2d...0x3d, 0x44...0x6d, 0x90...0xaf, 0xd0...0xe2: return 2
        case 0x6e...0x72, 0x74...0x78: return 3
        case 0xfa, 0xfb: return 4
        default: return 1
        }
    }

    func hasAppClass(_ name: String) -> Bool {
        return !isFrameworkName(name) && apk.dexFiles.contains { $0.hasClass(name) }
    }

    func warnOnce(_ s: String) {
        if warned.insert(s).inserted { log("⚠︎ " + s) }
    }

    // MARK: - Jobs

    /// Runs work on the VM thread. Uncaught Java exceptions are reported as a crash.
    func post(_ what: String = "", _ work: @escaping () throws -> Void) {
        thread.enqueue { [weak self] in
            guard let self = self, !self.stopped else { return }
            self.steps = 0
            self.depth = 0
            self.frames.removeAll()
            do {
                try work()
            } catch let t as JavaThrow {
                self.reportCrash(t.obj)
            } catch VMError.stopped {
                // closed
            } catch {
                self.log("✖ \(error)")
                let msg = "\(error)"
                let h = self.host
                DispatchQueue.main.async { h?.showError(title: "Interpreter stopped", message: msg) }
            }
        }
    }

    /// Posts a Java callback (listener.onClick etc.) to the VM thread.
    func postCall(_ obj: JObject, _ name: String, params: [String] = [], args: [Value] = []) {
        post(name) { [weak self] in
            _ = try self?.call(obj, name, params: params, args: args)
        }
    }

    func reportCrash(_ ex: JObject) {
        let text = describeThrowable(ex)
        var stack = ex.fields["__stack"]?.o?.string ?? ""
        if stack.isEmpty { stack = stackTrace() }
        log("FATAL EXCEPTION: " + text + (stack.isEmpty ? "" : "\n" + stack))
        let h = host
        let name = apk.label
        DispatchQueue.main.async { h?.showError(title: "\(name) has stopped", message: text) }
    }

    func describeThrowable(_ ex: JObject) -> String {
        let msg = ex.fields["__message"]?.o?.string
        return ex.cls.javaName + (msg.map { ": " + $0 } ?? "")
    }

    // MARK: - Classes

    func classFor(_ name: String) -> VMClass {
        if let c = classes[name] { return c }
        let dc = isFrameworkName(name) ? nil : dexClass(name)
        let c = VMClass(name: name, dex: dc)
        classes[name] = c
        if let dc = dc {
            if let s = dc.superDesc { c.superclass = classFor(s) }
            c.interfaces = dc.interfaces.map { classFor($0) }
        } else if let real = libraryClasses[name] {
            c.superclass = classFor(real)
        } else if name != "Ljava/lang/Object;" {
            c.superclass = classFor(Framework.superOf(name))
        }
        return c
    }

    func ensureInit(_ c: VMClass) throws {
        guard c.initState == 0 else { return }
        c.initState = 1
        if let s = c.superclass { try ensureInit(s) }
        guard let dc = c.dex else { c.initState = 2; return }
        for (i, f) in dc.staticFields.enumerated() {
            var v = Value.defaultFor(f.type)
            if i < dc.staticValues.count {
                switch dc.staticValues[i] {
                case .int(let x): v = .int(x)
                case .long(let x): v = .wide(x)
                case .string(let s): v = .obj(str(s))
                case .null, .unsupported: break
                }
            }
            c.statics[f.name] = v
        }
        if let clinit = dc.methods["<clinit>()V"] {
            _ = try execute(clinit, [])
        }
        c.initState = 2
    }

    func isSubclass(_ c: VMClass, of target: String) -> Bool {
        var cur: VMClass? = c
        var guardCount = 0
        while let k = cur, guardCount < 64 {
            if k.name == target { return true }
            for i in k.interfaces where implements(i, target) { return true }
            cur = k.superclass
            guardCount += 1
        }
        return false
    }

    private func implements(_ i: VMClass, _ target: String) -> Bool {
        if i.name == target { return true }
        for s in i.interfaces where implements(s, target) { return true }
        return false
    }

    func instanceOf(_ o: JObject, _ type: String) -> Bool {
        if type == "Ljava/lang/Object;" { return true }
        if isSubclass(o.cls, of: type) { return true }
        if isFrameworkName(type) || !hasAppClass(type) {
            return Framework.looselyInstance(self, o, type)
        }
        return false
    }

    // MARK: - Objects

    func str(_ s: String) -> JObject {
        return JObject(cls: classFor("Ljava/lang/String;"), native: s)
    }

    func intern(_ s: String) -> JObject {
        if let o = internedStrings[s] { return o }
        let o = str(s)
        internedStrings[s] = o
        return o
    }

    func newObject(_ type: String, native: Any? = nil) -> JObject {
        return JObject(cls: classFor(type), native: native)
    }

    func throwable(_ type: String, _ message: String? = nil) -> JavaThrow {
        let o = JObject(cls: classFor(type))
        if let m = message { o.fields["__message"] = .obj(str(m)) }
        o.fields["__stack"] = .obj(str(stackTrace()))
        return JavaThrow(obj: o)
    }

    /// "at com.example.Foo.bar" lines for the innermost Java frames.
    func stackTrace(limit: Int = 6) -> String {
        return frames.suffix(limit).reversed().map {
            "    at " + VMClass.javaName($0.ref.classDesc) + "." + $0.ref.name
        }.joined(separator: "\n")
    }

    func npe(_ what: String) -> JavaThrow {
        return throwable("Ljava/lang/NullPointerException;", "Attempt to invoke '\(what)' on a null object reference")
    }

    // MARK: - Method lookup & invocation

    func findVirtual(_ cls: VMClass, _ sig: String) -> DexMethod? {
        if let m = cls.vcache[sig] { return m }
        if cls.vmiss.contains(sig) { return nil }
        var cur: VMClass? = cls
        var found: DexMethod? = nil
        while let k = cur, found == nil {
            if let m = k.dex?.methods[sig], !m.isStatic, m.code != nil { found = m }
            cur = k.superclass
        }
        if found == nil { found = findDefault(cls, sig) }
        if let f = found { cls.vcache[sig] = f } else { cls.vmiss.insert(sig) }
        return found
    }

    private func findDefault(_ cls: VMClass, _ sig: String) -> DexMethod? {
        var cur: VMClass? = cls
        while let k = cur {
            for i in k.interfaces {
                if let m = searchInterface(i, sig) { return m }
            }
            cur = k.superclass
        }
        return nil
    }

    private func searchInterface(_ i: VMClass, _ sig: String) -> DexMethod? {
        if let m = i.dex?.methods[sig], m.code != nil, !m.isStatic { return m }
        for s in i.interfaces { if let m = searchInterface(s, sig) { return m } }
        return nil
    }

    private func findStatic(_ cls: VMClass, _ sig: String) -> (DexMethod, VMClass)? {
        var cur: VMClass? = cls
        while let k = cur {
            if let m = k.dex?.methods[sig] { return (m, k) }
            cur = k.superclass
        }
        return nil
    }

    /// kind: 0 virtual, 1 super, 2 direct, 3 static, 4 interface
    func invoke(kind: Int, ref: DexMethodRef, args: [Value]) throws -> Value? {
        switch kind {
        case 3:
            let c = classFor(ref.classDesc)
            if c.isApp, let found = findStatic(c, ref.sig) {
                try ensureInit(found.1)
                if found.0.code != nil { return try execute(found.0, args) }
            }
            return try Framework.call(self, ref, this: nil, args: args)
        case 2:
            let c = classFor(ref.classDesc)
            if let m = c.dex?.methods[ref.sig], m.code != nil {
                return try execute(m, args)
            }
            guard let this = args.first?.o else { throw npe(ref.name) }
            return try Framework.call(self, ref, this: this, args: args)
        case 1:
            guard let this = args.first?.o else { throw npe(ref.name) }
            let c = classFor(ref.classDesc)
            if let m = findVirtual(c, ref.sig) { return try execute(m, args) }
            return try Framework.call(self, ref, this: this, args: args)
        default:
            guard let this = args.first?.o else { throw npe(VMClass.javaName(ref.classDesc) + "." + ref.name + "()") }
            if this.cls.isApp, let m = findVirtual(this.cls, ref.sig) {
                return try execute(m, args)
            }
            return try Framework.call(self, ref, this: this, args: args)
        }
    }

    /// Calls a virtual method on an object by name (used for lifecycle and UI callbacks).
    @discardableResult
    func call(_ obj: JObject, _ name: String, params: [String] = [], ret: String = "V", args: [Value] = []) throws -> Value? {
        let sig = name + "(" + params.joined() + ")" + ret
        let ref = DexMethodRef(classDesc: obj.cls.name, name: name, params: params, ret: ret, sig: sig)
        return try invoke(kind: 0, ref: ref, args: [.obj(obj)] + args)
    }

    /// Finds a public method by name only (for android:onClick="name").
    func callByName(_ obj: JObject, _ name: String, args: [Value]) throws {
        var cur: VMClass? = obj.cls
        while let k = cur {
            if let dc = k.dex {
                for (_, m) in dc.methods where m.ref.name == name && m.ref.params.count == args.count && m.code != nil {
                    _ = try execute(m, [.obj(obj)] + args)
                    return
                }
            }
            cur = k.superclass
        }
        warnOnce("onClick handler '\(name)' not found")
    }

    // MARK: - Interpreter

    private func findHandler(_ code: DexCode, _ pc: Int, _ ex: JObject) -> Int? {
        for t in code.tries where pc >= t.start && pc < t.end {
            for h in t.handlers {
                if let type = h.type {
                    if instanceOf(ex, type) { return h.addr }
                } else {
                    return h.addr
                }
            }
        }
        return nil
    }

    func execute(_ m: DexMethod, _ args: [Value]) throws -> Value? {
        guard let code = m.code else {
            return try Framework.call(self, m.ref, this: m.isStatic ? nil : args.first?.o, args: args)
        }
        interpretedMethodCount += 1
        depth += 1
        frames.append(m)
        defer {
            depth -= 1
            if !frames.isEmpty { frames.removeLast() }
        }
        if depth > 600 {
            throw throwable("Ljava/lang/StackOverflowError;", "stack size \(depth)")
        }

        let n = max(code.registers, 1)
        var regs = [Value](repeating: .int(0), count: n)
        let base = code.registers - code.ins
        for (i, a) in args.enumerated() where base + i >= 0 && base + i < n { regs[base + i] = a }

        let insns = code.insns
        let count = insns.count
        let dex = m.dex
        var pc = 0
        var result: Value = .int(0)
        var caught: JObject? = nil

        // Register helpers
        func R(_ r: Int) -> Value { return r < n ? regs[r] : .int(0) }
        func I(_ r: Int) -> Int32 { return R(r).i }
        func J(_ r: Int) -> Int64 { return R(r).j }
        func F(_ r: Int) -> Float { return R(r).f }
        func D(_ r: Int) -> Double { return R(r).d }
        func O(_ r: Int) -> JObject? { return R(r).o }
        func set(_ r: Int, _ v: Value) { if r < n { regs[r] = v } }
        func setI(_ r: Int, _ v: Int32) { if r < n { regs[r] = .int(v) } }
        func setW(_ r: Int, _ v: Int64) {
            if r < n { regs[r] = .wide(v) }
            if r + 1 < n { regs[r + 1] = .int(0) }
        }
        func setF(_ r: Int, _ v: Float) { set(r, .float(v)) }
        func setD(_ r: Int, _ v: Double) { setW(r, Int64(bitPattern: v.bitPattern)) }
        func unit(_ i: Int) -> Int { return i < count ? Int(insns[i]) : 0 }
        func s16(_ i: Int) -> Int { return Int(Int16(truncatingIfNeeded: unit(i))) }
        func s32(_ i: Int) -> Int { return Int(Int32(truncatingIfNeeded: unit(i) | (unit(i + 1) << 16))) }

        // MARK: arithmetic (nested so they can write registers)

        func litop(_ k: Int, dst: Int, _ a: Int32, _ b: Int32) throws {
            if k == -1 { setI(dst, b &- a); return }
            try setI(dst, VM.intOp(self, k, a, b))
        }

        func binop(_ code: Int, dst: Int, _ b: Int, _ c: Int) throws {
            switch code {
            case 0...10: try setI(dst, VM.intOp(self, code, I(b), I(c)))
            case 11...21:
                let k = code - 11
                if k >= 8 {
                    let s = Int64(I(c) & 63)
                    let x = J(b)
                    switch k {
                    case 8: setW(dst, x &<< s)
                    case 9: setW(dst, x &>> s)
                    default: setW(dst, Int64(bitPattern: UInt64(bitPattern: x) &>> UInt64(s)))
                    }
                } else {
                    try setW(dst, VM.longOp(self, k, J(b), J(c)))
                }
            case 22...26:
                let x = F(b), y = F(c)
                switch code - 22 {
                case 0: setF(dst, x + y)
                case 1: setF(dst, x - y)
                case 2: setF(dst, x * y)
                case 3: setF(dst, x / y)
                default: setF(dst, x.truncatingRemainder(dividingBy: y))
                }
            default:
                let x = D(b), y = D(c)
                switch code - 27 {
                case 0: setD(dst, x + y)
                case 1: setD(dst, x - y)
                case 2: setD(dst, x * y)
                case 3: setD(dst, x / y)
                default: setD(dst, x.truncatingRemainder(dividingBy: y))
                }
            }
        }

        while true {
            steps += 1
            if steps & 0x3ff == 0 {
                if stopped { throw VMError.stopped }
                if steps > stepLimit { throw VMError.timeout }
                if steps & 0xfffff == 0 { try checkFootprint() }
            }
            guard pc >= 0 && pc < count else {
                throw VMError.internalError("pc \(pc) out of range in \(m.ref.classDesc)->\(m.ref.name)")
            }
            let w0 = Int(insns[pc])
            let op = w0 & 0xff
            let A4 = (w0 >> 8) & 0xf
            let B4 = (w0 >> 12) & 0xf
            let AA = w0 >> 8

            do {
                switch op {
                case 0x00: pc += 1
                case 0x01, 0x07: set(A4, R(B4)); pc += 1
                case 0x02, 0x08: set(AA, R(unit(pc + 1))); pc += 2
                case 0x03, 0x09: set(unit(pc + 1), R(unit(pc + 2))); pc += 3
                case 0x04: setW(A4, J(B4)); pc += 1
                case 0x05: setW(AA, J(unit(pc + 1))); pc += 2
                case 0x06: setW(unit(pc + 1), J(unit(pc + 2))); pc += 3
                case 0x0a, 0x0c: set(AA, result); pc += 1
                case 0x0b: setW(AA, result.j); pc += 1
                case 0x0d: set(AA, .obj(caught)); pc += 1
                case 0x0e: return nil
                case 0x0f, 0x11: return R(AA)
                case 0x10: return .wide(J(AA))
                case 0x12:
                    let v = Int32(Int8(truncatingIfNeeded: B4 << 4)) >> 4
                    setI(A4, v); pc += 1
                case 0x13: setI(AA, Int32(s16(pc + 1))); pc += 2
                case 0x14: setI(AA, Int32(s32(pc + 1))); pc += 3
                case 0x15: setI(AA, Int32(truncatingIfNeeded: unit(pc + 1) << 16)); pc += 2
                case 0x16: setW(AA, Int64(s16(pc + 1))); pc += 2
                case 0x17: setW(AA, Int64(s32(pc + 1))); pc += 3
                case 0x18:
                    var v: UInt64 = 0
                    for k in 0..<4 { v |= UInt64(unit(pc + 1 + k)) << UInt64(16 * k) }
                    setW(AA, Int64(bitPattern: v)); pc += 5
                case 0x19: setW(AA, Int64(unit(pc + 1)) << 48); pc += 2
                case 0x1a: set(AA, .obj(intern(dex.string(unit(pc + 1))))); pc += 2
                case 0x1b: set(AA, .obj(intern(dex.string(unit(pc + 1) | (unit(pc + 2) << 16))))); pc += 3
                case 0x1c:
                    let t = dex.type(unit(pc + 1))
                    set(AA, .obj(newObject("Ljava/lang/Class;", native: ClassRef(name: t)))); pc += 2
                case 0x1d, 0x1e: pc += 1
                case 0x1f:
                    let t = dex.type(unit(pc + 1))
                    if let o = O(AA), !instanceOf(o, t), !isFrameworkName(t), hasAppClass(t) {
                        throw throwable("Ljava/lang/ClassCastException;", "\(o.cls.javaName) cannot be cast to \(VMClass.javaName(t))")
                    }
                    pc += 2
                case 0x20:
                    let t = dex.type(unit(pc + 1))
                    if let o = O(B4) { setI(A4, instanceOf(o, t) ? 1 : 0) } else { setI(A4, 0) }
                    pc += 2
                case 0x21:
                    guard let o = O(B4) else { throw npe("length") }
                    setI(A4, Int32((o.native as? JArray)?.count ?? 0)); pc += 1
                case 0x22:
                    let t = dex.type(unit(pc + 1))
                    let c = classFor(t)
                    try ensureInit(c)
                    set(AA, .obj(JObject(cls: c))); pc += 2
                case 0x23:
                    let t = dex.type(unit(pc + 1))
                    let size = Int(I(B4))
                    if size < 0 { throw throwable("Ljava/lang/NegativeArraySizeException;", "\(size)") }
                    try checkAllocation(type: t, count: size)
                    set(A4, .obj(newObject(t, native: JArray(type: t, count: size)))); pc += 2
                case 0x24, 0x25:
                    let t = dex.type(unit(pc + 1))
                    var vals: [Value] = []
                    if op == 0x24 {
                        let w2 = unit(pc + 2)
                        let rl = [w2 & 0xf, (w2 >> 4) & 0xf, (w2 >> 8) & 0xf, (w2 >> 12) & 0xf, A4]
                        for k in 0..<min(B4, 5) { vals.append(R(rl[k])) }
                    } else {
                        let first = unit(pc + 2)
                        for k in 0..<AA { vals.append(R(first + k)) }
                    }
                    result = .obj(newObject(t, native: JArray(type: t, items: vals)))
                    pc += 3
                case 0x26:
                    let tbl = pc + s32(pc + 1)
                    guard let arrObj = O(AA), let arr = arrObj.native as? JArray else { throw npe("fill-array-data") }
                    let width = unit(tbl + 1)
                    let size = unit(tbl + 2) | (unit(tbl + 3) << 16)
                    func byte(_ k: Int) -> Int {
                        let u = unit(tbl + 4 + k / 2)
                        return k % 2 == 0 ? (u & 0xff) : (u >> 8)
                    }
                    let et = arr.elementType
                    for e in 0..<min(size, arr.count) {
                        var raw: UInt64 = 0
                        for b in 0..<width { raw |= UInt64(byte(e * width + b)) << UInt64(8 * b) }
                        switch width {
                        case 1: arr[e] = .int(et == "Z" ? Int32(raw) : Int32(Int8(truncatingIfNeeded: raw)))
                        case 2: arr[e] = .int(et == "C" ? Int32(raw) : Int32(Int16(truncatingIfNeeded: raw)))
                        case 4: arr[e] = .int(Int32(truncatingIfNeeded: raw))
                        default: arr[e] = .wide(Int64(bitPattern: raw))
                        }
                    }
                    pc += 3
                case 0x27:
                    guard let ex = O(AA) else { throw npe("throw") }
                    if ex.fields["__stack"] == nil { ex.fields["__stack"] = .obj(str(stackTrace())) }
                    throw JavaThrow(obj: ex)
                case 0x28: pc += Int(Int8(truncatingIfNeeded: AA))
                case 0x29: pc += s16(pc + 1)
                case 0x2a: pc += s32(pc + 1)
                case 0x2b:
                    let tbl = pc + s32(pc + 1)
                    let size = unit(tbl + 1)
                    let first = s32(tbl + 2)
                    let k = Int(I(AA)) - first
                    if k >= 0 && k < size { pc += s32(tbl + 4 + k * 2) } else { pc += 3 }
                case 0x2c:
                    let tbl = pc + s32(pc + 1)
                    let size = unit(tbl + 1)
                    let v = Int(I(AA))
                    var jumped = false
                    for k in 0..<size where s32(tbl + 2 + k * 2) == v {
                        pc += s32(tbl + 2 + size * 2 + k * 2)
                        jumped = true
                        break
                    }
                    if !jumped { pc += 3 }
                case 0x2d...0x31:
                    let b = unit(pc + 1) & 0xff, c = unit(pc + 1) >> 8
                    var r: Int32 = 0
                    switch op {
                    case 0x2d, 0x2e:
                        let x = F(b), y = F(c)
                        if x.isNaN || y.isNaN { r = op == 0x2d ? -1 : 1 } else { r = x < y ? -1 : (x > y ? 1 : 0) }
                    case 0x2f, 0x30:
                        let x = D(b), y = D(c)
                        if x.isNaN || y.isNaN { r = op == 0x2f ? -1 : 1 } else { r = x < y ? -1 : (x > y ? 1 : 0) }
                    default:
                        let x = J(b), y = J(c)
                        r = x < y ? -1 : (x > y ? 1 : 0)
                    }
                    setI(AA, r); pc += 2
                case 0x32...0x37:
                    var take = false
                    switch op {
                    case 0x32: take = sameValue(R(A4), R(B4))
                    case 0x33: take = !sameValue(R(A4), R(B4))
                    case 0x34: take = I(A4) < I(B4)
                    case 0x35: take = I(A4) >= I(B4)
                    case 0x36: take = I(A4) > I(B4)
                    default: take = I(A4) <= I(B4)
                    }
                    pc += take ? s16(pc + 1) : 2
                case 0x38...0x3d:
                    var take = false
                    switch op {
                    case 0x38: take = R(AA).isZero
                    case 0x39: take = !R(AA).isZero
                    case 0x3a: take = I(AA) < 0
                    case 0x3b: take = I(AA) >= 0
                    case 0x3c: take = I(AA) > 0
                    default: take = I(AA) <= 0
                    }
                    pc += take ? s16(pc + 1) : 2
                case 0x44...0x51:
                    let b = unit(pc + 1) & 0xff, c = unit(pc + 1) >> 8
                    guard let ao = O(b), let arr = ao.native as? JArray else { throw npe("array access") }
                    let idx = Int(I(c))
                    let length = arr.count
                    guard idx >= 0 && idx < length else {
                        throw throwable("Ljava/lang/ArrayIndexOutOfBoundsException;", "length=\(length); index=\(idx)")
                    }
                    if op <= 0x4a {
                        if op == 0x45 { setW(AA, arr[idx].j) } else { set(AA, arr[idx]) }
                    } else {
                        switch op {
                        case 0x4c: arr[idx] = .wide(J(AA))
                        case 0x4d: arr[idx] = R(AA)
                        case 0x4f: arr[idx] = .int(Int32(Int8(truncatingIfNeeded: I(AA))))
                        case 0x50: arr[idx] = .int(Int32(UInt16(truncatingIfNeeded: I(AA))))
                        case 0x51: arr[idx] = .int(Int32(Int16(truncatingIfNeeded: I(AA))))
                        default: arr[idx] = .int(I(AA))
                        }
                    }
                    pc += 2
                case 0x52...0x5f:
                    let f = dex.fieldRef(unit(pc + 1))
                    guard let o = O(B4) else { throw npe("field " + f.name) }
                    if op <= 0x58 {
                        let v = o.fields[f.name] ?? Framework.instanceField(self, o, f)
                        if op == 0x53 { setW(A4, v.j) } else { set(A4, v) }
                    } else {
                        o.fields[f.name] = op == 0x5a ? .wide(J(A4)) : R(A4)
                    }
                    pc += 2
                case 0x60...0x6d:
                    let f = dex.fieldRef(unit(pc + 1))
                    if let owner = staticOwner(f) {
                        try ensureInit(owner)
                        if op <= 0x66 {
                            let v = owner.statics[f.name] ?? Value.defaultFor(f.type)
                            if op == 0x61 { setW(AA, v.j) } else { set(AA, v) }
                        } else {
                            owner.statics[f.name] = op == 0x68 ? .wide(J(AA)) : R(AA)
                        }
                    } else if op <= 0x66 {
                        let v = Framework.staticField(self, f)
                        if op == 0x61 { setW(AA, v.j) } else { set(AA, v) }
                    }
                    pc += 2
                case 0x6e...0x72, 0x74...0x78:
                    let ref = dex.methodRef(unit(pc + 1))
                    var args: [Value] = []
                    if op <= 0x72 {
                        let w2 = unit(pc + 2)
                        let rl = [w2 & 0xf, (w2 >> 4) & 0xf, (w2 >> 8) & 0xf, (w2 >> 12) & 0xf, A4]
                        for k in 0..<min(B4, 5) { args.append(R(rl[k])) }
                    } else {
                        let first = unit(pc + 2)
                        for k in 0..<AA { args.append(R(first + k)) }
                    }
                    let kind = op <= 0x72 ? op - 0x6e : op - 0x74
                    let r = try invoke(kind: kind, ref: ref, args: args)
                    result = r ?? Value.defaultFor(ref.ret)
                    pc += 3
                case 0x7b...0x8f:
                    switch op {
                    case 0x7b: setI(A4, 0 &- I(B4))
                    case 0x7c: setI(A4, ~I(B4))
                    case 0x7d: setW(A4, 0 &- J(B4))
                    case 0x7e: setW(A4, ~J(B4))
                    case 0x7f: setF(A4, -F(B4))
                    case 0x80: setD(A4, -D(B4))
                    case 0x81: setW(A4, Int64(I(B4)))
                    case 0x82: setF(A4, Float(I(B4)))
                    case 0x83: setD(A4, Double(I(B4)))
                    case 0x84: setI(A4, Int32(truncatingIfNeeded: J(B4)))
                    case 0x85: setF(A4, Float(J(B4)))
                    case 0x86: setD(A4, Double(J(B4)))
                    case 0x87: setI(A4, VM.f2i(Double(F(B4))))
                    case 0x88: setW(A4, VM.f2l(Double(F(B4))))
                    case 0x89: setD(A4, Double(F(B4)))
                    case 0x8a: setI(A4, VM.f2i(D(B4)))
                    case 0x8b: setW(A4, VM.f2l(D(B4)))
                    case 0x8c: setF(A4, Float(D(B4)))
                    case 0x8d: setI(A4, Int32(Int8(truncatingIfNeeded: I(B4))))
                    case 0x8e: setI(A4, Int32(UInt16(truncatingIfNeeded: I(B4))))
                    default: setI(A4, Int32(Int16(truncatingIfNeeded: I(B4))))
                    }
                    pc += 1
                case 0x90...0xaf:
                    let b = unit(pc + 1) & 0xff, c = unit(pc + 1) >> 8
                    try binop(op - 0x90, dst: AA, b, c)
                    pc += 2
                case 0xb0...0xcf:
                    try binop(op - 0xb0, dst: A4, A4, B4)
                    pc += 1
                case 0xd0...0xd7:
                    let lit = Int32(s16(pc + 1))
                    let ops = [0, -1, 2, 3, 4, 5, 6, 7]
                    try litop(ops[op - 0xd0], dst: A4, I(B4), lit)
                    pc += 2
                case 0xd8...0xe2:
                    let b = unit(pc + 1) & 0xff
                    let lit = Int32(Int8(truncatingIfNeeded: unit(pc + 1) >> 8))
                    let ops = [0, -1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
                    try litop(ops[op - 0xd8], dst: AA, I(b), lit)
                    pc += 2
                default:
                    let names: [Int: String] = [0xfa: "invoke-polymorphic", 0xfb: "invoke-polymorphic/range",
                                                0xfc: "invoke-custom", 0xfd: "invoke-custom/range",
                                                0xfe: "const-method-handle", 0xff: "const-method-type"]
                    throw VMError.unsupported("opcode \(names[op] ?? String(format: "0x%02x", op)) in \(VMClass.javaName(m.ref.classDesc)).\(m.ref.name)")
                }
            } catch let t as JavaThrow {
                if let h = findHandler(code, pc, t.obj) {
                    caught = t.obj
                    pc = h
                    continue
                }
                throw t
            }
        }

    }

    private func staticOwner(_ f: DexFieldRef) -> VMClass? {
        var cur: VMClass? = classFor(f.classDesc)
        while let k = cur {
            guard let dc = k.dex else { return nil }
            if dc.staticFields.contains(where: { $0.name == f.name }) { return k }
            for i in k.interfaces {
                if let idc = i.dex, idc.staticFields.contains(where: { $0.name == f.name }) { return i }
            }
            cur = k.superclass
        }
        return nil
    }

    /// Throws java.lang.OutOfMemoryError (like Android does) when an array
    /// wouldn't fit in the virtual device's heap or in this iPhone's memory.
    func checkAllocation(type: String, count: Int) throws {
        let bytes = JArray.bytes(type: type, count: count)
        let budget = HeapBudget.shared
        if !budget.canAllocate(bytes) {
            throw throwable("Ljava/lang/OutOfMemoryError;",
                            "Failed to allocate a \(bytes) byte allocation with \(budget.freeBytes) free bytes and \(budget.limit >> 20)MB heap limit")
        }
    }

    /// Long loops that build lots of small objects are checked here.
    func checkFootprint() throws {
        let fp = ProcessMemory.footprint()
        if fp > VirtualDevice.footprintLimit {
            throw throwable("Ljava/lang/OutOfMemoryError;",
                            "App is using \(ProcessMemory.megabytes(fp)); the sandbox limit on this iPhone is \(ProcessMemory.megabytes(VirtualDevice.footprintLimit))")
        }
    }

    func sameValue(_ a: Value, _ b: Value) -> Bool {
        switch (a, b) {
        case (.obj(let x), .obj(let y)): return x === y
        case (.obj(let x), _): return x == nil && b.isZero
        case (_, .obj(let y)): return y == nil && a.isZero
        default: return a.i == b.i
        }
    }

    static func intOp(_ vm: VM, _ k: Int, _ a: Int32, _ b: Int32) throws -> Int32 {
        switch k {
        case 0: return a &+ b
        case 1: return a &- b
        case 2: return a &* b
        case 3:
            if b == 0 { throw vm.throwable("Ljava/lang/ArithmeticException;", "divide by zero") }
            return a.dividedReportingOverflow(by: b).partialValue
        case 4:
            if b == 0 { throw vm.throwable("Ljava/lang/ArithmeticException;", "divide by zero") }
            return a.remainderReportingOverflow(dividingBy: b).partialValue
        case 5: return a & b
        case 6: return a | b
        case 7: return a ^ b
        case 8: return a &<< (b & 31)
        case 9: return a &>> (b & 31)
        default: return Int32(bitPattern: UInt32(bitPattern: a) &>> UInt32(b & 31))
        }
    }

    static func longOp(_ vm: VM, _ k: Int, _ a: Int64, _ b: Int64) throws -> Int64 {
        switch k {
        case 0: return a &+ b
        case 1: return a &- b
        case 2: return a &* b
        case 3:
            if b == 0 { throw vm.throwable("Ljava/lang/ArithmeticException;", "divide by zero") }
            return a.dividedReportingOverflow(by: b).partialValue
        case 4:
            if b == 0 { throw vm.throwable("Ljava/lang/ArithmeticException;", "divide by zero") }
            return a.remainderReportingOverflow(dividingBy: b).partialValue
        case 5: return a & b
        case 6: return a | b
        default: return a ^ b
        }
    }

    static func f2i(_ v: Double) -> Int32 {
        if v.isNaN { return 0 }
        if v >= Double(Int32.max) { return Int32.max }
        if v <= Double(Int32.min) { return Int32.min }
        return Int32(v)
    }

    static func f2l(_ v: Double) -> Int64 {
        if v.isNaN { return 0 }
        if v >= 9.223372036854775e18 { return Int64.max }
        if v <= -9.223372036854775e18 { return Int64.min }
        return Int64(v)
    }
}

/// java.lang.Class value.
final class ClassRef {
    let name: String
    init(name: String) { self.name = name }
}
