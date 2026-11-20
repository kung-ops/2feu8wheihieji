import Foundation

/// Split-APK bundles from app stores: .apks (bundletool / SAI), .xapk
/// (APKPure), .apkm (APKMirror) and plain .zip files with APKs inside.
/// Their main APK ("base") holds the app's code and layouts; the other
/// "split" APKs hold extra screen densities, languages and native code.
enum ApkBundle {
    static let extensions: Set<String> = ["apk", "apks", "xapk", "apkm", "zip"]

    struct Resolved {
        /// The APK to install (the file itself, or the base pulled out of a bundle).
        let apk: URL
        /// Set when `apk` was extracted to a temporary file.
        let temporary: Bool
        /// Split APKs left out (names), for the installer to mention.
        let skippedSplits: [String]
        /// Extra files (e.g. OBB game data) found in the bundle.
        let extraFiles: [String]
    }

    enum BundleError: LocalizedError {
        case notAnApp
        case noBase
        var errorDescription: String? {
            switch self {
            case .notAnApp: return "This file is not an Android app (.apk) or an app bundle (.apks, .xapk, .apkm)."
            case .noBase: return "This bundle has no main (base) APK inside."
            }
        }
    }

    /// Finds the APK to install in `url`. Plain APKs are returned as they are.
    static func resolve(_ url: URL) throws -> Resolved {
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        guard let zip = ZipArchive(data: data) else { throw BundleError.notAnApp }
        if zip.contains("AndroidManifest.xml") {
            return Resolved(apk: url, temporary: false, skippedSplits: [], extraFiles: [])
        }
        let apks = zip.names.filter { $0.lowercased().hasSuffix(".apk") && !$0.hasSuffix("/") }
        guard !apks.isEmpty else { throw BundleError.notAnApp }
        let base = pickBase(apks, zip: zip)
        guard let baseName = base else { throw BundleError.noBase }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("bundle-\(UUID().uuidString.prefix(8)).apk")
        guard zip.extract(baseName, to: out) else { throw BundleError.noBase }
        let extras = zip.names.filter { !$0.lowercased().hasSuffix(".apk") && !$0.hasSuffix("/")
            && ($0.hasPrefix("Android/obb/") || $0.lowercased().hasSuffix(".obb")) }
        return Resolved(apk: out, temporary: true, skippedSplits: apks.filter { $0 != baseName }, extraFiles: extras)
    }

    /// base.apk / base-master.apk, the XAPK's "<package>.apk", or else the
    /// biggest APK that isn't a config split.
    static func pickBase(_ apks: [String], zip: ZipArchive) -> String? {
        let lower = { (s: String) in (s as NSString).lastPathComponent.lowercased() }
        for preferred in ["base.apk", "base-master.apk", "base_master.apk"] {
            if let b = apks.first(where: { lower($0) == preferred }) { return b }
        }
        if let json = zip.read("manifest.json"),
           let obj = try? JSONSerialization.jsonObject(with: Data(json)) as? [String: Any],
           let pkg = obj["package_name"] as? String,
           let b = apks.first(where: { lower($0) == pkg.lowercased() + ".apk" }) {
            return b
        }
        let candidates = apks.filter {
            let n = lower($0)
            return !n.hasPrefix("config.") && !n.hasPrefix("split_") && !n.contains("split_config")
        }
        return (candidates.isEmpty ? apks : candidates).max { zip.size(of: $0) < zip.size(of: $1) }
    }
}

/// Writes a .zip with stored (uncompressed) files: app data backups.
final class ZipWriter {
    private var data = Data()
    private var central = Data()
    private var count = 0

    private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ bytes: Data) -> UInt32 {
        var c: UInt32 = 0xffffffff
        for b in bytes { c = crcTable[Int((c ^ UInt32(b)) & 0xff)] ^ (c >> 8) }
        return c ^ 0xffffffff
    }

    private func le16(_ v: Int, _ d: inout Data) { d.append(UInt8(v & 0xff)); d.append(UInt8((v >> 8) & 0xff)) }
    private func le32(_ v: UInt32, _ d: inout Data) { for k in 0..<4 { d.append(UInt8((v >> (8 * UInt32(k))) & 0xff)) } }

    func add(_ name: String, _ contents: Data) {
        let nameBytes = Data(name.utf8)
        let crc = ZipWriter.crc32(contents)
        let offset = UInt32(data.count)
        // Local header
        le32(0x04034b50, &data); le16(20, &data); le16(0x0800, &data); le16(0, &data)
        le16(0, &data); le16(0x21, &data)
        le32(crc, &data); le32(UInt32(contents.count), &data); le32(UInt32(contents.count), &data)
        le16(nameBytes.count, &data); le16(0, &data)
        data.append(nameBytes)
        data.append(contents)
        // Central directory entry
        le32(0x02014b50, &central); le16(20, &central); le16(20, &central); le16(0x0800, &central); le16(0, &central)
        le16(0, &central); le16(0x21, &central)
        le32(crc, &central); le32(UInt32(contents.count), &central); le32(UInt32(contents.count), &central)
        le16(nameBytes.count, &central); le16(0, &central); le16(0, &central); le16(0, &central); le16(0, &central)
        le32(0, &central); le32(offset, &central)
        central.append(nameBytes)
        count += 1
    }

    func finish() -> Data {
        var out = data
        let cdOffset = UInt32(out.count)
        out.append(central)
        le32(0x06054b50, &out); le16(0, &out); le16(0, &out)
        le16(count, &out); le16(count, &out)
        le32(UInt32(central.count), &out); le32(cdOffset, &out); le16(0, &out)
        return out
    }
}
