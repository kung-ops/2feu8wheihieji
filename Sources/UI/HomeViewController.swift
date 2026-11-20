import UIKit

/// The virtual Android phone's home screen: a clock, the installed apps and
/// a dock with Install, Downloads and Settings. Tap an app to open it, touch
/// and hold for App info, Clear storage and Uninstall.
final class HomeViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate,
                                UICollectionViewDelegateFlowLayout, UIDocumentPickerDelegate {

    private let gradient = CAGradientLayer()
    private let timeLabel = UILabel()
    private let dateLabel = UILabel()
    private let layout = UICollectionViewFlowLayout()
    private lazy var grid = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private let emptyLabel = UILabel()
    private let dock = UIStackView()
    private var apps: [InstalledApp] = []
    private var iconCache: [String: UIImage] = [:]
    private var clockTimer: Timer?

    override var preferredStatusBarStyle: UIStatusBarStyle { return .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Home"
        gradient.colors = [Theme.wallpaperTop.cgColor, Theme.wallpaperBottom.cgColor]
        gradient.startPoint = CGPoint(x: 0.2, y: 0)
        gradient.endPoint = CGPoint(x: 0.8, y: 1)
        view.layer.insertSublayer(gradient, at: 0)

        timeLabel.font = .systemFont(ofSize: 64, weight: .thin)
        timeLabel.textColor = .white
        dateLabel.font = .systemFont(ofSize: 16, weight: .medium)
        dateLabel.textColor = UIColor(white: 1, alpha: 0.85)
        for l in [timeLabel, dateLabel] {
            l.textAlignment = .center
            l.shadowColor = UIColor(white: 0, alpha: 0.3)
            l.shadowOffset = CGSize(width: 0, height: 1)
            l.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(l)
        }

        layout.minimumLineSpacing = 18
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = UIEdgeInsets(top: 8, left: 12, bottom: 16, right: 12)
        grid.backgroundColor = .clear
        grid.alwaysBounceVertical = true
        grid.dataSource = self
        grid.delegate = self
        grid.register(AppCell.self, forCellWithReuseIdentifier: "app")
        grid.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(grid)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(longPress(_:)))
        hold.minimumPressDuration = 0.45
        grid.addGestureRecognizer(hold)

        emptyLabel.text = "No apps installed yet.\n\nTap Install to add an Android app (.apk) from Files or iCloud Drive, or open an .apk with \"APK Sandbox\" from Safari, Mail or Files."
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = UIColor(white: 1, alpha: 0.85)
        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        let dockBackground = UIView()
        dockBackground.backgroundColor = UIColor(white: 1, alpha: 0.14)
        dockBackground.layer.cornerRadius = 26
        dockBackground.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dockBackground)
        dock.axis = .horizontal
        dock.distribution = .fillEqually
        dock.translatesAutoresizingMaskIntoConstraints = false
        dock.addArrangedSubview(dockButton("Install", Theme.glyphIcon("+", background: Theme.accent), #selector(installTapped)))
        dock.addArrangedSubview(dockButton("Downloads", Theme.glyphIcon("↓", background: UIColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1)), #selector(downloadsTapped)))
        dock.addArrangedSubview(dockButton("Settings", Theme.glyphIcon("⚙︎", background: UIColor(white: 0.45, alpha: 1)), #selector(settingsTapped)))
        view.addSubview(dock)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            timeLabel.topAnchor.constraint(equalTo: guide.topAnchor, constant: 18),
            timeLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dateLabel.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: -4),
            dateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            grid.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 22),
            grid.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            grid.bottomAnchor.constraint(equalTo: dockBackground.topAnchor, constant: -8),

            emptyLabel.centerYAnchor.constraint(equalTo: grid.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 36),
            emptyLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -36),

            dockBackground.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 14),
            dockBackground.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -14),
            dockBackground.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -10),
            dockBackground.heightAnchor.constraint(equalToConstant: 96),
            dock.topAnchor.constraint(equalTo: dockBackground.topAnchor, constant: 6),
            dock.bottomAnchor.constraint(equalTo: dockBackground.bottomAnchor, constant: -4),
            dock.leadingAnchor.constraint(equalTo: dockBackground.leadingAnchor, constant: 8),
            dock.trailingAnchor.constraint(equalTo: dockBackground.trailingAnchor, constant: -8)
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: TaskManager.changed, object: nil)
        installBuiltInAppsIfNeeded()
        NotificationCenter.default.addObserver(self, selector: #selector(updateClock), name: UIApplication.didBecomeActiveNotification, object: nil)
        updateClock()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.updateClock() }
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        reload()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if navigationController?.topViewController !== self {
            navigationController?.setNavigationBarHidden(false, animated: animated)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradient.frame = view.bounds
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        iconCache.removeAll()
    }

    private func dockButton(_ title: String, _ icon: UIImage, _ action: Selector) -> UIView {
        let b = UIButton(type: .custom)
        b.setImage(icon, for: .normal)
        b.addTarget(self, action: action, for: .touchUpInside)
        b.accessibilityLabel = title
        let l = UILabel()
        l.text = title
        l.font = .systemFont(ofSize: 12, weight: .medium)
        l.textColor = .white
        l.textAlignment = .center
        let s = UIStackView(arrangedSubviews: [b, l])
        s.axis = .vertical
        s.spacing = 2
        s.alignment = .center
        b.widthAnchor.constraint(equalToConstant: 56).isActive = true
        b.heightAnchor.constraint(equalToConstant: 56).isActive = true
        return s
    }

    @objc private func updateClock() {
        let t = DateFormatter()
        t.dateFormat = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: Locale.current) ?? "HH:mm"
        timeLabel.text = t.string(from: Date())
        let d = DateFormatter()
        d.dateFormat = DateFormatter.dateFormat(fromTemplate: "EEEEMMMMd", options: 0, locale: Locale.current) ?? "EEEE, MMMM d"
        dateLabel.text = d.string(from: Date())
    }

    /// First launch: LineageOS's Calculator and Easter Egg come preinstalled.
    private func installBuiltInAppsIfNeeded() {
        guard !PackageManager.shared.pendingBuiltInApps().isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            PackageManager.shared.installBuiltInApps()
            DispatchQueue.main.async { self?.reload() }
        }
    }

    @objc func reload() {
        guard isViewLoaded else { return }
        PackageManager.shared.reload()
        apps = PackageManager.shared.apps
        let present = Set(apps.map { $0.packageName })
        for k in iconCache.keys where !present.contains(k) { iconCache[k] = nil }
        emptyLabel.isHidden = !apps.isEmpty
        grid.reloadData()
    }

    // MARK: - Grid

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return apps.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "app", for: indexPath) as! AppCell
        let app = apps[indexPath.item]
        cell.label.text = PackageManager.shared.displayName(app)
        cell.icon.image = icon(app)
        cell.runningDot.isHidden = !TaskManager.shared.isRunning(app.packageName)
        cell.accessibilityLabel = cell.label.text
        return cell
    }

    private func icon(_ app: InstalledApp) -> UIImage {
        let key = app.packageName + "#" + String(app.updatedAt.timeIntervalSince1970)
        if let i = iconCache[key] { return i }
        let i = Theme.icon(for: app, side: 58)
        iconCache[key] = i
        return i
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let w = (collectionView.bounds.width - 24) / 4
        return CGSize(width: floor(w), height: 96)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        open(apps[indexPath.item])
    }

    private func open(_ app: InstalledApp) {
        TaskManager.shared.launch(app.packageName, from: self)
    }

    @objc private func longPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let ip = grid.indexPathForItem(at: g.location(in: grid)), ip.item < apps.count else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let app = apps[ip.item]
        let sheet = UIAlertController(title: PackageManager.shared.displayName(app), message: "Version \(app.versionName)", preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Open", style: .default) { [weak self] _ in self?.open(app) })
        sheet.addAction(UIAlertAction(title: "App info & game settings", style: .default) { [weak self] _ in self?.showInfo(app) })
        if TaskManager.shared.isRunning(app.packageName) {
            sheet.addAction(UIAlertAction(title: "Force stop", style: .default) { _ in TaskManager.shared.stop(app.packageName) })
        }
        sheet.addAction(UIAlertAction(title: "Uninstall", style: .destructive) { [weak self] _ in self?.confirmUninstall(app) })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        anchor(sheet, to: grid.cellForItem(at: ip))
        present(sheet, animated: true)
    }

    func showInfo(_ app: InstalledApp) {
        navigationController?.pushViewController(AppInfoViewController(packageName: app.packageName), animated: true)
    }

    private func confirmUninstall(_ app: InstalledApp) {
        let a = UIAlertController(title: "Uninstall \(app.label)?", message: "The app and all of its data will be removed.", preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        a.addAction(UIAlertAction(title: "Uninstall", style: .destructive) { [weak self] _ in
            TaskManager.shared.stop(app.packageName)
            PackageManager.shared.uninstall(app.packageName)
            self?.reload()
        })
        present(a, animated: true)
    }

    // MARK: - Dock

    @objc private func installTapped() {
        let sheet = UIAlertController(title: "Add a game or app", message: "APK files and app bundles (.apks, .xapk, .apkm).", preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Choose from Files", style: .default) { [weak self] _ in
            guard let self = self else { return }
            let picker = UIDocumentPickerViewController(documentTypes: ["com.android.package-archive", "public.data", "public.zip-archive"], in: .import)
            picker.delegate = self
            picker.allowsMultipleSelection = false
            self.present(picker, animated: true)
        })
        sheet.addAction(UIAlertAction(title: "Download from a link", style: .default) { [weak self] _ in
            guard let self = self else { return }
            LinkDownloader.ask(from: self) { [weak self] file in self?.install(file) }
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        anchor(sheet, to: dock)
        present(sheet, animated: true)
    }

    @objc private func downloadsTapped() {
        navigationController?.pushViewController(DownloadsViewController(), animated: true)
    }

    @objc private func settingsTapped() {
        navigationController?.pushViewController(DeviceSettingsViewController(style: .grouped), animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        install(url)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        install(url)
    }

    /// Shows the package installer for an APK from anywhere (picker, "Open in").
    func install(_ url: URL) {
        var delay = 0.05
        if let run = presentedViewController as? RunViewController {
            run.goHome()
            delay = 0.7
        } else if presentedViewController is UIDocumentPickerViewController {
            delay = 0.5
        } else if let presented = presentedViewController {
            presented.dismiss(animated: false)
        }
        navigationController?.popToRootViewController(animated: false)
        let staged: URL
        do {
            staged = try ApkStore.stage(url)
        } catch {
            showMessage("Couldn't read the file", error.localizedDescription)
            return
        }
        let installer = InstallerViewController(apkURL: staged, temporary: true)
        installer.onFinish = { [weak self] pkg, openNow in
            self?.reload()
            guard let self = self, let pkg = pkg, openNow else { return }
            TaskManager.shared.launch(pkg, from: self)
        }
        let nav = AppNavigationController(rootViewController: installer)
        nav.modalPresentationStyle = .formSheet
        if #available(iOS 13.0, *) { nav.isModalInPresentation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            var top: UIViewController = self
            while let p = top.presentedViewController, !p.isBeingDismissed { top = p }
            top.present(nav, animated: true)
        }
    }
}

/// One app on the home screen.
final class AppCell: UICollectionViewCell {
    let icon = UIImageView()
    let label = UILabel()
    let runningDot = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.shadowColor = UIColor(white: 0, alpha: 0.4)
        label.shadowOffset = CGSize(width: 0, height: 1)
        label.translatesAutoresizingMaskIntoConstraints = false
        runningDot.backgroundColor = UIColor(red: 0.45, green: 0.95, blue: 0.55, alpha: 1)
        runningDot.layer.cornerRadius = 4
        runningDot.isHidden = true
        runningDot.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(icon)
        contentView.addSubview(label)
        contentView.addSubview(runningDot)
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            icon.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant: 58),
            icon.heightAnchor.constraint(equalToConstant: 58),
            label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 5),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
            runningDot.widthAnchor.constraint(equalToConstant: 8),
            runningDot.heightAnchor.constraint(equalToConstant: 8),
            runningDot.centerXAnchor.constraint(equalTo: icon.trailingAnchor, constant: -4),
            runningDot.centerYAnchor.constraint(equalTo: icon.topAnchor, constant: 4)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isHighlighted: Bool {
        didSet { icon.alpha = isHighlighted ? 0.6 : 1 }
    }
}

/// Lets the visible screen pick the status bar style (light on the home
/// screen's dark wallpaper, dark on white screens).
final class AppNavigationController: UINavigationController {
    override var childForStatusBarStyle: UIViewController? { return topViewController }
    /// The virtual phone's own screens stay portrait; games turn on their own screen.
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { return .portrait }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { return .portrait }

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.styleNavigationBar(navigationBar)
    }
}
