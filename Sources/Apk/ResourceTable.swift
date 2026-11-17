import Foundation

/// Parser for resources.arsc: maps resource IDs (0x7fXXYYYY) to values,
/// e.g. strings, colors, and file paths of layouts and drawables.
final class ResourceTable {
    struct Entry {
        let value: ResValue
        let density: Int
        let isDefault: Bool   // no language / qualifiers except density
    }

    private(set) var values: [Int: [Entry]] = [:]
    private(set) var names: [Int: String] = [:]     // "layout/activity_main"
    private var globalPool = StringPool()

    init?(bytes: [UInt8]) {
        let d = Bytes(bytes)
        guard d.count >= 12, d.u16(0) == 0x0002 else { return nil }
        var p = d.u16(2)
        while p + 8 <= d.count {
            let type = d.u16(p)
            let size = d.u32(p + 4)
            if size < 8 { break }
            if type == 0x0001 {
                globalPool = StringPool(d, at: p)
            } else if type == 0x0200 {
                parsePackage(d, at: p, size: size)
            }
            p += size
        }
    }

    private func parsePackage(_ d: Bytes, at start: Int, size: Int) {
        let pkgId = d.u32(start + 8)
        let headerSize = d.u16(start + 2)
        var typeNames = StringPool()
        var keyNames = StringPool()
        let typeStringsOff = d.u32(start + 268)
        let keyStringsOff = d.u32(start + 276)
        if typeStringsOff > 0 { typeNames = StringPool(d, at: start + typeStringsOff) }
        if keyStringsOff > 0 { keyNames = StringPool(d, at: start + keyStringsOff) }

        var p = start + headerSize
        let end = start + size
        while p + 8 <= end {
            let type = d.u16(p)
            let csize = d.u32(p + 4)
            if csize < 8 { break }
            if type == 0x0201 {
                parseType(d, at: p, pkgId: pkgId, typeNames: typeNames, keyNames: keyNames)
            }
            p += csize
        }
    }

    private func parseType(_ d: Bytes, at p: Int, pkgId: Int, typeNames: StringPool, keyNames: StringPool) {
        let headerSize = d.u16(p + 2)
        let typeId = d.u8(p + 8)
        let flags = d.u8(p + 9)
        let entryCount = d.u32(p + 12)
        let entriesStart = d.u32(p + 16)
        let config = p + 20
        let configSize = d.u32(config)

        // ResTable_config: imsi(4) locale(4) screenType(4: orientation, touch, density16) ...
        let locale = d.u32(config + 8)
        let density = d.u16(config + 14)
        var otherQualifiers = false
        if configSize > 16 {
            for k in 16..<min(configSize, 64) where d.u8(config + k) != 0 {
                otherQualifiers = true
                break
            }
        }
        // Translations are skipped: we always show the default language, and big
        // apps ship ~100 languages, which would cost a lot of memory on an iPhone 6.
        if locale != 0 { return }
        let isDefault = !otherQualifiers && d.u32(config + 4) == 0
        let typeName = typeNames[typeId - 1] ?? "type\(typeId)"
        let sparse = (flags & 0x01) != 0
        guard entryCount < 200_000 else { return }

        for i in 0..<entryCount {
            var index = i
            var off: Int
            if sparse {
                index = d.u16(p + headerSize + i * 4)
                off = d.u16(p + headerSize + i * 4 + 2) * 4
            } else {
                off = d.u32(p + headerSize + i * 4)
                if off == 0xFFFFFFFF { continue }
            }
            let e = p + entriesStart + off
            let eSize = d.u16(e)
            let eFlags = d.u16(e + 2)
            let resId = (pkgId << 24) | (typeId << 16) | index

            var keyIdx: Int
            var value: ResValue
            if eFlags & 0x0008 != 0 {
                // compact entry
                keyIdx = eSize
                let vType = (eFlags >> 8) & 0xff
                let vData = d.u32(e + 4)
                value = ResValue(type: vType, data: vData, string: vType == ResValue.typeString ? globalPool[vData] : nil)
            } else {
                keyIdx = d.u32(e + 4)
                if eFlags & 0x0001 != 0 {
                    // complex (style/array/plurals) – record the name only
                    if names[resId] == nil, let k = keyNames[keyIdx] { names[resId] = "\(typeName)/\(k)" }
                    continue
                }
                let v = e + eSize
                let vType = d.u8(v + 3)
                let vData = d.u32(v + 4)
                value = ResValue(type: vType, data: vData, string: vType == ResValue.typeString ? globalPool[vData] : nil)
            }
            if names[resId] == nil, let k = keyNames[keyIdx] { names[resId] = "\(typeName)/\(k)" }
            values[resId, default: []].append(Entry(value: value, density: density, isDefault: isDefault))
        }
    }

    /// Best value for normal use (default language, default config).
    func value(_ id: Int) -> ResValue? {
        guard let list = values[id], !list.isEmpty else { return nil }
        if let def = list.first(where: { $0.isDefault && $0.density == 0 }) { return def.value }
        if let def = list.first(where: { $0.isDefault }) { return def.value }
        return list[0].value
    }

    /// Follows reference chains (@string/a -> @string/b) up to a few hops.
    func resolve(_ v: ResValue) -> ResValue {
        var cur = v
        var hops = 0
        while cur.type == ResValue.typeReference, hops < 8, let next = value(cur.data) {
            cur = next
            hops += 1
        }
        return cur
    }

    func string(_ id: Int) -> String? {
        guard let v = value(id) else { return nil }
        let r = resolve(v)
        return r.string
    }

    /// Path of a file resource (layout or drawable). Prefers the highest-density PNG.
    func filePath(_ id: Int, preferBitmap: Bool = false) -> String? {
        guard let list = values[id] else { return nil }
        var candidates: [(String, Int)] = []
        for e in list {
            let r = resolve(e.value)
            if let s = r.string, s.hasPrefix("res/") { candidates.append((s, e.density)) }
        }
        if candidates.isEmpty { return nil }
        if preferBitmap {
            let bitmaps = candidates.filter { $0.0.hasSuffix(".png") || $0.0.hasSuffix(".webp") || $0.0.hasSuffix(".jpg") }
            if let best = bitmaps.filter({ $0.1 < 0xfffe }).max(by: { $0.1 < $1.1 }) ?? bitmaps.first { return best.0 }
        }
        if let best = candidates.first(where: { $0.1 == 0 }) { return best.0 }
        return candidates[0].0
    }

    func name(_ id: Int) -> String? { return names[id] }
}
