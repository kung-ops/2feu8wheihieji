import UIKit

/// Android's "App info" for an installed app: open, force stop, uninstall,
/// storage (clear storage / cache), details and permissions.
final class AppInfoViewController: UITableViewController {

    private let packageName: String
    private var app: InstalledApp?
    private var sizes: (app: Int64, data: Int64)?

    private enum Row {
        case info(String, String)
        case action(String, destructive: Bool, () -> Void)
        case text(String)
    }
    private var sections: [(title: String, rows: [Row], footer: String?)] = []

    init(packageName: String) {
        self.packageName = packageName
        super.init(style: .grouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "App info"
        tableView.estimatedRowHeight = 44
        tableView.rowHeight = UITableView.automaticDimension
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: TaskManager.changed, object: nil)
        refresh()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
    }

    @objc private func refresh() {
        guard isViewLoaded else { return }
        guard let app = PackageManager.shared.app(packageName) else {
            navigationController?.popViewController(animated: true)
            return
        }
        self.app = app
        tableView.tableHeaderView = header(app)
        build(app)
        let pkg = packageName
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let s = PackageManager.shared.storageUsed(pkg)
            DispatchQueue.main.async {
                guard let self = self, let app = self.app else { return }
                self.sizes = s
                self.build(app)
            }
        }
    }

    private func build(_ app: InstalledApp) {
        let running = TaskManager.shared.isRunning(app.packageName)
        var s: [(String, [Row], String?)] = []

        var storage: [Row] = []
        if let z = sizes {
            storage.append(.info("App", Theme.bytes(z.app)))
            storage.append(.info("User data", Theme.bytes(z.data)))
            storage.append(.info("Total", Theme.bytes(z.app + z.data)))
        } else {
            storage.append(.info("Size", "Calculating…"))
        }
        storage.append(.action("Clear storage", destructive: true, { [weak self] in self?.confirmClear() }))
        storage.append(.action("Clear cache", destructive: false, { [weak self] in
            PackageManager.shared.clearCache(app.packageName)
            self?.sizes = nil
            self?.refresh()
        }))
        s.append(("Storage", storage, nil))

        s.append(("Memory", [
            .info("Status", running ? "Running" : "Stopped"),
            .info("Memory limit", "\(VirtualDevice.heapLimit >> 20) MB of \(VirtualDevice.ramBytes >> 20) MB virtual RAM")
        ], "Apps that ask for more memory than the limit get java.lang.OutOfMemoryError instead of crashing APK Sandbox."))

        var details: [Row] = [
            .info("Package", app.packageName),
            .info("Version", "\(app.versionName) (\(app.versionCode))")
        ]
        if !app.minSdk.isEmpty { details.append(.info("Android", "\(app.minSdk)+" + (app.targetSdk.isEmpty ? "" : ", targets \(app.targetSdk)"))) }
        details.append(.info("Installed", Theme.date(app.installedAt)))
        if app.updatedAt.timeIntervalSince(app.installedAt) > 1 { details.append(.info("Updated", Theme.date(app.updatedAt))) }
        details.append(.info("Code", "\(app.dexCount) dex · \(app.classCount) classes · \(app.methodCount) methods"))
        details.append(.info("Start screen", app.launcherActivity.map { AndroidLayoutInflater.simpleName($0) } ?? "none"))
        details.append(.info("Screens", "\(app.activityCount)"))
        s.append(("Details", details, nil))

        if !app.nativeLibs.isEmpty {
            s.append(("Compatibility", [.text("Contains \(app.nativeLibs.count) native libraries (\(app.nativeABIs.joined(separator: ", "))). Native Android code can't run on iOS, so parts of this app won't work.")], nil))
        }
        if !app.permissions.isEmpty {
            s.append(("Permissions (\(app.permissions.count))",
                      app.permissions.map { .text($0.replacingOccurrences(of: "android.permission.", with: "")) },
                      "Android permissions are listed for information. Apps in the sandbox can't reach your iPhone's contacts, photos, location or other data."))
        }
        s.append(("Advanced", [
            .action("View AndroidManifest.xml", destructive: false, { [weak self] in self?.showManifest() }),
            .action("Share APK…", destructive: false, { [weak self] in self?.shareApk() })
        ], nil))
        sections = s.map { (title: $0.0, rows: $0.1, footer: $0.2) }
        tableView.reloadData()
    }

    private func header(_ app: InstalledApp) -> UIView {
        let v = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 190))
        let icon = UIImageView(image: Theme.icon(for: app, side: 72))
        let name = UILabel()
        name.text = app.label
        name.font = .boldSystemFont(ofSize: 21)
        name.textAlignment = .center
        let running = TaskManager.shared.isRunning(app.packageName)
        let open = headerButton("Open", #selector(openApp))
        let stop = headerButton("Force stop", #selector(forceStop))
        stop.isEnabled = running
        let remove = headerButton("Uninstall", #selector(uninstall))
        remove.setTitleColor(Theme.danger, for: .normal)
        let buttons = UIStackView(arrangedSubviews: [open, stop, remove])
        buttons.axis = .horizontal
        buttons.distribution = .fillEqually
        buttons.spacing = 10
        let stack = UIStackView(arrangedSubviews: [icon, name, buttons])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.setCustomSpacing(16, after: name)
        stack.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 72),
            icon.heightAnchor.constraint(equalToConstant: 72),
            buttons.widthAnchor.constraint(equalTo: v.widthAnchor, constant: -40),
            stack.topAnchor.constraint(equalTo: v.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -20)
        ])
        return v
    }

    private func headerButton(_ title: String, _ action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        b.backgroundColor = .white
        b.layer.cornerRadius = 10
        b.heightAnchor.constraint(equalToConstant: 44).isActive = true
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    // MARK: - Actions

    @objc private func openApp() {
        guard let nav = navigationController else { return }
        nav.popToRootViewController(animated: false)
        if let home = nav.viewControllers.first {
            TaskManager.shared.launch(packageName, from: home)
        }
    }

    @objc private func forceStop() {
        let a = UIAlertController(title: "Force stop?", message: "If you force stop an app, it may misbehave.", preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        a.addAction(UIAlertAction(title: "OK", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            TaskManager.shared.stop(self.packageName)
            self.refresh()
        })
        present(a, animated: true)
    }

    @objc private func uninstall() {
        guard let app = app else { return }
        let a = UIAlertController(title: "Uninstall \(app.label)?", message: "The app and all of its data will be removed.", preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        a.addAction(UIAlertAction(title: "Uninstall", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            TaskManager.shared.stop(self.packageName)
            PackageManager.shared.uninstall(self.packageName)
            self.navigationController?.popToRootViewController(animated: true)
        })
        present(a, animated: true)
    }

    private func confirmClear() {
        let a = UIAlertController(title: "Clear app storage?", message: "All this app's data – files, settings, accounts – will be deleted permanently.", preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        a.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            TaskManager.shared.stop(self.packageName)
            PackageManager.shared.clearData(self.packageName)
            self.sizes = nil
            self.refresh()
        })
        present(a, animated: true)
    }

    private func showManifest() {
        let pkg = packageName
        let vc = TextViewController(title: "AndroidManifest.xml", text: "Loading…")
        navigationController?.pushViewController(vc, animated: true)
        DispatchQueue.global(qos: .userInitiated).async {
            let text = (try? PackageManager.shared.open(pkg))?.manifestText() ?? "Could not read the manifest."
            DispatchQueue.main.async { vc.setText(text) }
        }
    }

    private func shareApk() {
        guard let app = app else { return }
        // Share a copy named after the app, not "base.apk".
        let safe = app.label.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined(separator: "-")
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe)-\(app.versionName).apk")
        try? FileManager.default.removeItem(at: out)
        do {
            try FileManager.default.copyItem(at: PackageManager.shared.apkURL(app.packageName), to: out)
        } catch {
            showMessage("Couldn't share", error.localizedDescription)
            return
        }
        let share = UIActivityViewController(activityItems: [out], applicationActivities: nil)
        if let pop = share.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 40, width: 1, height: 1)
        }
        present(share, animated: true)
    }

    // MARK: - Table

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
            c.detailTextLabel?.numberOfLines = 2
            c.detailTextLabel?.adjustsFontSizeToFitWidth = true
            c.detailTextLabel?.minimumScaleFactor = 0.6
            c.selectionStyle = .none
            return c
        case .action(let t, let destructive, _):
            let c = UITableViewCell(style: .default, reuseIdentifier: nil)
            c.textLabel?.text = t
            c.textLabel?.textColor = destructive ? Theme.danger : Theme.accent
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
        if case .action(_, _, let run) = sections[indexPath.section].rows[indexPath.row] { run() }
    }
}

/// A read-only monospaced text screen (manifest, logs).
final class TextViewController: UIViewController {
    private let textView = UITextView()
    private var text: String

    init(title: String, text: String) {
        self.text = text
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        textView.isEditable = false
        textView.font = UIFont(name: "Menlo", size: 11) ?? .systemFont(ofSize: 11)
        textView.backgroundColor = .white
        textView.textColor = .black
        textView.text = text
        view = textView
    }

    func setText(_ t: String) {
        text = t
        if isViewLoaded { textView.text = t }
    }
}
