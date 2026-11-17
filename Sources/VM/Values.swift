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

final class JArray {
    let type: String
    var items: [Value]
    init(type: String, items: [Value]) {
        self.type = type
        self.items = items
    }
    var elementType: String { return String(type.dropFirst()) }
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
