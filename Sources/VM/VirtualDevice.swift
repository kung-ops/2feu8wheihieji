import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// The Android phone the sandbox pretends to be: a 1 GB RAM, Android 9
/// "Go"-class device. Apps see these values through Build, ActivityManager
/// and Runtime; the real limits underneath depend on the iPhone.
enum VirtualDevice {
    static let ramBytes: Int64 = 1 << 30
    static let model = "Virtual Android 1GB"
    static let manufacturer = "APK Sandbox"
    static let brand = "apksandbox"
    static let device = "vandroid"
    static let sdkInt: Int32 = 28
    static let release = "9"

    /// Physical RAM of the iPhone we run on.
    static var hostRAM: UInt64 { return ProcessInfo.processInfo.physicalMemory }

    /// iPhones with 1 GB of RAM (iPhone 6 / 6 Plus, iPod touch 6, iPad mini 2/3).
    static var isOneGigHost: Bool { return hostRAM > 0 && hostRAM <= 1_300_000_000 }

    /// Java heap each app may use (Runtime.maxMemory()). Kept well inside what
    /// iOS lets one app use: about 650 MB on a 1 GB iPhone and 1.4 GB on a
    /// 2 GB iPhone 7.
    static var heapLimit: Int {
        let ram = hostRAM
        if ram == 0 { return 256 << 20 }
        if ram <= 1_300_000_000 { return 160 << 20 }
        if ram <= 2_300_000_000 { return 320 << 20 }
        return 512 << 20
    }

    /// Whole-app memory at which the VM refuses new allocations, so iOS never
    /// has to kill the app.
    static var footprintLimit: Int {
        let ram = hostRAM
        if ram == 0 { return 2048 << 20 }
        if ram <= 1_300_000_000 { return 430 << 20 }
        if ram <= 2_300_000_000 { return 950 << 20 }
        if ram <= 3_300_000_000 { return 1400 << 20 }
        return 1900 << 20
    }

    /// ActivityManager.getMemoryClass(), in MB.
    static var memoryClassMB: Int32 { return Int32(min(heapLimit >> 20, 256)) }

    /// Number of apps that may stay paused in the background.
    static var backgroundApps: Int { return isOneGigHost ? 0 : 1 }

    /// Lines kept in the log console.
    static var logLines: Int { return isOneGigHost ? 400 : 1500 }

    /// Largest bitmap side (in pixels) we decode; bigger images are downscaled.
    static var maxBitmapSide: Int { return isOneGigHost ? 1024 : 2048 }
}

/// Memory the app is really using, as iOS counts it for its memory limit.
enum ProcessMemory {
    static func footprint() -> Int {
        #if canImport(Darwin)
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int(info.phys_footprint) : 0
        #else
        guard let s = try? String(contentsOfFile: "/proc/self/statm", encoding: .utf8) else { return 0 }
        let parts = s.split(separator: " ")
        guard parts.count > 1, let pages = Int(parts[1]) else { return 0 }
        return pages * 4096
        #endif
    }

    static func megabytes(_ bytes: Int) -> String {
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}

/// Bytes used by Java arrays, checked before every allocation so an app that
/// wants too much gets java.lang.OutOfMemoryError instead of iOS killing
/// APK Sandbox.
final class HeapBudget {
    static let shared = HeapBudget()

    private let lock = NSLock()
    private var used = 0
    private var peakUsed = 0
    let limit = VirtualDevice.heapLimit

    func add(_ n: Int) {
        lock.lock()
        used += n
        if used > peakUsed { peakUsed = used }
        lock.unlock()
    }

    func remove(_ n: Int) {
        lock.lock()
        used -= n
        lock.unlock()
    }

    var usedBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        return max(0, used)
    }

    var peakBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        return peakUsed
    }

    var freeBytes: Int { return max(0, limit - usedBytes) }

    /// Whether `n` more bytes fit in the Java heap and in this iPhone's memory.
    func canAllocate(_ n: Int) -> Bool {
        if usedBytes + n > limit { return false }
        if n >= 256 * 1024 {
            let fp = ProcessMemory.footprint()
            if fp > 0 && fp + n > VirtualDevice.footprintLimit { return false }
        }
        return true
    }
}
