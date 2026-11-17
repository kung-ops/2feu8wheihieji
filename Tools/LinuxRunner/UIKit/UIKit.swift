// Minimal Linux stand-in for the parts of UIKit the APK Sandbox engine uses.
// Views keep their state so the test runner can print the screen as text.
@_exported import Foundation

public typealias CGFloat = Foundation.CGFloat

public struct UIEdgeInsets { public var top, left, bottom, right: CGFloat
    public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) { self.top = top; self.left = left; self.bottom = bottom; self.right = right }
    public static let zero = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
}
public enum NSTextAlignment { case left, center, right, natural, justified }

public final class UIColor: Equatable {
    public let r, g, b, a: CGFloat
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { r = red; g = green; b = blue; a = alpha }
    public init(white: CGFloat, alpha: CGFloat) { r = white; g = white; b = white; a = alpha }
    public static let white = UIColor(white: 1, alpha: 1)
    public static let black = UIColor(white: 0, alpha: 1)
    public static let gray = UIColor(white: 0.5, alpha: 1)
    public static let darkText = UIColor(white: 0, alpha: 1)
    public static let clear = UIColor(white: 0, alpha: 0)
    public static func == (l: UIColor, r: UIColor) -> Bool { return l === r }
    public func setFill() {}
}

public final class UIFont {
    public let pointSize: CGFloat
    public let bold: Bool
    public init(size: CGFloat, bold: Bool = false) { pointSize = size; self.bold = bold }
    public convenience init?(name: String, size: CGFloat) { self.init(size: size) }
    public struct Weight { public static let regular = Weight(); public static let medium = Weight(); public static let semibold = Weight(); public static let bold = Weight() }
    public static func systemFont(ofSize s: CGFloat) -> UIFont { return UIFont(size: s) }
    public static func systemFont(ofSize s: CGFloat, weight: Weight) -> UIFont { return UIFont(size: s) }
    public static func boldSystemFont(ofSize s: CGFloat) -> UIFont { return UIFont(size: s, bold: true) }
    public static func italicSystemFont(ofSize s: CGFloat) -> UIFont { return UIFont(size: s) }
    public func withSize(_ s: CGFloat) -> UIFont { return UIFont(size: s, bold: bold) }
}

public final class UIImage {
    public let data: Data
    public init?(data: Data) { if data.isEmpty { return nil }; self.data = data }
    public enum RenderingMode { case alwaysOriginal, automatic }
    public func withRenderingMode(_ m: RenderingMode) -> UIImage { return self }
}

public struct UILayoutPriority { public let rawValue: Float; public init(_ v: Float) { rawValue = v } }
public final class NSLayoutConstraint {
    public var isActive = false
    public var priority = UILayoutPriority(1000)
    public static func activate(_ c: [NSLayoutConstraint]) { c.forEach { $0.isActive = true } }
    public init() {}
}
public final class NSLayoutDimension {
    public init() {}
    public func constraint(equalToConstant c: CGFloat) -> NSLayoutConstraint { return NSLayoutConstraint() }
    public func constraint(greaterThanOrEqualToConstant c: CGFloat) -> NSLayoutConstraint { return NSLayoutConstraint() }
    public func constraint(equalTo o: NSLayoutDimension) -> NSLayoutConstraint { return NSLayoutConstraint() }
    public func constraint(equalTo o: NSLayoutDimension, multiplier: CGFloat) -> NSLayoutConstraint { return NSLayoutConstraint() }
    public func constraint(greaterThanOrEqualTo o: NSLayoutDimension, constant: CGFloat) -> NSLayoutConstraint { return NSLayoutConstraint() }
}
public final class NSLayoutAnchorX {
    public init() {}
    public func constraint(equalTo o: NSLayoutAnchorX) -> NSLayoutConstraint { return NSLayoutConstraint() }
    public func constraint(equalTo o: NSLayoutAnchorX, constant: CGFloat) -> NSLayoutConstraint { return NSLayoutConstraint() }
    public func constraint(lessThanOrEqualTo o: NSLayoutAnchorX, constant: CGFloat) -> NSLayoutConstraint { return NSLayoutConstraint() }
}
public final class UILayoutGuide {
    public init() {}
    public let topAnchor = NSLayoutAnchorX(), bottomAnchor = NSLayoutAnchorX(), leadingAnchor = NSLayoutAnchorX(), trailingAnchor = NSLayoutAnchorX()
    public let widthAnchor = NSLayoutDimension(), heightAnchor = NSLayoutDimension()
}
public final class CALayer { public var cornerRadius: CGFloat = 0 }

open class UIView {
    public init() {}
    public var subviews: [UIView] = []
    public weak var superview: UIView?
    public var isHidden = false
    public var alpha: CGFloat = 1
    public var backgroundColor: UIColor?
    public var isUserInteractionEnabled = true
    public var translatesAutoresizingMaskIntoConstraints = true
    public var clipsToBounds = false
    public var bounds = CGRect(x: 0, y: 0, width: 320, height: 40)
    public var frame: CGRect { return bounds }
    public let layer = CALayer()
    public enum ContentMode { case scaleAspectFit, scaleToFill }
    public var contentMode = ContentMode.scaleToFill
    public let topAnchor = NSLayoutAnchorX(), bottomAnchor = NSLayoutAnchorX(), leadingAnchor = NSLayoutAnchorX(), trailingAnchor = NSLayoutAnchorX(), centerXAnchor = NSLayoutAnchorX(), centerYAnchor = NSLayoutAnchorX()
    public let widthAnchor = NSLayoutDimension(), heightAnchor = NSLayoutDimension()
    open func addSubview(_ v: UIView) { v.removeFromSuperview(); subviews.append(v); v.superview = self }
    public func removeFromSuperview() {
        if let s = superview { s.subviews.removeAll { $0 === self }; (s as? UIStackView)?.arrangedSubviews.removeAll { $0 === self } }
        superview = nil
    }
    public func addGestureRecognizer(_ g: AnyObject) {}
    public func layoutIfNeeded() {}
}
public final class UILabel: UIView {
    public var text: String?
    public var textColor: UIColor! = .black
    public var font: UIFont! = UIFont(size: 17)
    public var numberOfLines = 1
    public var textAlignment = NSTextAlignment.natural
}
open class UIControl: UIView {
    public var isEnabled = true
    public struct Event: OptionSet { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }
        public static let touchUpInside = Event(rawValue: 1); public static let valueChanged = Event(rawValue: 2) }
}
public final class UIButton: UIControl {
    public enum ButtonType { case system, custom }
    public init(type: ButtonType) { super.init() }
    private var title: String?
    public let titleLabel: UILabel? = UILabel()
    public var image: UIImage?
    public var contentEdgeInsets = UIEdgeInsets.zero
    public enum State { case normal }
    public func setTitle(_ t: String?, for s: State) { title = t; titleLabel?.text = t }
    public func title(for s: State) -> String? { return title }
    public func setTitleColor(_ c: UIColor?, for s: State) {}
    public func setImage(_ i: UIImage?, for s: State) { image = i }
}
public final class UITextField: UIControl {
    public var text: String? = ""
    public var placeholder: String?
    public var font: UIFont? = UIFont(size: 17)
    public var textColor: UIColor?
    public var textAlignment = NSTextAlignment.natural
    public enum BorderStyle { case roundedRect, none }
    public var borderStyle = BorderStyle.none
    public enum Caps { case none, words }
    public var autocapitalizationType = Caps.words
}
public final class UISwitch: UIControl {
    public var isOn = false
    public func setOn(_ on: Bool, animated: Bool) { isOn = on }
}
public final class UISlider: UIControl {
    public var value: Float = 0, minimumValue: Float = 0, maximumValue: Float = 1
}
public final class UIImageView: UIView {
    public var image: UIImage?
    public init(image: UIImage? = nil) { self.image = image; super.init() }
}
public final class UIActivityIndicatorView: UIView {
    public enum Style { case gray, white }
    public init(style: Style) { super.init() }
    public func startAnimating() {}
    public func stopAnimating() {}
}
public final class UIStackView: UIView {
    public enum Axis { case horizontal, vertical }
    public enum Alignment { case fill, center, leading, trailing }
    public enum Distribution { case fill, fillEqually }
    public var arrangedSubviews: [UIView] = []
    public var axis = Axis.horizontal
    public var spacing: CGFloat = 0
    public var alignment = Alignment.fill
    public var distribution = Distribution.fill
    public var isLayoutMarginsRelativeArrangement = false
    public var layoutMargins = UIEdgeInsets.zero
    public init(arrangedSubviews: [UIView] = []) { super.init(); arrangedSubviews.forEach { addArrangedSubview($0) } }
    public func addArrangedSubview(_ v: UIView) { addSubview(v); arrangedSubviews.append(v) }
    public func insertArrangedSubview(_ v: UIView, at i: Int) { addSubview(v); arrangedSubviews.insert(v, at: min(i, arrangedSubviews.count)) }
}
public final class UIScrollView: UIView {
    public var alwaysBounceVertical = false
    public enum KeyboardDismissMode { case interactive, none }
    public var keyboardDismissMode = KeyboardDismissMode.none
    public let contentLayoutGuide = UILayoutGuide()
    public let frameLayoutGuide = UILayoutGuide()
}
public final class UIAlertAction { public enum Style { case `default`, cancel, destructive } }

