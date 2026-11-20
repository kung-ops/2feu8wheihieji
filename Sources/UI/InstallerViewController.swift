import UIKit

/// Android-style package installer: shows what the APK is, asks before
/// installing (or updating), then installs it into the virtual phone.
final class InstallerViewController: UIViewController {

    private let apkURL: URL
    /// Delete the APK file when done (it was a private copy).
    private let temporary: Bool
    private var apk: ApkPackage?
    /// What's in the file: the APK itself, or a bundle's base APK.
    private var bundle: ApkBundle.Resolved?
    private var installedPackage: String?
    private var finished = false

    /// (installed package or nil, user tapped Open)
    var onFinish: ((String?, Bool) -> Void)?

    private let scroll = UIScrollView()
    private let content = UIStackView()
    private let iconView = UIImageView()
    private let nameLabel = UILabel()
    private let versionLabel = UILabel()
    private let messageLabel = UILabel()
    private let progress = UIProgressView(progressViewStyle: .default)
    private let stepLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .gray)
    private let buttonBar = UIStackView()
    private let leftButton = UIButton(type: .system)
    private let rightButton = UIButton(type: .system)

    private enum Stage { case loading, ready, installing, done, failed }
    private var stage = Stage.loading

    init(apkURL: URL, temporary: Bool) {
        self.apkURL = apkURL
        self.temporary = temporary
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Package installer"
        view.backgroundColor = .white
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))

        iconView.contentMode = .scaleAspectFit
        iconView.widthAnchor.constraint(equalToConstant: 64).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 64).isActive = true
        nameLabel.font = .boldSystemFont(ofSize: 21)
        nameLabel.numberOfLines = 2
        versionLabel.font = .systemFont(ofSize: 14)
        versionLabel.textColor = Theme.secondaryText
        let names = UIStackView(arrangedSubviews: [nameLabel, versionLabel])
        names.axis = .vertical
        names.spacing = 2
        let header = UIStackView(arrangedSubviews: [iconView, names])
        header.axis = .horizontal
        header.spacing = 16
        header.alignment = .center

        messageLabel.font = .systemFont(ofSize: 16)
        messageLabel.numberOfLines = 0
        messageLabel.text = "Reading the app…"
        stepLabel.font = .systemFont(ofSize: 13)
        stepLabel.textColor = Theme.secondaryText
        stepLabel.numberOfLines = 0
        progress.progressTintColor = Theme.accent
        progress.isHidden = true
        stepLabel.isHidden = true
        spinner.startAnimating()

        content.axis = .vertical
        content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false
        for v in [header, divider(), messageLabel, spinner, progress, stepLabel] as [UIView] { content.addArrangedSubview(v) }
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        view.addSubview(scroll)

        for b in [leftButton, rightButton] {
            b.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
            b.setTitleColor(Theme.accent, for: .normal)
            b.heightAnchor.constraint(equalToConstant: 50).isActive = true
        }
        leftButton.setTitle("Cancel", for: .normal)
        leftButton.addTarget(self, action: #selector(leftTapped), for: .touchUpInside)
        rightButton.setTitle("Install", for: .normal)
        rightButton.addTarget(self, action: #selector(rightTapped), for: .touchUpInside)
        rightButton.isEnabled = false
        buttonBar.axis = .horizontal
        buttonBar.distribution = .fillEqually
        buttonBar.addArrangedSubview(leftButton)
        buttonBar.addArrangedSubview(rightButton)
        buttonBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(buttonBar)
        let line = divider()
        line.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(line)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: guide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: line.topAnchor),
            content.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 24),
            content.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -24),
            content.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -24),
            content.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -48),
            line.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            line.bottomAnchor.constraint(equalTo: buttonBar.topAnchor),
            buttonBar.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 12),
            buttonBar.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -12),
            buttonBar.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -6)
        ])

        let url = apkURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var pkg: ApkPackage? = nil
            var resolved: ApkBundle.Resolved? = nil
            var err: Error? = nil
            do {
                let r = try ApkBundle.resolve(url)
                resolved = r
                pkg = try ApkPackage(url: r.apk, scanCode: true)
            } catch { err = error }
            let icon = pkg?.iconImage(maxSide: 192)
            DispatchQueue.main.async {
                guard let self = self else {
                    if let r = resolved, r.temporary { try? FileManager.default.removeItem(at: r.apk) }
                    return
                }
                self.bundle = resolved
                if let pkg = pkg { self.showReady(pkg, icon: icon) } else { self.showFailure(err?.localizedDescription ?? "Unknown error") }
            }
        }
    }

    private func divider() -> UIView {
        let v = UIView()
        v.backgroundColor = UIColor(white: 0.85, alpha: 1)
        v.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        return v
    }

    private func section(_ title: String, _ body: String, warning: Bool = false) -> UIView {
        let t = UILabel()
        t.text = title.uppercased()
        t.font = .systemFont(ofSize: 12, weight: .semibold)
        t.textColor = warning ? UIColor(red: 0.62, green: 0.38, blue: 0, alpha: 1) : Theme.secondaryText
        let b = UILabel()
        b.text = body
        b.numberOfLines = 0
        b.font = .systemFont(ofSize: 14)
        b.textColor = UIColor(white: 0.2, alpha: 1)
        let s = UIStackView(arrangedSubviews: [t, b])
        s.axis = .vertical
        s.spacing = 4
        if warning {
            s.isLayoutMarginsRelativeArrangement = true
            s.layoutMargins = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
            let bg = UIView()
            bg.backgroundColor = UIColor(red: 1, green: 0.96, blue: 0.85, alpha: 1)
            bg.layer.cornerRadius = 10
            bg.translatesAutoresizingMaskIntoConstraints = false
            s.insertSubview(bg, at: 0)
            NSLayoutConstraint.activate([
                bg.topAnchor.constraint(equalTo: s.topAnchor), bg.bottomAnchor.constraint(equalTo: s.bottomAnchor),
                bg.leadingAnchor.constraint(equalTo: s.leadingAnchor), bg.trailingAnchor.constraint(equalTo: s.trailingAnchor)
            ])
        }
        return s
    }

    // MARK: - Stages

    private func showReady(_ apk: ApkPackage, icon: UIImage?) {
        self.apk = apk
        stage = .ready
        spinner.stopAnimating()
        spinner.isHidden = true
        iconView.image = icon ?? Theme.letterIcon(apk.label, seed: apk.packageName, side: 64)
        nameLabel.text = apk.label
        versionLabel.text = "Version \(apk.versionName.isEmpty ? "?" : apk.versionName)"
        guard PackageManager.isValidPackageName(apk.packageName) else {
            showFailure("The APK's package name is missing or invalid.")
            return
        }
        switch PackageManager.shared.installKind(apk) {
        case .new:
            messageLabel.text = "Do you want to install this app?"
            rightButton.setTitle("Install", for: .normal)
        case .update(let old):
            messageLabel.text = "Do you want to install an update to this existing app (version \(old.versionName))? Your existing data will not be lost."
            rightButton.setTitle("Update", for: .normal)
        case .downgrade(let old):
            messageLabel.text = "The installed version (\(old.versionName)) is newer than this one. Install this older version anyway? Your data will be kept."
            rightButton.setTitle("Install", for: .normal)
        case .reinstall:
            messageLabel.text = "This version is already installed. Install it again? Your data will be kept."
            rightButton.setTitle("Reinstall", for: .normal)
        }
        rightButton.isEnabled = true

        var notes: [String] = []
        if !apk.nativeLibs.isEmpty {
            notes.append("Contains native Android code (.so) that can't run on iOS – parts of the app will not work.")
        }
        if apk.dexNames.isEmpty { notes.append("Has no code (classes.dex), so it can't be opened.") }
        if apk.launcherActivity == nil { notes.append("Has no start screen (launcher activity).") }
        if apk.classCount > 8000 {
            notes.append("Very large app (\(apk.classCount) classes). APK Sandbox runs simple apps; this one will probably not work.")
        } else if apk.classCount > 3000 {
            notes.append("Large app (\(apk.classCount) classes): expect missing screens.")
        }
        if VirtualDevice.isOneGigHost && apk.codeSize > 24 << 20 {
            notes.append("Its code is \(apk.codeSize >> 20) MB, which is a lot for an iPhone with 1 GB of RAM.")
        }
        if !notes.isEmpty {
            content.addArrangedSubview(section("Compatibility", notes.map { "• " + $0 }.joined(separator: "\n"), warning: true))
        }
        if let b = bundle, b.temporary {
            var body = "This is an app bundle. Its main APK is installed"
            if !b.skippedSplits.isEmpty {
                body += "; \(b.skippedSplits.count) extra part(s) for other screen sizes, languages or native code are left out, so some pictures may be missing"
            }
            body += "."
            if !b.extraFiles.isEmpty {
                body += " Its game data (\(b.extraFiles.count) file(s)) is copied to Shared Storage."
            }
            content.addArrangedSubview(section("App bundle", body))
        }
        let perms = apk.permissions.map { $0.replacingOccurrences(of: "android.permission.", with: "") }
        if !perms.isEmpty {
            var body = perms.prefix(12).map { "• " + $0 }.joined(separator: "\n")
            if perms.count > 12 { body += "\n…and \(perms.count - 12) more" }
            content.addArrangedSubview(section("Permissions (\(perms.count)) – not granted to real iPhone data", body))
        }
        var details = "Package: \(apk.packageName)"
        if !apk.minSdk.isEmpty { details += "\nAndroid: \(apk.minSdk)+" + (apk.targetSdk.isEmpty ? "" : " (targets \(apk.targetSdk))") }
        details += "\nSize: \(ApkStore.sizeString(apkURL)), code \(apk.codeSize / 1024) KB in \(apk.dexNames.count) dex"
        content.addArrangedSubview(section("Details", details))
    }

    private func startInstall() {
        guard apk != nil, stage == .ready else { return }
        stage = .installing
        navigationItem.leftBarButtonItem?.isEnabled = false
        buttonBar.isHidden = true
        messageLabel.text = "Installing…"
        progress.isHidden = false
        stepLabel.isHidden = false
        progress.setProgress(0.02, animated: false)
        // Like Android, a running copy of the app is stopped before it's replaced.
        if let pkg = apk?.packageName { TaskManager.shared.stop(pkg) }
        let url = apkURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let info = try PackageManager.shared.install(from: url) { step, fraction in
                    DispatchQueue.main.async {
                        self?.stepLabel.text = step
                        self?.progress.setProgress(Float(fraction), animated: true)
                    }
                }
                DispatchQueue.main.async {
                    PackageManager.shared.reload()
                    self?.showInstalled(info)
                }
            } catch {
                DispatchQueue.main.async { self?.showFailure(error.localizedDescription) }
            }
        }
    }

    private func showInstalled(_ info: InstalledApp) {
        stage = .done
        installedPackage = info.packageName
        progress.isHidden = true
        stepLabel.isHidden = true
        messageLabel.text = "✓ App installed."
        navigationItem.leftBarButtonItem = nil
        buttonBar.isHidden = false
        leftButton.setTitle("Done", for: .normal)
        rightButton.setTitle("Open", for: .normal)
        rightButton.isEnabled = info.launcherActivity != nil && info.dexCount > 0
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func showFailure(_ why: String) {
        stage = .failed
        spinner.stopAnimating()
        spinner.isHidden = true
        progress.isHidden = true
        stepLabel.isHidden = true
        if nameLabel.text == nil { nameLabel.text = apkURL.deletingPathExtension().lastPathComponent }
        messageLabel.text = "✖ App not installed.\n\n" + why
        navigationItem.leftBarButtonItem = nil
        buttonBar.isHidden = false
        leftButton.setTitle("Done", for: .normal)
        rightButton.isHidden = true
    }

    // MARK: - Buttons

    @objc private func cancel() { finish(open: false) }

    @objc private func leftTapped() { finish(open: false) }

    @objc private func rightTapped() {
        switch stage {
        case .ready: startInstall()
        case .done: finish(open: true)
        default: break
        }
    }

    private func finish(open: Bool) {
        guard !finished, stage != .installing else { return }
        finished = true
        if temporary { try? FileManager.default.removeItem(at: apkURL) }
        if let b = bundle, b.temporary { try? FileManager.default.removeItem(at: b.apk) }
        let pkg = installedPackage
        let done = onFinish
        dismiss(animated: true) { done?(pkg, open) }
    }
}
