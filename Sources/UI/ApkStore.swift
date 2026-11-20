import Foundation

/// APK files the user keeps in the app's Documents folder ("Downloads"):
/// visible in the Files app under On My iPhone › APK Sandbox, and in
/// Finder / iTunes File Sharing.
enum ApkStore {
    static var documents: URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func all() -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        for dir in [documents, documents.appendingPathComponent("Inbox")] {
            let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
            out += items.filter { $0.pathExtension.lowercased() == "apk" }
        }
        return out.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
            return (da ?? .distantPast) > (db ?? .distantPast)
        }
    }

    /// Folder for APKs waiting in the installer (not shown in Files).
    static var staging: URL {
        return FileManager.default.temporaryDirectory.appendingPathComponent("incoming", isDirectory: true)
    }

    /// Makes a private copy of a picked / opened file for the installer.
    /// Copies handed to us by iOS (Inbox folders) are moved, not copied.
    static func stage(_ url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        var name = url.deletingPathExtension().lastPathComponent
        if name.isEmpty { name = "app" }
        let dest = staging.appendingPathComponent(String(UUID().uuidString.prefix(8)) + "-" + name + ".apk")
        let isInbox = url.path.contains("/Inbox/") || url.path.contains("-Inbox/")
        if isInbox, (try? fm.moveItem(at: url, to: dest)) != nil { return dest }
        try fm.copyItem(at: url, to: dest)
        return dest
    }

    /// Copies a picked file into Downloads (Documents) and returns the copy.
    static func importFile(_ url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        if url.standardizedFileURL.deletingLastPathComponent() == documents.standardizedFileURL { return url }
        var name = url.lastPathComponent
        if url.pathExtension.lowercased() != "apk" { name += ".apk" }
        var dest = documents.appendingPathComponent(name)
        var n = 2
        let base = (name as NSString).deletingPathExtension
        while fm.fileExists(atPath: dest.path) {
            dest = documents.appendingPathComponent("\(base) \(n).apk")
            n += 1
        }
        try fm.copyItem(at: url, to: dest)
        if url.path.contains("/Inbox/") || url.path.contains("-Inbox/") { try? fm.removeItem(at: url) }
        return dest
    }

    /// Removes leftovers from earlier installs.
    static func cleanStaging() {
        try? FileManager.default.removeItem(at: staging)
    }

    static func sizeString(_ url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? nil
        return ByteCountFormatter.string(fromByteCount: Int64(size ?? 0), countStyle: .file)
    }
}
