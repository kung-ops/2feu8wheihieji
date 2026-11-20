import UIKit

/// The UIKit side of an Android View: a plain view that can also show what
/// the app drew in onDraw(Canvas), and pass touches back as MotionEvents.
/// (The Linux test runner builds a minimal version with APKSANDBOX_RUNNER.)
final class CanvasView: UIView {
    weak var box: ViewBox?
    private(set) var ops: [DrawOp] = []
    /// Send touches to the app (it has onTouchEvent or an OnTouchListener).
    var acceptsTouches = false
    /// Height to use when the layout doesn't give one (custom views).
    var preferredHeight: CGFloat = 0
    private var reportedSize = CGSize.zero

    #if APKSANDBOX_RUNNER
    func show(_ ops: [DrawOp]) { self.ops = ops }
    #else
    func show(_ ops: [DrawOp]) {
        self.ops = ops
        redraw()
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: preferredHeight > 0 ? preferredHeight : UIView.noIntrinsicMetric)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        if size != reportedSize {
            reportedSize = size
            if let b = box { b.sizeHandler?(b, size.width, size.height) }
            if !ops.isEmpty { redraw() }
        }
    }

    /// Renders the recorded commands into the layer (no backing store for
    /// views that never draw).
    private func redraw() {
        let size = bounds.size
        guard size.width > 0, size.height > 0, !ops.isEmpty else {
            layer.contents = nil
            return
        }
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.scaleBy(x: 1 / Graphics.density, y: 1 / Graphics.density)
        CanvasRenderer.draw(ops, in: ctx, depth: 0)
        layer.contents = UIGraphicsGetImageFromCurrentImageContext()?.cgImage
    }

    private func forward(_ touches: Set<UITouch>, _ action: Int32) {
        guard acceptsTouches, let t = touches.first, let b = box else { return }
        let p = t.location(in: self)
        b.touchHandler?(b, action, p.x, p.y)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        forward(touches, 0)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        forward(touches, 2)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        forward(touches, 1)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        forward(touches, 3)
    }
    #endif
}

#if !APKSANDBOX_RUNNER
/// Replays recorded android.graphics commands with CoreGraphics. The
/// context is in Android pixels (the caller scales it to points).
enum CanvasRenderer {
    static func color(_ argb: UInt32) -> CGColor {
        return UIColor(red: CGFloat((argb >> 16) & 0xff) / 255, green: CGFloat((argb >> 8) & 0xff) / 255,
                       blue: CGFloat(argb & 0xff) / 255, alpha: CGFloat(argb >> 24) / 255).cgColor
    }

    static func draw(_ ops: [DrawOp], in ctx: CGContext, depth: Int) {
        var saves = 0
        for op in ops {
            switch op {
            case .fill(let c):
                ctx.setFillColor(color(c))
                ctx.fill(CGRect(x: -100_000, y: -100_000, width: 200_000, height: 200_000))
            case .rect(let r, let p):
                shape(UIBezierPath(rect: r.standardized), p, ctx)
            case .roundRect(let r, let rx, let ry, let p):
                let s = r.standardized
                let cw = max(0, min(rx, s.width / 2)), ch = max(0, min(ry, s.height / 2))
                shape(UIBezierPath(cgPath: CGPath(roundedRect: s, cornerWidth: cw, cornerHeight: ch, transform: nil)), p, ctx)
            case .oval(let r, let p):
                shape(UIBezierPath(ovalIn: r.standardized), p, ctx)
            case .arc(let r, let start, let sweep, let useCenter, let p):
                shape(arcPath(r.standardized, start, sweep, useCenter: useCenter), p, ctx)
            case .line(let a, let b, var p):
                let path = UIBezierPath()
                path.move(to: a)
                path.addLine(to: b)
                p.style = 1
                shape(path, p, ctx)
            case .text(let s, let pt, let p):
                text(s, at: pt, p)
            case .path(let pops, let evenOdd, let p):
                let path = bezier(pops)
                path.usesEvenOddFillRule = evenOdd
                shape(path, p, ctx)
            case .bitmap(let content, let size, let src, let dst, let alpha):
                bitmap(content, size, src, dst, alpha, ctx, depth)
            case .save:
                ctx.saveGState()
                saves += 1
            case .restore:
                if saves > 0 { ctx.restoreGState(); saves -= 1 }
            case .translate(let x, let y):
                ctx.translateBy(x: x, y: y)
            case .scale(let x, let y):
                ctx.scaleBy(x: x, y: y)
            case .rotate(let deg):
                ctx.rotate(by: deg * .pi / 180)
            case .clip(let r):
                ctx.clip(to: r.standardized)
            case .concat(let a, let b, let c, let d, let tx, let ty):
                ctx.concatenate(CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty))
            }
        }
        while saves > 0 { ctx.restoreGState(); saves -= 1 }
    }

    private static func shape(_ path: UIBezierPath, _ p: PaintState, _ ctx: CGContext) {
        if p.style == 0 || p.style == 2 {
            ctx.setFillColor(color(p.color))
            ctx.addPath(path.cgPath)
            ctx.fillPath(using: path.usesEvenOddFillRule ? .evenOdd : .winding)
        }
        if p.style == 1 || p.style == 2 {
            ctx.setStrokeColor(color(p.color))
            ctx.setLineWidth(max(1, p.strokeWidth))
            ctx.setLineCap(p.cap == 1 ? .round : (p.cap == 2 ? .square : .butt))
            ctx.addPath(path.cgPath)
            ctx.strokePath()
        }
    }

    private static func arcPath(_ r: CGRect, _ start: CGFloat, _ sweep: CGFloat, useCenter: Bool) -> UIBezierPath {
        // Unit circle, then stretched to the oval; Android angles are degrees,
        // clockwise from 3 o'clock, like UIKit's.
        let a0 = start * .pi / 180, a1 = (start + sweep) * .pi / 180
        let path = UIBezierPath()
        if useCenter { path.move(to: .zero) }
        path.addArc(withCenter: .zero, radius: 1, startAngle: a0, endAngle: a1, clockwise: sweep >= 0)
        if useCenter { path.close() }
        path.apply(CGAffineTransform(scaleX: r.width / 2, y: r.height / 2))
        path.apply(CGAffineTransform(translationX: r.midX, y: r.midY))
        return path
    }

    private static func bezier(_ ops: [PathOp]) -> UIBezierPath {
        let path = UIBezierPath()
        var started = false
        for op in ops {
            switch op {
            case .move(let p):
                path.move(to: p)
                started = true
            case .line(let p):
                if !started { path.move(to: .zero); started = true }
                path.addLine(to: p)
            case .quad(let c, let p):
                if !started { path.move(to: .zero); started = true }
                path.addQuadCurve(to: p, controlPoint: c)
            case .cubic(let c1, let c2, let p):
                if !started { path.move(to: .zero); started = true }
                path.addCurve(to: p, controlPoint1: c1, controlPoint2: c2)
            case .close:
                if started { path.close() }
            case .oval(let r):
                path.append(UIBezierPath(ovalIn: r.standardized))
            case .rect(let r):
                path.append(UIBezierPath(rect: r.standardized))
            case .roundRect(let r, let rx, let ry):
                let s = r.standardized
                let cw = max(0, min(rx, s.width / 2)), ch = max(0, min(ry, s.height / 2))
                path.append(UIBezierPath(cgPath: CGPath(roundedRect: s, cornerWidth: cw, cornerHeight: ch, transform: nil)))
            case .arc(let r, let start, let sweep):
                path.append(arcPath(r.standardized, start, sweep, useCenter: false))
            }
        }
        return path
    }

    private static func text(_ s: String, at pt: CGPoint, _ p: PaintState) {
        let size = max(1, p.textSize)
        let font = p.bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(cgColor: color(p.color))]
        let ns = s as NSString
        var x = pt.x
        if p.align != 0 {
            let w = ns.size(withAttributes: attrs).width
            x -= p.align == 1 ? w / 2 : w
        }
        // Android draws text from its baseline; UIKit from the top of the line.
        ns.draw(at: CGPoint(x: x, y: pt.y - font.ascender), withAttributes: attrs)
    }

    private static func bitmap(_ content: BitmapContent, _ size: CGSize, _ src: CGRect?, _ dst: CGRect,
                               _ alpha: UInt8, _ ctx: CGContext, _ depth: Int) {
        let d = dst.standardized
        guard d.width > 0, d.height > 0, size.width > 0, size.height > 0 else { return }
        if let img = content.image, var cg = img.cgImage {
            if let s = src {
                // `src` is in the bitmap's pixels; the decoded image may be smaller.
                let fx = CGFloat(cg.width) / size.width, fy = CGFloat(cg.height) / size.height
                let crop = CGRect(x: s.minX * fx, y: s.minY * fy, width: s.width * fx, height: s.height * fy).integral
                if let c = cg.cropping(to: crop) { cg = c }
            }
            UIImage(cgImage: cg).draw(in: d, blendMode: .normal, alpha: CGFloat(alpha) / 255)
        }
        if !content.ops.isEmpty, depth < 4 {
            ctx.saveGState()
            ctx.clip(to: d)
            let s = src ?? CGRect(origin: .zero, size: size)
            ctx.translateBy(x: d.minX, y: d.minY)
            ctx.scaleBy(x: d.width / max(1, s.width), y: d.height / max(1, s.height))
            ctx.translateBy(x: -s.minX, y: -s.minY)
            draw(content.ops, in: ctx, depth: depth + 1)
            ctx.restoreGState()
        }
    }
}
#endif
