import UIKit

/// An Android view rendered with UIKit. Lives in JObject.native.
/// UIKit properties are only touched on the main thread; listener
/// fields are only touched on the VM thread.
final class ViewBox: NSObject {
    enum Kind { case label, button, field, check, image, container, slider, progress, other }

    let kind: Kind
    let elementName: String
    let view: UIView            // outer view placed in the hierarchy
    let control: UIView         // the interactive / text-bearing part
    var checkLabel: UILabel?    // text of a CheckBox / Switch
    var iconLabel: UILabel?     // stand-in text for an icon we can't draw
    /// > 0: children are arranged in rows of this many (keypads).
    var gridColumns = 0
    private var gridRows: [UIStackView] = []
    var stack: UIStackView? { return control as? UIStackView }

    // VM-thread state
    var id: Int = -1
    var onClickAttr: String?
    var clickListener: JObject?
    var checkedListener: JObject?
    var seekListener: JObject?
    var tag: Value = .null
    var children: [ViewBox] = []
    weak var parent: ViewBox?
    weak var jobj: JObject?
    var maxProgress: Int32 = 100
    /// ListView / GridView (rows come from `adapter`).
    var isList = false
    var adapter: JObject?
    var itemClickListener: JObject?
    var itemLongClickListener: JObject?
    var emptyView: ViewBox?
    /// Row index when this view is a row of a list, else -1.
    var listPosition = -1
    /// Cursor / selection (UTF-16 offsets); -1 means "end of text".
    var selStart: Int = -1
    var selEnd: Int = -1

    /// Called on the main thread when the user interacts: (box, event, int value)
    var handler: ((ViewBox, String, Int32) -> Void)?

    private var tapInstalled = false

    init(kind: Kind, elementName: String, view: UIView, control: UIView) {
        self.kind = kind
        self.elementName = elementName
        self.view = view
        self.control = control
        super.init()
        #if canImport(ObjectiveC)
        switch kind {
        case .button:
            (control as? UIButton)?.addTarget(self, action: #selector(tapped), for: .touchUpInside)
        case .check:
            (control as? UISwitch)?.addTarget(self, action: #selector(switched), for: .valueChanged)
        case .slider:
            (control as? UISlider)?.addTarget(self, action: #selector(slid), for: .valueChanged)
        default:
            break
        }
        #endif
    }

    /// Lets non-button views receive clicks once a listener is attached.
    func makeTappable() {
        guard !tapInstalled, kind != .button, kind != .check, kind != .slider, kind != .field else { return }
        tapInstalled = true
        view.isUserInteractionEnabled = true
        #if canImport(ObjectiveC)
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        #endif
    }

    /// Same as the user tapping / toggling / sliding this view.
    func tap() { handler?(self, "click", 0) }
    func toggle() {
        let on = (control as? UISwitch)?.isOn ?? false
        handler?(self, "checked", on ? 1 : 0)
    }
    func slide() {
        let v = (control as? UISlider)?.value ?? 0
        handler?(self, "progress", Int32(v))
    }

    #if canImport(ObjectiveC)
    @objc private func tapped() { tap() }
    @objc private func switched() { toggle() }
    @objc private func slid() { slide() }
    #endif

    // MARK: main-thread accessors

    var text: String {
        get {
            switch control {
            case let l as UILabel: return l.text ?? ""
            case let b as UIButton: return b.title(for: .normal) ?? ""
            case let f as UITextField: return f.text ?? ""
            default: return checkLabel?.text ?? ""
            }
        }
        set {
            switch control {
            case let l as UILabel: l.text = newValue
            case let b as UIButton: b.setTitle(newValue, for: .normal)
            case let f as UITextField: f.text = newValue
            default: checkLabel?.text = newValue
            }
        }
    }

    func setTextColor(_ c: UIColor) {
        switch control {
        case let l as UILabel: l.textColor = c
        case let b as UIButton: b.setTitleColor(c, for: .normal)
        case let f as UITextField: f.textColor = c
        default: checkLabel?.textColor = c
        }
    }

    func setFontSize(_ size: CGFloat) {
        let s = max(6, min(size, 120))
        switch control {
        case let l as UILabel: l.font = l.font.withSize(s)
        case let b as UIButton: b.titleLabel?.font = b.titleLabel?.font.withSize(s)
        case let f as UITextField: f.font = f.font?.withSize(s)
        default: checkLabel?.font = checkLabel?.font.withSize(s)
        }
    }

    func setBold() {
        switch control {
        case let l as UILabel: l.font = UIFont.boldSystemFont(ofSize: l.font.pointSize)
        case let b as UIButton:
            let size = b.titleLabel?.font.pointSize ?? 17
            b.titleLabel?.font = UIFont.boldSystemFont(ofSize: size)
        default: break
        }
    }

    func setAlignment(_ a: NSTextAlignment) {
        switch control {
        case let l as UILabel: l.textAlignment = a
        case let f as UITextField: f.textAlignment = a
        case let s as UIStackView:
            if s.axis == .vertical { s.alignment = a == .center ? .center : (a == .right ? .trailing : .fill) }
        default: break
        }
    }

    /// Android visibility: 0 visible, 4 invisible, 8 gone
    func setVisibility(_ v: Int32) {
        view.isHidden = v == 8
        view.alpha = v == 4 ? 0 : 1
    }

    var visibility: Int32 {
        if view.isHidden { return 8 }
        return view.alpha == 0 ? 4 : 0
    }

    var isChecked: Bool {
        get { return (control as? UISwitch)?.isOn ?? false }
        set { (control as? UISwitch)?.setOn(newValue, animated: true) }
    }

    func addChild(_ c: ViewBox) {
        c.parent = self
        children.append(c)
        if gridColumns > 0, let s = stack {
            if gridRows.last == nil || gridRows.last!.arrangedSubviews.count >= gridColumns {
                let row = UIStackView()
                row.axis = .horizontal
                row.distribution = .fillEqually
                row.alignment = .fill
                row.spacing = 8
                s.addArrangedSubview(row)
                gridRows.append(row)
            }
            gridRows.last!.addArrangedSubview(c.view)
        } else if let s = stack {
            s.addArrangedSubview(c.view)
        } else {
            control.addSubview(c.view)
        }
    }

    func removeAllChildren() {
        for c in children {
            c.view.removeFromSuperview()
            c.parent = nil
        }
        for r in gridRows { r.removeFromSuperview() }
        gridRows.removeAll()
        children.removeAll()
    }

    /// Main thread: makes a list row look and behave like one (tappable,
    /// at least 44 pt tall, with a hairline under it).
    func decorateAsListRow() {
        makeTappable()
        let minHeight = view.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        minHeight.priority = UILayoutPriority(999)
        minHeight.isActive = true
        let line = UIView()
        line.backgroundColor = UIColor(white: 0.85, alpha: 1)
        line.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            line.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            line.heightAnchor.constraint(equalToConstant: 0.5)
        ])
    }

    func find(id: Int) -> ViewBox? {
        if self.id == id { return self }
        for c in children { if let f = c.find(id: id) { return f } }
        return nil
    }
}
