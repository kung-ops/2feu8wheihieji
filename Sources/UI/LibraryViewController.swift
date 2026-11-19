import UIKit

/// Home screen: the list of imported APKs.
final class LibraryViewController: UITableViewController, UIDocumentPickerDelegate {

    private var files: [URL] = []
    private var icons: [URL: UIImage] = [:]
    private var labels: [URL: String] = [:]
    private let emptyLabel = UILabel()
    private let iconQueue = DispatchQueue(label: "apk-icons", qos: .utility)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "APK Sandbox"
        // Keep the existing + APK picker and add a separate optional PC media bridge.
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(pick)),
            UIBarButtonItem(title: "PC", style: .plain, target: self, action: #selector(openPCBridge))
        ]
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "About", style: .plain, target: self, action: #selector(about))
        tableView.rowHeight = 64
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "c")

        emptyLabel.text = "No APKs yet.\n\nTap + to choose an .apk file from Files or iCloud Drive, or use \"Open in APK Sandbox\" from Safari, Mail or the Files app."
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = .gray
        emptyLabel.font = .systemFont(ofSize: 15)

        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(reloadPulled), for: .valueChanged)
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: UIApplication.didBecomeActiveNotification, object: nil)
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    @objc func reload() {
        files = ApkStore.all()
        tableView.reloadData()
        if files.isEmpty {
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
        let picker = UIDocumentPickerViewController(documentTypes: ["com.android.package-archive", "public.data", "public.zip-archive"], in: .import)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    @objc private func openPCBridge() {
        navigationController?.pushViewController(PCBridgeViewController(), animated: true)
    }

    @objc private func about() {
        let msg = """
        APK Sandbox opens Android apps (.apk) and runs their Java/Kotlin bytecode with a small built-in Dalvik interpreter. Layouts are drawn with native iOS views.

        Works best with simple apps: text, buttons, text fields, checkboxes, Toasts, dialogs, several screens.

        Not supported: native code (.so), games/OpenGL, WebView, lists (RecyclerView), Google Play services, networking.
        """
        let a = UIAlertController(title: "About (build \(buildCommit))", message: msg, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        present(a, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        importAndOpen(url)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        importAndOpen(url)
    }

    func importAndOpen(_ url: URL) {
        do {
            let local = try ApkStore.importFile(url)
            reload()
            open(local)
        } catch {
            let a = UIAlertController(title: "Couldn't import", message: error.localizedDescription, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default))
            present(a, animated: true)
        }
    }

    func open(_ url: URL) {
        navigationController?.popToRootViewController(animated: false)
        navigationController?.pushViewController(ApkInfoViewController(url: url), animated: true)
    }

    // MARK: - Table

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return files.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let url = files[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = labels[url] ?? url.deletingPathExtension().lastPathComponent
        cell.detailTextLabel?.text = url.lastPathComponent + " · " + ApkStore.sizeString(url)
        cell.detailTextLabel?.textColor = .gray
        cell.accessoryType = .disclosureIndicator
        cell.imageView?.image = icons[url] ?? LibraryViewController.placeholderIcon
        cell.imageView?.layer.cornerRadius = 8
        cell.imageView?.clipsToBounds = true
        if icons[url] == nil && labels[url] == nil { loadIcon(url) }
        return cell
    }

    private func loadIcon(_ url: URL) {
        labels[url] = url.deletingPathExtension().lastPathComponent
        iconQueue.async { [weak self] in
            let pkg = try? ApkPackage(url: url)
            let img = pkg?.iconImage()
            let name = pkg?.label
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let img = img { self.icons[url] = LibraryViewController.resize(img) }
                if let name = name, !name.isEmpty { self.labels[url] = name }
                if let row = self.files.firstIndex(of: url) {
                    self.tableView.reloadRows(at: [IndexPath(row: row, section: 0)], with: .none)
                }
            }
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        open(files[indexPath.row])
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        let url = files[indexPath.row]
        try? FileManager.default.removeItem(at: url)
        files.remove(at: indexPath.row)
        tableView.deleteRows(at: [indexPath], with: .automatic)
        if files.isEmpty { reload() }
    }

    // MARK: - Images

    static func resize(_ img: UIImage, to side: CGFloat = 44) -> UIImage {
        let size = CGSize(width: side, height: side)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        img.draw(in: CGRect(origin: .zero, size: size))
        let out = UIGraphicsGetImageFromCurrentImageContext() ?? img
        UIGraphicsEndImageContext()
        return out
    }

    static let placeholderIcon: UIImage = {
        let size = CGSize(width: 44, height: 44)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        UIColor(red: 0.24, green: 0.86, blue: 0.52, alpha: 1).setFill()
        UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 10).fill()
        let text = "APK" as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 13), .foregroundColor: UIColor.white]
        let ts = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(x: (44 - ts.width) / 2, y: (44 - ts.height) / 2), withAttributes: attrs)
        let img = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return img
    }()
}
