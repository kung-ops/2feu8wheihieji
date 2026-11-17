import Foundation

/// Where imported APKs are kept: Documents/ (visible in the Files app).
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

    /// Copies a picked / opened file into Documents and returns the copy.
    static func importFile(_ url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        // Already ours?
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
        if url.path.contains("/Inbox/") { try? fm.removeItem(at: url) }
        return dest
    }

    static func sizeString(_ url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? nil
        return ByteCountFormatter.string(fromByteCount: Int64(size ?? 0), countStyle: .file)
    }
}
