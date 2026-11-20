import UIKit

/// Turns Android layout XML (and programmatic `new TextView(ctx)` calls)
/// into UIKit views. Main thread only.
final class AndroidLayoutInflater {
    let apk: ApkPackage
    private var depth = 0

    init(apk: ApkPackage) { self.apk = apk }

    static func simpleName(_ element: String) -> String {
        if let dot = element.lastIndex(of: ".") { return String(element[element.index(after: dot)...]) }
        if let slash = element.lastIndex(of: "/") {
            return String(element[element.index(after: slash)...]).replacingOccurrences(of: ";", with: "")
        }
        return element
    }

    static func color(_ argb: Int) -> UIColor {
        let a = CGFloat((argb >> 24) & 0xff) / 255
        let r = CGFloat((argb >> 16) & 0xff) / 255
        let g = CGFloat((argb >> 8) & 0xff) / 255
        let b = CGFloat(argb & 0xff) / 255
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }

    // MARK: - Factory

    static func kind(for element: String, hasChildren: Bool) -> ViewBox.Kind {
        let s = simpleName(element).lowercased()
        if s.contains("edittext") || s.contains("autocompletetextview") { return .field }
        if s.contains("checkbox") || s.contains("radiobutton") || s.contains("switch") || s.contains("togglebutton") { return .check }
        if s.contains("button") { return .button }
        if s.contains("textview") || s == "chip" { return .label }
        if s.contains("imageview") { return .image }
        if s.contains("seekbar") || s == "slider" || s == "ratingbar" { return .slider }
        if s.contains("progressbar") || s.contains("progressindicator") { return .progress }
        if s == "listview" || s == "gridview" { return .container }
        if s.contains("layout") || s.contains("scrollview") || s.contains("cardview") || s == "radiogroup"
            || s == "tablerow" || s == "viewgroup" || s.contains("viewflipper") || s == "merge" || s == "include" {
            return .container
        }
        if hasChildren { return .container }
        return .other
    }

    /// "Plus" → "+", "Division" → "÷" … for icon-only calculator-style keys.
    static func symbol(for description: String) -> String {
        let d = description.lowercased().trimmingCharacters(in: .whitespaces)
        let table: [(String, String)] = [
            ("plus", "+"), ("add", "+"), ("minus", "−"), ("subtract", "−"), ("multipl", "×"), ("times", "×"),
            ("divi", "÷"), ("equal", "="), ("calculat", "="), ("result", "="), ("percent", "%"), ("backspace", "⌫"), ("delete", "⌫"),
            ("clear", "C"), ("parenthes", "( )"), ("bracket", "( )"), ("plus/minus", "±"), ("decimal", "."),
            ("square root", "√"), ("menu", "☰"), ("more options", "⋮"), ("back", "‹"), ("search", "🔍"),
            ("settings", "⚙︎"), ("close", "✕"), ("history", "🕘"), ("share", "⇪")
        ]
        for (k, v) in table where d.hasPrefix(k) || d == k { return v }
        return description
    }

    static func isUnsupportedWidget(_ element: String) -> Bool {
        let s = simpleName(element).lowercased()
        return ["webview", "recyclerview", "surfaceview", "textureview",
                "videoview", "mapview", "fragmentcontainerview", "fragment", "viewpager", "viewpager2",
                "glsurfaceview", "spinner", "calendarview", "datepicker", "timepicker"].contains(s)
    }

    /// The widget kind for an element, looking through the app's own view
    /// classes: a custom class that extends TextView shows text, one that
    /// extends LinearLayout holds children, one that extends View draws.
    func kind(of element: String, hasChildren: Bool) -> ViewBox.Kind {
        if !element.hasPrefix("android."), let base = apk.frameworkAncestor(ofView: element) {
            let simple = AndroidLayoutInflater.simpleName(base)
            if simple == "View" || simple == "SurfaceView" || simple == "TextureView" {
                return hasChildren ? .container : .other
            }
            return AndroidLayoutInflater.kind(for: simple, hasChildren: hasChildren)
        }
        return AndroidLayoutInflater.kind(for: element, hasChildren: hasChildren)
    }

    /// Creates an empty widget for an element / class name.
    func make(_ element: String, orientation: Int? = nil, hasChildren: Bool = false) -> ViewBox {
        let simple = AndroidLayoutInflater.simpleName(element)
        if AndroidLayoutInflater.isUnsupportedWidget(element) {
            let l = UILabel()
            l.text = "[\(simple) is not supported in the sandbox]"
            l.textColor = .gray
            l.font = .italicSystemFont(ofSize: 13)
            l.numberOfLines = 0
            return ViewBox(kind: .other, elementName: element, view: l, control: l)
        }
        let k = kind(of: element, hasChildren: hasChildren)
        switch k {
        case .label:
            let l = UILabel()
            l.numberOfLines = 0
            l.font = .systemFont(ofSize: 15)
            l.textColor = .darkText
            return ViewBox(kind: k, elementName: element, view: l, control: l)
        case .button:
            let b = UIButton(type: .system)
            b.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
            b.titleLabel?.numberOfLines = 0
            b.backgroundColor = UIColor(red: 0.40, green: 0.31, blue: 0.64, alpha: 1)
            b.setTitleColor(.white, for: .normal)
            b.layer.cornerRadius = 6
            b.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
            return ViewBox(kind: k, elementName: element, view: b, control: b)
        case .field:
            let f = UITextField()
            f.borderStyle = .roundedRect
            f.font = .systemFont(ofSize: 15)
            f.autocapitalizationType = .none
            f.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
            return ViewBox(kind: k, elementName: element, view: f, control: f)
        case .check:
            let sw = UISwitch()
            let l = UILabel()
            l.numberOfLines = 0
            l.font = .systemFont(ofSize: 15)
            let row = UIStackView(arrangedSubviews: [sw, l])
            row.axis = .horizontal
            row.spacing = 10
            row.alignment = .center
            let box = ViewBox(kind: k, elementName: element, view: row, control: sw)
            box.checkLabel = l
            return box
        case .image:
            let iv = UIImageView()
            iv.contentMode = .scaleAspectFit
            iv.clipsToBounds = true
            return ViewBox(kind: k, elementName: element, view: iv, control: iv)
        case .slider:
            let s = UISlider()
            s.minimumValue = 0
            s.maximumValue = 100
            return ViewBox(kind: k, elementName: element, view: s, control: s)
        case .progress:
            let a = UIActivityIndicatorView(style: .gray)
            a.startAnimating()
            return ViewBox(kind: k, elementName: element, view: a, control: a)
        case .container:
            let st = UIStackView()
            let lower = simple.lowercased()
            var horizontal = false
            if let o = orientation { horizontal = o == 0 }
            else if lower == "linearlayout" || lower == "linearlayoutcompat" || lower == "tablerow" || lower == "horizontalscrollview" {
                horizontal = true   // Android's LinearLayout defaults to horizontal
            }
            st.axis = horizontal ? .horizontal : .vertical
            st.spacing = 8
            st.alignment = horizontal ? .center : .fill
            st.distribution = .fill
            let box = ViewBox(kind: k, elementName: element, view: st, control: st)
            if lower == "listview" || lower == "gridview" {
                // Rows come from the adapter; drawn as a plain list.
                box.isList = true
                st.axis = .vertical
                st.alignment = .fill
                st.spacing = 0
            }
            return box
        case .other:
            // Plain Views, and the app's own custom views (which may draw).
            let v = CanvasView()
            return ViewBox(kind: k, elementName: element, view: v, control: v)
        }
    }

    // MARK: - XML

    /// Adds the items of the element's style="@style/…" (and its parents) as
    /// attributes, behind the element's own ones, the way Android applies a
    /// style: e.g. a calculator key's android:onClick set in PadButtonStyle.
    func mergeStyle(_ node: AXMLNode) {
        guard !node.styleMerged else { return }
        node.styleMerged = true
        guard let st = node.attr("style"), st.type == ResValue.typeReference, st.data != 0,
              let table = apk.resources else { return }
        for (name, v) in table.styleItems(st.data) where node.attr(name) == nil {
            node.attrs.append((name, v))
        }
    }

    func inflate(_ node: AXMLNode) -> ViewBox {
        depth += 1
        defer { depth -= 1 }
        if node.name == "include", let ref = node.attr("layout"), ref.type == ResValue.typeReference,
           depth < 20, let sub = apk.layout(ref.data) {
            let box = inflate(sub)
            if let idv = node.attr("id"), idv.type == ResValue.typeReference { box.id = idv.data }
            return box
        }

        mergeStyle(node)
        var orientation: Int? = nil
        if let o = node.attr("orientation") { orientation = o.data }
        let box = make(node.name, orientation: orientation, hasChildren: !node.children.isEmpty)
        apply(node, to: box)
        if box.kind == .container && depth < 40 {
            let kids = node.children.filter { $0.name != "requestFocus" && $0.name != "tag" }
            // A custom/relative container made mostly of buttons (a keypad) is laid
            // out as a 4-column grid instead of one long column.
            let simple = AndroidLayoutInflater.simpleName(node.name).lowercased()
            let keyLike = kids.filter {
                let k = kind(of: $0.name, hasChildren: !$0.children.isEmpty)
                return k == .button || k == .image
            }.count
            if kids.count >= 8, keyLike * 10 >= kids.count * 8, !simple.contains("linearlayout"), !simple.contains("scrollview") {
                box.gridColumns = node.attr("columnCount").map { max(1, min(8, $0.data)) } ?? 4
            }
            for c in kids { box.addChild(inflate(c)) }
        }
        if box.kind == .image, let iv = box.control as? UIImageView, iv.image == nil,
           let desc = string(node.attr("contentDescription")), !desc.isEmpty {
            // Vector icons can't be drawn yet; show the icon's meaning as text.
            let l = UILabel()
            l.text = AndroidLayoutInflater.symbol(for: desc)
            l.textAlignment = .center
            l.font = .systemFont(ofSize: 22)
            l.translatesAutoresizingMaskIntoConstraints = false
            iv.addSubview(l)
            NSLayoutConstraint.activate([
                l.centerXAnchor.constraint(equalTo: iv.centerXAnchor),
                l.centerYAnchor.constraint(equalTo: iv.centerYAnchor)
            ])
            box.iconLabel = l
        }
        return box
    }

    private func string(_ v: ResValue?) -> String? {
        guard let v = v else { return nil }
        let s = apk.resolveString(v)
        return s
    }

    private func resolvedColor(_ v: ResValue?) -> UIColor? {
        guard var r = v else { return nil }
        if r.type == ResValue.typeReference, let res = apk.resources { r = res.resolve(r) }
        return r.isColor ? AndroidLayoutInflater.color(r.data) : nil
    }

    private func apply(_ node: AXMLNode, to box: ViewBox) {
        if let idv = node.attr("id"), idv.type == ResValue.typeReference { box.id = idv.data }
        if let t = node.attr("text") { box.text = string(t) ?? "" }
        // Icon-only buttons (their picture is a vector drawable we can't draw):
        // show their accessibility description instead, as a symbol if it's a common one.
        if box.kind == .button, box.text.isEmpty,
           let desc = string(node.attr("contentDescription") ?? node.attr("tooltipText")), !desc.isEmpty {
            box.text = AndroidLayoutInflater.symbol(for: desc)
        }
        if let h = node.attr("hint"), let f = box.control as? UITextField { f.placeholder = string(h) }
        if let ts = node.attr("textSize"), ts.type == ResValue.typeDimension { box.setFontSize(ts.dimension) }
        if var tc = node.attr("textColor") {
            if tc.type == ResValue.typeReference, let res = apk.resources { tc = res.resolve(tc) }
            if tc.isColor {
                box.textARGB = UInt32(truncatingIfNeeded: tc.data)
                box.setTextColor(AndroidLayoutInflater.color(tc.data))
            }
        }
        if let st = node.attr("textStyle"), st.data & 1 != 0 { box.setBold() }
        if let bg = resolvedColor(node.attr("background")) ?? resolvedColor(node.attr("backgroundTint")) {
            if box.kind == .button { box.control.backgroundColor = bg } else { box.view.backgroundColor = bg }
        }
        if let g = node.attr("gravity") {
            let h = g.data & 0x07
            if g.data & 0x11 == 0x11 || h == 0x01 { box.setAlignment(.center) }
            else if h == 0x05 || g.data & 0x800005 == 0x800005 { box.setAlignment(.right) }
        }
        if let vis = node.attr("visibility") { box.setVisibility(Int32(truncatingIfNeeded: vis.data)) }
        if let en = node.attr("enabled"), en.type == ResValue.typeBoolean, en.data == 0 {
            (box.control as? UIControl)?.isEnabled = false
        }
        if let ch = node.attr("checked"), ch.type == ResValue.typeBoolean, ch.data != 0,
           let sw = box.control as? UISwitch { sw.isOn = true }
        if let oc = node.attr("onClick"), let name = oc.string { box.onClickAttr = name }
        if let mx = node.attr("max"), let s = box.control as? UISlider {
            s.maximumValue = Float(max(1, mx.data))
            box.maxProgress = Int32(truncatingIfNeeded: mx.data)
        }
        if let pr = node.attr("progress"), let s = box.control as? UISlider { s.value = Float(pr.data) }
        if let src = node.attr("src") ?? node.attr("srcCompat"), src.type == ResValue.typeReference {
            let img = apk.image(resource: src.data)
            if let iv = box.control as? UIImageView { iv.image = img }
            else if let b = box.control as? UIButton, let img = img {
                b.setImage(img.withRenderingMode(.alwaysOriginal), for: .normal)
            }
        }
        if let st = box.stack, let pad = node.attr("padding"), pad.type == ResValue.typeDimension {
            let p = pad.dimension
            st.isLayoutMarginsRelativeArrangement = true
            st.layoutMargins = UIEdgeInsets(top: p, left: p, bottom: p, right: p)
        }

        // Fixed sizes (dp). match_parent / wrap_content are ints (-1 / -2) and are left to the stack.
        if let w = node.attr("layout_width"), w.type == ResValue.typeDimension, w.dimension > 0 {
            let c = box.view.widthAnchor.constraint(equalToConstant: min(w.dimension, 600))
            c.priority = UILayoutPriority(999)
            c.isActive = true
        }
        if let h = node.attr("layout_height"), h.type == ResValue.typeDimension, h.dimension > 0 {
            let c = box.view.heightAnchor.constraint(equalToConstant: min(h.dimension, 1200))
            c.priority = UILayoutPriority(999)
            c.isActive = true
        } else if box.kind == .image {
            let c = box.view.heightAnchor.constraint(equalToConstant: 120)
            c.priority = UILayoutPriority(750)
            c.isActive = true
        } else if box.kind == .other, box.view.backgroundColor != nil {
            let c = box.view.heightAnchor.constraint(equalToConstant: 1)
            c.priority = UILayoutPriority(250)
            c.isActive = true
        }
    }
}
