import UIKit

/// Settings › About phone for the virtual Android device, plus the real
/// iPhone's memory, PC Link and what APK Sandbox can run.
final class DeviceSettingsViewController: UITableViewController {

    private enum Row {
        case info(String, String)
        case action(String, () -> Void)
        case text(String)
    }
    private var sections: [(title: String, rows: [Row], footer: String?)] = []
    private var storageBytes: Int64?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        tableView.estimatedRowHeight = 44
        tableView.rowHeight = UITableView.automaticDimension
        build()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var total: Int64 = 0
            if let e = FileManager.default.enumerator(at: PackageManager.root, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let f as URL in e {
                    total += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                }
            }
            DispatchQueue.main.async {
                self?.storageBytes = total
                self?.build()
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        build()
    }

    private func build() {
        let ram = VirtualDevice.hostRAM
        let lowMem = VirtualDevice.isOneGigHost
        let running = TaskManager.shared.sessions.count
        sections = [
            ("Virtual Android phone", [
                .info("Model", VirtualDevice.model),
                .info("Android version", "\(VirtualDevice.release) (API \(VirtualDevice.sdkInt))"),
                .info("RAM", "\(VirtualDevice.ramBytes >> 20) MB"),
                .info("Memory per app", "\(VirtualDevice.heapLimit >> 20) MB"),
                .info("Apps installed", "\(PackageManager.shared.apps.count)"),
                .info("Storage used", storageBytes.map { Theme.bytes($0) } ?? "Calculating…"),
                .info("Running apps", "\(running)")
            ], "The virtual phone reports 1 GB of RAM to apps (Runtime, ActivityManager). How much each app really gets depends on this iPhone."),
            ("This iPhone", [
                .info("Model", Theme.deviceName),
                .info("iOS", UIDevice.current.systemVersion),
                .info("RAM", "\(ram >> 20) MB"),
                .info("APK Sandbox is using", ProcessMemory.megabytes(ProcessMemory.footprint())),
                .info("Memory mode", lowMem ? "Low memory (1 GB)" : "Standard"),
                .info("Apps kept in background", "\(VirtualDevice.backgroundApps)")
            ], lowMem
                ? "On 1 GB iPhones only one Android app runs at a time; pressing Home closes it."
                : "One app can stay paused in the background; it is stopped first if iOS runs low on memory."),
            ("Tools", [
                .action("Stop all apps", { [weak self] in
                    for pkg in Array(TaskManager.shared.sessions.keys) { TaskManager.shared.stop(pkg) }
                    self?.build()
                })
            ] + builtInRow() + [
                .action("Open-source notices", { [weak self] in
                    self?.navigationController?.pushViewController(NoticesViewController(), animated: true)
                }),
                .action("PC Link (audio, camera, microphone)", { [weak self] in
                    self?.navigationController?.pushViewController(PCLinkViewController(), animated: true)
                })
            ], nil),
            ("About APK Sandbox", [
                .info("Build", buildCommit),
                .text("""
                APK Sandbox runs Android apps' Java/Kotlin bytecode (classes.dex) with a built-in Dalvik interpreter and draws their layouts with native iOS views.

                Works best with simple apps: text, buttons, text fields, checkboxes, lists, timers, Toasts, dialogs, several screens, Canvas drawing, SharedPreferences, SQLite databases and files. Android 9's own resources (from LineageOS 16.0) are built in.

                Comes with LineageOS's Calculator and Android Easter Egg.

                Not supported: native code (.so), OpenGL, WebView, RecyclerView, Fragments, Jetpack Compose, Google Play services, networking.
                """)
            ], nil)
        ]
        tableView.reloadData()
    }

    /// "Reinstall Calculator, Android Easter Egg" when a built-in app was removed.
    private func builtInRow() -> [Row] {
        let missing = PackageManager.shared.pendingBuiltInApps(includingRemoved: true)
        guard !missing.isEmpty else { return [] }
        let names = missing.map { $0.package == "com.android.egg" ? "Android Easter Egg" : "Calculator" }
        return [.action("Reinstall built-in apps (\(names.joined(separator: ", ")))", { [weak self] in
            DispatchQueue.global(qos: .userInitiated).async {
                let done = PackageManager.shared.installBuiltInApps(includingRemoved: true)
                DispatchQueue.main.async {
                    PackageManager.shared.reload()
                    NotificationCenter.default.post(name: TaskManager.changed, object: nil)
                    self?.build()
                    let a = UIAlertController(title: done.isEmpty ? "Nothing installed" : "Installed",
                                              message: done.joined(separator: ", "), preferredStyle: .alert)
                    a.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(a, animated: true)
                }
            }
        })]
    }

    override func numberOfSections(in tableView: UITableView) -> Int { return sections.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return sections[section].title
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return sections[section].footer
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].rows.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch sections[indexPath.section].rows[indexPath.row] {
        case .info(let k, let v):
            let c = UITableViewCell(style: .value1, reuseIdentifier: nil)
            c.textLabel?.text = k
            c.detailTextLabel?.text = v
            c.detailTextLabel?.adjustsFontSizeToFitWidth = true
            c.detailTextLabel?.minimumScaleFactor = 0.6
            c.selectionStyle = .none
            return c
        case .action(let t, _):
            let c = UITableViewCell(style: .default, reuseIdentifier: nil)
            c.textLabel?.text = t
            c.textLabel?.textColor = Theme.accent
            c.accessoryType = .disclosureIndicator
            return c
        case .text(let t):
            let c = UITableViewCell(style: .default, reuseIdentifier: nil)
            c.textLabel?.text = t
            c.textLabel?.numberOfLines = 0
            c.textLabel?.font = .systemFont(ofSize: 14)
            c.selectionStyle = .none
            return c
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if case .action(_, let run) = sections[indexPath.section].rows[indexPath.row] { run() }
    }
}

/// The licenses of what APK Sandbox ships from Android / LineageOS.
final class NoticesViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Open-source notices"
        view.backgroundColor = .white
        let tv = UITextView()
        tv.isEditable = false
        tv.font = .systemFont(ofSize: 13)
        tv.translatesAutoresizingMaskIntoConstraints = false
        var text = ""
        if let u = Bundle.main.url(forResource: "PreinstalledApps-NOTICE", withExtension: "txt"),
           let s = try? String(contentsOf: u, encoding: .utf8) { text += s + "\n\n" }
        if let pack = FrameworkResources.shared, let n = pack.read("@android/NOTICE.txt") {
            text += String(decoding: n, as: UTF8.self)
        }
        tv.text = text.isEmpty ? "No notices found." : text
        view.addSubview(tv)
        NSLayoutConstraint.activate([
            tv.topAnchor.constraint(equalTo: view.topAnchor),
            tv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tv.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            tv.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8)
        ])
    }
}
