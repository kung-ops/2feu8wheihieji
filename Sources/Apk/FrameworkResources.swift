import Foundation

/// Android 9's own resources (`@android:string/ok`, `@android:color/white`,
/// `android.R.layout.simple_list_item_1`, system icons…), taken from
/// LineageOS 16.0's framework-res.apk and trimmed to what fits a 1 GB
/// iPhone: default-language values, layouts and xhdpi pictures. Built by
/// `runner make-framework-pack`; shipped as Sources/Android/android9-res.zip.
///
///     values.json   {"<id hex>": [type, data, "string"?]}
///     files.json    {"<id hex>": "res/…"}
///     attrs.json    {"<id hex>": "onClick"}            attribute names
///     styles.json   {"<id hex>": [parent, [[attr, type, data, "string"?]…]]}
///     res/…         the layout / drawable files
final class FrameworkResources {
    /// Where the pack is. Set by the Linux runner; the app finds it in its bundle.
    static var packURL: URL? = Bundle.main.url(forResource: "android9-res", withExtension: "zip")

    static let shared: FrameworkResources? = {
        guard let url = packURL, let data = try? Data(contentsOf: url, options: .alwaysMapped),
              let zip = ZipArchive(data: data) else { return nil }
        return FrameworkResources(zip: zip)
    }()

    private let zip: ZipArchive
    private var values: [Int: ResValue] = [:]
    private var files: [Int: String] = [:]
    private var attrs: [Int: String] = [:]
    private var styles: [String: [Any]] = [:]

    init?(zip: ZipArchive) {
        self.zip = zip
        guard let vb = zip.read("values.json"),
              let v = try? JSONSerialization.jsonObject(with: Data(vb)) as? [String: [Any]] else { return nil }
        values.reserveCapacity(v.count)
        for (k, arr) in v {
            guard let id = Int(k, radix: 16), arr.count >= 2,
                  let t = (arr[0] as? NSNumber)?.intValue, let d = (arr[1] as? NSNumber)?.int64Value else { continue }
            values[id] = ResValue(type: t, data: Int(UInt32(truncatingIfNeeded: d)), string: arr.count > 2 ? arr[2] as? String : nil)
        }
        if let fb = zip.read("files.json"), let f = try? JSONSerialization.jsonObject(with: Data(fb)) as? [String: String] {
            for (k, path) in f { if let id = Int(k, radix: 16) { files[id] = path } }
        }
        if let ab = zip.read("attrs.json"), let f = try? JSONSerialization.jsonObject(with: Data(ab)) as? [String: String] {
            for (k, n) in f { if let id = Int(k, radix: 16) { attrs[id] = n } }
        }
        if let sb = zip.read("styles.json"), let f = try? JSONSerialization.jsonObject(with: Data(sb)) as? [String: [Any]] {
            styles = f
        }
    }

    static func isFramework(_ id: Int) -> Bool { return (id >> 24) & 0xff == 0x01 }

    func value(_ id: Int) -> ResValue? { return values[id] }

    func attrName(_ id: Int) -> String? { return attrs[id] }

    /// An Android style (Widget.Material.Button…), decoded when first asked for.
    private var bagCache: [Int: ResourceTable.Bag] = [:]
    private let lock = NSLock()
    func bag(_ id: Int) -> ResourceTable.Bag? {
        lock.lock()
        defer { lock.unlock() }
        if let b = bagCache[id] { return b }
        guard let raw = styles[String(id, radix: 16)], raw.count == 2,
              let parent = (raw[0] as? NSNumber)?.intValue, let list = raw[1] as? [[Any]] else { return nil }
        var items: [(attr: Int, value: ResValue)] = []
        for it in list where it.count >= 3 {
            guard let a = (it[0] as? NSNumber)?.intValue, let t = (it[1] as? NSNumber)?.intValue,
                  let d = (it[2] as? NSNumber)?.int64Value else { continue }
            items.append((a, ResValue(type: t, data: Int(UInt32(truncatingIfNeeded: d)), string: it.count > 3 ? it[3] as? String : nil)))
        }
        let b = ResourceTable.Bag(parent: parent, items: items, isDefault: true)
        bagCache[id] = b
        return b
    }

    /// Path inside the pack, marked with the "@android/" prefix.
    func filePath(_ id: Int) -> String? { return files[id].map { "@android/" + $0 } }

    func read(_ markedPath: String) -> [UInt8]? {
        guard markedPath.hasPrefix("@android/") else { return nil }
        return zip.read(String(markedPath.dropFirst("@android/".count)))
    }

    var count: Int { return values.count }
}
