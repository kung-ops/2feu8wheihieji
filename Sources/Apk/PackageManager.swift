import Foundation

/// An app installed on the virtual Android device.
struct InstalledApp: Codable, Equatable {
    var packageName: String
    var label: String
    var versionName: String
    var versionCode: String
    var minSdk: String
    var targetSdk: String
    var permissions: [String]
    var launcherActivity: String?
    var activityCount: Int
    var nativeLibs: [String]
    var dexCount: Int
    var classCount: Int
    var methodCount: Int
    var codeSize: Int
    var apkSize: Int64
    var installedAt: Date
    var updatedAt: Date
    var hasIcon: Bool
    /// android:screenOrientation of the start screen (nil: not set). Optional
    /// so package.json files written by older builds still load.
    var screenOrientation: Int?
    /// Split APKs that were left out when it was installed from a bundle.
    var skippedSplits: Int?

    /// Wants landscape (landscape, sensorLandscape, reverse, userLandscape).
    var prefersLandscape: Bool { return [0, 6, 8, 11].contains(screenOrientation ?? -1) }

    /// Version code as a number, for update / downgrade checks.
    var versionNumber: Int { return Int(versionCode) ?? 0 }

    /// ABIs of the native libraries ("arm64-v8a", …).
    var nativeABIs: [String] {
        return Array(Set(nativeLibs.compactMap { $0.split(separator: "/").dropFirst().first.map(String.init) })).sorted()
    }
}

/// Husk-style per-app choices, kept next to the installed app.
struct AppSettings: Codable, Equatable {
    /// Name shown on the home screen (the app itself is not changed).
    var displayName: String?
    /// 0 = as the app asks, 1 = portrait, 2 = landscape
    var orientation: Int?
    var fullScreen: Bool?
    var keepScreenOn: Bool?
    var playSeconds: Double?
    var lastPlayed: Date?
    var launches: Int?
}

/// An app's private folders on the virtual device, like Android's
/// /data/data/<package>. Apps may only touch files inside these folders
/// (and the shared "sdcard").
struct AppStorage {
    let packageName: String

    var dataDir: URL { return PackageManager.root.appendingPathComponent("data").appendingPathComponent(packageName) }
    var filesDir: URL { return AppStorage.made(dataDir.appendingPathComponent("files")) }
    var cacheDir: URL { return AppStorage.made(dataDir.appendingPathComponent("cache")) }
    /// The shared "internal storage" every app can see (/sdcard). It's the
    /// "Shared Storage" folder in Files › On My iPhone › APK Sandbox, so you
    /// can put game data there.
    var externalDir: URL { return AppStorage.made(AppStorage.sharedStorage) }

    static var sharedStorage: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Shared Storage", isDirectory: true)
    }

    /// Whether an app may read or write `path`.
    func allows(_ path: String) -> Bool {
        let p = URL(fileURLWithPath: path).standardizedFileURL.path
        for dir in [dataDir, AppStorage.sharedStorage] {
            let d = dir.standardizedFileURL.path
            if p == d || p.hasPrefix(d + "/") { return true }
        }
        return false
    }

    private static func made(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

enum AppData {
    /// Deletes an app's files, cache and SharedPreferences.
    static func clear(packageName: String) {
        PackageManager.shared.clearData(packageName)
    }
}

/// Installs, updates and removes apps on the virtual Android device.
///
/// Everything lives in Library/Application Support/VirtualAndroid (private
/// to APK Sandbox, not shown in the Files app):
///
///     app/<package>/base.apk       the installed APK
///     app/<package>/icon.png       launcher icon
///     app/<package>/package.json   name, version, permissions…
///     app/<package>/oat/*.dex      unpacked code, memory-mapped at launch
///     data/<package>/files|cache   the app's private data
///     sdcard/                      shared storage
///
/// Call from the main thread, except `install`, which does slow work and
/// should run on a background queue.
final class PackageManager {
    static let shared = PackageManager()

    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("VirtualAndroid")
    }

    private(set) var apps: [InstalledApp] = []
    private let fm = FileManager.default

    private init() {
        try? fm.createDirectory(at: appsRoot, withIntermediateDirectories: true)
        excludeFromBackup(PackageManager.root)
        moveOldSharedStorage()
        reload()
    }

    /// Builds before Shared Storage was visible in Files kept it in VirtualAndroid/sdcard.
    private func moveOldSharedStorage() {
        let old = PackageManager.root.appendingPathComponent("sdcard")
        guard let items = try? fm.contentsOfDirectory(at: old, includingPropertiesForKeys: nil), !items.isEmpty else { return }
        let new = AppStorage.sharedStorage
        try? fm.createDirectory(at: new, withIntermediateDirectories: true)
        for i in items where !fm.fileExists(atPath: new.appendingPathComponent(i.lastPathComponent).path) {
            try? fm.moveItem(at: i, to: new.appendingPathComponent(i.lastPathComponent))
        }
        try? fm.removeItem(at: old)
    }

    private var appsRoot: URL { return PackageManager.root.appendingPathComponent("app") }

    func appDir(_ pkg: String) -> URL { return appsRoot.appendingPathComponent(pkg) }
    func apkURL(_ pkg: String) -> URL { return appDir(pkg).appendingPathComponent("base.apk") }
    func iconURL(_ pkg: String) -> URL { return appDir(pkg).appendingPathComponent("icon.png") }
    func oatDir(_ pkg: String) -> URL { return appDir(pkg).appendingPathComponent("oat") }
    private func infoURL(_ pkg: String) -> URL { return appDir(pkg).appendingPathComponent("package.json") }
    private func settingsURL(_ pkg: String) -> URL { return appDir(pkg).appendingPathComponent("settings.json") }
    func lastRunLogURL(_ pkg: String) -> URL { return appDir(pkg).appendingPathComponent("last-run.log") }

    // MARK: - Settings & logs

    func settings(_ pkg: String) -> AppSettings {
        guard let d = try? Data(contentsOf: settingsURL(pkg)),
              let s = try? JSONDecoder().decode(AppSettings.self, from: d) else { return AppSettings() }
        return s
    }

    func saveSettings(_ s: AppSettings, for pkg: String) {
        guard fm.fileExists(atPath: appDir(pkg).path), let d = try? JSONEncoder().encode(s) else { return }
        try? d.write(to: settingsURL(pkg), options: .atomic)
    }

    /// Name for the home screen: the user's name for it, or the app's label.
    func displayName(_ app: InstalledApp) -> String {
        let n = settings(app.packageName).displayName ?? ""
        return n.trimmingCharacters(in: .whitespaces).isEmpty ? app.label : n
    }

    /// Adds play time after a run of the app.
    func recordRun(_ pkg: String, seconds: Double) {
        var s = settings(pkg)
        s.playSeconds = (s.playSeconds ?? 0) + max(0, seconds)
        s.lastPlayed = Date()
        s.launches = (s.launches ?? 0) + 1
        saveSettings(s, for: pkg)
    }

    func saveLastRunLog(_ pkg: String, _ text: String) {
        guard fm.fileExists(atPath: appDir(pkg).path) else { return }
        try? Data(text.utf8).write(to: lastRunLogURL(pkg), options: .atomic)
    }

    func lastRunLog(_ pkg: String) -> String? {
        guard let d = try? Data(contentsOf: lastRunLogURL(pkg)) else { return nil }
        return String(decoding: d, as: UTF8.self)
    }

    func app(_ pkg: String) -> InstalledApp? { return apps.first { $0.packageName == pkg } }

    /// Reads an app's package.json from disk (safe on any thread).
    func info(_ pkg: String) -> InstalledApp? {
        guard let data = try? Data(contentsOf: infoURL(pkg)) else { return nil }
        return try? JSONDecoder().decode(InstalledApp.self, from: data)
    }

    /// Re-reads the list of installed apps from disk.
    func reload() {
        let dirs = (try? fm.contentsOfDirectory(at: appsRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        var list: [InstalledApp] = []
        let dec = JSONDecoder()
        for d in dirs {
            let pkg = d.lastPathComponent
            guard fm.fileExists(atPath: apkURL(pkg).path),
                  let data = try? Data(contentsOf: infoURL(pkg)),
                  let app = try? dec.decode(InstalledApp.self, from: data) else { continue }
            list.append(app)
        }
        apps = list.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    // MARK: - Install

    enum InstallError: LocalizedError {
        case invalidPackageName(String)
        case copyFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidPackageName(let n): return "The APK's package name (\"\(n)\") is not valid."
            case .copyFailed(let why): return "Couldn't copy the app into the virtual phone: \(why)"
            }
        }
    }

    /// What installing `apk` would do (for the installer screen).
    enum InstallKind { case new, update(from: InstalledApp), downgrade(from: InstalledApp), reinstall }

    func installKind(_ apk: ApkPackage) -> InstallKind {
        guard let old = app(apk.packageName) else { return .new }
        let newCode = Int(apk.versionCode) ?? 0
        if newCode > old.versionNumber { return .update(from: old) }
        if newCode < old.versionNumber { return .downgrade(from: old) }
        return .reinstall
    }

    static func isValidPackageName(_ n: String) -> Bool {
        guard !n.isEmpty, n != "?", n.count < 256 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._")
        return n.unicodeScalars.allSatisfy { allowed.contains($0) } && !n.hasPrefix(".") && !n.contains("..")
    }

    /// Copies the APK into the virtual phone, unpacks its code and saves its
    /// icon. Keeps the app's data when it updates an installed app.
    /// Slow: call off the main thread. `progress` is called with a step name
    /// and a fraction (0…1) on the calling thread.
    func install(from source: URL, progress: (String, Double) -> Void = { _, _ in }) throws -> InstalledApp {
        progress("Reading package…", 0.05)
        #if canImport(Darwin)
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        #endif
        // A bundle (.apks / .xapk / .apkm): install its base APK.
        let originalSource = source
        let bundle = try ApkBundle.resolve(source)
        defer { if bundle.temporary { try? fm.removeItem(at: bundle.apk) } }
        let source = bundle.apk
        let apk = try ApkPackage(url: source, scanCode: true)
        let pkg = apk.packageName
        guard PackageManager.isValidPackageName(pkg) else { throw InstallError.invalidPackageName(pkg) }

        let dir = appDir(pkg)
        let staging = appsRoot.appendingPathComponent(".install-\(pkg)-\(UUID().uuidString)")
        try? fm.removeItem(at: staging)
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            progress("Copying…", 0.15)
            try fm.copyItem(at: source, to: staging.appendingPathComponent("base.apk"))
        } catch {
            try? fm.removeItem(at: staging)
            throw InstallError.copyFailed(error.localizedDescription)
        }

        // Unpack the code once now (Android does the same at install time),
        // so launching only has to memory-map it.
        let staged = try ApkPackage(url: staging.appendingPathComponent("base.apk"))
        let oat = staging.appendingPathComponent("oat")
        try? fm.createDirectory(at: oat, withIntermediateDirectories: true)
        for (i, name) in staged.dexNames.enumerated() {
            progress("Optimizing app (\(i + 1)/\(staged.dexNames.count))…", 0.2 + 0.7 * Double(i) / Double(max(1, staged.dexNames.count)))
            autoreleasepool {
                _ = staged.zip.extract(name, to: oat.appendingPathComponent(name))
            }
        }

        progress("Finishing…", 0.95)
        var hasIcon = false
        if let icon = apk.iconData() {
            hasIcon = (try? icon.write(to: staging.appendingPathComponent("icon.png"))) != nil
        }
        let now = Date()
        let old = info(pkg)
        let size = (try? fm.attributesOfItem(atPath: source.path)[.size] as? NSNumber)?.int64Value ?? 0
        let info = InstalledApp(
            packageName: pkg, label: apk.label, versionName: apk.versionName, versionCode: apk.versionCode,
            minSdk: apk.minSdk, targetSdk: apk.targetSdk, permissions: apk.permissions,
            launcherActivity: apk.launcherActivity, activityCount: apk.activities.count,
            nativeLibs: apk.nativeLibs, dexCount: apk.dexNames.count, classCount: apk.classCount,
            methodCount: apk.methodCount, codeSize: apk.codeSize, apkSize: size,
            installedAt: old?.installedAt ?? now, updatedAt: now, hasIcon: hasIcon,
            screenOrientation: apk.launcherOrientation >= 0 ? apk.launcherOrientation : nil,
            skippedSplits: bundle.skippedSplits.isEmpty ? nil : bundle.skippedSplits.count)
        let enc = JSONEncoder()
        enc.outputFormatting = .prettyPrinted
        try enc.encode(info).write(to: staging.appendingPathComponent("package.json"))

        // Swap the new version in (the old one, if any, is removed; data and
        // the user's settings stay).
        if let oldSettings = try? Data(contentsOf: settingsURL(pkg)) {
            try? oldSettings.write(to: staging.appendingPathComponent("settings.json"))
        }
        try? fm.removeItem(at: dir)
        do {
            try fm.moveItem(at: staging, to: dir)
        } catch {
            try? fm.removeItem(at: staging)
            throw InstallError.copyFailed(error.localizedDescription)
        }
        _ = AppStorage(packageName: pkg).filesDir
        if !bundle.extraFiles.isEmpty { copyGameData(bundle.extraFiles, from: originalSource) }
        progress("Installed", 1)
        return info
    }

    /// OBB game data inside an XAPK goes to Shared Storage (Android/obb/…),
    /// where games look for it. Files over 64 MB are left for the user to
    /// copy, so unpacking can't run a 1 GB iPhone out of memory.
    private func copyGameData(_ names: [String], from bundleURL: URL) {
        guard let data = try? Data(contentsOf: bundleURL, options: .alwaysMapped), let zip = ZipArchive(data: data) else { return }
        let shared = AppStorage.sharedStorage
        for name in names where !name.contains("..") && zip.size(of: name) <= 64 << 20 {
            let rel = name.hasPrefix("Android/") ? name : "Android/obb/" + (name as NSString).lastPathComponent
            let dest = shared.appendingPathComponent(rel)
            try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            autoreleasepool { _ = zip.extract(name, to: dest) }
        }
    }

    // MARK: - Remove / clear

    /// Removes the app and all of its data.
    func uninstall(_ pkg: String) {
        try? fm.removeItem(at: appDir(pkg))
        clearData(pkg)
        try? fm.removeItem(at: AppStorage(packageName: pkg).dataDir)
        reload()
    }

    /// Like Android's "Clear storage": files, cache and SharedPreferences.
    func clearData(_ pkg: String) {
        let dataDir = AppStorage(packageName: pkg).dataDir
        if let items = try? fm.contentsOfDirectory(at: dataDir, includingPropertiesForKeys: nil) {
            for i in items { try? fm.removeItem(at: i) }
        }
        let prefix = "apk.prefs.\(pkg)."
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }

    func clearCache(_ pkg: String) {
        let cache = AppStorage(packageName: pkg).dataDir.appendingPathComponent("cache")
        try? fm.removeItem(at: cache)
    }

    // MARK: - Backup (Husk-style "Back Up Saves")

    enum BackupError: LocalizedError {
        case notABackup
        case otherApp(String)
        var errorDescription: String? {
            switch self {
            case .notABackup: return "This file is not an APK Sandbox backup."
            case .otherApp(let p): return "This backup belongs to another app (\(p))."
            }
        }
    }

    /// Everything the app saved (files, databases, SharedPreferences) as a .zip.
    func backup(_ pkg: String, label: String) throws -> URL {
        let z = ZipWriter()
        let meta: [String: Any] = ["package": pkg, "label": label, "date": ISO8601DateFormatter().string(from: Date()),
                                   "format": "apksandbox-backup-1"]
        z.add("backup.json", try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted]))
        var prefs: [String: Any] = [:]
        let prefix = "apk.prefs.\(pkg)."
        for (k, v) in UserDefaults.standard.dictionaryRepresentation() where k.hasPrefix(prefix) {
            prefs[String(k.dropFirst(prefix.count))] = v
        }
        z.add("shared_prefs.plist", try PropertyListSerialization.data(fromPropertyList: prefs, format: .xml, options: 0))
        let data = AppStorage(packageName: pkg).dataDir
        if let e = fm.enumerator(at: data, includingPropertiesForKeys: [.isDirectoryKey]) {
            let base = data.standardizedFileURL.path + "/"
            for case let f as URL in e {
                let path = f.standardizedFileURL.path
                guard path.hasPrefix(base) else { continue }
                let rel = String(path.dropFirst(base.count))
                if rel.hasPrefix("cache") { continue }
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue, let d = try? Data(contentsOf: f) {
                    z.add("data/" + rel, d)
                }
            }
        }
        let safe = label.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined(separator: "-")
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HHmm"
        let out = fm.temporaryDirectory.appendingPathComponent("\(safe) saves \(df.string(from: Date())).zip")
        try z.finish().write(to: out, options: .atomic)
        return out
    }

    /// Replaces what the app has saved with a backup made by `backup`.
    func restore(_ pkg: String, from url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let zip = ZipArchive(data: data), let metaBytes = zip.read("backup.json"),
              let meta = try? JSONSerialization.jsonObject(with: Data(metaBytes)) as? [String: Any] else {
            throw BackupError.notABackup
        }
        if let p = meta["package"] as? String, p != pkg { throw BackupError.otherApp(p) }
        clearData(pkg)
        let dataDir = AppStorage(packageName: pkg).dataDir
        for name in zip.names where name.hasPrefix("data/") && !name.hasSuffix("/") && !name.contains("..") {
            let dest = dataDir.appendingPathComponent(String(name.dropFirst(5)))
            try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let bytes = zip.read(name) { try Data(bytes).write(to: dest, options: .atomic) }
        }
        if let pb = zip.read("shared_prefs.plist"),
           let prefs = try? PropertyListSerialization.propertyList(from: Data(pb), options: [], format: nil) as? [String: Any] {
            for (k, v) in prefs { UserDefaults.standard.set(v, forKey: "apk.prefs.\(pkg).\(k)") }
        }
    }

    // MARK: - Sizes

    func storageUsed(_ pkg: String) -> (app: Int64, data: Int64) {
        return (folderSize(appDir(pkg)), folderSize(AppStorage(packageName: pkg).dataDir))
    }

    private func folderSize(_ url: URL) -> Int64 {
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            total += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    // MARK: - Launch

    /// Opens an installed app's APK, set up to memory-map its unpacked code.
    func open(_ pkg: String) throws -> ApkPackage {
        let apk = try ApkPackage(url: apkURL(pkg))
        apk.dexCacheDir = oatDir(pkg)
        return apk
    }

    private func excludeFromBackup(_ url: URL) {
        var u = url
        try? fm.createDirectory(at: u, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? u.setResourceValues(values)
    }
}
