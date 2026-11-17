import UIKit

/// Runs an APK: shows the Android activity on top and the log console below.
final class RunViewController: UIViewController, RunHost {

    private let apk: ApkPackage
    private var vm: VM?
    private var stack: [ActivityHost] = []

    private let screen = UIView()
    private let console = UITextView()
    private var consoleHeight: NSLayoutConstraint!
    private var logLines: [String] = []
    private var pendingLog: [String] = []
    private var logFlushScheduled = false
    private var consoleVisible = true
    private var closed = false

    init(apk: ApkPackage) {
        self.apk = apk
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.1, alpha: 1)
        title = apk.label
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "✕ Close", style: .plain, target: self, action: #selector(close))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Log", style: .plain, target: self, action: #selector(toggleConsole))

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

        let guide = view.safeAreaLayoutGuide
        consoleHeight = console.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.25)
        NSLayoutConstraint.activate([
            screen.topAnchor.constraint(equalTo: guide.topAnchor),
            screen.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            screen.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            screen.bottomAnchor.constraint(equalTo: console.topAnchor),
            console.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            console.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            console.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            consoleHeight
        ])

        start()
    }

    private func start() {
        appendLog("APK Sandbox – \(apk.label) (\(apk.packageName))")
        guard !apk.dexFiles.isEmpty else {
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
        let vm = VM(apk: apk)
        self.vm = vm
        vm.host = self
        vm.log = { [weak self] line in
            DispatchQueue.main.async { self?.appendLog(line) }
        }
        let desc = VMClass.descriptor(launcher)
        vm.post("launch") { [weak vm] in
            try vm?.launchActivity(desc, intent: nil)
        }
    }

    @objc private func close() {
        guard !closed else { return }
        closed = true
        vm?.shutdown()
        vm = nil
        dismiss(animated: true)
    }

    @objc private func back() {
        guard let top = stack.last else { return }
        if stack.count > 1, let vm = vm, let act = top.activity {
            vm.postCall(act, "onBackPressed")
        } else {
            close()
        }
    }

    @objc private func toggleConsole() {
        consoleVisible.toggle()
        consoleHeight.isActive = false
        consoleHeight = console.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: consoleVisible ? 0.25 : 0)
        consoleHeight.isActive = true
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }

    private func show(_ host: ActivityHost) {
        for v in screen.subviews { v.removeFromSuperview() }
        let sv = host.scrollView
        sv.translatesAutoresizingMaskIntoConstraints = false
        screen.addSubview(sv)
        NSLayoutConstraint.activate([
            sv.topAnchor.constraint(equalTo: screen.topAnchor),
            sv.leadingAnchor.constraint(equalTo: screen.leadingAnchor),
            sv.trailingAnchor.constraint(equalTo: screen.trailingAnchor),
            sv.bottomAnchor.constraint(equalTo: screen.bottomAnchor)
        ])
        title = host.title
        if stack.count > 1 {
            navigationItem.leftBarButtonItem = UIBarButtonItem(title: "‹ Back", style: .plain, target: self, action: #selector(back))
        } else {
            navigationItem.leftBarButtonItem = UIBarButtonItem(title: "✕ Close", style: .plain, target: self, action: #selector(close))
        }
    }

    // MARK: - Log

    func appendLog(_ line: String) {
        pendingLog.append(line)
        guard !logFlushScheduled else { return }
        logFlushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.flushLog() }
    }

    private func flushLog() {
        logFlushScheduled = false
        logLines += pendingLog
        pendingLog.removeAll()
        if logLines.count > 1500 { logLines.removeFirst(logLines.count - 1500) }
        console.text = logLines.joined(separator: "\n")
        let end = NSRange(location: max(0, (console.text as NSString).length - 1), length: 1)
        console.scrollRangeToVisible(end)
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
        if stack.last === activity { title = activity.title }
    }

    func showToast(_ text: String) {
        guard !closed else { return }
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
        a.addAction(UIAlertAction(title: "Keep open", style: .cancel))
        presentAlert(a)
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
