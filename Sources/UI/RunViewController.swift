import UIKit

/// Runs an APK full screen, dressed like an Android phone: an app bar on
/// top, the activity in the middle and the ◁ ○ □ navigation bar at the
/// bottom. The log console is hidden until you ask for it.
final class RunViewController: UIViewController, RunHost {

    let apk: ApkPackage
    /// Set for apps installed on the virtual phone (they can be minimised).
    let packageName: String?
    private(set) var vm: VM?
    private var stack: [ActivityHost] = []

    private let appBar = UIView()
    private let titleLabel = UILabel()
    private let screen = UIView()
    private let console = UITextView()
    private let navBar = UIStackView()
    private var consoleHeight: NSLayoutConstraint!
    private var logLines: [String] = []
    private var pendingLog: [String] = []
    private var logFlushScheduled = false
    private var consoleVisible = false
    private(set) var closed = false
    private(set) var minimized = false
    private var pendingAlerts: [UIAlertController] = []
    private var lastMemoryWarning = Date.distantPast

    // Husk-style game settings (installed apps).
    private var settings = AppSettings()
    private var manifestLandscape = false
    /// Orientation the app asked for at run time (Android constant), -1 none.
    private var requested: Int32 = -1
    private var chromeHidden = false
    private var shownSince: Date?
    private var playSeconds: Double = 0
    private var barConstraints: [NSLayoutConstraint] = []
    private var fullConstraints: [NSLayoutConstraint] = []

    /// Called once when the app has ended (closed, crashed and closed, killed).
    var onEnd: ((RunViewController) -> Void)?
    /// Called when the user pressed Home and the app keeps running.
    var onMinimize: ((RunViewController) -> Void)?

    init(apk: ApkPackage, packageName: String?) {
        self.apk = apk
        self.packageName = packageName
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        if let pkg = packageName {
            settings = PackageManager.shared.settings(pkg)
            manifestLandscape = PackageManager.shared.app(pkg)?.prefersLandscape ?? false
        } else {
            manifestLandscape = [0, 6, 8, 11].contains(apk.launcherOrientation)
        }
    }

    // MARK: - Orientation & full screen

    private var wantsLandscape: Bool {
        switch settings.orientation ?? 0 {
        case 1: return false
        case 2: return true
        default:
            if requested >= 0 { return [0, 6, 8, 11].contains(Int(requested)) }
            return manifestLandscape
        }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return wantsLandscape ? .landscape : .portrait
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return wantsLandscape ? .landscapeRight : .portrait
    }

    override var shouldAutorotate: Bool { return true }

    override var prefersStatusBarHidden: Bool { return chromeHidden }

    override var prefersHomeIndicatorAutoHidden: Bool { return chromeHidden }

    /// Activity.setRequestedOrientation from the app.
    func requestOrientation(_ androidOrientation: Int32) {
        requested = androidOrientation
        guard settings.orientation ?? 0 == 0 else { return }
        rotateToPreferred()
    }

    private func rotateToPreferred() {
        // iOS 12–15: ask UIKit to re-read supportedInterfaceOrientations, and
        // turn the screen if the app needs the other orientation.
        let target: UIInterfaceOrientation = wantsLandscape ? .landscapeRight : .portrait
        UIDevice.current.setValue(target.rawValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
    }

    /// Full screen hides the app bar and the ◁ ○ □ bar; three fingers bring them back.
    private func setChrome(hidden: Bool, animated: Bool) {
        chromeHidden = hidden
        appBar.isHidden = hidden
        navBar.isHidden = hidden
        if hidden {
            NSLayoutConstraint.deactivate(barConstraints)
            NSLayoutConstraint.activate(fullConstraints)
        } else {
            NSLayoutConstraint.deactivate(fullConstraints)
            NSLayoutConstraint.activate(barConstraints)
        }
        setNeedsStatusBarAppearanceUpdate()
        if animated {
            UIView.animate(withDuration: 0.2) { self.view.layoutIfNeeded() }
        }
    }

    @objc private func threeFingerTap() {
        guard settings.fullScreen ?? false else { return }
        setChrome(hidden: !chromeHidden, animated: true)
        if !chromeHidden {
            // Hide again after a few seconds, like Android's immersive mode.
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let self = self, !self.closed, self.settings.fullScreen ?? false, !self.chromeHidden else { return }
                self.setChrome(hidden: true, animated: true)
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var preferredStatusBarStyle: UIStatusBarStyle { return .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.navBar

        appBar.backgroundColor = Theme.appBar
        appBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(appBar)
        titleLabel.text = apk.label
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 19, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        appBar.addSubview(titleLabel)
        let more = UIButton(type: .custom)
        more.setImage(Theme.navIcon(.menu), for: .normal)
        more.addTarget(self, action: #selector(showMenu), for: .touchUpInside)
        more.accessibilityLabel = "More options"
        more.translatesAutoresizingMaskIntoConstraints = false
        appBar.addSubview(more)

        screen.backgroundColor = .white
        screen.clipsToBounds = true
        screen.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(screen)

        console.isEditable = false
        console.backgroundColor = UIColor(white: 0.08, alpha: 1)
        console.textColor = UIColor(red: 0.55, green: 0.95, blue: 0.6, alpha: 1)
        console.font = UIFont(name: "Menlo", size: 10) ?? .systemFont(ofSize: 10)
        console.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(console)

        navBar.axis = .horizontal
        navBar.distribution = .fillEqually
        navBar.backgroundColor = Theme.navBar
        navBar.translatesAutoresizingMaskIntoConstraints = false
        for (key, action, name) in [(Theme.NavKey.back, #selector(back), "Back"),
                                    (Theme.NavKey.home, #selector(goHome), "Home"),
                                    (Theme.NavKey.recents, #selector(showMenu), "Recent apps")] {
            let b = UIButton(type: .custom)
            b.setImage(Theme.navIcon(key), for: .normal)
            b.addTarget(self, action: action, for: .touchUpInside)
            b.accessibilityLabel = name
            navBar.addArrangedSubview(b)
        }
        view.addSubview(navBar)

        let guide = view.safeAreaLayoutGuide
        consoleHeight = console.heightAnchor.constraint(equalToConstant: 0)
        barConstraints = [
            screen.topAnchor.constraint(equalTo: appBar.bottomAnchor),
            console.bottomAnchor.constraint(equalTo: navBar.topAnchor)
        ]
        fullConstraints = [
            screen.topAnchor.constraint(equalTo: view.topAnchor),
            console.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ]
        NSLayoutConstraint.activate(barConstraints)
        NSLayoutConstraint.activate([
            appBar.topAnchor.constraint(equalTo: view.topAnchor),
            appBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            appBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            appBar.bottomAnchor.constraint(equalTo: guide.topAnchor, constant: 52),
            titleLabel.leadingAnchor.constraint(equalTo: appBar.leadingAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: more.leadingAnchor, constant: -8),
            titleLabel.bottomAnchor.constraint(equalTo: appBar.bottomAnchor, constant: -14),
            more.trailingAnchor.constraint(equalTo: appBar.trailingAnchor, constant: -6),
            more.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            more.widthAnchor.constraint(equalToConstant: 44),
            more.heightAnchor.constraint(equalToConstant: 44),

            screen.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            screen.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            screen.bottomAnchor.constraint(equalTo: console.topAnchor),

            console.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            console.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            consoleHeight,

            navBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navBar.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            navBar.heightAnchor.constraint(equalToConstant: 48)
        ])
        // Black under the home indicator, like Android's gesture area.
        let bottomFill = UIView()
        bottomFill.backgroundColor = Theme.navBar
        bottomFill.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(bottomFill, belowSubview: navBar)
        NSLayoutConstraint.activate([
            bottomFill.topAnchor.constraint(equalTo: navBar.bottomAnchor),
            bottomFill.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomFill.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomFill.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        let three = UITapGestureRecognizer(target: self, action: #selector(threeFingerTap))
        three.numberOfTouchesRequired = 3
        three.cancelsTouchesInView = false
        view.addGestureRecognizer(three)
        if settings.fullScreen ?? false { setChrome(hidden: true, animated: false) }

        start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
        if let s = shownSince { playSeconds += Date().timeIntervalSince(s) }
        shownSince = nil
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        shownSince = Date()
        if settings.keepScreenOn ?? false { UIApplication.shared.isIdleTimerDisabled = true }
        if !pendingAlerts.isEmpty {
            let a = pendingAlerts.removeFirst()
            presentAlert(a)
        }
    }

    // MARK: - Start

    private func start() {
        appendLog("APK Sandbox build \(buildCommit) – \(apk.label) (\(apk.packageName))")
        appendLog("Virtual device: \(VirtualDevice.model), Android \(VirtualDevice.release), " +
                  "heap \(VirtualDevice.heapLimit >> 20) MB on \(Theme.deviceName) with \(VirtualDevice.hostRAM >> 20) MB RAM")
        guard !apk.dexNames.isEmpty else {
            showError(title: "Nothing to run", message: "This APK has no classes.dex, so there is no code to run.")
            return
        }
        guard let launcher = apk.launcherActivity else {
            showError(title: "Nothing to run", message: "This APK has no launcher activity.")
            return
        }
        if !apk.nativeLibs.isEmpty {
            appendLog("⚠︎ This APK contains native (.so) libraries – calls into native code will fail.")
        }
        appendLog("Loading \(apk.dexNames.count) dex file(s), \(apk.codeSize / 1024) KB…")
        let apk = self.apk
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            apk.loadCode()
            DispatchQueue.main.async {
                guard let self = self, !self.closed else { return }
                for issue in apk.codeErrors { self.appendLog("✖ " + issue) }
                guard !apk.dexFiles.isEmpty else {
                    let message = apk.codeErrors.isEmpty
                        ? "No valid DEX bytecode could be loaded."
                        : apk.codeErrors.joined(separator: "\n")
                    self.showError(title: "DEX loading failed", message: message)
                    return
                }
                let desc = VMClass.descriptor(launcher)
                guard apk.dexFiles.contains(where: { $0.hasClass(desc) }) else {
                    self.showError(title: "Launcher missing",
                                   message: "\(launcher) was not found in the loaded DEX classes.")
                    return
                }
                self.appendLog(apk.dexCacheDir != nil ? "Code is memory-mapped from the installed app." : "Code unpacked into memory.")
                self.launch(launcher)
            }
        }
    }

    private func launch(_ launcher: String) {
        let vm = VM(apk: apk)
        self.vm = vm
        vm.host = self
        vm.log = { [weak self] line in
            DispatchQueue.main.async { self?.appendLog(line) }
        }
        let desc = VMClass.descriptor(launcher)
        vm.post("launch") { [weak vm] in
            guard let vm = vm else { return }
            defer {
                vm.log("DEX methods executed: \(vm.interpretedMethodCount); compatibility no-ops: \(vm.stubCallCount)")
            }
            try vm.launchActivity(desc, intent: nil)
        }
    }

    // MARK: - Memory

    /// Frees what can be rebuilt; stops the app only if the iPhone is still
    /// short of memory afterwards (not on the first warning, which on 1 GB
    /// iPhones can come from other apps). Called by TaskManager when iOS
    /// sends a memory warning.
    func handleMemoryWarning() {
        guard let vm = vm, !closed else { return }
        let now = Date()
        let since = now.timeIntervalSince(lastMemoryWarning)
        if since < 1 { return }
        let repeated = since < 10
        lastMemoryWarning = now
        if logLines.count > 100 { logLines.removeFirst(logLines.count - 100) }
        if !consoleVisible { console.text = "" }
        vm.trimMemory()
        appendLog("⚠︎ iOS memory warning – freed caches (app memory \(ProcessMemory.megabytes(ProcessMemory.footprint())))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self = self, !self.closed else { return }
            let fp = ProcessMemory.footprint()
            if fp > VirtualDevice.footprintLimit || (repeated && fp > VirtualDevice.footprintLimit * 8 / 10) {
                self.kill()
                self.showErrorOnPresenter(title: "\(self.apk.label) stopped",
                                          message: "It needed more memory than this iPhone has free (\(ProcessMemory.megabytes(fp))).")
            }
        }
    }

    // MARK: - Navigation keys

    @objc private func back() {
        guard let vm = vm, let top = stack.last, let act = top.activity, !closed else {
            close()
            return
        }
        // Like Android: the activity decides (onBackPressed finishes it by default;
        // the last activity finishing closes the app).
        vm.postCall(act, "onBackPressed")
    }

    /// Home key: the app keeps running in the background if there is room,
    /// otherwise it is paused, stopped and closed.
    @objc func goHome() {
        guard !closed else { return }
        guard let vm = vm, packageName != nil, VirtualDevice.backgroundApps > 0 else {
            // No room to keep it in the background: stop it properly.
            if let vm = vm {
                vm.moveToBackground { [weak self] in self?.close() }
            } else {
                close()
            }
            return
        }
        minimized = true
        vm.moveToBackground()
        dismiss(animated: true)
        onMinimize?(self)
    }

    /// Brings a minimised app back (call after presenting this screen again).
    func resumeFromBackground() {
        guard minimized, !closed else { return }
        minimized = false
        vm?.moveToForeground()
    }

    @objc private func showMenu() {
        let sheet = UIAlertController(title: apk.label, message: apk.packageName, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: consoleVisible ? "Hide log" : "Show log", style: .default) { [weak self] _ in
            self?.toggleConsole()
        })
        if packageName != nil {
            sheet.addAction(UIAlertAction(title: "Restart app", style: .default) { [weak self] _ in self?.restart() })
        }
        sheet.addAction(UIAlertAction(title: "Close app", style: .default) { [weak self] _ in self?.closeGracefully() })
        sheet.addAction(UIAlertAction(title: "Force stop", style: .destructive) { [weak self] _ in self?.close() })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        anchor(sheet, to: navBar)
        present(sheet, animated: true)
    }

    private func restart() {
        guard let pkg = packageName else { return }
        let presenter = presentingViewController
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let p = presenter { TaskManager.shared.launch(pkg, from: p) }
        }
    }

    /// Runs onPause / onStop / onDestroy, then closes.
    private func closeGracefully() {
        guard let vm = vm, let host = stack.last else { close(); return }
        vm.post("close") { [weak vm] in
            guard let vm = vm else { return }
            for h in vm.activityStack.reversed() where h !== host { vm.finishActivity(h) }
            vm.finishActivity(host)
        }
    }

    private func toggleConsole() {
        consoleVisible.toggle()
        if consoleVisible { console.text = logLines.joined(separator: "\n") }
        consoleHeight.isActive = false
        consoleHeight = consoleVisible
            ? console.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.3)
            : console.heightAnchor.constraint(equalToConstant: 0)
        consoleHeight.isActive = true
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
        if consoleVisible { scrollConsoleToEnd() }
    }

    /// Stops the app at once (Force stop).
    func kill() {
        guard !closed else { return }
        closed = true
        vm?.shutdown()
        vm = nil
        if let s = shownSince { playSeconds += Date().timeIntervalSince(s) }
        shownSince = nil
        if let pkg = packageName {
            // Husk-style "last run" log and play time, shown in App info.
            let text = (logLines + pendingLog).suffix(400).joined(separator: "\n")
            PackageManager.shared.saveLastRunLog(pkg, text)
            PackageManager.shared.recordRun(pkg, seconds: playSeconds)
        }
        UIApplication.shared.isIdleTimerDisabled = false
        onEnd?(self)
    }

    @objc func close() {
        let wasMinimized = minimized
        kill()
        if !wasMinimized && presentingViewController != nil {
            dismiss(animated: true)
        }
    }

    private func show(_ host: ActivityHost) {
        for v in screen.subviews where !(v is PaddedLabel) { v.removeFromSuperview() }
        let sv = host.scrollView
        sv.translatesAutoresizingMaskIntoConstraints = false
        screen.insertSubview(sv, at: 0)
        NSLayoutConstraint.activate([
            sv.topAnchor.constraint(equalTo: screen.topAnchor),
            sv.leadingAnchor.constraint(equalTo: screen.leadingAnchor),
            sv.trailingAnchor.constraint(equalTo: screen.trailingAnchor),
            sv.bottomAnchor.constraint(equalTo: screen.bottomAnchor)
        ])
        titleLabel.text = host.title
    }

    // MARK: - Log

    func appendLog(_ line: String) {
        pendingLog.append(line)
        guard !logFlushScheduled else { return }
        logFlushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.flushLog() }
    }

    private func flushLog() {
        logFlushScheduled = false
        logLines += pendingLog
        pendingLog.removeAll()
        let cap = VirtualDevice.logLines
        if logLines.count > cap { logLines.removeFirst(logLines.count - cap) }
        guard consoleVisible else { return }
        console.text = logLines.joined(separator: "\n")
        scrollConsoleToEnd()
    }

    private func scrollConsoleToEnd() {
        let length = (console.text as NSString).length
        guard length > 0 else { return }
        console.scrollRangeToVisible(NSRange(location: length - 1, length: 1))
    }

    // MARK: - RunHost

    func push(_ activity: ActivityHost) {
        guard !closed else { return }
        stack.append(activity)
        show(activity)
    }

    func finish(_ activity: ActivityHost) {
        guard !closed else { return }
        stack.removeAll { $0 === activity }
        if let top = stack.last { show(top) } else { close() }
    }

    func finishAll() {
        close()
    }

    func titleChanged(_ activity: ActivityHost) {
        if stack.last === activity { titleLabel.text = activity.title }
    }

    func showToast(_ text: String) {
        guard !closed, view.window != nil else { return }
        let label = PaddedLabel()
        label.text = text
        label.numberOfLines = 3
        label.textAlignment = .center
        label.textColor = .white
        label.font = .systemFont(ofSize: 14)
        label.backgroundColor = UIColor(white: 0.2, alpha: 0.92)
        label.layer.cornerRadius = 16
        label.clipsToBounds = true
        label.alpha = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        screen.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: screen.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: screen.bottomAnchor, constant: -24),
            label.widthAnchor.constraint(lessThanOrEqualTo: screen.widthAnchor, constant: -48)
        ])
        UIView.animate(withDuration: 0.2, animations: { label.alpha = 1 }, completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 2.0, options: [], animations: { label.alpha = 0 }, completion: { _ in
                label.removeFromSuperview()
            })
        })
    }

    func showError(title: String, message: String) {
        guard !closed else { return }
        appendLog("✖ \(title): \(message)")
        let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Close app", style: .destructive) { [weak self] _ in self?.close() })
        a.addAction(UIAlertAction(title: "Show log", style: .default) { [weak self] _ in
            guard let self = self, !self.consoleVisible else { return }
            self.toggleConsole()
        })
        a.addAction(UIAlertAction(title: "Keep open", style: .cancel))
        presentAlert(a)
    }

    /// After the app is gone: show a message on whatever screen is visible.
    private func showErrorOnPresenter(title: String, message: String) {
        let presenter = presentingViewController
        let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        if presenter != nil {
            dismiss(animated: true) { presenter?.present(a, animated: true) }
        } else if let root = UIApplication.shared.keyWindow?.rootViewController {
            var top = root
            while let p = top.presentedViewController { top = p }
            top.present(a, animated: true)
        }
    }

    func showDialog(title: String?, message: String?, items: [String],
                    buttons: [(text: String, style: UIAlertAction.Style, action: () -> Void)],
                    itemTapped: ((Int) -> Void)?) {
        guard !closed else { return }
        let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
        for (i, item) in items.enumerated() {
            a.addAction(UIAlertAction(title: item, style: .default) { _ in itemTapped?(i) })
        }
        for b in buttons {
            a.addAction(UIAlertAction(title: b.text, style: b.style) { _ in b.action() })
        }
        if a.actions.isEmpty { a.addAction(UIAlertAction(title: "OK", style: .cancel)) }
        presentAlert(a)
    }

    private func presentAlert(_ a: UIAlertController) {
        guard view.window != nil else {
            // Minimised: show it when the app is opened again.
            if pendingAlerts.count < 3 { pendingAlerts.append(a) }
            return
        }
        var top: UIViewController = self
        while let p = top.presentedViewController { top = p }
        if top is UIAlertController {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.presentAlert(a) }
            return
        }
        top.present(a, animated: true)
    }

    deinit {
        vm?.shutdown()
    }
}

/// UILabel with padding, for toasts.
final class PaddedLabel: UILabel {
    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)))
    }
    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width: s.width + 32, height: s.height + 16)
    }
}
