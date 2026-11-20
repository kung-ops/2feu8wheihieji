import UIKit

/// Keeps track of running apps on the virtual phone: the one on screen and
/// (on iPhones with 2 GB or more) one minimised in the background, like
/// Android's recent apps. Main thread only.
final class TaskManager {
    static let shared = TaskManager()
    static let changed = Notification.Name("TaskManagerChanged")

    /// Running sessions of installed apps, by package name.
    private(set) var sessions: [String: RunViewController] = [:]
    /// Packages in the background, least recently used first.
    private var background: [String] = []
    /// An APK running without being installed.
    private weak var adHoc: RunViewController?

    func isRunning(_ pkg: String) -> Bool { return sessions[pkg] != nil }

    /// Opens an installed app: brings it back if it is in the background,
    /// otherwise starts it.
    func launch(_ pkg: String, from presenter: UIViewController) {
        if let s = sessions[pkg], !s.closed {
            background.removeAll { $0 == pkg }
            presenter.present(s, animated: true) { s.resumeFromBackground() }
            notify()
            return
        }
        makeRoom(keeping: VirtualDevice.backgroundApps)
        let apk: ApkPackage
        do {
            apk = try PackageManager.shared.open(pkg)
        } catch {
            presenter.showMessage("Can't open app", error.localizedDescription)
            return
        }
        let s = RunViewController(apk: apk, packageName: pkg)
        s.onEnd = { [weak self] s in self?.ended(s) }
        s.onMinimize = { [weak self] s in self?.minimized(s) }
        sessions[pkg] = s
        presenter.present(s, animated: true)
        notify()
    }

    /// Runs an APK that isn't installed (from Downloads → Details → Run).
    func runUninstalled(_ apk: ApkPackage, from presenter: UIViewController) {
        makeRoom(keeping: 0)
        let s = RunViewController(apk: apk, packageName: nil)
        adHoc = s
        presenter.present(s, animated: true)
    }

    /// Force stop.
    func stop(_ pkg: String) {
        sessions[pkg]?.close()
    }

    /// Low memory: background apps are killed first, like Android's
    /// low-memory killer; the app on screen frees its caches.
    func trimMemory() {
        for pkg in background { sessions[pkg]?.kill() }
        for s in sessions.values where !s.minimized { s.handleMemoryWarning() }
        adHoc?.handleMemoryWarning()
    }

    private func minimized(_ s: RunViewController) {
        guard let pkg = s.packageName else { return }
        background.removeAll { $0 == pkg }
        background.append(pkg)
        makeRoom(keeping: VirtualDevice.backgroundApps)
        notify()
    }

    private func ended(_ s: RunViewController) {
        guard let pkg = s.packageName, sessions[pkg] === s else { return }
        sessions[pkg] = nil
        background.removeAll { $0 == pkg }
        notify()
    }

    /// Kills the oldest background apps until at most `keeping` are left.
    private func makeRoom(keeping: Int) {
        while background.count > keeping {
            let pkg = background.removeFirst()
            sessions[pkg]?.kill()
        }
    }

    private func notify() {
        NotificationCenter.default.post(name: TaskManager.changed, object: nil)
    }
}
