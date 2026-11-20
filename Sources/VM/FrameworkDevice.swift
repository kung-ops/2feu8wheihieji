import Foundation

/// java.lang.Runtime
final class RuntimeBox {}
/// android.app.ActivityManager
final class ActivityManagerBox {}

/// The virtual device's system services: memory (Runtime, ActivityManager),
/// process info and the app's private folders.
extension Framework {

    static func deviceStatic(_ vm: VM, _ ref: DexMethodRef, _ a: [Value]) -> Ret? {
        let n = ref.name
        switch ref.classDesc {
        case "Ljava/lang/Runtime;":
            if n == "getRuntime" { return O(vm.newObject("Ljava/lang/Runtime;", native: RuntimeBox())) }
            return nil
        case "Landroid/app/ActivityManager;":
            switch n {
            case "isUserAMonkey", "isRunningInTestHarness", "isRunningInUserTestHarness": return B(false)
            case "isLowRamDeviceStatic": return B(true)
            default: return nil
            }
        case "Landroid/os/Process;":
            switch n {
            case "myPid", "myTid": return I(Int32(truncatingIfNeeded: ProcessInfo.processInfo.processIdentifier))
            case "myUid": return I(10_000 + Int32(abs(vm.apk.packageName.hashValue % 9_000)))
            case "killProcess":
                let h = vm.host
                DispatchQueue.main.async { h?.finishAll() }
                return .void
            case "setThreadPriority": return .void
            case "getElapsedCpuTime": return .val(.wide(Int64(ProcessInfo.processInfo.systemUptime * 1000)))
            default: return nil
            }
        case "Landroid/os/Environment;":
            switch n {
            case "getExternalStorageState": return S(vm, "mounted")
            case "getExternalStorageDirectory", "getDataDirectory", "getRootDirectory", "getDownloadCacheDirectory":
                return O(file(vm, vm.storage.externalDir.path))
            case "getExternalStoragePublicDirectory":
                let sub = (a.first?.o?.native as? String) ?? "Download"
                return O(file(vm, vm.storage.externalDir.appendingPathComponent(sub).path))
            case "isExternalStorageEmulated", "isExternalStorageRemovable": return B(n.hasSuffix("Emulated"))
            default: return nil
            }
        default:
            return nil
        }
    }

    static func runtimeMethod(_ vm: VM, _ ref: DexMethodRef) -> Ret? {
        let budget = HeapBudget.shared
        switch ref.name {
        case "maxMemory": return .val(.wide(Int64(budget.limit)))
        case "totalMemory": return .val(.wide(Int64(max(budget.usedBytes, min(budget.limit, 16 << 20)))))
        case "freeMemory":
            let total = max(budget.usedBytes, min(budget.limit, 16 << 20))
            return .val(.wide(Int64(total - budget.usedBytes)))
        case "availableProcessors": return I(Int32(max(1, ProcessInfo.processInfo.activeProcessorCount)))
        case "gc", "runFinalization", "addShutdownHook", "removeShutdownHook": return ref.ret == "Z" ? B(true) : .void
        case "exit", "halt":
            let h = vm.host
            DispatchQueue.main.async { h?.finishAll() }
            return .void
        default: return nil
        }
    }

    static func activityManagerMethod(_ vm: VM, _ ref: DexMethodRef, _ a: [Value]) -> Ret? {
        switch ref.name {
        case "getMemoryInfo":
            guard let mi = a.first?.o else { return .void }
            let total = VirtualDevice.ramBytes
            // Free RAM on the virtual phone: what our heap still has, plus a
            // slice the "system" keeps for itself.
            let avail = Int64(HeapBudget.shared.freeBytes) + 96 << 20
            mi.fields["totalMem"] = .wide(total)
            mi.fields["availMem"] = .wide(min(avail, total))
            mi.fields["threshold"] = .wide(64 << 20)
            mi.fields["lowMemory"] = .int(HeapBudget.shared.freeBytes < 16 << 20 ? 1 : 0)
            return .void
        case "getMemoryClass": return I(VirtualDevice.memoryClassMB)
        case "getLargeMemoryClass": return I(VirtualDevice.memoryClassMB)
        case "isLowRamDevice": return B(true)
        case "getLauncherLargeIconDensity": return I(320)
        case "getLauncherLargeIconSize": return I(96)
        case "isBackgroundRestricted", "isInLockTaskMode": return B(false)
        case "getRunningAppProcesses", "getRunningServices", "getAppTasks", "getRecentTasks", "getRunningTasks":
            return O(vm.newObject("Ljava/util/ArrayList;", native: ListBox(items: [])))
        case "killBackgroundProcesses": return .void
        case "clearApplicationUserData":
            let pkg = vm.apk.packageName
            DispatchQueue.main.async { AppData.clear(packageName: pkg) }
            return B(true)
        default: return nil
        }
    }

    /// Context.getSystemService(String or Class)
    static func systemService(_ vm: VM, _ ref: DexMethodRef, _ a: [Value]) -> Ret? {
        var name = ""
        if ref.params.first == "Ljava/lang/String;" {
            name = (a.first?.o?.native as? String) ?? ""
        } else if let cr = a.first?.o?.native as? ClassRef {
            switch cr.name {
            case "Landroid/app/ActivityManager;": name = "activity"
            case "Landroid/view/LayoutInflater;": name = "layout_inflater"
            default: name = cr.name
            }
        }
        switch name {
        case "activity": return O(vm.newObject("Landroid/app/ActivityManager;", native: ActivityManagerBox()))
        case "layout_inflater": return O(vm.newObject("Landroid/view/LayoutInflater;", native: InflaterBox()))
        default:
            vm.warnOnce("system service '\(name)' is not available on the virtual device")
            return O(nil)
        }
    }

    /// A java.io.File object for a path.
    static func file(_ vm: VM, _ path: String) -> JObject {
        let o = vm.newObject("Ljava/io/File;")
        o.fields["__path"] = .obj(vm.str(path))
        return o
    }

    /// Context's private folders (getFilesDir, getCacheDir, …).
    static func contextDir(_ vm: VM, _ ref: DexMethodRef, _ a: [Value]) -> Ret? {
        let s = vm.storage
        switch ref.name {
        case "getFilesDir": return O(file(vm, s.filesDir.path))
        case "getCacheDir", "getCodeCacheDir": return O(file(vm, s.cacheDir.path))
        case "getNoBackupFilesDir": return O(file(vm, s.filesDir.path))
        case "getDataDir": return O(file(vm, s.dataDir.path))
        case "getExternalFilesDir", "getExternalCacheDir":
            return O(file(vm, s.externalDir.appendingPathComponent(ref.name == "getExternalCacheDir" ? "cache" : "files").path))
        case "getDir":
            let name = (a.first?.o?.native as? String) ?? "app"
            let url = s.dataDir.appendingPathComponent("app_" + name)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return O(file(vm, url.path))
        case "getDatabasePath":
            let name = (a.first?.o?.native as? String) ?? "db"
            return O(file(vm, s.dataDir.appendingPathComponent("databases").appendingPathComponent(name).path))
        case "getPackageCodePath", "getPackageResourcePath":
            return S(vm, vm.apk.url.path)
        default: return nil
        }
    }

    // MARK: - java.io.File

    static func filePath(_ o: JObject) -> String? { return o.fields["__path"]?.o?.native as? String }

    static func fileConstruct(_ vm: VM, _ t: JObject, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        guard ref.classDesc == "Ljava/io/File;" else { return nil }
        let p = ref.params
        var path = ""
        if p.count == 1 {
            path = (try? vm.stringOf(a[0].o)) ?? ""
        } else if p.count == 2 {
            let child = (try? vm.stringOf(a[1].o)) ?? ""
            let parent: String
            if p[0] == "Ljava/io/File;" { parent = a[0].o.flatMap(filePath) ?? "" } else { parent = (try? vm.stringOf(a[0].o)) ?? "" }
            path = parent.isEmpty ? child : (parent as NSString).appendingPathComponent(child)
        }
        t.fields["__path"] = .obj(vm.str(path))
        return .void
    }

    static func fileMethod(_ vm: VM, _ t: JObject, _ path: String, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        guard vm.storage.allows(path) else {
            if ["exists", "isFile", "isDirectory", "canRead", "canWrite", "mkdirs", "mkdir", "delete", "createNewFile"].contains(ref.name) {
                return B(false)
            }
            if ref.name != "getPath" && ref.name != "getAbsolutePath" && ref.name != "getName" && ref.name != "toString" {
                return nil
            }
            return S(vm, ref.name == "getName" ? (path as NSString).lastPathComponent : path)
        }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: path, isDirectory: &isDir)
        switch ref.name {
        case "getPath", "getAbsolutePath", "getCanonicalPath", "toString": return S(vm, path)
        case "getName": return S(vm, (path as NSString).lastPathComponent)
        case "getParent": return S(vm, (path as NSString).deletingLastPathComponent)
        case "getParentFile", "getAbsoluteFile", "getCanonicalFile":
            return O(file(vm, ref.name == "getParentFile" ? (path as NSString).deletingLastPathComponent : path))
        case "exists": return B(exists)
        case "isDirectory": return B(exists && isDir.boolValue)
        case "isFile": return B(exists && !isDir.boolValue)
        case "canRead", "canWrite": return B(exists)
        case "length":
            let size = (try? fm.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
            return .val(.wide(size))
        case "lastModified":
            let d = (try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? nil
            return .val(.wide(Int64((d?.timeIntervalSince1970 ?? 0) * 1000)))
        case "mkdir", "mkdirs":
            if exists { return B(false) }
            return B((try? fm.createDirectory(atPath: path, withIntermediateDirectories: ref.name == "mkdirs")) != nil)
        case "createNewFile":
            if exists { return B(false) }
            return B(fm.createFile(atPath: path, contents: Data()))
        case "delete":
            return B((try? fm.removeItem(atPath: path)) != nil)
        case "renameTo":
            guard let dest = a.first?.o.flatMap(filePath), vm.storage.allows(dest) else { return B(false) }
            return B((try? fm.moveItem(atPath: path, toPath: dest)) != nil)
        case "list", "listFiles":
            let names = ((try? fm.contentsOfDirectory(atPath: path)) ?? []).sorted()
            if ref.name == "list" {
                let items = names.map { Value.obj(vm.str($0)) }
                return O(vm.newObject("[Ljava/lang/String;", native: JArray(type: "[Ljava/lang/String;", items: items)))
            }
            let items = names.map { Value.obj(file(vm, (path as NSString).appendingPathComponent($0))) }
            return O(vm.newObject("[Ljava/io/File;", native: JArray(type: "[Ljava/io/File;", items: items)))
        case "setReadable", "setWritable", "setExecutable", "setLastModified": return B(true)
        case "equals": return B(a.first?.o.flatMap(filePath) == path)
        case "hashCode": return I(try vm.javaHash(vm.str(path)))
        default: return nil
        }
    }

    // MARK: - Simple whole-file streams (FileOutputStream / FileInputStream)

    static func streamConstruct(_ vm: VM, _ t: JObject, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        switch ref.classDesc {
        case "Ljava/io/FileOutputStream;", "Ljava/io/FileInputStream;":
            var path: String? = nil
            if let f = a.first?.o { path = filePath(f) ?? (f.native as? String) }
            guard let p = path, vm.storage.allows(p) else {
                throw vm.throwable("Ljava/io/FileNotFoundException;", "\(path ?? "null"): open failed: EACCES (Permission denied)")
            }
            if ref.classDesc == "Ljava/io/FileInputStream;" {
                guard let data = FileManager.default.contents(atPath: p) else {
                    throw vm.throwable("Ljava/io/FileNotFoundException;", "\(p): open failed: ENOENT (No such file or directory)")
                }
                t.native = FileStreamBox(path: p, data: [UInt8](data), writing: false)
            } else {
                let append = ref.params.count > 1 && a[1].i != 0
                var start: [UInt8] = []
                if append, let d = FileManager.default.contents(atPath: p) { start = [UInt8](d) }
                t.native = FileStreamBox(path: p, data: start, writing: true)
                FileManager.default.createFile(atPath: p, contents: Data(start))
            }
            return .void
        default:
            return nil
        }
    }

    static func fileStreamMethod(_ vm: VM, _ t: JObject, _ fs: FileStreamBox, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        let p = ref.params
        switch ref.name {
        case "write":
            if p.first == "I" {
                fs.data.append(UInt8(truncatingIfNeeded: a[0].i))
            } else if let arr = a.first?.o?.native as? JArray {
                var bytes = arr.byteValues
                if p.count == 3 {
                    let off = max(0, Int(a[1].i)), len = max(0, Int(a[2].i))
                    bytes = Array(bytes.dropFirst(off).prefix(len))
                }
                fs.data += bytes
            }
            return .void
        case "flush", "close", "getFD", "sync":
            if fs.writing {
                FileManager.default.createFile(atPath: fs.path, contents: Data(fs.data))
            }
            return ref.ret == "V" ? .void : O(nil)
        case "read":
            if p.isEmpty {
                guard fs.position < fs.data.count else { return I(-1) }
                fs.position += 1
                return I(Int32(fs.data[fs.position - 1]))
            }
            guard let arr = a.first?.o?.native as? JArray else { throw vm.npe("read") }
            let off = p.count == 3 ? max(0, Int(a[1].i)) : 0
            let len = p.count == 3 ? max(0, Int(a[2].i)) : arr.count
            guard fs.position < fs.data.count else { return I(-1) }
            let n = min(len, fs.data.count - fs.position, arr.count - off)
            for k in 0..<max(0, n) { arr[off + k] = .int(Int32(Int8(bitPattern: fs.data[fs.position + k]))) }
            fs.position += max(0, n)
            return I(Int32(max(0, n)))
        case "available": return I(Int32(max(0, fs.data.count - fs.position)))
        case "skip":
            let k = max(0, min(Int(a[0].j), fs.data.count - fs.position))
            fs.position += k
            return .val(.wide(Int64(k)))
        case "readAllBytes":
            let rest = Array(fs.data[min(fs.position, fs.data.count)...])
            fs.position = fs.data.count
            return O(vm.newObject("[B", native: JArray(type: "[B", items: rest.map { .int(Int32(Int8(bitPattern: $0))) })))
        default: return nil
        }
    }
}

final class FileStreamBox {
    let path: String
    var data: [UInt8]
    var position = 0
    let writing: Bool
    init(path: String, data: [UInt8], writing: Bool) {
        self.path = path
        self.data = data
        self.writing = writing
    }
}
