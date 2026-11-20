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

    /// Version code as a number, for update / downgrade checks.
    var versionNumber: Int { return Int(versionCode) ?? 0 }

    /// ABIs of the native libraries ("arm64-v8a", …).
    var nativeABIs: [String] {
        return Array(Set(nativeLibs.compactMap { $0.split(separator: "/").dropFirst().first.map(String.init) })).sorted()
    }
}

/// An app's private folders on the virtual device, like Android's
/// /data/data/<package>. Apps may only touch files inside these folders
/// (and the shared "sdcard").
struct AppStorage {
    let packageName: String

    var dataDir: URL { return PackageManager.root.appendingPathComponent("data").appendingPathComponent(packageName) }
    var filesDir: URL { return AppStorage.made(dataDir.appendingPathComponent("files")) }
    var cacheDir: URL { return AppStorage.made(dataDir.appendingPathComponent("cache")) }
    /// The shared "internal storage" every app can see (/sdcard).
    var externalDir: URL { return AppStorage.made(PackageManager.root.appendingPathComponent("sdcard")) }

    /// Whether an app may read or write `path`.
    func allows(_ path: String) -> Bool {
        let p = URL(fileURLWithPath: path).standardizedFileURL.path
        for dir in [dataDir, PackageManager.root.appendingPathComponent("sdcard")] {
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
        reload()
    }

    private var appsRoot: URL { return PackageManager.root.appendingPathComponent("app") }

    func appDir(_ pkg: String) -> URL { return appsRoot.appendingPathComponent(pkg) }
    func apkURL(_ pkg: String) -> URL { return appDir(pkg).appendingPathComponent("base.apk") }
    func iconURL(_ pkg: String) -> URL { return appDir(pkg).appendingPathComponent("icon.png") }
    func oatDir(_ pkg: String) -> URL { return appDir(pkg).appendingPathComponent("oat") }
    private func infoURL(_ pkg: String) -> URL { return appDir(pkg).appendingPathComponent("package.json") }

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
            installedAt: old?.installedAt ?? now, updatedAt: now, hasIcon: hasIcon)
        let enc = JSONEncoder()
        enc.outputFormatting = .prettyPrinted
        try enc.encode(info).write(to: staging.appendingPathComponent("package.json"))

        // Swap the new version in (the old one, if any, is removed; data stays).
        try? fm.removeItem(at: dir)
        do {
            try fm.moveItem(at: staging, to: dir)
        } catch {
            try? fm.removeItem(at: staging)
            throw InstallError.copyFailed(error.localizedDescription)
        }
        _ = AppStorage(packageName: pkg).filesDir
        progress("Installed", 1)
        return info
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
