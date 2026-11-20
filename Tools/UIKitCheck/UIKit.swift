// Declarations-only stand-in for the parts of UIKit APK Sandbox uses, with
// the same signatures as the real iOS SDK. Lets `typecheck.sh` catch Swift
// errors in the app's screens on Linux, without a Mac. Nothing here runs.
@_exported import Foundation
#if canImport(FoundationNetworking)
@_exported import FoundationNetworking
#endif

public typealias CGFloat = Foundation.CGFloat

private func never<T>() -> T { fatalError() }

// MARK: - Basics

public struct Selector { public init(_ s: String) {} }
/// `#selector(x)` is rewritten to `__selector(x)` by typecheck.sh.
public func __selector(_ f: Any) -> Selector { return Selector("") }

public struct UIEdgeInsets {
    public var top, left, bottom, right: CGFloat
    public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) { self.top = top; self.left = left; self.bottom = bottom; self.right = right }
    public static let zero = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
}
extension CGRect {
    public func inset(by insets: UIEdgeInsets) -> CGRect { return self }
}
public enum NSTextAlignment: Int { case left, center, right, justified, natural }
public enum NSLineBreakMode: Int { case byWordWrapping, byCharWrapping, byClipping, byTruncatingHead, byTruncatingTail, byTruncatingMiddle }

extension NSAttributedString.Key {
    public static let font = NSAttributedString.Key("NSFont")
    public static let foregroundColor = NSAttributedString.Key("NSColor")
}
extension NSString {
    public func size(withAttributes attrs: [NSAttributedString.Key: Any]? = nil) -> CGSize { return .zero }
    public func draw(at point: CGPoint, withAttributes attrs: [NSAttributedString.Key: Any]? = nil) {}
}

public final class CGColor {}
public final class CGImage {
    public var width: Int { return 0 }
    public var height: Int { return 0 }
    public func cropping(to rect: CGRect) -> CGImage? { return nil }
}

// MARK: - CoreGraphics (the parts the canvas renderer uses)

public struct CGAffineTransform {
    public init(scaleX sx: CGFloat, y sy: CGFloat) {}
    public init(translationX tx: CGFloat, y ty: CGFloat) {}
    public init(rotationAngle angle: CGFloat) {}
}
public enum CGPathFillRule: Int { case winding, evenOdd }
public enum CGLineCap: Int32 { case butt, round, square }
public enum CGBlendMode: Int32 { case normal, multiply, screen, overlay, clear, copy }
public final class CGPath {
    public init(roundedRect rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat, transform: UnsafePointer<CGAffineTransform>?) {}
}
public final class CGContext {
    public func scaleBy(x sx: CGFloat, y sy: CGFloat) {}
    public func translateBy(x tx: CGFloat, y ty: CGFloat) {}
    public func rotate(by angle: CGFloat) {}
    public func saveGState() {}
    public func restoreGState() {}
    public func clip(to rect: CGRect) {}
    public func setFillColor(_ color: CGColor) {}
    public func setStrokeColor(_ color: CGColor) {}
    public func setLineWidth(_ width: CGFloat) {}
    public func setLineCap(_ cap: CGLineCap) {}
    public func fill(_ rect: CGRect) {}
    public func addPath(_ path: CGPath) {}
    public func fillPath(using rule: CGPathFillRule = .winding) {}
    public func strokePath() {}
}
public func UIGraphicsGetCurrentContext() -> CGContext? { return nil }

open class UIColor: NSObject {
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {}
    public init(white: CGFloat, alpha: CGFloat) {}
    public init(cgColor: CGColor) {}
    open class var white: UIColor { return never() }
    open class var black: UIColor { return never() }
    open class var gray: UIColor { return never() }
    open class var darkText: UIColor { return never() }
    open class var clear: UIColor { return never() }
    open class var lightGray: UIColor { return never() }
    public var cgColor: CGColor { return never() }
    open func setFill() {}
    open func setStroke() {}
}

open class UIFont: NSObject {
    public struct Weight { public static let thin = Weight(), regular = Weight(), medium = Weight(), semibold = Weight(), bold = Weight() }
    public init?(name fontName: String, size fontSize: CGFloat) {}
    open class func systemFont(ofSize fontSize: CGFloat) -> UIFont { return never() }
    open class func systemFont(ofSize fontSize: CGFloat, weight: UIFont.Weight) -> UIFont { return never() }
    open class func boldSystemFont(ofSize fontSize: CGFloat) -> UIFont { return never() }
    open class func italicSystemFont(ofSize fontSize: CGFloat) -> UIFont { return never() }
    open var pointSize: CGFloat { return 0 }
    open var ascender: CGFloat { return 0 }
    open var descender: CGFloat { return 0 }
    open func withSize(_ fontSize: CGFloat) -> UIFont { return self }
}

open class UIImage: NSObject {
    public enum RenderingMode: Int { case automatic, alwaysOriginal, alwaysTemplate }
    public enum Orientation: Int { case up, down }
    public init?(data: Data) {}
    public override init() {}
    public init(cgImage: CGImage) {}
    open var size: CGSize { return .zero }
    open var scale: CGFloat { return 1 }
    open var cgImage: CGImage? { return nil }
    open func draw(in rect: CGRect, blendMode: CGBlendMode, alpha: CGFloat) {}
    open func withRenderingMode(_ renderingMode: UIImage.RenderingMode) -> UIImage { return self }
    open func draw(in rect: CGRect) {}
}

public func UIGraphicsBeginImageContextWithOptions(_ size: CGSize, _ opaque: Bool, _ scale: CGFloat) {}
public func UIGraphicsGetImageFromCurrentImageContext() -> UIImage? { return nil }
public func UIGraphicsEndImageContext() {}

open class UIBezierPath: NSObject {
    public override init() {}
    public init(rect: CGRect) {}
    public init(ovalIn rect: CGRect) {}
    public init(roundedRect rect: CGRect, cornerRadius: CGFloat) {}
    public init(cgPath: CGPath) {}
    open var cgPath: CGPath { get { return never() } set {} }
    open var usesEvenOddFillRule = false
    open func addArc(withCenter center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) {}
    open func addQuadCurve(to endPoint: CGPoint, controlPoint: CGPoint) {}
    open func addCurve(to endPoint: CGPoint, controlPoint1: CGPoint, controlPoint2: CGPoint) {}
    open func apply(_ transform: CGAffineTransform) {}
    open var lineWidth: CGFloat = 1
    public enum LineJoin { case miter, round, bevel }
    open var lineJoinStyle: CGLineJoin = .miter
    open func move(to point: CGPoint) {}
    open func addLine(to point: CGPoint) {}
    open func close() {}
    open func append(_ bezierPath: UIBezierPath) {}
    open func fill() {}
    open func stroke() {}
    open func addClip() {}
}
public enum CGLineJoin: Int32 { case miter, round, bevel }

// MARK: - Layers & layout

open class CALayer: NSObject {
    open var cornerRadius: CGFloat = 0
    open var frame: CGRect = .zero
    open var contents: Any?
    open func insertSublayer(_ layer: CALayer, at idx: UInt32) {}
    open func addSublayer(_ layer: CALayer) {}
}
open class CAGradientLayer: CALayer {
    open var colors: [Any]?
    open var startPoint: CGPoint = .zero
    open var endPoint: CGPoint = .zero
}

public struct UILayoutPriority: Equatable {
    public let rawValue: Float
    public init(_ rawValue: Float) { self.rawValue = rawValue }
    public static let required = UILayoutPriority(1000), defaultHigh = UILayoutPriority(750), defaultLow = UILayoutPriority(250)
}
open class NSLayoutConstraint: NSObject {
    open var isActive = false
    open var priority = UILayoutPriority(1000)
    open var constant: CGFloat = 0
    open class func activate(_ constraints: [NSLayoutConstraint]) {}
    open class func deactivate(_ constraints: [NSLayoutConstraint]) {}
}
open class NSLayoutAnchor<AnchorType: AnyObject>: NSObject {
    open func constraint(equalTo anchor: NSLayoutAnchor<AnchorType>) -> NSLayoutConstraint { return never() }
    open func constraint(greaterThanOrEqualTo anchor: NSLayoutAnchor<AnchorType>) -> NSLayoutConstraint { return never() }
    open func constraint(lessThanOrEqualTo anchor: NSLayoutAnchor<AnchorType>) -> NSLayoutConstraint { return never() }
    open func constraint(equalTo anchor: NSLayoutAnchor<AnchorType>, constant c: CGFloat) -> NSLayoutConstraint { return never() }
    open func constraint(greaterThanOrEqualTo anchor: NSLayoutAnchor<AnchorType>, constant c: CGFloat) -> NSLayoutConstraint { return never() }
    open func constraint(lessThanOrEqualTo anchor: NSLayoutAnchor<AnchorType>, constant c: CGFloat) -> NSLayoutConstraint { return never() }
}
open class NSLayoutXAxisAnchor: NSLayoutAnchor<NSLayoutXAxisAnchor> {}
open class NSLayoutYAxisAnchor: NSLayoutAnchor<NSLayoutYAxisAnchor> {}
open class NSLayoutDimension: NSLayoutAnchor<NSLayoutDimension> {
    open func constraint(equalToConstant c: CGFloat) -> NSLayoutConstraint { return never() }
    open func constraint(greaterThanOrEqualToConstant c: CGFloat) -> NSLayoutConstraint { return never() }
    open func constraint(lessThanOrEqualToConstant c: CGFloat) -> NSLayoutConstraint { return never() }
    open func constraint(equalTo anchor: NSLayoutDimension, multiplier m: CGFloat) -> NSLayoutConstraint { return never() }
    open func constraint(equalTo anchor: NSLayoutDimension, multiplier m: CGFloat, constant c: CGFloat) -> NSLayoutConstraint { return never() }
}
open class UILayoutGuide: NSObject {
    open var topAnchor: NSLayoutYAxisAnchor { return never() }
    open var bottomAnchor: NSLayoutYAxisAnchor { return never() }
    open var leadingAnchor: NSLayoutXAxisAnchor { return never() }
    open var trailingAnchor: NSLayoutXAxisAnchor { return never() }
    open var centerXAnchor: NSLayoutXAxisAnchor { return never() }
    open var centerYAnchor: NSLayoutYAxisAnchor { return never() }
    open var widthAnchor: NSLayoutDimension { return never() }
    open var heightAnchor: NSLayoutDimension { return never() }
}

// MARK: - Responders, views

open class UIResponder: NSObject {
    open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {}
    open func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {}
    open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {}
    open func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {}
}
open class UITouch: NSObject {
    open func location(in view: UIView?) -> CGPoint { return .zero }
}
open class UIEvent: NSObject {}

open class UIGestureRecognizer: NSObject {
    public enum State: Int { case possible, began, changed, ended, cancelled, failed }
    public init(target: Any?, action: Selector?) {}
    open var state: UIGestureRecognizer.State { return .possible }
    open var cancelsTouchesInView = true
    open func location(in view: UIView?) -> CGPoint { return .zero }
}
open class UITapGestureRecognizer: UIGestureRecognizer {
    open var numberOfTouchesRequired = 1
    open var numberOfTapsRequired = 1
}
open class UILongPressGestureRecognizer: UIGestureRecognizer {
    open var minimumPressDuration: TimeInterval = 0.5
}

open class UIView: UIResponder {
    public enum ContentMode: Int { case scaleToFill, scaleAspectFit, scaleAspectFill, center }
    public enum AnimationOptions { case curveEaseInOut }
    public init(frame: CGRect) {}
    public convenience override init() { self.init(frame: .zero) }
    public required init?(coder: NSCoder) {}
    open var subviews: [UIView] { return [] }
    open var superview: UIView? { return nil }
    open var window: UIWindow? { return nil }
    open var isHidden = false
    open var alpha: CGFloat = 1
    open var backgroundColor: UIColor?
    open var tintColor: UIColor!
    open var isUserInteractionEnabled = true
    open var translatesAutoresizingMaskIntoConstraints = true
    open var clipsToBounds = false
    open var frame: CGRect = .zero
    open var bounds: CGRect = .zero
    open var center: CGPoint = .zero
    open var layer: CALayer { return never() }
    open var contentMode: UIView.ContentMode = .scaleToFill
    open var accessibilityLabel: String?
    open var tag: Int = 0
    open var layoutMargins: UIEdgeInsets = .zero
    open var safeAreaLayoutGuide: UILayoutGuide { return never() }
    open var topAnchor: NSLayoutYAxisAnchor { return never() }
    open var bottomAnchor: NSLayoutYAxisAnchor { return never() }
    open var leadingAnchor: NSLayoutXAxisAnchor { return never() }
    open var trailingAnchor: NSLayoutXAxisAnchor { return never() }
    open var centerXAnchor: NSLayoutXAxisAnchor { return never() }
    open var centerYAnchor: NSLayoutYAxisAnchor { return never() }
    open var widthAnchor: NSLayoutDimension { return never() }
    open var heightAnchor: NSLayoutDimension { return never() }
    open var intrinsicContentSize: CGSize { return .zero }
    public static let noIntrinsicMetric: CGFloat = -1
    open func addSubview(_ view: UIView) {}
    open func insertSubview(_ view: UIView, at index: Int) {}
    open func insertSubview(_ view: UIView, belowSubview siblingSubview: UIView) {}
    open func removeFromSuperview() {}
    open func addGestureRecognizer(_ gestureRecognizer: UIGestureRecognizer) {}
    open func layoutIfNeeded() {}
    open func invalidateIntrinsicContentSize() {}
    open func setNeedsLayout() {}
    open func layoutSubviews() {}
    open class func animate(withDuration duration: TimeInterval, animations: @escaping () -> Void) {}
    open class func animate(withDuration duration: TimeInterval, animations: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {}
    open class func animate(withDuration duration: TimeInterval, delay: TimeInterval, options: UIView.AnimationOptions = [], animations: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {}
}
extension UIView.AnimationOptions: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: UIView.AnimationOptions...) { self = .curveEaseInOut }
}

open class UIWindow: UIView {
    open var rootViewController: UIViewController?
    open func makeKeyAndVisible() {}
}

open class UILabel: UIView {
    open var text: String?
    open var font: UIFont!
    open var textColor: UIColor!
    open var shadowColor: UIColor?
    open var shadowOffset: CGSize = .zero
    open var textAlignment: NSTextAlignment = .natural
    open var lineBreakMode: NSLineBreakMode = .byTruncatingTail
    open var numberOfLines: Int = 1
    open var adjustsFontSizeToFitWidth = false
    open var minimumScaleFactor: CGFloat = 0
    open func drawText(in rect: CGRect) {}
}

open class UIControl: UIView {
    public struct Event: OptionSet {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let touchUpInside = Event(rawValue: 1 << 6), valueChanged = Event(rawValue: 1 << 12)
    }
    public struct State: OptionSet {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let normal = State([]), highlighted = State(rawValue: 1), disabled = State(rawValue: 2)
    }
    open var isEnabled = true
    open var isHighlighted = false
    open func addTarget(_ target: Any?, action: Selector, for controlEvents: UIControl.Event) {}
}

open class UIButton: UIControl {
    public enum ButtonType: Int { case custom, system }
    public convenience init(type buttonType: UIButton.ButtonType) { self.init(frame: .zero) }
    open var titleLabel: UILabel? { return nil }
    open var imageView: UIImageView? { return nil }
    open var contentEdgeInsets: UIEdgeInsets = .zero
    open func setTitle(_ title: String?, for state: UIControl.State) {}
    open func title(for state: UIControl.State) -> String? { return nil }
    open func setTitleColor(_ color: UIColor?, for state: UIControl.State) {}
    open func setImage(_ image: UIImage?, for state: UIControl.State) {}
}

open class UITextField: UIControl {
    public enum BorderStyle: Int { case none, line, bezel, roundedRect }
    open var text: String?
    open var placeholder: String?
    open var font: UIFont?
    open var textColor: UIColor?
    open var textAlignment: NSTextAlignment = .natural
    open var borderStyle: UITextField.BorderStyle = .none
    open var autocapitalizationType: UITextAutocapitalizationType = .sentences
    open var autocorrectionType: UITextAutocorrectionType = .default
    open var keyboardType: UIKeyboardType = .default
    open var isSecureTextEntry = false
    public enum ViewMode: Int { case never, whileEditing, unlessEditing, always }
    open var clearButtonMode: UITextField.ViewMode = .never
}
public enum UITextAutocapitalizationType: Int { case none, words, sentences, allCharacters }
public enum UITextAutocorrectionType: Int { case `default`, no, yes }
public enum UIKeyboardType: Int { case `default`, URL, numberPad }

open class UISwitch: UIControl {
    open var isOn = false
    open var onTintColor: UIColor?
    open func setOn(_ on: Bool, animated: Bool) {}
}
open class UISlider: UIControl {
    open var value: Float = 0
    open var minimumValue: Float = 0
    open var maximumValue: Float = 1
}
open class UIImageView: UIView {
    public init(image: UIImage?) { super.init(frame: .zero) }
    public override init(frame: CGRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    open var image: UIImage?
}
open class UIActivityIndicatorView: UIView {
    public enum Style: Int { case whiteLarge, white, gray }
    public init(style: UIActivityIndicatorView.Style) { super.init(frame: .zero) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    open func startAnimating() {}
    open func stopAnimating() {}
}
open class UIProgressView: UIView {
    public enum Style: Int { case `default`, bar }
    public init(progressViewStyle style: UIProgressView.Style) { super.init(frame: .zero) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    open var progressTintColor: UIColor?
    open func setProgress(_ progress: Float, animated: Bool) {}
}
open class UIStackView: UIView {
    public enum Axis: Int { case horizontal, vertical }
    public enum Alignment: Int { case fill, leading, firstBaseline, center, trailing, lastBaseline }
    public enum Distribution: Int { case fill, fillEqually, fillProportionally, equalSpacing, equalCentering }
    public init(arrangedSubviews views: [UIView]) { super.init(frame: .zero) }
    public override init(frame: CGRect) { super.init(frame: frame) }
    public required init(coder: NSCoder) { super.init(coder: coder)! }
    open var arrangedSubviews: [UIView] { return [] }
    open var axis: UIStackView.Axis = .horizontal
    open var distribution: UIStackView.Distribution = .fill
    open var alignment: UIStackView.Alignment = .fill
    open var spacing: CGFloat = 0
    open var isLayoutMarginsRelativeArrangement = false
    open func addArrangedSubview(_ view: UIView) {}
    open func insertArrangedSubview(_ view: UIView, at stackIndex: Int) {}
    open func setCustomSpacing(_ spacing: CGFloat, after arrangedSubview: UIView) {}
}
open class UIScrollView: UIView {
    public enum KeyboardDismissMode: Int { case none, onDrag, interactive }
    open var alwaysBounceVertical = false
    open var isScrollEnabled = true
    open var keyboardDismissMode: UIScrollView.KeyboardDismissMode = .none
    open var contentLayoutGuide: UILayoutGuide { return never() }
    open var frameLayoutGuide: UILayoutGuide { return never() }
    open var refreshControl: UIRefreshControl?
}
open class UITextView: UIScrollView {
    open var text: String!
    open var font: UIFont?
    open var textColor: UIColor?
    open var isEditable = true
    open func scrollRangeToVisible(_ range: NSRange) {}
}
open class UIRefreshControl: UIControl {
    open func endRefreshing() {}
}

// MARK: - Tables & collections

extension IndexPath {
    public init(row: Int, section: Int) { self.init(indexes: [section, row]) }
    public init(item: Int, section: Int) { self.init(indexes: [section, item]) }
    public var row: Int { return self[1] }
    public var item: Int { return self[1] }
    public var section: Int { return self[0] }
}

open class UITableViewCell: UIView {
    public enum CellStyle: Int { case `default`, value1, value2, subtitle }
    public enum AccessoryType: Int { case none, disclosureIndicator, detailDisclosureButton, checkmark, detailButton }
    public enum SelectionStyle: Int { case none, blue, gray, `default` }
    public enum EditingStyle: Int { case none, delete, insert }
    public init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) { super.init(frame: .zero) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    open var textLabel: UILabel? { return nil }
    open var detailTextLabel: UILabel? { return nil }
    open var imageView: UIImageView? { return nil }
    open var accessoryType: UITableViewCell.AccessoryType = .none
    open var accessoryView: UIView?
    open var selectionStyle: UITableViewCell.SelectionStyle = .default
}

open class UITableView: UIScrollView {
    public enum Style: Int { case plain, grouped }
    public enum RowAnimation: Int { case fade, right, left, top, bottom, none, middle, automatic }
    public static let automaticDimension: CGFloat = -1
    open var rowHeight: CGFloat = 44
    open var estimatedRowHeight: CGFloat = 44
    open var tableHeaderView: UIView?
    open var backgroundView: UIView?
    open func reloadData() {}
    open func reloadRows(at indexPaths: [IndexPath], with animation: UITableView.RowAnimation) {}
    open func deleteRows(at indexPaths: [IndexPath], with animation: UITableView.RowAnimation) {}
    open func deselectRow(at indexPath: IndexPath, animated: Bool) {}
    open func register(_ cellClass: AnyClass?, forCellReuseIdentifier identifier: String) {}
}

open class UICollectionViewLayout: NSObject {}
open class UICollectionViewFlowLayout: UICollectionViewLayout {
    open var minimumLineSpacing: CGFloat = 10
    open var minimumInteritemSpacing: CGFloat = 10
    open var itemSize: CGSize = .zero
    open var sectionInset: UIEdgeInsets = .zero
}
open class UICollectionViewCell: UIView {
    public override init(frame: CGRect) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    open var contentView: UIView { return never() }
    open var isHighlighted = false
    open var isSelected = false
}
public protocol UICollectionViewDataSource: AnyObject {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell
}
public protocol UICollectionViewDelegate: AnyObject {}
public protocol UICollectionViewDelegateFlowLayout: UICollectionViewDelegate {}
open class UICollectionView: UIScrollView {
    public init(frame: CGRect, collectionViewLayout layout: UICollectionViewLayout) { super.init(frame: frame) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    open weak var dataSource: UICollectionViewDataSource?
    open weak var delegate: UICollectionViewDelegate?
    open func register(_ cellClass: AnyClass?, forCellWithReuseIdentifier identifier: String) {}
    open func dequeueReusableCell(withReuseIdentifier identifier: String, for indexPath: IndexPath) -> UICollectionViewCell { return never() }
    open func reloadData() {}
    open func indexPathForItem(at point: CGPoint) -> IndexPath? { return nil }
    open func cellForItem(at indexPath: IndexPath) -> UICollectionViewCell? { return nil }
}

// MARK: - View controllers

public enum UIStatusBarStyle: Int { case `default`, lightContent }
public enum UIInterfaceOrientation: Int { case unknown, portrait, portraitUpsideDown, landscapeLeft, landscapeRight }
public struct UIInterfaceOrientationMask: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let portrait = UIInterfaceOrientationMask(rawValue: 2), landscapeLeft = UIInterfaceOrientationMask(rawValue: 16),
        landscapeRight = UIInterfaceOrientationMask(rawValue: 8), landscape = UIInterfaceOrientationMask(rawValue: 24),
        all = UIInterfaceOrientationMask(rawValue: 30), allButUpsideDown = UIInterfaceOrientationMask(rawValue: 26)
}
public enum UIModalPresentationStyle: Int { case fullScreen, pageSheet, formSheet, currentContext, custom, overFullScreen, popover, none, automatic }

open class UIViewController: UIResponder {
    public init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {}
    public required init?(coder: NSCoder) {}
    public override convenience init() { self.init(nibName: nil, bundle: nil) }
    open var view: UIView! = nil
    open var isViewLoaded: Bool { return true }
    open var title: String?
    open var navigationItem: UINavigationItem { return never() }
    open var navigationController: UINavigationController? { return nil }
    open var presentedViewController: UIViewController? { return nil }
    open var presentingViewController: UIViewController? { return nil }
    open var isBeingDismissed: Bool { return false }
    open var modalPresentationStyle: UIModalPresentationStyle = .fullScreen
    @available(iOS 13.0, *)
    open var isModalInPresentation: Bool = false
    open var popoverPresentationController: UIPopoverPresentationController? { return nil }
    open var preferredStatusBarStyle: UIStatusBarStyle { return .default }
    open var childForStatusBarStyle: UIViewController? { return nil }
    open var supportedInterfaceOrientations: UIInterfaceOrientationMask { return .portrait }
    open var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { return .portrait }
    open var shouldAutorotate: Bool { return true }
    open var prefersStatusBarHidden: Bool { return false }
    open var prefersHomeIndicatorAutoHidden: Bool { return false }
    open class func attemptRotationToDeviceOrientation() {}
    open func loadView() {}
    open func loadViewIfNeeded() {}
    open func viewDidLoad() {}
    open func viewWillAppear(_ animated: Bool) {}
    open func viewDidAppear(_ animated: Bool) {}
    open func viewWillDisappear(_ animated: Bool) {}
    open func viewDidDisappear(_ animated: Bool) {}
    open func viewDidLayoutSubviews() {}
    open func didReceiveMemoryWarning() {}
    open func setNeedsStatusBarAppearanceUpdate() {}
    open func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {}
    open func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {}
}

open class UIPopoverPresentationController: NSObject {
    open var sourceView: UIView?
    open var sourceRect: CGRect = .zero
    open var barButtonItem: UIBarButtonItem?
}

open class UINavigationItem: NSObject {
    open var leftBarButtonItem: UIBarButtonItem?
    open var rightBarButtonItem: UIBarButtonItem?
    open var leftBarButtonItems: [UIBarButtonItem]?
    open var rightBarButtonItems: [UIBarButtonItem]?
    open var title: String?
}

open class UIBarItem: NSObject {
    open var isEnabled = true
    open var title: String?
}
open class UIBarButtonItem: UIBarItem {
    public enum Style: Int { case plain, done }
    public enum SystemItem: Int { case done, cancel, edit, save, add, action }
    public init(title: String?, style: UIBarButtonItem.Style, target: Any?, action: Selector?) {}
    public init(barButtonSystemItem systemItem: UIBarButtonItem.SystemItem, target: Any?, action: Selector?) {}
}

public enum UIBarStyle: Int { case `default`, black }
@available(iOS 13.0, *)
open class UINavigationBarAppearance: NSObject {
    public override init() {}
    open func configureWithOpaqueBackground() {}
    open var backgroundColor: UIColor?
    open var titleTextAttributes: [NSAttributedString.Key: Any] = [:]
    open var largeTitleTextAttributes: [NSAttributedString.Key: Any] = [:]
}
open class UINavigationBar: UIView {
    open var barStyle: UIBarStyle = .default
    open var isTranslucent = true
    open var barTintColor: UIColor?
    @available(iOS 13.0, *)
    open var standardAppearance: UINavigationBarAppearance { get { return never() } set {} }
    @available(iOS 13.0, *)
    open var scrollEdgeAppearance: UINavigationBarAppearance? { get { return nil } set {} }
    @available(iOS 13.0, *)
    open var compactAppearance: UINavigationBarAppearance? { get { return nil } set {} }
}

open class UINavigationController: UIViewController {
    public init(rootViewController: UIViewController) { super.init(nibName: nil, bundle: nil) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) { super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil) }
    open var navigationBar: UINavigationBar { return never() }
    open var topViewController: UIViewController? { return nil }
    open var viewControllers: [UIViewController] = []
    open func pushViewController(_ viewController: UIViewController, animated: Bool) {}
    @discardableResult open func popViewController(animated: Bool) -> UIViewController? { return nil }
    @discardableResult open func popToRootViewController(animated: Bool) -> [UIViewController]? { return nil }
    open func setNavigationBarHidden(_ hidden: Bool, animated: Bool) {}
}
public protocol UINavigationControllerDelegate: AnyObject {}

open class UITableViewController: UIViewController {
    public init(style: UITableView.Style) { super.init(nibName: nil, bundle: nil) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) { super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil) }
    open var tableView: UITableView! = nil
    open var refreshControl: UIRefreshControl?
    open func numberOfSections(in tableView: UITableView) -> Int { return 1 }
    open func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { return 0 }
    open func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell { return never() }
    open func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { return nil }
    open func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { return nil }
    open func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {}
    open func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {}
    open func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {}
}

open class UIAlertAction: NSObject {
    public enum Style: Int { case `default`, cancel, destructive }
    public convenience init(title: String?, style: UIAlertAction.Style, handler: ((UIAlertAction) -> Void)? = nil) { self.init() }
    open var isEnabled = true
}
open class UIAlertController: UIViewController {
    public enum Style: Int { case actionSheet, alert }
    public convenience init(title: String?, message: String?, preferredStyle: UIAlertController.Style) { self.init(nibName: nil, bundle: nil) }
    open var actions: [UIAlertAction] { return [] }
    open func addAction(_ action: UIAlertAction) {}
    open var textFields: [UITextField]? { return nil }
    open var message: String?
    open func addTextField(configurationHandler: ((UITextField) -> Void)? = nil) {}
}

open class UIActivityViewController: UIViewController {
    public init(activityItems: [Any], applicationActivities: [AnyObject]?) { super.init(nibName: nil, bundle: nil) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
}

public enum UIDocumentPickerMode: UInt { case `import`, open, exportToService, moveToService }
public protocol UIDocumentPickerDelegate: AnyObject {}
open class UIDocumentPickerViewController: UIViewController {
    public init(documentTypes allowedUTIs: [String], in mode: UIDocumentPickerMode) { super.init(nibName: nil, bundle: nil) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    open weak var delegate: UIDocumentPickerDelegate?
    open var allowsMultipleSelection = false
}

// MARK: - App, screen, device, haptics

public protocol UIApplicationDelegate: AnyObject {}
open class UIApplication: UIResponder {
    public struct LaunchOptionsKey: Hashable { public init(_ s: String) {} }
    public struct OpenURLOptionsKey: Hashable { public init(_ s: String) {} }
    open class var shared: UIApplication { return never() }
    open var keyWindow: UIWindow? { return nil }
    open var isIdleTimerDisabled = false
    public static let didBecomeActiveNotification = Notification.Name("UIApplicationDidBecomeActiveNotification")
    public static let didReceiveMemoryWarningNotification = Notification.Name("UIApplicationDidReceiveMemoryWarningNotification")
}
public func UIApplicationMain(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>, _ principalClassName: String?, _ delegateClassName: String?) -> Int32 { return 0 }

open class UIScreen: NSObject {
    open class var main: UIScreen { return never() }
    open var scale: CGFloat { return 2 }
    open var bounds: CGRect { return .zero }
}
open class UIDevice: NSObject {
    open class var current: UIDevice { return never() }
    open var systemVersion: String { return "" }
    open func setValue(_ value: Any?, forKey key: String) {}
    open var model: String { return "" }
}
open class UIFeedbackGenerator: NSObject {}
open class UIImpactFeedbackGenerator: UIFeedbackGenerator {
    public enum FeedbackStyle: Int { case light, medium, heavy }
    public init(style: UIImpactFeedbackGenerator.FeedbackStyle) {}
    open func impactOccurred() {}
}
open class UINotificationFeedbackGenerator: UIFeedbackGenerator {
    public enum FeedbackType: Int { case success, warning, error }
    open func notificationOccurred(_ notificationType: UINotificationFeedbackGenerator.FeedbackType) {}
}

// Foundation's NotificationCenter on Linux has no selector-based observers.
extension NotificationCenter {
    public func addObserver(_ observer: Any, selector aSelector: Selector, name aName: NSNotification.Name?, object anObject: Any?) {}
}

// Darwin-only Foundation API used with document picker URLs.
extension URL {
    public func startAccessingSecurityScopedResource() -> Bool { return false }
    public func stopAccessingSecurityScopedResource() {}
}
