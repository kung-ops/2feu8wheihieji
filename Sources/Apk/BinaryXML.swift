import UIKit

/// A typed attribute value from Android binary XML / resources.
struct ResValue {
    static let typeNull = 0x00
    static let typeReference = 0x01
    static let typeAttribute = 0x02
    static let typeString = 0x03
    static let typeFloat = 0x04
    static let typeDimension = 0x05
    static let typeFraction = 0x06
    static let typeIntDec = 0x10
    static let typeIntHex = 0x11
    static let typeBoolean = 0x12
    // 0x1c...0x1f are colors

    let type: Int
    let data: Int
    /// Literal string, for typeString.
    let string: String?

    var isColor: Bool { return type >= 0x1c && type <= 0x1f }

    /// Dimension in Android dp/sp, roughly equal to iOS points.
    var dimension: CGFloat {
        let mults: [Double] = [1.0 / 256.0, 1.0 / 32768.0, 1.0 / 8388608.0, 1.0 / 2147483648.0]
        let raw = Int32(truncatingIfNeeded: data)
        let mantissa = Double(raw & ~0xff)
        let radix = (data >> 4) & 3
        let value = mantissa * mults[radix]
        let unit = data & 0xf
        if unit == 0 { return CGFloat(value / 2.0) }   // px → pt (assume 2x)
        return CGFloat(value)
    }
}

final class AXMLNode {
    let name: String
    var attrs: [(name: String, value: ResValue)] = []
    var children: [AXMLNode] = []
    weak var parent: AXMLNode?

    init(name: String) { self.name = name }

    func attr(_ n: String) -> ResValue? {
        for a in attrs where a.name == n { return a.value }
        return nil
    }

    /// Depth-first search for all nodes with a given name.
    func all(_ n: String) -> [AXMLNode] {
        var out: [AXMLNode] = []
        for c in children {
            if c.name == n { out.append(c) }
            out.append(contentsOf: c.all(n))
        }
        return out
    }
}

/// Parser for Android's compiled ("binary") XML, used by AndroidManifest.xml
/// and res/layout/*.xml inside an APK.
enum BinaryXML {
    /// Android framework attribute IDs, used when attribute names were stripped.
    static let knownAttrIDs: [Int: String] = [
        0x01010001: "label", 0x01010002: "icon", 0x01010003: "name",
        0x0101021b: "versionCode", 0x0101021c: "versionName",
        0x0101020c: "minSdkVersion", 0x01010270: "targetSdkVersion",
        0x010100d0: "id", 0x0101014f: "text", 0x01010095: "textSize",
        0x01010098: "textColor", 0x010100d4: "background", 0x010100c4: "orientation",
        0x01010150: "hint", 0x01010119: "src", 0x010100af: "gravity",
        0x010100d5: "padding", 0x010100dc: "visibility", 0x0101026f: "onClick",
        0x010100f4: "layout_width", 0x010100f5: "layout_height",
        0x01010097: "textStyle", 0x01010107: "checked", 0x01010220: "inputType",
        0x0101000e: "enabled", 0x01010176: "max", 0x01010137: "progress",
        0x01010010: "exported", 0x0101001e: "theme", 0x01010273: "contentDescription",
        0x0101057a: "tooltipText"
    ]

    static func parse(_ bytes: [UInt8]) -> AXMLNode? {
        let d = Bytes(bytes)
        guard d.count >= 8, d.u16(0) == 0x0003 else { return nil }
        var pool = StringPool()
        var resMap: [Int] = []
        let root = AXMLNode(name: "#document")
        var current = root

        var p = d.u16(2)
        while p + 8 <= d.count {
            let type = d.u16(p)
            let headerSize = d.u16(p + 2)
            let size = d.u32(p + 4)
            if size < 8 { break }

            switch type {
            case 0x0001:
                pool = StringPool(d, at: p)
            case 0x0180:
                let n = (size - headerSize) / 4
                resMap = (0..<max(0, n)).map { d.u32(p + headerSize + $0 * 4) }
            case 0x0102:
                let nameIdx = d.u32(p + 20)
                let attrStart = d.u16(p + 24)
                let attrSize = max(20, d.u16(p + 26))
                let attrCount = d.u16(p + 28)
                let node = AXMLNode(name: pool[nameIdx] ?? "?")
                for i in 0..<attrCount {
                    let a = p + 16 + attrStart + i * attrSize
                    let nIdx = d.u32(a + 4)
                    let raw = d.u32(a + 8)
                    let vType = d.u8(a + 15)
                    let vData = d.u32(a + 16)
                    var aname = pool[nIdx] ?? ""
                    if aname.isEmpty, nIdx < resMap.count, let known = knownAttrIDs[resMap[nIdx]] {
                        aname = known
                    }
                    if aname.isEmpty, nIdx < resMap.count { aname = String(format: "0x%08x", resMap[nIdx]) }
                    var str: String? = nil
                    if vType == ResValue.typeString { str = pool[vData] ?? pool[raw] }
                    else if raw != 0xFFFFFFFF { str = pool[raw] }
                    node.attrs.append((aname, ResValue(type: vType, data: vData, string: str)))
                }
                node.parent = current
                current.children.append(node)
                current = node
            case 0x0103:
                if let parent = current.parent { current = parent }
            default:
                break
            }
            p += size
        }
        return root
    }
}
