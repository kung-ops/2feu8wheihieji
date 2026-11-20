import Foundation

/// A Dalvik register value. Wide (long/double) values live in the first
/// register of a pair; floats/doubles are stored as raw bit patterns.
enum Value {
    case int(Int32)
    case wide(Int64)
    case obj(JObject?)

    static let null = Value.obj(nil)
    static let zero = Value.int(0)

    var i: Int32 {
        switch self {
        case .int(let v): return v
        case .wide(let v): return Int32(truncatingIfNeeded: v)
        case .obj(let o): return o == nil ? 0 : 1
        }
    }
    var j: Int64 {
        switch self {
        case .wide(let v): return v
        case .int(let v): return Int64(v)
        case .obj: return 0
        }
    }
    var f: Float { return Float(bitPattern: UInt32(bitPattern: i)) }
    var d: Double { return Double(bitPattern: UInt64(bitPattern: j)) }
    var o: JObject? {
        if case .obj(let x) = self { return x }
        return nil
    }
    var isZero: Bool {
        switch self {
        case .int(let v): return v == 0
        case .wide(let v): return v == 0
        case .obj(let x): return x == nil
        }
    }

    static func float(_ v: Float) -> Value { return .int(Int32(bitPattern: v.bitPattern)) }
    static func double(_ v: Double) -> Value { return .wide(Int64(bitPattern: v.bitPattern)) }
    static func bool(_ v: Bool) -> Value { return .int(v ? 1 : 0) }

    /// Default value for a field/array element of the given type descriptor.
    static func defaultFor(_ type: String) -> Value {
        switch type.first {
        case "J", "D": return .wide(0)
        case "L", "[": return .null
        case nil: return .null
        default: return .int(0)
        }
    }
}

/// A Java array. Primitive arrays are stored compactly (a byte[] costs one
/// byte per element, not a 16-byte `Value`), which matters on 1 GB iPhones.
/// Every array is counted against the VM heap budget (see `HeapBudget`).
final class JArray {
    enum Storage {
        case refs([Value])      // objects and arrays of arrays
        case bytes([Int8])      // byte[] and boolean[]
        case chars([UInt16])    // char[]
        case shorts([Int16])    // short[]
        case ints([Int32])      // int[] and float[] (raw bits)
        case longs([Int64])     // long[] and double[] (raw bits)
    }

    let type: String
    private(set) var storage: Storage

    /// A zero-filled array of `count` elements.
    init(type: String, count: Int) {
        self.type = type
        let n = max(0, count)
        switch type.dropFirst().first {
        case "B", "Z": storage = .bytes([Int8](repeating: 0, count: n))
        case "C": storage = .chars([UInt16](repeating: 0, count: n))
        case "S": storage = .shorts([Int16](repeating: 0, count: n))
        case "I", "F": storage = .ints([Int32](repeating: 0, count: n))
        case "J", "D": storage = .longs([Int64](repeating: 0, count: n))
        default: storage = .refs([Value](repeating: .null, count: n))
        }
        HeapBudget.shared.add(JArray.bytes(type: type, count: n))
    }

    convenience init(type: String, items: [Value]) {
        self.init(type: type, count: 0)
        self.items = items
    }

    /// A byte[] holding `bytes`.
    convenience init(bytes: [UInt8]) {
        self.init(type: "[B", count: 0)
        storage = .bytes(bytes.map { Int8(bitPattern: $0) })
        HeapBudget.shared.add(bytes.count)
    }

    /// Writes `bytes` into a byte[] starting at `offset` (clipped to the array).
    func setBytes(_ bytes: ArraySlice<UInt8>, at offset: Int) {
        guard case .bytes(var a) = storage else {
            for (k, b) in bytes.enumerated() where offset + k < count { self[offset + k] = .int(Int32(Int8(bitPattern: b))) }
            return
        }
        storage = .refs([])
        for (k, b) in bytes.enumerated() where offset + k < a.count { a[offset + k] = Int8(bitPattern: b) }
        storage = .bytes(a)
    }

    deinit { HeapBudget.shared.remove(currentBytes) }

    /// Bytes of storage a `type` array of `count` elements needs.
    static func bytes(type: String, count: Int) -> Int {
        let n = max(0, count)
        switch type.dropFirst().first {
        case "B", "Z": return 32 + n
        case "C", "S": return 32 + n * 2
        case "I", "F": return 32 + n * 4
        case "J", "D": return 32 + n * 8
        default: return 32 + n * MemoryLayout<Value>.stride
        }
    }

    private var currentBytes: Int { return JArray.bytes(type: type, count: count) }

    var elementType: String { return String(type.dropFirst()) }

    var count: Int {
        switch storage {
        case .refs(let a): return a.count
        case .bytes(let a): return a.count
        case .chars(let a): return a.count
        case .shorts(let a): return a.count
        case .ints(let a): return a.count
        case .longs(let a): return a.count
        }
    }

    /// Element access with Java widening/narrowing (no bounds check).
    subscript(i: Int) -> Value {
        get {
            switch storage {
            case .refs(let a): return a[i]
            case .bytes(let a): return .int(Int32(a[i]))
            case .chars(let a): return .int(Int32(a[i]))
            case .shorts(let a): return .int(Int32(a[i]))
            case .ints(let a): return .int(a[i])
            case .longs(let a): return .wide(a[i])
            }
        }
        set {
            switch storage {
            case .refs(var a):
                storage = .bytes([])   // drop the reference so `a` is uniquely owned
                a[i] = newValue
                storage = .refs(a)
            case .bytes(var a):
                storage = .refs([])
                a[i] = Int8(truncatingIfNeeded: newValue.i)
                storage = .bytes(a)
            case .chars(var a):
                storage = .refs([])
                a[i] = UInt16(truncatingIfNeeded: newValue.i)
                storage = .chars(a)
            case .shorts(var a):
                storage = .refs([])
                a[i] = Int16(truncatingIfNeeded: newValue.i)
                storage = .shorts(a)
            case .ints(var a):
                storage = .refs([])
                a[i] = newValue.i
                storage = .ints(a)
            case .longs(var a):
                storage = .refs([])
                a[i] = newValue.j
                storage = .longs(a)
            }
        }
    }

    /// All elements as `Value`s (a copy). Setting replaces the contents
    /// (and the length) of the array.
    var items: [Value] {
        get {
            switch storage {
            case .refs(let a): return a
            case .bytes(let a): return a.map { .int(Int32($0)) }
            case .chars(let a): return a.map { .int(Int32($0)) }
            case .shorts(let a): return a.map { .int(Int32($0)) }
            case .ints(let a): return a.map { .int($0) }
            case .longs(let a): return a.map { .wide($0) }
            }
        }
        set {
            let before = currentBytes
            switch type.dropFirst().first {
            case "B", "Z": storage = .bytes(newValue.map { Int8(truncatingIfNeeded: $0.i) })
            case "C": storage = .chars(newValue.map { UInt16(truncatingIfNeeded: $0.i) })
            case "S": storage = .shorts(newValue.map { Int16(truncatingIfNeeded: $0.i) })
            case "I", "F": storage = .ints(newValue.map { $0.i })
            case "J", "D": storage = .longs(newValue.map { $0.j })
            default: storage = .refs(newValue)
            }
            let after = currentBytes
            if after != before { HeapBudget.shared.add(after - before) }
        }
    }

    /// The array as UTF-16 code units (for char[] → String).
    var utf16: [UInt16] {
        if case .chars(let a) = storage { return a }
        return items.map { UInt16(truncatingIfNeeded: $0.i) }
    }

    /// The array as raw bytes (for byte[] → String, streams, images).
    var byteValues: [UInt8] {
        if case .bytes(let a) = storage { return a.map { UInt8(bitPattern: $0) } }
        return items.map { UInt8(truncatingIfNeeded: $0.i) }
    }

    /// Copies `len` elements from `src[sp...]` to `self[dp...]` (System.arraycopy;
    /// overlapping copies within one array behave like Java's).
    func copy(from src: JArray, _ sp: Int, to dp: Int, count len: Int) {
        if len <= 0 { return }
        switch (src.storage, storage) {
        case (.bytes(let s), .bytes(var d)):
            storage = .refs([])
            d.replaceSubrange(dp..<(dp + len), with: s[sp..<(sp + len)])
            storage = .bytes(d)
        case (.chars(let s), .chars(var d)):
            storage = .refs([])
            d.replaceSubrange(dp..<(dp + len), with: s[sp..<(sp + len)])
            storage = .chars(d)
        case (.ints(let s), .ints(var d)):
            storage = .refs([])
            d.replaceSubrange(dp..<(dp + len), with: s[sp..<(sp + len)])
            storage = .ints(d)
        case (.longs(let s), .longs(var d)):
            storage = .refs([])
            d.replaceSubrange(dp..<(dp + len), with: s[sp..<(sp + len)])
            storage = .longs(d)
        case (.refs(let s), .refs(var d)):
            storage = .bytes([])
            d.replaceSubrange(dp..<(dp + len), with: s[sp..<(sp + len)])
            storage = .refs(d)
        default:
            let tmp = (0..<len).map { src[sp + $0] }
            for k in 0..<len { self[dp + k] = tmp[k] }
        }
    }

    /// Sets elements `from..<to` to `v`.
    func fill(_ v: Value, from: Int, to: Int) {
        guard from < to else { return }
        for k in from..<to { self[k] = v }
    }
}

/// A Java object. App objects keep fields in `fields`; framework objects
/// (strings, views, lists...) keep a Swift representation in `native`.
final class JObject {
    let cls: VMClass
    var fields: [String: Value] = [:]
    var native: Any?

    init(cls: VMClass, native: Any? = nil) {
        self.cls = cls
        self.native = native
    }

    var string: String? { return native as? String }
}

final class VMClass {
    let name: String
    let dex: DexClass?
    var superclass: VMClass?
    var interfaces: [VMClass] = []
    var statics: [String: Value] = [:]
    var initState = 0
    var vcache: [String: DexMethod] = [:]
    var vmiss: Set<String> = []

    init(name: String, dex: DexClass?) {
        self.name = name
        self.dex = dex
    }

    var isApp: Bool { return dex != nil }

    /// "com.example.Foo" from "Lcom/example/Foo;"
    var javaName: String { return VMClass.javaName(name) }

    static func javaName(_ desc: String) -> String {
        if desc.hasPrefix("L") && desc.hasSuffix(";") {
            return String(desc.dropFirst().dropLast()).replacingOccurrences(of: "/", with: ".")
        }
        return desc
    }

    static func descriptor(_ javaName: String) -> String {
        return "L" + javaName.replacingOccurrences(of: ".", with: "/") + ";"
    }
}

/// A Java exception travelling up the Swift call stack.
struct JavaThrow: Error {
    let obj: JObject
}

enum VMError: Error, CustomStringConvertible {
    case unsupported(String)
    case stopped
    case timeout
    case internalError(String)

    var description: String {
        switch self {
        case .unsupported(let s): return "Unsupported: \(s)"
        case .stopped: return "Stopped"
        case .timeout: return "Gave up: code ran too long without returning (possible infinite loop)"
        case .internalError(let s): return "Interpreter error: \(s)"
        }
    }
}
