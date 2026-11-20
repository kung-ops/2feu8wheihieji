import UIKit

/// Colours, icons and small helpers shared by the virtual Android screens.
/// Everything here works on iOS 12 (no SF Symbols, no dynamic colours).
enum Theme {
    static let accent = UIColor(red: 0.13, green: 0.62, blue: 0.36, alpha: 1)       // Android green
    static let appBar = UIColor(red: 0.18, green: 0.20, blue: 0.25, alpha: 1)
    static let navBar = UIColor(white: 0.04, alpha: 1)
    static let wallpaperTop = UIColor(red: 0.05, green: 0.27, blue: 0.33, alpha: 1)
    static let wallpaperBottom = UIColor(red: 0.10, green: 0.09, blue: 0.24, alpha: 1)
    static let secondaryText = UIColor(white: 0.45, alpha: 1)
    static let danger = UIColor(red: 0.85, green: 0.20, blue: 0.18, alpha: 1)

    /// Launcher icon for an installed app: its own icon, or a coloured
    /// circle with its first letter.
    static func icon(for app: InstalledApp, side: CGFloat = 60) -> UIImage {
        if app.hasIcon, let data = try? Data(contentsOf: PackageManager.shared.iconURL(app.packageName)),
           let img = ApkPackage.decodeImage(data, maxSide: Int(side * UIScreen.main.scale)) {
            return rounded(img, side: side)
        }
        return letterIcon(app.label, seed: app.packageName, side: side)
    }

    static func rounded(_ img: UIImage, side: CGFloat) -> UIImage {
        let size = CGSize(width: side, height: side)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }
        let rect = CGRect(origin: .zero, size: size)
        UIBezierPath(roundedRect: rect, cornerRadius: side * 0.24).addClip()
        img.draw(in: rect)
        return UIGraphicsGetImageFromCurrentImageContext() ?? img
    }

    static func letterIcon(_ label: String, seed: String, side: CGFloat = 60) -> UIImage {
        let palette: [UIColor] = [
            UIColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1), UIColor(red: 0.92, green: 0.26, blue: 0.21, alpha: 1),
            UIColor(red: 0.98, green: 0.74, blue: 0.02, alpha: 1), UIColor(red: 0.20, green: 0.66, blue: 0.33, alpha: 1),
            UIColor(red: 0.61, green: 0.15, blue: 0.69, alpha: 1), UIColor(red: 0.00, green: 0.59, blue: 0.53, alpha: 1),
            UIColor(red: 1.00, green: 0.44, blue: 0.26, alpha: 1), UIColor(red: 0.25, green: 0.32, blue: 0.71, alpha: 1)
        ]
        var h = 0
        for u in seed.unicodeScalars { h = (h &* 31 &+ Int(u.value)) & 0x7fffffff }
        let color = palette[h % palette.count]
        let letter = label.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "A"
        return drawIcon(side: side, background: color) { rect in
            drawCentered(letter, in: rect, font: .boldSystemFont(ofSize: side * 0.46), color: .white)
        }
    }

    /// A round icon with a glyph (used for the dock: install, files, settings).
    static func glyphIcon(_ glyph: String, background: UIColor, side: CGFloat = 60) -> UIImage {
        return drawIcon(side: side, background: background) { rect in
            drawCentered(glyph, in: rect, font: .systemFont(ofSize: side * 0.44, weight: .semibold), color: .white)
        }
    }

    private static func drawIcon(side: CGFloat, background: UIColor, content: (CGRect) -> Void) -> UIImage {
        let size = CGSize(width: side, height: side)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }
        let rect = CGRect(origin: .zero, size: size)
        background.setFill()
        UIBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
        content(rect)
        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }

    private static func drawCentered(_ text: String, in rect: CGRect, font: UIFont, color: UIColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let s = text as NSString
        let ts = s.size(withAttributes: attrs)
        s.draw(at: CGPoint(x: rect.midX - ts.width / 2, y: rect.midY - ts.height / 2), withAttributes: attrs)
    }

    enum NavKey { case back, home, recents, menu }

    /// Android navigation bar keys, drawn as outlines (◁ ○ □).
    static func navIcon(_ key: NavKey, color: UIColor = .white) -> UIImage {
        let side: CGFloat = 22
        let size = CGSize(width: side, height: side)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }
        color.setStroke()
        color.setFill()
        let r = CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3)
        let path: UIBezierPath
        switch key {
        case .back:
            path = UIBezierPath()
            path.move(to: CGPoint(x: r.maxX, y: r.minY))
            path.addLine(to: CGPoint(x: r.minX, y: r.midY))
            path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            path.close()
        case .home:
            path = UIBezierPath(ovalIn: r)
        case .recents:
            path = UIBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), cornerRadius: 2)
        case .menu:
            path = UIBezierPath()
            for k in 0..<3 {
                let y = r.minY + CGFloat(k) * r.height / 2
                path.append(UIBezierPath(ovalIn: CGRect(x: r.midX - 2, y: y - 2, width: 4, height: 4)))
            }
            path.fill()
            return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        }
        path.lineWidth = 2
        path.lineJoinStyle = .round
        path.stroke()
        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }

    static func bytes(_ n: Int64) -> String {
        return ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    static func date(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }

    /// Opaque navigation bars on iOS 13–15 too (iOS 15 made them see-through
    /// over scrolled content), in the same style iOS 12 uses.
    static func styleNavigationBar(_ bar: UINavigationBar) {
        bar.tintColor = accent
        bar.barStyle = .default
        bar.isTranslucent = false
        if #available(iOS 13.0, *) {
            let a = UINavigationBarAppearance()
            a.configureWithOpaqueBackground()
            a.backgroundColor = UIColor(white: 0.98, alpha: 1)
            a.titleTextAttributes = [.foregroundColor: UIColor.black]
            a.largeTitleTextAttributes = [.foregroundColor: UIColor.black]
            bar.standardAppearance = a
            bar.scrollEdgeAppearance = a
            bar.compactAppearance = a
        }
    }

    /// The iPhone model, e.g. "iPhone9,3" (an iPhone 7).
    static var hardwareModel: String {
        var info = utsname()
        uname(&info)
        let mirror = Mirror(reflecting: info.machine)
        var s = ""
        for child in mirror.children {
            guard let v = child.value as? Int8, v != 0 else { break }
            s.append(Character(UnicodeScalar(UInt8(bitPattern: v))))
        }
        return s.isEmpty ? UIDevice.current.model : s
    }

    /// A friendly name for common older iPhones.
    static var deviceName: String {
        let names: [String: String] = [
            "iPhone7,2": "iPhone 6", "iPhone7,1": "iPhone 6 Plus", "iPhone8,1": "iPhone 6s", "iPhone8,2": "iPhone 6s Plus",
            "iPhone8,4": "iPhone SE", "iPhone9,1": "iPhone 7", "iPhone9,3": "iPhone 7", "iPhone9,2": "iPhone 7 Plus",
            "iPhone9,4": "iPhone 7 Plus", "iPhone10,1": "iPhone 8", "iPhone10,4": "iPhone 8", "iPhone10,2": "iPhone 8 Plus",
            "iPhone10,5": "iPhone 8 Plus", "iPhone10,3": "iPhone X", "iPhone10,6": "iPhone X", "iPod7,1": "iPod touch (6th gen)",
            "iPod9,1": "iPod touch (7th gen)"
        ]
        let m = hardwareModel
        return names[m] ?? m
    }
}

extension UIViewController {
    /// Shows a simple alert with an OK button.
    func showMessage(_ title: String, _ message: String?) {
        let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        present(a, animated: true)
    }

    /// Action sheets need an anchor on iPad; harmless on iPhone.
    func anchor(_ sheet: UIAlertController, to view: UIView?) {
        if let pop = sheet.popoverPresentationController {
            let v = view ?? self.view!
            pop.sourceView = v
            pop.sourceRect = v.bounds
        }
    }
}
