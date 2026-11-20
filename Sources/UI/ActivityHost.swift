import UIKit

/// What the VM needs from the screen that hosts a running APK.
protocol RunHost: AnyObject {
    func showError(title: String, message: String)
    func showToast(_ text: String)
    func push(_ activity: ActivityHost)
    func finish(_ activity: ActivityHost)
    func titleChanged(_ activity: ActivityHost)
    func showDialog(title: String?, message: String?, items: [String],
                    buttons: [(text: String, style: UIAlertAction.Style, action: () -> Void)],
                    itemTapped: ((Int) -> Void)?)
    func finishAll()
    /// Activity.setRequestedOrientation (Android SCREEN_ORIENTATION_* value).
    func requestOrientation(_ androidOrientation: Int32)
}

extension RunHost {
    func requestOrientation(_ androidOrientation: Int32) {}
}

/// One running Android Activity: its Java object plus the UIKit view showing it.
final class ActivityHost {
    let className: String
    var title: String
    let scrollView = UIScrollView()
    private let content = UIView()
    private var root: UIView?

    // VM-thread state
    var activity: JObject?
    var intent: JObject?
    /// getWindow(): one Window object per activity.
    var window: JObject?
    var viewObjects: [JObject] = []
    var rootBox: ViewBox?
    var finished = false
    var requestedOrientation: Int32 = -1

    init(className: String, title: String) {
        self.className = className
        self.title = title
        scrollView.backgroundColor = .white
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    /// Main thread.
    func setContent(_ v: UIView) { setContent(v, fill: v is CanvasView) }

    /// Makes the current content fill the screen (it turned out to be a
    /// drawing, e.g. an ImageView showing an app Drawable).
    func fillScreen() {
        guard let r = root, scrollView.isScrollEnabled else { return }
        setContent(r, fill: true)
    }

    /// Android window background (Window.setBackgroundDrawable…).
    func setBackground(_ c: UIColor) {
        scrollView.backgroundColor = c
    }

    func setContent(_ v: UIView, fill: Bool) {
        root?.removeFromSuperview()
        root = v
        v.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(v)
        if fill {
            // A drawing view (a game) fills the screen and gets every touch.
            scrollView.isScrollEnabled = false
            NSLayoutConstraint.activate([
                v.topAnchor.constraint(equalTo: content.topAnchor),
                v.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                v.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                v.bottomAnchor.constraint(equalTo: content.bottomAnchor),
                v.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
            ])
            return
        }
        scrollView.isScrollEnabled = true
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            v.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            v.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            v.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -16)
        ])
        let h = content.heightAnchor.constraint(greaterThanOrEqualTo: v.heightAnchor, constant: 32)
        h.isActive = true
    }

    func findView(id: Int) -> JObject? {
        return rootBox?.find(id: id)?.jobj
    }
}
