import UIKit

/// Result of a native framework call.
enum Ret {
    case void
    case val(Value)
    var value: Value? {
        if case .val(let v) = self { return v }
        return nil
    }
}

/// Swift implementations of the Android & Java library methods that APK
/// code calls. Unsupported, non-noop APIs fail explicitly in strict execution mode.
enum Framework {

    // MARK: - Class hierarchy guesses for framework classes

    static func superOf(_ n: String) -> String {
        let obj = "Ljava/lang/Object;"
        switch n {
        case obj: return obj
        case "Landroid/app/Activity;": return "Landroid/view/ContextThemeWrapper;"
        case "Landroid/view/ContextThemeWrapper;": return "Landroid/content/ContextWrapper;"
        case "Landroid/content/ContextWrapper;": return "Landroid/content/Context;"
        case "Landroid/content/Context;", "Landroid/view/View;", "Ljava/lang/Throwable;": return obj
        case "Landroid/view/ViewGroup;", "Landroid/widget/TextView;", "Landroid/widget/ImageView;",
             "Landroid/widget/ProgressBar;": return "Landroid/view/View;"
        case "Landroid/widget/Button;", "Landroid/widget/EditText;": return "Landroid/widget/TextView;"
        case "Landroid/widget/CompoundButton;": return "Landroid/widget/Button;"
        case "Landroid/widget/ImageButton;": return "Landroid/widget/ImageView;"
        case "Landroid/widget/AbsSeekBar;": return "Landroid/widget/ProgressBar;"
        case "Landroid/widget/LinearLayout;", "Landroid/widget/FrameLayout;", "Landroid/widget/RelativeLayout;":
            return "Landroid/view/ViewGroup;"
        case "Ljava/lang/Exception;", "Ljava/lang/Error;": return "Ljava/lang/Throwable;"
        case "Ljava/lang/RuntimeException;": return "Ljava/lang/Exception;"
        case "Ljava/lang/IllegalArgumentException;", "Ljava/lang/IllegalStateException;",
             "Ljava/lang/NullPointerException;", "Ljava/lang/ArithmeticException;",
             "Ljava/lang/ClassCastException;", "Ljava/lang/IndexOutOfBoundsException;",
             "Ljava/lang/UnsupportedOperationException;": return "Ljava/lang/RuntimeException;"
        case "Ljava/lang/NumberFormatException;": return "Ljava/lang/IllegalArgumentException;"
        case "Ljava/lang/ArrayIndexOutOfBoundsException;", "Ljava/lang/StringIndexOutOfBoundsException;":
            return "Ljava/lang/IndexOutOfBoundsException;"
        default: break
        }
        let simple = AndroidLayoutInflater.simpleName(n)
        var r = obj
        if simple.hasSuffix("Activity") { r = "Landroid/app/Activity;" }
        else if simple.contains("EditText") { r = "Landroid/widget/EditText;" }
        else if simple.contains("CheckBox") || simple.contains("Switch") || simple.contains("RadioButton") || simple.contains("ToggleButton") {
            r = "Landroid/widget/CompoundButton;"
        }
        else if simple.contains("ImageButton") || simple.contains("FloatingActionButton") { r = "Landroid/widget/ImageButton;" }
        else if simple.contains("Button") { r = "Landroid/widget/Button;" }
        else if simple.contains("TextView") { r = "Landroid/widget/TextView;" }
        else if simple.contains("ImageView") { r = "Landroid/widget/ImageView;" }
        else if simple.contains("SeekBar") { r = "Landroid/widget/AbsSeekBar;" }
        else if simple.contains("ProgressBar") { r = "Landroid/widget/ProgressBar;" }
        else if simple.contains("Layout") || simple.contains("ScrollView") || simple.contains("Group") || simple.contains("CardView") {
            r = "Landroid/view/ViewGroup;"
        }
        else if simple.hasSuffix("View") && n.hasPrefix("Landroid") { r = "Landroid/view/View;" }
        else if simple.hasSuffix("Exception") { r = "Ljava/lang/RuntimeException;" }
        else if simple.hasSuffix("Error") { r = "Ljava/lang/Error;" }
        return r == n ? obj : r
    }

    static func isViewClass(_ vm: VM, _ desc: String) -> Bool {
        return vm.isSubclass(vm.classFor(desc), of: "Landroid/view/View;")
    }

    static func looselyInstance(_ vm: VM, _ o: JObject, _ type: String) -> Bool {
        let s = type.lowercased()
        switch o.native {
        case is String:
            return ["Ljava/lang/CharSequence;", "Ljava/lang/Comparable;", "Ljava/io/Serializable;", "Ljava/lang/String;"].contains(type)
        case is StringBuilderBox:
            return s.contains("charsequence") || s.contains("stringbuilder") || s.contains("stringbuffer") || s.contains("appendable")
        case let b as Boxed:
            if type == "Ljava/lang/Number;" || s.contains("comparable") || s.contains("serializable") { return b.kind != .bool && b.kind != .char || !type.contains("Number") }
            return o.cls.name == type
        case let l as ListBox:
            return s.contains("list") || s.contains("collection") || s.contains("iterable") || s.contains("queue")
                || s.contains("deque") || (l.isSet && s.contains("set"))
        case is MapBox:
            return s.contains("map")
        case let v as ViewBox:
            if s.hasSuffix("/view;") { return true }
            switch v.kind {
            case .label: return s.contains("textview")
            case .button: return s.contains("button") || s.contains("textview")
            case .field: return s.contains("edittext") || s.contains("textview")
            case .check: return s.contains("button") || s.contains("checkbox") || s.contains("switch") || s.contains("checkable") || s.contains("textview")
            case .image: return s.contains("imageview") || s.contains("imagebutton")
            case .container: return s.contains("viewgroup") || s.contains("layout") || s.contains("scrollview") || s.contains("cardview")
                || (v.isList && (s.contains("listview") || s.contains("adapterview") || s.contains("gridview")))
            case .slider: return s.contains("seekbar") || s.contains("progressbar") || s.contains("slider")
            case .progress: return s.contains("progressbar") || s.contains("progressindicator")
            case .other: return false
            }
        case is ActivityBox:
            return s.contains("context") || s.contains("activity") || s.contains("lifecycleowner")
        case is BigIntegerBox, is DecimalBox:
            return s.contains("number") || s.contains("comparable") || s.contains("serializable") || o.cls.name == type
        case is JArray:
            return type.hasPrefix("[")
        default:
            return false
        }
    }

    // MARK: - Fields

    static func staticField(_ vm: VM, _ f: DexFieldRef) -> Value {
        let c = vm.classFor(f.classDesc)
        if let v = c.statics[f.name] { return v }
        var v: Value
        switch (f.classDesc, f.name) {
        case ("Ljava/lang/System;", "out"): v = .obj(vm.newObject("Ljava/io/PrintStream;", native: PrintStreamBox(isErr: false)))
        case ("Ljava/lang/System;", "err"): v = .obj(vm.newObject("Ljava/io/PrintStream;", native: PrintStreamBox(isErr: true)))
        case ("Landroid/os/Build$VERSION;", "SDK_INT"): v = .int(VirtualDevice.sdkInt)
        case ("Landroid/os/Build$VERSION;", "RELEASE"), ("Landroid/os/Build$VERSION;", "RELEASE_OR_CODENAME"):
            v = .obj(vm.str(VirtualDevice.release))
        case ("Landroid/os/Build$VERSION;", "CODENAME"): v = .obj(vm.str("REL"))
        case ("Landroid/os/Build;", "MODEL"), ("Landroid/os/Build;", "PRODUCT"): v = .obj(vm.str(VirtualDevice.model))
        case ("Landroid/os/Build;", "MANUFACTURER"): v = .obj(vm.str(VirtualDevice.manufacturer))
        case ("Landroid/os/Build;", "BRAND"): v = .obj(vm.str(VirtualDevice.brand))
        case ("Landroid/os/Build;", "DEVICE"), ("Landroid/os/Build;", "HARDWARE"), ("Landroid/os/Build;", "BOARD"):
            v = .obj(vm.str(VirtualDevice.device))
        case ("Landroid/os/Build;", "FINGERPRINT"):
            v = .obj(vm.str("\(VirtualDevice.brand)/\(VirtualDevice.device)/\(VirtualDevice.device):\(VirtualDevice.release)/PQ3A/1:user/release-keys"))
        case ("Landroid/os/Build;", "SUPPORTED_ABIS"), ("Landroid/os/Build;", "SUPPORTED_64_BIT_ABIS"):
            v = .obj(vm.newObject("[Ljava/lang/String;", native: JArray(type: "[Ljava/lang/String;", items: [.obj(vm.str("arm64-v8a"))])))
        case ("Landroid/os/Build;", "CPU_ABI"): v = .obj(vm.str("arm64-v8a"))
        case ("Ljava/lang/Boolean;", "TRUE"): v = .obj(vm.box(.int(1), type: "Z"))
        case ("Ljava/lang/Boolean;", "FALSE"): v = .obj(vm.box(.int(0), type: "Z"))
        case ("Ljava/math/BigDecimal;", "ZERO"), ("Ljava/math/BigInteger;", "ZERO"),
             ("Ljava/math/BigDecimal;", "ONE"), ("Ljava/math/BigInteger;", "ONE"),
             ("Ljava/math/BigDecimal;", "TEN"), ("Ljava/math/BigInteger;", "TEN"),
             ("Ljava/math/BigInteger;", "TWO"):
            let n: Decimal = f.name == "ZERO" ? 0 : (f.name == "ONE" ? 1 : (f.name == "TWO" ? 2 : 10))
            v = .obj(newDecimal(vm, n, integer: f.classDesc == "Ljava/math/BigInteger;"))
        default:
            if f.type == "Ljava/lang/String;" { v = .obj(vm.str("")) }
            else if f.type.hasPrefix("L") {
                // Placeholder; remembers its field name so enum-like constants
                // (RoundingMode.HALF_UP, Locale.US, …) can be recognised later.
                let o = vm.newObject(f.type)
                o.fields["__name"] = .obj(vm.str(f.name))
                v = .obj(o)
            }
            else { v = Value.defaultFor(f.type) }
        }
        c.statics[f.name] = v
        return v
    }

    static func instanceField(_ vm: VM, _ o: JObject, _ f: DexFieldRef) -> Value {
        // A field read on a placeholder (an Android/AndroidX object the sandbox
        // doesn't really have) gives another placeholder instead of null, so
        // chains like `getSavedStateRegistry().a.c` don't crash. It is stored so
        // later reads see the same object.
        if !o.cls.isApp, f.type.hasPrefix("L") {
            let v: Value = f.type == "Ljava/lang/String;" ? .obj(vm.str("")) : .obj(vm.newObject(f.type))
            o.fields[f.name] = v
            return v
        }
        return Value.defaultFor(f.type)
    }

    // MARK: - Calls

    /// Methods that are fine to ignore silently (lifecycle callbacks etc.).
    static let silent: Set<String> = [
        "onAnimationStart", "onAnimationEnd", "onAnimationCancel", "onAnimationRepeat", "onAnimationPause",
        "onAnimationResume", "onAnimationUpdate", "onTransitionStart", "onTransitionEnd", "onTransitionCancel",
        "onTransitionPause", "onTransitionResume",
        "<init>", "onCreate", "onStart", "onResume", "onPause", "onStop", "onDestroy", "onRestart",
        "onPostCreate", "onPostResume", "onSaveInstanceState", "onRestoreInstanceState",
        "onWindowFocusChanged", "onAttachedToWindow", "onContentChanged", "onConfigurationChanged",
        "onUserInteraction", "onNewIntent", "onActivityResult", "onRequestPermissionsResult",
        "onCreateOptionsMenu", "onOptionsItemSelected", "onPrepareOptionsMenu", "onLowMemory",
        "onTrimMemory", "attachBaseContext", "onKeyDown", "onKeyUp", "onTouchEvent", "onSupportNavigateUp",
        "checkNotNull", "checkNotNullParameter", "checkNotNullExpressionValue", "checkParameterIsNotNull",
        "checkExpressionValueIsNotNull", "checkFieldIsNotNull", "enable", "setOnApplyWindowInsetsListener",
        "setSupportActionBar", "setDisplayHomeAsUpEnabled", "setLayoutParams", "setTypeface", "requestFocus",
        "invalidate", "requestLayout", "setContentDescription", "setTheme", "setRequestedOrientation",
        "overridePendingTransition", "setElevation", "setScaleType", "setAdjustViewBounds", "setInputType",
        "setMaxLines", "setLines", "setSingleLine", "setAllCaps", "setClickable", "setFocusable",
        "setOnLongClickListener", "setOnTouchListener", "setTextAlignment", "setBackgroundResource",
        "setBackground", "setImageDrawable", "setImageBitmap", "setSelection", "setError", "setMovementMethod",
        "addTextChangedListener", "setOnEditorActionListener", "setFlags", "addFlags", "clearFlags",
        "setStatusBarColor", "setNavigationBarColor", "setSoftInputMode", "setCancelable", "setIcon",
        "setCanceledOnTouchOutside", "setDuration", "setGravity", "dismiss", "cancel", "printStackTrace",
        "sleep", "setDefaultNightMode", "installSplashScreen", "setKeepOnScreenCondition", "getInsets",
        "setPadding", "setMinimumHeight", "setMinimumWidth", "setHintTextColor", "setLetterSpacing"
    ]

    static func call(_ vm: VM, _ ref: DexMethodRef, this: JObject?, args raw: [Value]) throws -> Value? {
        var a: [Value] = []
        var i = this == nil ? 0 : 1
        for p in ref.params {
            a.append(i < raw.count ? raw[i] : .zero)
            i += (p == "J" || p == "D") ? 2 : 1
        }
        if let t = this {
            if let r = try instanceCall(vm, t, ref, a) { return r.value }
        } else {
            if let r = try staticCall(vm, ref, a) { return r.value }
        }
        let api = "\(VMClass.javaName(ref.classDesc)).\(ref.sig)"
        if !silent.contains(ref.name) {
            let message = "Unsupported Android API: " + api
            vm.warnOnce(message)
            if vm.strictRealApkMode { throw VMError.unsupported(message) }
        } else {
            vm.warnOnce("Compatibility no-op: " + api)
        }
        vm.stubCallCount += 1
        return stub(vm, ref)
    }

    static func stub(_ vm: VM, _ ref: DexMethodRef) -> Value? {
        let r = ref.ret
        switch r.first {
        case "V": return nil
        case "J", "D": return .wide(0)
        case "L":
            if r == "Ljava/lang/String;" || r == "Ljava/lang/CharSequence;" { return .obj(vm.str("")) }
            return .obj(vm.newObject(r))
        case "[": return .obj(vm.newObject(r, native: JArray(type: r, items: [])))
        default: return .int(0)
        }
    }

    // MARK: helpers

    static func S(_ vm: VM, _ s: String) -> Ret { return .val(.obj(vm.str(s))) }
    static func I(_ v: Int32) -> Ret { return .val(.int(v)) }
    static func B(_ v: Bool) -> Ret { return .val(.int(v ? 1 : 0)) }
    static func O(_ o: JObject?) -> Ret { return .val(.obj(o)) }

    static func resId(_ v: Value) -> Int { return Int(UInt32(bitPattern: v.i)) }

    static func resString(_ vm: VM, _ v: Value) -> String {
        return vm.apk.resources?.string(resId(v)) ?? ""
    }

    static func resColor(_ vm: VM, _ v: Value) -> Int32 {
        guard let res = vm.apk.resources, let raw = res.value(resId(v)) else { return Int32(bitPattern: 0xff000000) }
        let r = res.resolve(raw)
        return r.isColor ? Int32(truncatingIfNeeded: r.data) : Int32(bitPattern: 0xff000000)
    }

    /// Text argument that may be a CharSequence or a string resource id.
    static func text(_ vm: VM, _ v: Value, _ type: String) throws -> String {
        if type == "I" { return resString(vm, v) }
        guard let o = v.o else { return "" }
        return try vm.stringOf(o)
    }

    static func varargs(_ v: Value) -> [JObject?] {
        return (v.o?.native as? JArray)?.items.map { $0.o } ?? []
    }

    static func units(_ s: String) -> [UInt16] { return Array(s.utf16) }
    static func fromUnits<C: Collection>(_ u: C) -> String where C.Element == UInt16 { return String(decoding: u, as: UTF16.self) }

    static func numberFormat(_ vm: VM, _ s: String) -> JavaThrow {
        return vm.throwable("Ljava/lang/NumberFormatException;", "For input string: \"\(s)\"")
    }

    static func parseInt(_ vm: VM, _ s: String?, radix: Int = 10) throws -> Int32 {
        guard let s = s else { throw numberFormat(vm, "null") }
        let t = s.hasPrefix("+") ? String(s.dropFirst()) : s
        guard (2...36).contains(radix), let v = Int32(t, radix: radix) else { throw numberFormat(vm, s) }
        return v
    }

    static func parseDouble(_ vm: VM, _ s: String?) throws -> Double {
        guard let s = s, let d = Double(s.trimmingCharacters(in: .whitespaces)) else { throw numberFormat(vm, s ?? "null") }
        return d
    }

    static func javaSplit(_ s: String, _ regex: String, limit: Int) -> [String] {
        let ns = s as NSString
        guard let re = try? NSRegularExpression(pattern: regex) else { return [s] }
        let matches = re.matches(in: s, range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty { return [s] }
        var parts: [String] = []
        var last = 0
        for m in matches {
            if limit > 0 && parts.count == limit - 1 { break }
            if m.range.length == 0 && m.range.location == 0 { continue }
            parts.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
        }
        parts.append(ns.substring(from: last))
        if limit == 0 {
            while let l = parts.last, l.isEmpty { parts.removeLast() }
        }
        return parts
    }

    static func schedule(_ vm: VM, _ r: JObject, delayMs: Int64) {
        let key = ObjectIdentifier(r)
        let gen = vm.runnableGeneration[key] ?? 0
        let ms = Int(max(0, min(delayMs, 86_400_000)))
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) { [weak vm] in
            guard let vm = vm else { return }
            vm.post("runnable") { [weak vm] in
                guard let vm = vm, (vm.runnableGeneration[key] ?? 0) == gen else { return }
                try vm.call(r, "run")
            }
        }
    }

    static func cancel(_ vm: VM, _ r: JObject?) {
        if let r = r {
            let key = ObjectIdentifier(r)
            vm.runnableGeneration[key] = (vm.runnableGeneration[key] ?? 0) + 1
        } else {
            for k in vm.runnableGeneration.keys { vm.runnableGeneration[k] = (vm.runnableGeneration[k] ?? 0) + 1 }
        }
    }

    static func sortValues(_ vm: VM, _ items: inout [Value], comparator: JObject?) throws {
        // insertion sort so the Java comparator may throw
        if items.count < 2 { return }
        for i in 1..<items.count {
            let x = items[i]
            var j = i - 1
            while j >= 0 {
                let c = try compare(vm, items[j], x, comparator)
                if c <= 0 { break }
                items[j + 1] = items[j]
                j -= 1
            }
            items[j + 1] = x
        }
    }

    static func compare(_ vm: VM, _ a: Value, _ b: Value, _ comparator: JObject?) throws -> Int32 {
        if let c = comparator {
            return try vm.call(c, "compare", params: ["Ljava/lang/Object;", "Ljava/lang/Object;"], ret: "I", args: [a, b])?.i ?? 0
        }
        if let x = a.o?.native as? String, let y = b.o?.native as? String { return x < y ? -1 : (x > y ? 1 : 0) }
        if let x = a.o?.native as? Boxed, let y = b.o?.native as? Boxed {
            let p = x.asDouble, q = y.asDouble
            return p < q ? -1 : (p > q ? 1 : 0)
        }
        if let x = a.o?.native as? BigIntegerBox, let y = b.o?.native as? BigIntegerBox { return Int32(x.value.compare(y.value)) }
        if case .obj(let o) = a, let ao = o, ao.cls.isApp {
            return try vm.call(ao, "compareTo", params: ["Ljava/lang/Object;"], ret: "I", args: [b])?.i ?? 0
        }
        switch (a, b) {
        case (.wide(let x), .wide(let y)): return x < y ? -1 : (x > y ? 1 : 0)
        default: return a.i < b.i ? -1 : (a.i > b.i ? 1 : 0)
        }
    }
}
