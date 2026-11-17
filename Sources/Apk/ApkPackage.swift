import UIKit

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

        var names: [String] = []
        var n = 1
        while true {
            let name = n == 1 ? "classes.dex" : "classes\(n).dex"
            guard zip.contains(name) else { break }
            names.append(name)
            n += 1
        }
        dexNames = names
        nativeLibs = zip.names.filter { $0.hasPrefix("lib/") && $0.hasSuffix(".so") }
        readManifest()

        if scanCode {
            // One dex at a time, header only; each buffer is freed right away.
            for name in names {
                autoreleasepool {
                    if let bytes = zip.read(name), let c = DexFile.headerCounts(bytes) {
                        classCount += c.classes
                        methodCount += c.methods
                    }
                }
            }
        }
    }

    /// Size of all code once unpacked, in bytes.
    var codeSize: Int {
        return dexNames.reduce(0) { $0 + zip.size(of: $1) }
    }

    /// Unpacks the dex files (class bodies are still decoded lazily).
    /// Call off the main thread.
    func loadCode() {
        guard !codeLoaded else { return }
        var dexes: [DexFile] = []
        for name in dexNames {
            autoreleasepool {
                if let bytes = zip.read(name), let dex = try? DexFile(bytes: bytes) { dexes.append(dex) }
            }
        }
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

    func iconImage() -> UIImage? {
        guard let p = iconPath, let bytes = zip.read(p) else { return nil }
        return UIImage(data: Data(bytes))
    }

    func image(resource id: Int) -> UIImage? {
        guard let p = resources?.filePath(id, preferBitmap: true), let bytes = zip.read(p) else { return nil }
        return UIImage(data: Data(bytes))
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
