import UIKit

/// APK files kept in APK Sandbox's Documents folder (Files › On My iPhone ›
/// APK Sandbox): install them, see details, or run one without installing.
final class DownloadsViewController: UITableViewController, UIDocumentPickerDelegate {

    private struct Item {
        let url: URL
        var label: String
        var icon: UIImage?
        var packageName: String?
        var versionCode: Int?
        var loaded = false
    }

    private var items: [Item] = []
    private let emptyLabel = UILabel()
    private let iconQueue = DispatchQueue(label: "apk-icons", qos: .utility)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Downloads"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(pick))
        tableView.rowHeight = 64
        emptyLabel.text = "No APK files here.\n\nTap + to copy an .apk from Files or iCloud Drive, or put .apk files in Files › On My iPhone › APK Sandbox."
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = .gray
        emptyLabel.font = .systemFont(ofSize: 15)
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(reloadPulled), for: .valueChanged)
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    @objc func reload() {
        guard isViewLoaded else { return }
        let old = Dictionary(items.map { ($0.url, $0) }, uniquingKeysWith: { a, _ in a })
        items = ApkStore.all().map { old[$0] ?? Item(url: $0, label: $0.deletingPathExtension().lastPathComponent) }
        tableView.reloadData()
        if items.isEmpty {
            emptyLabel.frame = tableView.bounds.insetBy(dx: 32, dy: 0)
            tableView.backgroundView = emptyLabel
        } else {
            tableView.backgroundView = nil
        }
    }

    @objc private func reloadPulled() {
        reload()
        refreshControl?.endRefreshing()
    }

    @objc private func pick() {
        let sheet = UIAlertController(title: "Add a game or app", message: "APK files and app bundles (.apks, .xapk, .apkm).", preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Choose from Files", style: .default) { [weak self] _ in self?.pickFiles() })
        sheet.addAction(UIAlertAction(title: "Download from a link", style: .default) { [weak self] _ in
            guard let self = self else { return }
            LinkDownloader.ask(from: self) { [weak self] file in
                self?.reload()
                self?.openInstaller(file)
            }
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController { pop.barButtonItem = navigationItem.rightBarButtonItem }
        present(sheet, animated: true)
    }

    private func pickFiles() {
        let picker = UIDocumentPickerViewController(documentTypes: ["com.android.package-archive", "public.data", "public.zip-archive"], in: .import)
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        var failed: [String] = []
        for u in urls {
            do { _ = try ApkStore.importFile(u) } catch { failed.append(u.lastPathComponent) }
        }
        reload()
        if !failed.isEmpty { showMessage("Couldn't copy", failed.joined(separator: "\n")) }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        documentPicker(controller, didPickDocumentsAt: [url])
    }

    // MARK: - Table

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return items.isEmpty ? nil : "Tap a file to install it. ⓘ shows details and lets you run an app without installing it. Swipe left to delete a file. Game data (OBB files) goes in the Shared Storage folder next to these files."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = items[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = item.label
        var detail = item.url.lastPathComponent + " · " + ApkStore.sizeString(item.url)
        if let pkg = item.packageName, let installed = PackageManager.shared.app(pkg) {
            let code = item.versionCode ?? 0
            detail += code > installed.versionNumber ? " · Update available" : " · Installed"
        }
        cell.detailTextLabel?.text = detail
        cell.detailTextLabel?.textColor = .gray
        cell.accessoryType = .detailButton
        cell.imageView?.image = item.icon ?? Theme.letterIcon(item.label, seed: item.url.lastPathComponent, side: 44)
        if !item.loaded { load(indexPath.row) }
        return cell
    }

    private func load(_ row: Int) {
        items[row].loaded = true
        let url = items[row].url
        iconQueue.async { [weak self] in
            let pkg = try? ApkPackage(url: url)
            let img = pkg?.iconImage(maxSide: 132).map { Theme.rounded($0, side: 44) }
            DispatchQueue.main.async {
                guard let self = self, let i = self.items.firstIndex(where: { $0.url == url }) else { return }
                if let pkg = pkg {
                    self.items[i].label = pkg.label
                    self.items[i].packageName = pkg.packageName
                    self.items[i].versionCode = Int(pkg.versionCode)
                }
                self.items[i].icon = img
                self.tableView.reloadRows(at: [IndexPath(row: i, section: 0)], with: .none)
            }
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        openInstaller(items[indexPath.row].url)
    }

    private func openInstaller(_ url: URL) {
        let installer = InstallerViewController(apkURL: url, temporary: false)
        installer.onFinish = { [weak self] pkg, openNow in
            self?.reload()
            guard let self = self, let pkg = pkg, openNow, let nav = self.navigationController,
                  let home = nav.viewControllers.first else { return }
            nav.popToRootViewController(animated: false)
            TaskManager.shared.launch(pkg, from: home)
        }
        let nav = AppNavigationController(rootViewController: installer)
        nav.modalPresentationStyle = .formSheet
        if #available(iOS 13.0, *) { nav.isModalInPresentation = true }
        present(nav, animated: true)
    }

    override func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        navigationController?.pushViewController(ApkInfoViewController(url: items[indexPath.row].url), animated: true)
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        try? FileManager.default.removeItem(at: items[indexPath.row].url)
        items.remove(at: indexPath.row)
        tableView.deleteRows(at: [indexPath], with: .automatic)
        if items.isEmpty { reload() }
    }
}
