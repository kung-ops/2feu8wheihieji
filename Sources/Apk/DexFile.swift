import Foundation

struct DexTry {
    let start: Int
    let end: Int
    /// (exception type descriptor or nil for catch-all, handler address)
    let handlers: [(type: String?, addr: Int)]
}

final class DexCode {
    let registers: Int
    let ins: Int
    let insns: [UInt16]
    let tries: [DexTry]

    init(registers: Int, ins: Int, insns: [UInt16], tries: [DexTry]) {
        self.registers = registers
        self.ins = ins
        self.insns = insns
        self.tries = tries
    }
}

struct DexMethodRef {
    let classDesc: String
    let name: String
    let params: [String]
    let ret: String
    /// "name(params)ret", used as the dispatch key.
    let sig: String
}

struct DexFieldRef {
    let classDesc: String
    let name: String
    let type: String
}

final class DexMethod {
    let ref: DexMethodRef
    let accessFlags: Int
    let code: DexCode?
    unowned let dex: DexFile

    var isStatic: Bool { return accessFlags & 0x0008 != 0 }
    var isNative: Bool { return accessFlags & 0x0100 != 0 }
    var isAbstract: Bool { return accessFlags & 0x0400 != 0 }

    init(ref: DexMethodRef, accessFlags: Int, code: DexCode?, dex: DexFile) {
        self.ref = ref
        self.accessFlags = accessFlags
        self.code = code
        self.dex = dex
    }
}

/// Values found in a class's static initial values (encoded_array).
enum DexConst {
    case int(Int32)
    case long(Int64)
    case string(String)
    case null
    case unsupported
}

final class DexClass {
    let desc: String
    let superDesc: String?
    let interfaces: [String]
    let accessFlags: Int
    var staticFields: [DexFieldRef] = []
    var instanceFields: [DexFieldRef] = []
    var methods: [String: DexMethod] = [:]   // by sig
    var staticValues: [DexConst] = []
    unowned let dex: DexFile

    var isInterface: Bool { return accessFlags & 0x0200 != 0 }

    init(desc: String, superDesc: String?, interfaces: [String], accessFlags: Int, dex: DexFile) {
        self.desc = desc
        self.superDesc = superDesc
        self.interfaces = interfaces
        self.accessFlags = accessFlags
        self.dex = dex
    }
}

enum DexError: Error {
    case badMagic
}

/// Parser for Dalvik executable files (classes.dex).
final class DexFile {
    let d: Bytes
    private let stringIdsOff: Int, stringCount: Int
    private let typeIdsOff: Int, typeCount: Int
    private let protoIdsOff: Int, protoCount: Int
    private let fieldIdsOff: Int, fieldCount: Int
    private let methodIdsOff: Int, methodCount: Int
    private let classDefsOff: Int, classDefCount: Int

    private var stringCache: [Int: String] = [:]
    private var methodRefCache: [Int: DexMethodRef] = [:]
    private var fieldRefCache: [Int: DexFieldRef] = [:]
    private(set) var classes: [String: DexClass] = [:]
    private(set) var classOrder: [String] = []

    init(bytes: [UInt8]) throws {
        d = Bytes(bytes)
        guard d.count > 0x70, d.u8(0) == 0x64, d.u8(1) == 0x65, d.u8(2) == 0x78 else { throw DexError.badMagic }
        stringCount = d.u32(56); stringIdsOff = d.u32(60)
        typeCount = d.u32(64); typeIdsOff = d.u32(68)
        protoCount = d.u32(72); protoIdsOff = d.u32(76)
        fieldCount = d.u32(80); fieldIdsOff = d.u32(84)
        methodCount = d.u32(88); methodIdsOff = d.u32(92)
        classDefCount = d.u32(96); classDefsOff = d.u32(100)
        parseClasses()
    }

    var methodRefCount: Int { return methodCount }
    var stringIdCount: Int { return stringCount }

    // MARK: - Strings & types

    func string(_ idx: Int) -> String {
        if let s = stringCache[idx] { return s }
        guard idx >= 0, idx < stringCount else { return "" }
        var p = d.u32(stringIdsOff + idx * 4)
        let utf16Len = d.uleb(&p)
        var units = [UInt16]()
        units.reserveCapacity(utf16Len)
        // Modified UTF-8 → UTF-16
        while units.count < utf16Len + 4 {
            let a = d.u8(p)
            if a == 0 { break }
            p += 1
            if a < 0x80 {
                units.append(UInt16(a))
            } else if a & 0xe0 == 0xc0 {
                let b = d.u8(p); p += 1
                units.append(UInt16(((a & 0x1f) << 6) | (b & 0x3f)))
            } else if a & 0xf0 == 0xe0 {
                let b = d.u8(p), c = d.u8(p + 1); p += 2
                units.append(UInt16(((a & 0x0f) << 12) | ((b & 0x3f) << 6) | (c & 0x3f)))
            } else {
                units.append(0xfffd)
            }
        }
        let s = String(decoding: units, as: UTF16.self)
        stringCache[idx] = s
        return s
    }

    func type(_ idx: Int) -> String {
        guard idx >= 0, idx < typeCount else { return "Ljava/lang/Object;" }
        return string(d.u32(typeIdsOff + idx * 4))
    }

    private func typeList(_ off: Int) -> [String] {
        if off == 0 { return [] }
        let n = d.u32(off)
        guard n < 1000 else { return [] }
        return (0..<n).map { type(d.u16(off + 4 + $0 * 2)) }
    }

    func methodRef(_ idx: Int) -> DexMethodRef {
        if let r = methodRefCache[idx] { return r }
        let o = methodIdsOff + idx * 8
        let cls = type(d.u16(o))
        let protoIdx = d.u16(o + 2)
        let name = string(d.u32(o + 4))
        let po = protoIdsOff + protoIdx * 12
        let ret = type(d.u32(po + 4))
        let params = typeList(d.u32(po + 8))
        let sig = name + "(" + params.joined() + ")" + ret
        let r = DexMethodRef(classDesc: cls, name: name, params: params, ret: ret, sig: sig)
        methodRefCache[idx] = r
        return r
    }

    func fieldRef(_ idx: Int) -> DexFieldRef {
        if let r = fieldRefCache[idx] { return r }
        let o = fieldIdsOff + idx * 8
        let r = DexFieldRef(classDesc: type(d.u16(o)), name: string(d.u32(o + 4)), type: type(d.u16(o + 2)))
        fieldRefCache[idx] = r
        return r
    }

    // MARK: - Classes

    private func parseClasses() {
        guard classDefCount < 500_000 else { return }
        for i in 0..<classDefCount {
            let o = classDefsOff + i * 32
            let desc = type(d.u32(o))
            let flags = d.u32(o + 4)
            let superIdx = d.u32(o + 8)
            let superDesc: String? = superIdx == 0xFFFFFFFF ? nil : type(superIdx)
            let ifaces = typeList(d.u32(o + 12))
            let cls = DexClass(desc: desc, superDesc: superDesc, interfaces: ifaces, accessFlags: flags, dex: self)
            let dataOff = d.u32(o + 24)
            let staticValuesOff = d.u32(o + 28)
            if dataOff != 0 { parseClassData(cls, at: dataOff) }
            if staticValuesOff != 0 { cls.staticValues = parseEncodedArray(staticValuesOff) }
            if classes[desc] == nil { classOrder.append(desc) }
            classes[desc] = cls
        }
    }

    private func parseClassData(_ cls: DexClass, at off: Int) {
        var p = off
        let sf = d.uleb(&p), inf = d.uleb(&p), dm = d.uleb(&p), vm = d.uleb(&p)
        var idx = 0
        for _ in 0..<sf {
            idx += d.uleb(&p); _ = d.uleb(&p)
            cls.staticFields.append(fieldRef(idx))
        }
        idx = 0
        for _ in 0..<inf {
            idx += d.uleb(&p); _ = d.uleb(&p)
            cls.instanceFields.append(fieldRef(idx))
        }
        for count in [dm, vm] {
            idx = 0
            for _ in 0..<count {
                idx += d.uleb(&p)
                let flags = d.uleb(&p)
                let codeOff = d.uleb(&p)
                let ref = methodRef(idx)
                let m = DexMethod(ref: ref, accessFlags: flags, code: codeOff == 0 ? nil : parseCode(codeOff), dex: self)
                cls.methods[ref.sig] = m
            }
        }
    }

    private func parseCode(_ off: Int) -> DexCode {
        let regs = d.u16(off)
        let ins = d.u16(off + 2)
        let triesSize = d.u16(off + 6)
        let n = d.u32(off + 12)
        var insns = [UInt16]()
        let count = min(n, max(0, (d.count - off - 16) / 2))
        insns.reserveCapacity(count)
        for i in 0..<count { insns.append(UInt16(d.u16(off + 16 + i * 2))) }

        var tries: [DexTry] = []
        if triesSize > 0 {
            var tp = off + 16 + n * 2
            if n % 2 == 1 { tp += 2 }
            let handlersBase = tp + triesSize * 8
            for t in 0..<triesSize {
                let to = tp + t * 8
                let start = d.u32(to)
                let cnt = d.u16(to + 4)
                let hOff = d.u16(to + 6)
                var hp = handlersBase + hOff
                let size = d.sleb(&hp)
                var handlers: [(type: String?, addr: Int)] = []
                for _ in 0..<min(abs(size), 256) {
                    let typeIdx = d.uleb(&hp)
                    let addr = d.uleb(&hp)
                    handlers.append((type(typeIdx), addr))
                }
                if size <= 0 {
                    handlers.append((nil, d.uleb(&hp)))
                }
                tries.append(DexTry(start: start, end: start + cnt, handlers: handlers))
            }
        }
        return DexCode(registers: regs, ins: ins, insns: insns, tries: tries)
    }

    // MARK: - encoded values

    private func parseEncodedArray(_ off: Int) -> [DexConst] {
        var p = off
        let n = d.uleb(&p)
        var out: [DexConst] = []
        for _ in 0..<min(n, 100_000) { out.append(parseEncodedValue(&p)) }
        return out
    }

    private func readSigned(_ p: Int, _ size: Int) -> Int64 {
        var v: Int64 = 0
        for i in 0..<size { v |= Int64(d.u8(p + i)) << (8 * Int64(i)) }
        let shift = Int64(64 - size * 8)
        return (v << shift) >> shift
    }

    private func readUnsigned(_ p: Int, _ size: Int) -> Int64 {
        var v: Int64 = 0
        for i in 0..<size { v |= Int64(d.u8(p + i)) << (8 * Int64(i)) }
        return v
    }

    private func parseEncodedValue(_ p: inout Int) -> DexConst {
        let head = d.u8(p); p += 1
        let type = head & 0x1f
        let arg = head >> 5
        let size = arg + 1
        switch type {
        case 0x00, 0x02, 0x04:
            let v = readSigned(p, size); p += size
            return .int(Int32(truncatingIfNeeded: v))
        case 0x03:
            let v = readUnsigned(p, size); p += size
            return .int(Int32(truncatingIfNeeded: v))
        case 0x06:
            let v = readSigned(p, size); p += size
            return .long(v)
        case 0x10:
            let v = readUnsigned(p, size) << (8 * Int64(4 - size)); p += size
            return .int(Int32(truncatingIfNeeded: v))
        case 0x11:
            let v = readUnsigned(p, size) << (8 * Int64(8 - size)); p += size
            return .long(v)
        case 0x17:
            let v = readUnsigned(p, size); p += size
            return .string(string(Int(v)))
        case 0x15, 0x16, 0x18, 0x19, 0x1a, 0x1b:
            p += size
            return .unsupported
        case 0x1c:
            _ = parseEncodedArrayInline(&p)
            return .unsupported
        case 0x1d:
            _ = d.uleb(&p)
            let n = d.uleb(&p)
            for _ in 0..<min(n, 10_000) { _ = d.uleb(&p); _ = parseEncodedValue(&p) }
            return .unsupported
        case 0x1e:
            return .null
        case 0x1f:
            return .int(Int32(arg))
        default:
            return .unsupported
        }
    }

    private func parseEncodedArrayInline(_ p: inout Int) -> [DexConst] {
        let n = d.uleb(&p)
        var out: [DexConst] = []
        for _ in 0..<min(n, 100_000) { out.append(parseEncodedValue(&p)) }
        return out
    }
}
