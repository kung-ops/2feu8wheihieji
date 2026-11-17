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
    var viewObjects: [JObject] = []
    var rootBox: ViewBox?
    var finished = false

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
    func setContent(_ v: UIView) {
        root?.removeFromSuperview()
        root = v
        v.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(v)
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
