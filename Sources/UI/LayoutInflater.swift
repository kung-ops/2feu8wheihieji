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
        if s.contains("layout") || s.contains("scrollview") || s.contains("cardview") || s == "radiogroup"
            || s == "tablerow" || s == "viewgroup" || s.contains("viewflipper") || s == "merge" || s == "include" {
            return .container
        }
        if hasChildren { return .container }
        return .other
    }

    static func isUnsupportedWidget(_ element: String) -> Bool {
        let s = simpleName(element).lowercased()
        return ["webview", "recyclerview", "listview", "gridview", "surfaceview", "textureview",
                "videoview", "mapview", "fragmentcontainerview", "fragment", "viewpager", "viewpager2",
                "glsurfaceview", "spinner", "calendarview", "datepicker", "timepicker"].contains(s)
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
        let k = AndroidLayoutInflater.kind(for: element, hasChildren: hasChildren)
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
            return ViewBox(kind: k, elementName: element, view: st, control: st)
        case .other:
            let v = UIView()
            return ViewBox(kind: k, elementName: element, view: v, control: v)
        }
    }

    // MARK: - XML

    func inflate(_ node: AXMLNode) -> ViewBox {
        depth += 1
        defer { depth -= 1 }
        if node.name == "include", let ref = node.attr("layout"), ref.type == ResValue.typeReference,
           depth < 20, let sub = apk.layout(ref.data) {
            let box = inflate(sub)
            if let idv = node.attr("id"), idv.type == ResValue.typeReference { box.id = idv.data }
            return box
        }

        var orientation: Int? = nil
        if let o = node.attr("orientation") { orientation = o.data }
        let box = make(node.name, orientation: orientation, hasChildren: !node.children.isEmpty)
        apply(node, to: box)
        if box.kind == .container && depth < 40 {
            for c in node.children where c.name != "requestFocus" && c.name != "tag" {
                box.addChild(inflate(c))
            }
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
        if let h = node.attr("hint"), let f = box.control as? UITextField { f.placeholder = string(h) }
        if let ts = node.attr("textSize"), ts.type == ResValue.typeDimension { box.setFontSize(ts.dimension) }
        if let c = resolvedColor(node.attr("textColor")) { box.setTextColor(c) }
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
