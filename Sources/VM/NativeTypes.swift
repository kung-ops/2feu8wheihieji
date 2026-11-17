import Foundation

// Swift-side representations of Java/Android framework objects.
// They live in JObject.native.

final class StringBuilderBox {
    var s: String
    init(_ s: String = "") { self.s = s }
}

/// java.lang.Integer / Long / Boolean / Double / Float / Character / Short / Byte
final class Boxed {
    enum Kind { case int, long, bool, double, float, char, short, byte }
    let kind: Kind
    let value: Value
    init(_ kind: Kind, _ value: Value) {
        self.kind = kind
        self.value = value
    }

    var text: String {
        switch kind {
        case .int, .short, .byte: return String(value.i)
        case .long: return String(value.j)
        case .bool: return value.i != 0 ? "true" : "false"
        case .double: return Boxed.javaDouble(value.d)
        case .float: return Boxed.javaDouble(Double(value.f))
        case .char: return String(UnicodeScalar(UInt16(truncatingIfNeeded: value.i)).map { Character($0) } ?? "?")
        }
    }

    var asDouble: Double {
        switch kind {
        case .double: return value.d
        case .float: return Double(value.f)
        case .long: return Double(value.j)
        default: return Double(value.i)
        }
    }

    static func javaDouble(_ d: Double) -> String {
        if d.isNaN { return "NaN" }
        if d.isInfinite { return d > 0 ? "Infinity" : "-Infinity" }
        if d == d.rounded() && abs(d) < 1e7 { return String(format: "%.1f", d) }
        return "\(d)"
    }
}

final class ListBox {
    var items: [Value] = []
    let isSet: Bool
    init(isSet: Bool = false, items: [Value] = []) {
        self.isSet = isSet
        self.items = items
    }
}

final class MapBox {
    var keys: [Value] = []
    var values: [Value] = []
}

final class IteratorBox {
    let items: [Value]
    var index = 0
    init(_ items: [Value]) { self.items = items }
}

final class ToastBox {
    var text: String
    init(_ t: String) { text = t }
}

final class IntentBox {
    var target: String?       // class descriptor
    var action: String?
    var extras: [String: Value] = [:]
}

final class HandlerBox {}
final class RandomBox {}
final class ResourcesBox {}
final class InflaterBox {}
final class ActionBarBox {}

final class PrintStreamBox {
    let isErr: Bool
    var pending = ""
    init(isErr: Bool) { self.isErr = isErr }
}

final class ThreadBox {
    var runnable: JObject?
}

final class PrefsBox {
    let key: String
    init(key: String) { self.key = key }
}

final class PrefsEditorBox {
    let key: String
    var pending: [String: Any] = [:]
    var removed: Set<String> = []
    var clear = false
    init(key: String) { self.key = key }
}

final class DialogBuilderBox {
    var title: String?
    var message: String?
    var buttons: [(which: Int32, text: String, listener: JObject?)] = []
    var items: [String] = []
    var itemsListener: JObject?
}

final class ActivityBox {
    weak var host: ActivityHost?
    init(host: ActivityHost) { self.host = host }
}
