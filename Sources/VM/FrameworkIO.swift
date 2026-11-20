import Foundation

// java.io byte streams that live in memory or wrap other streams:
// ByteArrayOutputStream / ByteArrayInputStream, DataOutputStream /
// DataInputStream (with Java's modified UTF-8), BufferedInput/OutputStream.
// File streams (FileStreamBox) and the app's own InputStream/OutputStream
// subclasses can sit underneath.

/// ByteArrayOutputStream
final class ByteOutBox {
    var data: [UInt8] = []
}

/// ByteArrayInputStream
final class ByteInBox {
    let data: [UInt8]
    var pos: Int
    var mark: Int
    let end: Int
    init(_ data: [UInt8], offset: Int = 0, length: Int? = nil) {
        self.data = data
        pos = max(0, min(offset, data.count))
        mark = pos
        end = min(data.count, pos + max(0, length ?? data.count))
    }
}

/// DataOutputStream, BufferedOutputStream… (writing) or DataInputStream,
/// BufferedInputStream… (reading) around another stream.
final class StreamWrapBox {
    let target: JObject?
    let output: Bool
    var written = 0
    var pushback: [UInt8] = []
    init(target: JObject?, output: Bool) {
        self.target = target
        self.output = output
    }
}

extension Framework {

    static let outputWrappers: Set<String> = [
        "Ljava/io/DataOutputStream;", "Ljava/io/BufferedOutputStream;", "Ljava/io/FilterOutputStream;"
    ]
    static let inputWrappers: Set<String> = [
        "Ljava/io/DataInputStream;", "Ljava/io/BufferedInputStream;", "Ljava/io/FilterInputStream;",
        "Ljava/io/PushbackInputStream;"
    ]

    static func ioConstruct(_ vm: VM, _ t: JObject, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        let c = ref.classDesc
        switch c {
        case "Ljava/io/ByteArrayOutputStream;":
            t.native = ByteOutBox()
            return .void
        case "Ljava/io/ByteArrayInputStream;":
            guard let arr = a.first?.o?.native as? JArray else { throw vm.npe("ByteArrayInputStream") }
            if ref.params.count == 3 {
                t.native = ByteInBox(arr.byteValues, offset: Int(a[1].i), length: Int(a[2].i))
            } else {
                t.native = ByteInBox(arr.byteValues)
            }
            return .void
        default:
            if outputWrappers.contains(c) || inputWrappers.contains(c) {
                t.native = StreamWrapBox(target: a.first?.o, output: outputWrappers.contains(c))
                return .void
            }
            return nil
        }
    }

    // MARK: - Moving bytes

    /// Sends bytes to an output stream of any kind.
    static func streamWrite(_ vm: VM, _ out: JObject?, _ bytes: [UInt8]) throws {
        guard let o = out else { throw vm.npe("OutputStream.write") }
        switch o.native {
        case let b as ByteOutBox:
            b.data += bytes
            HeapBudget.shared.add(bytes.count)
        case let f as FileStreamBox:
            f.data += bytes
        case let w as StreamWrapBox:
            w.written += bytes.count
            try streamWrite(vm, w.target, bytes)
        case let p as PrintStreamBox:
            p.pending += String(decoding: bytes, as: UTF8.self)
        default:
            // The app's own OutputStream subclass.
            let arr = vm.newObject("[B", native: JArray(bytes: bytes))
            try vm.call(o, "write", params: ["[B", "I", "I"], args: [.obj(arr), .zero, .int(Int32(bytes.count))])
        }
    }

    /// Reads up to `max` bytes (fewer at the end of the stream; empty = end).
    static func streamRead(_ vm: VM, _ src: JObject?, _ max: Int) throws -> [UInt8] {
        guard let o = src else { throw vm.npe("InputStream.read") }
        guard max > 0 else { return [] }
        switch o.native {
        case let b as ByteInBox:
            let n = Swift.min(max, b.end - b.pos)
            guard n > 0 else { return [] }
            defer { b.pos += n }
            return Array(b.data[b.pos..<(b.pos + n)])
        case let f as FileStreamBox:
            let n = Swift.min(max, f.data.count - f.position)
            guard n > 0 else { return [] }
            defer { f.position += n }
            return Array(f.data[f.position..<(f.position + n)])
        case let w as StreamWrapBox:
            var out: [UInt8] = []
            if !w.pushback.isEmpty {
                let k = Swift.min(max, w.pushback.count)
                out = Array(w.pushback.prefix(k))
                w.pushback.removeFirst(k)
                if out.count == max { return out }
            }
            return out + (try streamRead(vm, w.target, max - out.count))
        default:
            // The app's own InputStream subclass: one byte at a time.
            var out: [UInt8] = []
            while out.count < max {
                let v = try vm.call(o, "read", ret: "I")?.i ?? -1
                if v < 0 { break }
                out.append(UInt8(truncatingIfNeeded: v))
            }
            return out
        }
    }

    static func readFully(_ vm: VM, _ src: JObject?, _ n: Int) throws -> [UInt8] {
        var out: [UInt8] = []
        while out.count < n {
            let part = try streamRead(vm, src, n - out.count)
            if part.isEmpty { throw vm.throwable("Ljava/io/EOFException;") }
            out += part
        }
        return out
    }

    // MARK: - Modified UTF-8 (DataOutput.writeUTF)

    static func modifiedUTF8(_ s: String) -> [UInt8] {
        var out: [UInt8] = []
        for u in s.utf16 {
            if u != 0 && u < 0x80 {
                out.append(UInt8(u))
            } else if u < 0x800 {
                out.append(UInt8(0xc0 | (u >> 6)))
                out.append(UInt8(0x80 | (u & 0x3f)))
            } else {
                out.append(UInt8(0xe0 | (u >> 12)))
                out.append(UInt8(0x80 | ((u >> 6) & 0x3f)))
                out.append(UInt8(0x80 | (u & 0x3f)))
            }
        }
        return out
    }

    static func decodeModifiedUTF8(_ vm: VM, _ b: [UInt8]) throws -> String {
        var units: [UInt16] = []
        var i = 0
        func bad() -> JavaThrow { return vm.throwable("Ljava/io/UTFDataFormatException;", "malformed input around byte \(i)") }
        while i < b.count {
            let c = b[i]
            if c < 0x80 {
                units.append(UInt16(c)); i += 1
            } else if c & 0xe0 == 0xc0 {
                guard i + 1 < b.count, b[i + 1] & 0xc0 == 0x80 else { throw bad() }
                units.append(UInt16(c & 0x1f) << 6 | UInt16(b[i + 1] & 0x3f)); i += 2
            } else if c & 0xf0 == 0xe0 {
                guard i + 2 < b.count, b[i + 1] & 0xc0 == 0x80, b[i + 2] & 0xc0 == 0x80 else { throw bad() }
                units.append(UInt16(c & 0x0f) << 12 | UInt16(b[i + 1] & 0x3f) << 6 | UInt16(b[i + 2] & 0x3f)); i += 3
            } else {
                throw bad()
            }
        }
        return String(decoding: units, as: UTF16.self)
    }

    static func bigEndian<T: FixedWidthInteger>(_ v: T) -> [UInt8] {
        return (0..<MemoryLayout<T>.size).reversed().map { UInt8(truncatingIfNeeded: v >> ($0 * 8)) }
    }

    static func fromBigEndian(_ b: [UInt8]) -> UInt64 {
        return b.reduce(0) { ($0 << 8) | UInt64($1) }
    }

    // MARK: - Methods

    static func ioMethod(_ vm: VM, _ t: JObject, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        switch t.native {
        case let b as ByteOutBox: return try byteOutMethod(vm, t, b, ref, a)
        case let b as ByteInBox: return try inputMethod(vm, t, ref, a, mark: { b.mark = b.pos }, reset: { b.pos = b.mark },
                                                         available: b.end - b.pos)
        case let w as StreamWrapBox:
            if w.output { return try dataOutMethod(vm, t, w, ref, a) }
            return try dataInMethod(vm, t, w, ref, a)
        default: return nil
        }
    }

    static func bytesArg(_ ref: DexMethodRef, _ a: [Value]) -> [UInt8]? {
        guard let arr = a.first?.o?.native as? JArray else { return nil }
        var bytes = arr.byteValues
        if ref.params.count == 3 {
            let off = max(0, min(Int(a[1].i), bytes.count)), len = max(0, min(Int(a[2].i), bytes.count - off))
            bytes = Array(bytes[off..<(off + len)])
        }
        return bytes
    }

    static func byteOutMethod(_ vm: VM, _ t: JObject, _ b: ByteOutBox, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        switch ref.name {
        case "write", "writeBytes":
            if ref.params.first == "I" { b.data.append(UInt8(truncatingIfNeeded: a[0].i)) }
            else if let bytes = bytesArg(ref, a) { b.data += bytes }
            return .void
        case "toByteArray": return O(vm.newObject("[B", native: JArray(bytes: b.data)))
        case "size": return I(Int32(b.data.count))
        case "reset": b.data.removeAll(); return .void
        case "toString": return S(vm, String(decoding: b.data, as: UTF8.self))
        case "writeTo": try streamWrite(vm, a[0].o, b.data); return .void
        case "close", "flush": return .void
        default: return nil
        }
    }

    /// read()/read(byte[])/skip/available… shared by the input streams.
    static func inputMethod(_ vm: VM, _ t: JObject, _ ref: DexMethodRef, _ a: [Value],
                            mark: () -> Void, reset: () -> Void, available: Int) throws -> Ret? {
        switch ref.name {
        case "read":
            if ref.params.isEmpty {
                let one = try streamRead(vm, t, 1)
                return I(one.first.map { Int32($0) } ?? -1)
            }
            guard let arr = a[0].o?.native as? JArray else { throw vm.npe("read") }
            let off = ref.params.count == 3 ? max(0, Int(a[1].i)) : 0
            let len = ref.params.count == 3 ? max(0, Int(a[2].i)) : arr.count
            if len == 0 { return I(0) }
            let got = try streamRead(vm, t, min(len, arr.count - off))
            if got.isEmpty { return I(-1) }
            arr.setBytes(got[...], at: off)
            return I(Int32(got.count))
        case "readAllBytes":
            var all: [UInt8] = []
            while true {
                let part = try streamRead(vm, t, 65536)
                if part.isEmpty { break }
                all += part
            }
            return O(vm.newObject("[B", native: JArray(bytes: all)))
        case "skip":
            let n = try streamRead(vm, t, Int(max(0, min(a[0].j, Int64(Int32.max))))).count
            return .val(.wide(Int64(n)))
        case "available": return I(Int32(max(0, available)))
        case "mark": mark(); return .void
        case "reset": reset(); return .void
        case "markSupported": return B(true)
        case "close": return .void
        default: return nil
        }
    }

    static func dataOutMethod(_ vm: VM, _ t: JObject, _ w: StreamWrapBox, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        var bytes: [UInt8]
        switch ref.name {
        case "write":
            if ref.params.first == "I" { bytes = [UInt8(truncatingIfNeeded: a[0].i)] }
            else { bytes = bytesArg(ref, a) ?? [] }
        case "writeBoolean": bytes = [a[0].i != 0 ? 1 : 0]
        case "writeByte": bytes = [UInt8(truncatingIfNeeded: a[0].i)]
        case "writeShort", "writeChar": bytes = bigEndian(UInt16(truncatingIfNeeded: a[0].i))
        case "writeInt": bytes = bigEndian(a[0].i)
        case "writeLong": bytes = bigEndian(a[0].j)
        case "writeFloat": bytes = bigEndian(a[0].f.bitPattern)
        case "writeDouble": bytes = bigEndian(a[0].d.bitPattern)
        case "writeBytes": bytes = try vm.stringOf(a[0].o).utf16.map { UInt8(truncatingIfNeeded: $0) }
        case "writeChars": bytes = try vm.stringOf(a[0].o).utf16.flatMap { bigEndian($0) }
        case "writeUTF":
            let body = modifiedUTF8(try vm.stringOf(a[0].o))
            guard body.count <= 65535 else {
                throw vm.throwable("Ljava/io/UTFDataFormatException;", "encoded string too long: \(body.count) bytes")
            }
            bytes = bigEndian(UInt16(body.count)) + body
        case "size": return I(Int32(truncatingIfNeeded: w.written))
        case "flush":
            if let f = w.target?.native as? FileStreamBox, f.writing {
                FileManager.default.createFile(atPath: f.path, contents: Data(f.data))
            }
            return .void
        case "close":
            if let target = w.target, target.native is FileStreamBox || target.native is StreamWrapBox {
                _ = try vm.call(target, "close")
            }
            return .void
        default: return nil
        }
        try streamWrite(vm, t, bytes)
        return .void
    }

    static func dataInMethod(_ vm: VM, _ t: JObject, _ w: StreamWrapBox, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        func n(_ k: Int) throws -> UInt64 { return fromBigEndian(try readFully(vm, t, k)) }
        switch ref.name {
        case "readFully":
            guard let arr = a[0].o?.native as? JArray else { throw vm.npe("readFully") }
            let off = ref.params.count == 3 ? max(0, Int(a[1].i)) : 0
            let len = ref.params.count == 3 ? max(0, Int(a[2].i)) : arr.count
            arr.setBytes(try readFully(vm, t, len)[...], at: off)
            return .void
        case "readBoolean": return B(try n(1) != 0)
        case "readByte": return I(Int32(Int8(truncatingIfNeeded: try n(1))))
        case "readUnsignedByte": return I(Int32(try n(1)))
        case "readShort": return I(Int32(Int16(truncatingIfNeeded: try n(2))))
        case "readUnsignedShort", "readChar": return I(Int32(try n(2)))
        case "readInt": return I(Int32(truncatingIfNeeded: try n(4)))
        case "readLong": return .val(.wide(Int64(bitPattern: try n(8))))
        case "readFloat": return .val(.float(Float(bitPattern: UInt32(truncatingIfNeeded: try n(4)))))
        case "readDouble": return .val(.double(Double(bitPattern: try n(8))))
        case "readUTF":
            let len = Int(try n(2))
            return S(vm, try decodeModifiedUTF8(vm, try readFully(vm, t, len)))
        case "readLine":
            var line: [UInt8] = []
            var any = false
            while true {
                let b = try streamRead(vm, t, 1)
                guard let c = b.first else { break }
                any = true
                if c == 10 { break }
                if c == 13 {
                    let next = try streamRead(vm, t, 1)
                    if let x = next.first, x != 10 { w.pushback.insert(x, at: 0) }
                    break
                }
                line.append(c)
            }
            return any ? S(vm, String(decoding: line, as: UTF8.self)) : O(nil)
        case "skipBytes":
            return I(Int32(try streamRead(vm, t, Int(max(0, a[0].i))).count))
        case "unread":
            if ref.params.first == "I" { w.pushback.insert(UInt8(truncatingIfNeeded: a[0].i), at: 0) }
            else if let bytes = bytesArg(ref, a) { w.pushback.insert(contentsOf: bytes, at: 0) }
            return .void
        case "close":
            if let target = w.target, !(target.native is ByteInBox) { _ = try? vm.call(target, "close") }
            return .void
        default:
            var avail = w.pushback.count
            switch w.target?.native {
            case let b as ByteInBox: avail += b.end - b.pos
            case let f as FileStreamBox: avail += f.data.count - f.position
            default: break
            }
            return try inputMethod(vm, t, ref, a, mark: {}, reset: {}, available: avail)
        }
    }
}
