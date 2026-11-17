import UIKit

/// Shows what's inside an APK and lets you run it.
final class ApkInfoViewController: UITableViewController {

    private let url: URL
    private var apk: ApkPackage?
    private var error: String?
    private let spinner = UIActivityIndicatorView(style: .gray)

    private enum Row { case info(String, String), action(String), list(String) }
    private var sections: [(title: String, rows: [Row])] = []

    init(url: URL) {
        self.url = url
        super.init(style: .grouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = url.deletingPathExtension().lastPathComponent
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "c")
        spinner.startAnimating()
        tableView.backgroundView = spinner
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var pkg: ApkPackage? = nil
            var err: String? = nil
            do { pkg = try ApkPackage(url: self.url, scanCode: true) } catch { err = error.localizedDescription }
            DispatchQueue.main.async {
                self.apk = pkg
                self.error = err
                self.build()
            }
        }
    }

    private func build() {
        spinner.stopAnimating()
        tableView.backgroundView = nil
        guard let apk = apk else {
            sections = [("Error", [.list(error ?? "Unknown error")])]
            tableView.reloadData()
            return
        }
        title = apk.label
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "▶︎ Run", style: .done, target: self, action: #selector(run))
        tableView.tableHeaderView = header(apk)

        var info: [Row] = [.info("Package", apk.packageName)]
        if !apk.versionName.isEmpty { info.append(.info("Version", "\(apk.versionName) (\(apk.versionCode))")) }
        if !apk.minSdk.isEmpty { info.append(.info("Android", "min SDK \(apk.minSdk)" + (apk.targetSdk.isEmpty ? "" : ", target \(apk.targetSdk)"))) }
        info.append(.info("Code", "\(apk.dexNames.count) dex · \(apk.classCount) classes · \(apk.methodCount) methods"))
        info.append(.info("Start screen", apk.launcherActivity.map { AndroidLayoutInflater.simpleName($0) } ?? "none"))
        info.append(.info("File size", ApkStore.sizeString(url)))
        sections = [("App", info)]

        var notes: [Row] = []
        if !apk.nativeLibs.isEmpty {
            let abis = Set(apk.nativeLibs.compactMap { $0.split(separator: "/").dropFirst().first.map(String.init) })
            notes.append(.list("⚠︎ Contains \(apk.nativeLibs.count) native libraries (\(abis.sorted().joined(separator: ", "))). Native Android code can't run on iOS, so parts of this app will not work."))
        }
        if apk.dexNames.isEmpty { notes.append(.list("⚠︎ No classes.dex – there is no code to run.")) }
        if apk.launcherActivity == nil { notes.append(.list("⚠︎ No launcher activity found.")) }
        let heavy = apk.classCount > 3000
        if heavy { notes.append(.list("This is a large app (\(apk.classCount) classes). Large apps usually depend on parts of Android the sandbox doesn't have, so expect missing screens.")) }
        if !notes.isEmpty { sections.append(("Compatibility", notes)) }

        sections.append(("", [.action("▶︎ Run app"), .action("View AndroidManifest.xml")]))
        if !apk.permissions.isEmpty {
            sections.append(("Permissions (\(apk.permissions.count))", apk.permissions.map { .list($0.replacingOccurrences(of: "android.permission.", with: "")) }))
        }
        if !apk.activities.isEmpty {
            sections.append(("Activities (\(apk.activities.count))", apk.activities.map { .list($0) }))
        }
        tableView.reloadData()
    }

    private func header(_ apk: ApkPackage) -> UIView {
        let v = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 120))
        let iv = UIImageView(image: apk.iconImage() ?? LibraryViewController.placeholderIcon)
        iv.contentMode = .scaleAspectFit
        iv.layer.cornerRadius = 16
        iv.clipsToBounds = true
        let name = UILabel()
        name.text = apk.label
        name.font = .boldSystemFont(ofSize: 22)
        name.numberOfLines = 2
        let pkg = UILabel()
        pkg.text = apk.packageName
        pkg.font = .systemFont(ofSize: 13)
        pkg.textColor = .gray
        let texts = UIStackView(arrangedSubviews: [name, pkg])
        texts.axis = .vertical
        texts.spacing = 4
        let row = UIStackView(arrangedSubviews: [iv, texts])
        row.axis = .horizontal
        row.spacing = 16
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(row)
        NSLayoutConstraint.activate([
            iv.widthAnchor.constraint(equalToConstant: 72),
            iv.heightAnchor.constraint(equalToConstant: 72),
            row.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 20),
            row.trailingAnchor.constraint(lessThanOrEqualTo: v.trailingAnchor, constant: -20),
            row.centerYAnchor.constraint(equalTo: v.centerYAnchor)
        ])
        return v
    }

    @objc private func run() {
        guard let apk = apk else { return }
        var problems: [String] = []
        if !apk.nativeLibs.isEmpty { problems.append("it contains native Android code (.so) that can't run on iOS") }
        if apk.classCount > 8000 { problems.append("it's a very large app (\(apk.classCount) classes) built on Android libraries the sandbox doesn't have") }
        if apk.codeSize > 60 * 1024 * 1024 { problems.append("its code is \(apk.codeSize / 1_048_576) MB, which may be too much for this iPhone's memory") }
        if problems.isEmpty { startRun(apk); return }
        let a = UIAlertController(title: "This app probably won't run",
                                  message: "APK Sandbox can only run simple apps, and " + problems.joined(separator: "; ") + ".\n\nYou can still try – the log will show what fails.",
                                  preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Try anyway", style: .default) { [weak self] _ in self?.startRun(apk) })
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(a, animated: true)
    }

    private func startRun(_ apk: ApkPackage) {
        let vc = RunViewController(apk: apk)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    private func showManifest() {
        guard let apk = apk else { return }
        let vc = UIViewController()
        vc.title = "AndroidManifest.xml"
        let tv = UITextView()
        tv.isEditable = false
        tv.font = UIFont(name: "Menlo", size: 11)
        tv.text = apk.manifestText()
        vc.view = tv
        navigationController?.pushViewController(vc, animated: true)
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int { return sections.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let t = sections[section].title
        return t.isEmpty ? nil : t
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].rows.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = sections[indexPath.section].rows[indexPath.row]
        switch row {
        case .info(let k, let v):
            let c = UITableViewCell(style: .value1, reuseIdentifier: nil)
            c.textLabel?.text = k
            c.detailTextLabel?.text = v
            c.detailTextLabel?.numberOfLines = 2
            c.detailTextLabel?.adjustsFontSizeToFitWidth = true
            c.selectionStyle = .none
            return c
        case .action(let t):
            let c = UITableViewCell(style: .default, reuseIdentifier: nil)
            c.textLabel?.text = t
            c.textLabel?.textColor = c.tintColor ?? UIColor(red: 0, green: 0.48, blue: 1, alpha: 1)
            if t.hasPrefix("▶︎") { c.textLabel?.font = .boldSystemFont(ofSize: 17) }
            return c
        case .list(let t):
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
        if case .action(let t) = sections[indexPath.section].rows[indexPath.row] {
            if t.hasPrefix("▶︎") { run() } else { showManifest() }
        }
    }
}
