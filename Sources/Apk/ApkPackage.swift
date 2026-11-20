import UIKit
#if canImport(ImageIO)
import ImageIO
#endif

/// Everything we know about an APK after opening it.
final class ApkPackage {
    let url: URL
    let zip: ZipArchive
    let manifest: AXMLNode?
    let resources: ResourceTable?
    /// "classes.dex", "classes2.dex", …
    let dexNames: [String]
    /// Filled by `loadCode()` just before running.
    private(set) var dexFiles: [DexFile] = []
    private(set) var codeLoaded = false
    /// DEX files that could not be loaded are recorded rather than silently dropped.
    private(set) var codeErrors: [String] = []

    private(set) var packageName = "?"
    private(set) var versionName = ""
    private(set) var versionCode = ""
    private(set) var minSdk = ""
    private(set) var targetSdk = ""
    private(set) var label = ""
    private(set) var iconPath: String?
    private(set) var permissions: [String] = []
    private(set) var activities: [String] = []
    private(set) var launcherActivity: String?
    private(set) var applicationClass: String?
    private(set) var nativeLibs: [String] = []
    private(set) var classCount = 0
    private(set) var methodCount = 0

    enum LoadError: LocalizedError {
        case notZip, noManifest
        var errorDescription: String? {
            switch self {
            case .notZip: return "This file is not a valid APK (not a ZIP archive)."
            case .noManifest: return "This APK has no AndroidManifest.xml."
            }
        }
    }

    /// Opens an APK. Cheap: the file is memory-mapped and only the manifest,
    /// resources and (with `scanCode`) the dex headers are read.
    init(url: URL, scanCode: Bool = false) throws {
        self.url = url
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        guard let zip = ZipArchive(data: data) else { throw LoadError.notZip }
        self.zip = zip
        guard let mbytes = zip.read("AndroidManifest.xml") else { throw LoadError.noManifest }
        manifest = BinaryXML.parse(mbytes)
        resources = zip.read("resources.arsc").flatMap { ResourceTable(bytes: $0) }

        // Load root-level classesN.dex entries, even if a sequence number is skipped.
        let names = zip.names.compactMap { name -> (Int, String)? in
            if name == "classes.dex" { return (1, name) }
            guard name.hasPrefix("classes"), name.hasSuffix(".dex") else { return nil }
            let digits = name.dropFirst("classes".count).dropLast(".dex".count)
            guard let number = Int(digits), number >= 2 else { return nil }
            return (number, name)
        }.sorted { $0.0 < $1.0 }.map { $0.1 }
        dexNames = names
        nativeLibs = zip.names.filter { $0.hasPrefix("lib/") && $0.hasSuffix(".so") }
        readManifest()

        if scanCode {
            // Only the 112-byte header of each dex is decompressed.
            for name in names {
                if let head = zip.readPrefix(name, maxBytes: 0x70),
                   let c = DexFile.headerCounts(head, fileSize: zip.size(of: name)) {
                    classCount += c.classes
                    methodCount += c.methods
                }
            }
        }
    }

    /// Folder with this app's dex files already unpacked (an installed app's
    /// "oat" folder). The files there are memory-mapped instead of being
    /// decompressed into RAM on every launch.
    var dexCacheDir: URL?

    /// Size of all code once unpacked, in bytes.
    var codeSize: Int {
        return dexNames.reduce(0) { $0 + zip.size(of: $1) }
    }

    /// Unpacks the dex files (class bodies are still decoded lazily).
    /// Call off the main thread.
    func loadCode() {
        guard !codeLoaded else { return }
        var dexes: [DexFile] = []
        var errors: [String] = []
        for name in dexNames {
            autoreleasepool {
                if let dir = dexCacheDir {
                    let file = dir.appendingPathComponent(name)
                    var ok = FileManager.default.fileExists(atPath: file.path)
                    if ok, let size = try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber,
                       size.intValue != zip.size(of: name) {
                        ok = false
                    }
                    if !ok {
                        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                        ok = zip.extract(name, to: file)
                    }
                    if ok, let store = ByteStore(mapping: file.path) {
                        do {
                            dexes.append(try DexFile(store: store))
                            return
                        } catch {
                            try? FileManager.default.removeItem(at: file)
                        }
                    }
                }
                guard let bytes = zip.read(name) else {
                    errors.append("Could not decompress \(name)")
                    return
                }
                do { dexes.append(try DexFile(bytes: bytes)) }
                catch { errors.append("Could not parse \(name): \(error)") }
            }
        }
        codeErrors = errors
        dexFiles = dexes
        codeLoaded = true
    }

    // MARK: - Manifest

    func resolveString(_ v: ResValue?) -> String {
        guard let v = v else { return "" }
        if let s = v.string, v.type == ResValue.typeString { return s }
        if v.type == ResValue.typeReference, let s = resources?.string(v.data) { return s }
        if v.type == ResValue.typeIntDec { return String(Int32(truncatingIfNeeded: v.data)) }
        if let s = v.string { return s }
        return ""
    }

    private func fullClassName(_ n: String) -> String {
        if n.hasPrefix(".") { return packageName + n }
        if !n.contains(".") { return packageName + "." + n }
        return n
    }

    private func readManifest() {
        guard let root = manifest, let m = root.children.first(where: { $0.name == "manifest" }) else { return }
        packageName = resolveString(m.attr("package"))
        versionName = resolveString(m.attr("versionName"))
        versionCode = resolveString(m.attr("versionCode"))
        if let sdk = m.children.first(where: { $0.name == "uses-sdk" }) {
            minSdk = resolveString(sdk.attr("minSdkVersion"))
            targetSdk = resolveString(sdk.attr("targetSdkVersion"))
        }
        permissions = m.children.filter { $0.name == "uses-permission" }.map { resolveString($0.attr("name")) }

        guard let app = m.children.first(where: { $0.name == "application" }) else { return }
        label = resolveString(app.attr("label"))
        let appName = resolveString(app.attr("name"))
        if !appName.isEmpty { applicationClass = fullClassName(appName) }
        if let icon = app.attr("icon"), icon.type == ResValue.typeReference {
            iconPath = resources?.filePath(icon.data, preferBitmap: true)
        }
        if iconPath == nil || iconPath?.hasSuffix(".xml") == true {
            // Adaptive icons are XML; look for a classic PNG launcher icon instead.
            let pngs = zip.names.filter { ($0.contains("ic_launcher") || $0.contains("app_icon")) && $0.hasSuffix(".png") }
            iconPath = pngs.sorted { (zip.entries[$0]?.size ?? 0) > (zip.entries[$1]?.size ?? 0) }.first ?? iconPath
        }

        for a in app.children where a.name == "activity" || a.name == "activity-alias" {
            var name = resolveString(a.attr("name"))
            if a.name == "activity-alias", let target = a.attr("targetActivity") {
                name = resolveString(target)
            }
            let full = fullClassName(name)
            if a.name == "activity" { activities.append(full) }
            if launcherActivity == nil {
                for f in a.children where f.name == "intent-filter" {
                    let actions = f.children.filter { $0.name == "action" }.map { resolveString($0.attr("name")) }
                    let cats = f.children.filter { $0.name == "category" }.map { resolveString($0.attr("name")) }
                    if actions.contains("android.intent.action.MAIN") &&
                        (cats.contains("android.intent.category.LAUNCHER") || cats.contains("android.intent.category.LEANBACK_LAUNCHER")) {
                        launcherActivity = full
                    }
                }
            }
        }
        if launcherActivity == nil { launcherActivity = activities.first }
        if label.isEmpty { label = packageName }
    }

    // MARK: - Assets

    /// The launcher icon file (PNG/WebP/JPEG bytes), if the APK has a bitmap one.
    func iconData() -> Data? {
        guard let p = iconPath, !p.hasSuffix(".xml"), let bytes = zip.read(p), !bytes.isEmpty else { return nil }
        return Data(bytes)
    }

    func iconImage(maxSide: Int = 192) -> UIImage? {
        guard let data = iconData() else { return nil }
        return ApkPackage.decodeImage(data, maxSide: maxSide)
    }

    func image(resource id: Int) -> UIImage? {
        guard let p = resources?.filePath(id, preferBitmap: true), !p.hasSuffix(".xml"),
              let bytes = zip.read(p) else { return nil }
        return ApkPackage.decodeImage(Data(bytes), maxSide: VirtualDevice.maxBitmapSide)
    }

    /// Decodes an image no larger than `maxSide` pixels, without first
    /// decoding a huge bitmap at full size (a 4000×3000 PNG would need 48 MB).
    static func decodeImage(_ data: Data, maxSide: Int) -> UIImage? {
        #if canImport(ImageIO)
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide
        ]
        if let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) {
            return UIImage(cgImage: cg)
        }
        return UIImage(data: data)
        #else
        return UIImage(data: data)
        #endif
    }

    func layout(_ id: Int) -> AXMLNode? {
        guard let p = resources?.filePath(id), p.hasSuffix(".xml"), let bytes = zip.read(p) else { return nil }
        return BinaryXML.parse(bytes)?.children.first
    }

    /// The manifest re-rendered as readable text XML.
    func manifestText() -> String {
        guard let root = manifest else { return "" }
        var out = ""
        func walk(_ n: AXMLNode, _ indent: String) {
            out += indent + "<" + n.name
            for a in n.attrs {
                var v = resolveString(a.value)
                if v.isEmpty {
                    if a.value.type == ResValue.typeReference { v = String(format: "@0x%08x", a.value.data) }
                    else if a.value.type == ResValue.typeBoolean { v = a.value.data != 0 ? "true" : "false" }
                    else { v = String(a.value.data) }
                }
                out += "\n" + indent + "    " + a.name + "=\"" + v + "\""
            }
            if n.children.isEmpty {
                out += " />\n"
            } else {
                out += ">\n"
                for c in n.children { walk(c, indent + "  ") }
                out += indent + "</" + n.name + ">\n"
            }
        }
        for c in root.children { walk(c, "") }
        return out
    }
}
