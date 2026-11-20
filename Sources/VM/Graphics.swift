import UIKit

// android.graphics for custom views and simple games: an app's
// View.onDraw(Canvas) runs in the interpreter and is recorded as a list of
// drawing commands (`DrawOp`); CanvasView replays them with CoreGraphics.
// Coordinates are Android pixels (2 px per iOS point, like an xhdpi phone).

/// How a Paint looked when something was drawn with it.
struct PaintState {
    var color: UInt32 = 0xff000000
    /// 0 fill, 1 stroke, 2 fill and stroke
    var style = 0
    var strokeWidth: CGFloat = 0
    var textSize: CGFloat = 24
    /// 0 left, 1 center, 2 right
    var align = 0
    var bold = false
    /// 0 butt, 1 round, 2 square
    var cap = 0
}

enum PathOp {
    case move(CGPoint)
    case line(CGPoint)
    case quad(CGPoint, CGPoint)
    case cubic(CGPoint, CGPoint, CGPoint)
    case close
    case oval(CGRect)
    case rect(CGRect)
    case roundRect(CGRect, CGFloat, CGFloat)
    case arc(CGRect, CGFloat, CGFloat)
}

/// What a Bitmap holds: decoded pixels, or drawing commands (for a bitmap
/// the app drew into with `new Canvas(bitmap)`).
final class BitmapContent {
    var image: UIImage?
    var ops: [DrawOp] = []
    init(image: UIImage?) { self.image = image }
}

indirect enum DrawOp {
    case fill(UInt32)
    case rect(CGRect, PaintState)
    case roundRect(CGRect, CGFloat, CGFloat, PaintState)
    case oval(CGRect, PaintState)
    case arc(CGRect, CGFloat, CGFloat, Bool, PaintState)
    case line(CGPoint, CGPoint, PaintState)
    case text(String, CGPoint, PaintState)
    case path([PathOp], Bool, PaintState)
    case bitmap(BitmapContent, CGSize, CGRect?, CGRect, UInt8)
    case save
    case restore
    case translate(CGFloat, CGFloat)
    case scale(CGFloat, CGFloat)
    case rotate(CGFloat)
    case clip(CGRect)
    /// Canvas.concat(Matrix): a, b, c, d, tx, ty (CGAffineTransform order).
    case concat(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)

    /// Short description, for the Linux runner and logs.
    var summary: String {
        switch self {
        case .fill: return "fill"
        case .rect: return "rect"
        case .roundRect: return "roundRect"
        case .oval: return "oval"
        case .arc: return "arc"
        case .line: return "line"
        case .text(let s, _, _): return "text \"\(s)\""
        case .path: return "path"
        case .bitmap: return "bitmap"
        case .save, .restore, .translate, .scale, .rotate, .clip, .concat: return "transform"
        }
    }
}

final class CanvasBox {
    let width: Int32
    let height: Int32
    var ops: [DrawOp] = []
    var saveCount: Int32 = 1
    /// Set when this canvas draws into a Bitmap.
    var target: BitmapContent?
    init(width: Int32, height: Int32) {
        self.width = width
        self.height = height
    }
    func add(_ op: DrawOp) {
        if ops.count < 20_000 { ops.append(op) }
    }
}

final class PaintBox {
    var state = PaintState()
    init() {}
    init(copy: PaintState) { state = copy }
}

final class PathBox {
    var ops: [PathOp] = []
    var evenOdd = false
    var last = CGPoint.zero
}

final class BitmapBox {
    let content: BitmapContent
    let width: Int32
    let height: Int32
    init(content: BitmapContent, width: Int32, height: Int32) {
        self.content = content
        self.width = width
        self.height = height
    }
}

/// android.graphics.drawable.Drawable (a bitmap or a solid colour).
final class DrawableBox {
    var bitmap: BitmapBox?
    var color: UInt32?
    var bounds = CGRect.zero
    var alpha: UInt8 = 255
}

final class MotionEventBox {
    var action: Int32
    var x: Float
    var y: Float
    let downTime: Int64
    let eventTime: Int64
    init(action: Int32, x: Float, y: Float, downTime: Int64, eventTime: Int64) {
        self.action = action
        self.x = x
        self.y = y
        self.downTime = downTime
        self.eventTime = eventTime
    }
}

/// android.view.WindowManager / Display (screen size for games).
final class WindowManagerBox {}
final class DisplayBox {}

enum Graphics {
    /// Android pixels per iOS point.
    static let density: CGFloat = 2

    /// Width of a line of text in pixels.
    static func textWidth(_ s: String, size: CGFloat, bold: Bool) -> CGFloat {
        #if !APKSANDBOX_RUNNER
        let font = bold ? UIFont.boldSystemFont(ofSize: size / density) : UIFont.systemFont(ofSize: size / density)
        return (s as NSString).size(withAttributes: [.font: font]).width * density
        #else
        return CGFloat(s.count) * size * (bold ? 0.6 : 0.55)
        #endif
    }

    /// Pixel size of a PNG / JPEG / WebP, read from its header.
    static func imageSize(_ d: [UInt8]) -> (Int32, Int32)? {
        func be32(_ o: Int) -> Int { return d.count > o + 3 ? (Int(d[o]) << 24) | (Int(d[o + 1]) << 16) | (Int(d[o + 2]) << 8) | Int(d[o + 3]) : 0 }
        func be16(_ o: Int) -> Int { return d.count > o + 1 ? (Int(d[o]) << 8) | Int(d[o + 1]) : 0 }
        if d.count > 24, d[0] == 0x89, d[1] == 0x50 { return (Int32(be32(16)), Int32(be32(20))) }
        if d.count > 4, d[0] == 0xff, d[1] == 0xd8 {
            var i = 2
            while i + 9 < d.count {
                guard d[i] == 0xff else { i += 1; continue }
                let marker = d[i + 1]
                if (0xc0...0xcf).contains(marker) && marker != 0xc4 && marker != 0xc8 && marker != 0xcc {
                    return (Int32(be16(i + 7)), Int32(be16(i + 5)))
                }
                i += 2 + be16(i + 2)
            }
        }
        // WebP: "RIFF" .... "WEBP" then a VP8 / VP8L / VP8X chunk.
        if d.count > 30, d[0] == 0x52, d[1] == 0x49, d[8] == 0x57, d[12] == 0x56, d[13] == 0x50, d[14] == 0x38 {
            switch d[15] {
            case 0x58:
                let w = 1 + (Int(d[24]) | (Int(d[25]) << 8) | (Int(d[26]) << 16))
                let h = 1 + (Int(d[27]) | (Int(d[28]) << 8) | (Int(d[29]) << 16))
                return (Int32(w), Int32(h))
            case 0x4c:
                let b = UInt32(d[21]) | UInt32(d[22]) << 8 | UInt32(d[23]) << 16 | UInt32(d[24]) << 24
                return (Int32((b & 0x3fff) + 1), Int32(((b >> 14) & 0x3fff) + 1))
            case 0x20:
                return (Int32(Int(d[26]) | (Int(d[27]) & 0x3f) << 8), Int32(Int(d[28]) | (Int(d[29]) & 0x3f) << 8))
            default:
                break
            }
        }
        return nil
    }
}

extension Framework {

    // MARK: - Helpers

    static func enumName(_ v: Value) -> String {
        return (v.o?.fields["__name"]?.o?.native as? String) ?? ""
    }

    static func paint(_ v: Value) -> PaintState {
        return (v.o?.native as? PaintBox)?.state ?? PaintState()
    }

    /// Reads android.graphics.Rect (int fields) or RectF (float fields).
    static func rect(_ o: JObject?) -> CGRect {
        guard let o = o else { return .zero }
        let isF = o.cls.name == "Landroid/graphics/RectF;"
        func f(_ n: String) -> CGFloat {
            let v = o.fields[n] ?? .int(0)
            return isF ? CGFloat(v.f) : CGFloat(v.i)
        }
        let l = f("left"), t = f("top"), r = f("right"), b = f("bottom")
        return CGRect(x: l, y: t, width: r - l, height: b - t)
    }

    static func setRect(_ o: JObject, _ l: CGFloat, _ t: CGFloat, _ r: CGFloat, _ b: CGFloat) {
        if o.cls.name == "Landroid/graphics/RectF;" {
            o.fields["left"] = .float(Float(l)); o.fields["top"] = .float(Float(t))
            o.fields["right"] = .float(Float(r)); o.fields["bottom"] = .float(Float(b))
        } else {
            o.fields["left"] = .int(Int32(l.rounded(.down))); o.fields["top"] = .int(Int32(t.rounded(.down)))
            o.fields["right"] = .int(Int32(r.rounded(.down))); o.fields["bottom"] = .int(Int32(b.rounded(.down)))
        }
    }

    static func newRect(_ vm: VM, _ r: CGRect, float: Bool) -> JObject {
        let o = vm.newObject(float ? "Landroid/graphics/RectF;" : "Landroid/graphics/Rect;")
        setRect(o, r.minX, r.minY, r.maxX, r.maxY)
        return o
    }

    static func newBitmap(_ vm: VM, image: UIImage?, width: Int32, height: Int32) -> JObject {
        return vm.newObject("Landroid/graphics/Bitmap;",
                            native: BitmapBox(content: BitmapContent(image: image), width: width, height: height))
    }

    static func decodeBitmap(_ vm: VM, bytes: [UInt8]) -> JObject? {
        guard !bytes.isEmpty else { return nil }
        let size = Graphics.imageSize(bytes)
        let img = ApkPackage.decodeImage(Data(bytes), maxSide: VirtualDevice.maxBitmapSide)
        guard size != nil || img != nil else { return nil }
        var w = size?.0 ?? 0, h = size?.1 ?? 0
        #if !APKSANDBOX_RUNNER
        if w == 0, let i = img { w = Int32(i.size.width * i.scale); h = Int32(i.size.height * i.scale) }
        #endif
        if w == 0 { w = 64; h = 64 }
        return newBitmap(vm, image: img, width: w, height: h)
    }

    static func resourceBitmap(_ vm: VM, _ id: Int) -> JObject? {
        guard let p = vm.apk.resources?.filePath(id, preferBitmap: true), !p.hasSuffix(".xml"),
              let bytes = vm.apk.readFile(p) else { return nil }
        return decodeBitmap(vm, bytes: bytes)
    }

    // MARK: - Constructors

    static func graphicsConstruct(_ vm: VM, _ t: JObject, _ ref: DexMethodRef, _ a: [Value]) -> Ret? {
        let p = ref.params
        switch ref.classDesc {
        case "Landroid/graphics/Paint;", "Landroid/text/TextPaint;":
            if p.first == "Landroid/graphics/Paint;", let src = a[0].o?.native as? PaintBox {
                t.native = PaintBox(copy: src.state)
            } else {
                t.native = PaintBox()
            }
            return .void
        case "Landroid/graphics/Path;":
            let pb = PathBox()
            if let src = a.first?.o?.native as? PathBox { pb.ops = src.ops; pb.last = src.last }
            t.native = pb
            return .void
        case "Landroid/graphics/Canvas;":
            if let bmp = a.first?.o?.native as? BitmapBox {
                let cb = CanvasBox(width: bmp.width, height: bmp.height)
                cb.target = bmp.content
                cb.ops = bmp.content.ops
                t.native = cb
            } else {
                t.native = CanvasBox(width: 0, height: 0)
            }
            return .void
        case "Landroid/graphics/Rect;", "Landroid/graphics/RectF;":
            if p.count == 4 {
                if p[0] == "F" { setRect(t, CGFloat(a[0].f), CGFloat(a[1].f), CGFloat(a[2].f), CGFloat(a[3].f)) }
                else { setRect(t, CGFloat(a[0].i), CGFloat(a[1].i), CGFloat(a[2].i), CGFloat(a[3].i)) }
            } else if p.count == 1 {
                let r = rect(a[0].o)
                setRect(t, r.minX, r.minY, r.maxX, r.maxY)
            } else {
                setRect(t, 0, 0, 0, 0)
            }
            return .void
        case "Landroid/graphics/Point;", "Landroid/graphics/PointF;":
            let isF = ref.classDesc.hasSuffix("PointF;")
            if p.count == 2 {
                t.fields["x"] = a[0]; t.fields["y"] = a[1]
            } else if p.count == 1, let o = a[0].o {
                t.fields["x"] = o.fields["x"] ?? .int(0); t.fields["y"] = o.fields["y"] ?? .int(0)
            } else {
                t.fields["x"] = isF ? .float(0) : .int(0); t.fields["y"] = isF ? .float(0) : .int(0)
            }
            return .void
        case "Landroid/graphics/drawable/ColorDrawable;":
            let d = DrawableBox()
            d.color = p.first == "I" ? UInt32(bitPattern: a[0].i) : 0
            t.native = d
            return .void
        case "Landroid/graphics/drawable/BitmapDrawable;":
            let d = DrawableBox()
            d.bitmap = a.last?.o?.native as? BitmapBox
            t.native = d
            return .void
        case "Landroid/util/DisplayMetrics;":
            fillDisplayMetrics(t)
            return .void
        default:
            return nil
        }
    }

    static func fillDisplayMetrics(_ o: JObject) {
        #if !APKSANDBOX_RUNNER
        let size = UIScreen.main.bounds.size
        #else
        let size = CGSize(width: 375, height: 667)
        #endif
        o.fields["density"] = .float(Float(Graphics.density))
        o.fields["scaledDensity"] = .float(Float(Graphics.density))
        o.fields["densityDpi"] = .int(320)
        o.fields["xdpi"] = .float(320)
        o.fields["ydpi"] = .float(320)
        o.fields["widthPixels"] = .int(Int32(size.width * Graphics.density))
        o.fields["heightPixels"] = .int(Int32(size.height * Graphics.density))
    }

    // MARK: - Static methods

    static func graphicsStatic(_ vm: VM, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        let n = ref.name
        let p = ref.params
        switch ref.classDesc {
        case "Landroid/graphics/BitmapFactory;":
            switch n {
            case "decodeResource":
                return O(resourceBitmap(vm, resId(a[1])))
            case "decodeByteArray":
                guard let arr = a[0].o?.native as? JArray else { return O(nil) }
                var bytes = arr.byteValues
                if p.count >= 3 { bytes = Array(bytes.dropFirst(Int(max(0, a[1].i))).prefix(Int(max(0, a[2].i)))) }
                return O(decodeBitmap(vm, bytes: bytes))
            case "decodeFile":
                let path = (try? vm.stringOf(a[0].o)) ?? ""
                guard vm.storage.allows(path), let d = FileManager.default.contents(atPath: path) else { return O(nil) }
                return O(decodeBitmap(vm, bytes: [UInt8](d)))
            case "decodeStream":
                guard let fs = a.first?.o?.native as? FileStreamBox else { return O(nil) }
                return O(decodeBitmap(vm, bytes: Array(fs.data[min(fs.position, fs.data.count)...])))
            default: return nil
            }
        case "Landroid/graphics/Bitmap;":
            switch n {
            case "createBitmap":
                if p.count >= 2, p[0] == "I", p[1] == "I" {
                    let w = max(1, a[0].i), h = max(1, a[1].i)
                    try vm.checkAllocation(type: "[I", count: Int(w) * Int(h))
                    return O(newBitmap(vm, image: nil, width: w, height: h))
                }
                if let src = a.first?.o?.native as? BitmapBox {
                    return O(vm.newObject("Landroid/graphics/Bitmap;", native: BitmapBox(content: src.content, width: src.width, height: src.height)))
                }
                return O(nil)
            case "createScaledBitmap":
                guard let src = a[0].o?.native as? BitmapBox else { throw vm.npe("createScaledBitmap") }
                return O(vm.newObject("Landroid/graphics/Bitmap;",
                                      native: BitmapBox(content: src.content, width: max(1, a[1].i), height: max(1, a[2].i))))
            default: return nil
            }
        case "Landroid/view/MotionEvent;":
            if n == "obtain", p.count >= 5 {
                let e = MotionEventBox(action: a[2].i, x: a[3].f, y: a[4].f, downTime: a[0].j, eventTime: a[1].j)
                return O(vm.newObject("Landroid/view/MotionEvent;", native: e))
            }
            return nil
        case "Landroid/graphics/Rect;", "Landroid/graphics/RectF;":
            if n == "intersects", a.count >= 2 {
                return B(rect(a[0].o).intersects(rect(a[1].o)))
            }
            return nil
        case "Landroid/graphics/Typeface;":
            if n == "create" || n == "defaultFromStyle" {
                let style = a.last?.i ?? 0
                let o = vm.newObject("Landroid/graphics/Typeface;")
                o.fields["__name"] = .obj(vm.str(style & 1 != 0 ? "DEFAULT_BOLD" : "DEFAULT"))
                return O(o)
            }
            return nil
        default:
            return nil
        }
    }

    // MARK: - Canvas

    static func canvasMethod(_ vm: VM, _ t: JObject, _ c: CanvasBox, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        let p = ref.params
        func pt(_ i: Int) -> CGFloat { return CGFloat(a[i].f) }
        func flush() { c.target?.ops = c.ops }
        defer { flush() }
        switch ref.name {
        case "getWidth": return I(c.width)
        case "getHeight": return I(c.height)
        case "getDensity": return I(320)
        case "isHardwareAccelerated": return B(false)
        case "drawColor", "drawRGB", "drawARGB":
            var col: UInt32
            if ref.name == "drawRGB" {
                col = 0xff000000 | (UInt32(a[0].i & 0xff) << 16) | (UInt32(a[1].i & 0xff) << 8) | UInt32(a[2].i & 0xff)
            } else if ref.name == "drawARGB" {
                col = (UInt32(a[0].i & 0xff) << 24) | (UInt32(a[1].i & 0xff) << 16) | (UInt32(a[2].i & 0xff) << 8) | UInt32(a[3].i & 0xff)
            } else {
                col = UInt32(bitPattern: a[0].i)
            }
            if col >> 24 == 0xff, c.target == nil {
                // An opaque fill hides everything drawn before it.
                c.ops.removeAll()
            }
            c.add(.fill(col))
            return .void
        case "drawPaint":
            c.add(.fill(paint(a[0]).color))
            return .void
        case "drawRect":
            if p.first == "F" {
                c.add(.rect(CGRect(x: pt(0), y: pt(1), width: pt(2) - pt(0), height: pt(3) - pt(1)), paint(a[4])))
            } else {
                c.add(.rect(rect(a[0].o), paint(a[1])))
            }
            return .void
        case "drawRoundRect":
            if p.first == "F" {
                c.add(.roundRect(CGRect(x: pt(0), y: pt(1), width: pt(2) - pt(0), height: pt(3) - pt(1)), pt(4), pt(5), paint(a[6])))
            } else {
                c.add(.roundRect(rect(a[0].o), pt(1), pt(2), paint(a[3])))
            }
            return .void
        case "drawCircle":
            let r = pt(2)
            c.add(.oval(CGRect(x: pt(0) - r, y: pt(1) - r, width: r * 2, height: r * 2), paint(a[3])))
            return .void
        case "drawOval":
            if p.first == "F" {
                c.add(.oval(CGRect(x: pt(0), y: pt(1), width: pt(2) - pt(0), height: pt(3) - pt(1)), paint(a[4])))
            } else {
                c.add(.oval(rect(a[0].o), paint(a[1])))
            }
            return .void
        case "drawArc":
            if p.first == "F" {
                c.add(.arc(CGRect(x: pt(0), y: pt(1), width: pt(2) - pt(0), height: pt(3) - pt(1)), pt(4), pt(5), a[6].i != 0, paint(a[7])))
            } else {
                c.add(.arc(rect(a[0].o), pt(1), pt(2), a[3].i != 0, paint(a[4])))
            }
            return .void
        case "drawLine":
            c.add(.line(CGPoint(x: pt(0), y: pt(1)), CGPoint(x: pt(2), y: pt(3)), paint(a[4])))
            return .void
        case "drawLines", "drawPoints":
            guard let arr = a[0].o?.native as? JArray else { return .void }
            var vals = arr.items.map { CGFloat($0.f) }
            var pnt = a[1]
            if p.count >= 4 {
                vals = Array(vals.dropFirst(Int(max(0, a[1].i))).prefix(Int(max(0, a[2].i))))
                pnt = a[3]
            }
            let ps = paint(pnt)
            if ref.name == "drawLines" {
                var i = 0
                while i + 3 < vals.count {
                    c.add(.line(CGPoint(x: vals[i], y: vals[i + 1]), CGPoint(x: vals[i + 2], y: vals[i + 3]), ps))
                    i += 4
                }
            } else {
                let r = max(1, ps.strokeWidth / 2)
                var i = 0
                while i + 1 < vals.count {
                    var dot = ps
                    dot.style = 0
                    c.add(.oval(CGRect(x: vals[i] - r, y: vals[i + 1] - r, width: r * 2, height: r * 2), dot))
                    i += 2
                }
            }
            return .void
        case "drawPoint":
            var ps = paint(a[2])
            let r = max(1, ps.strokeWidth / 2)
            ps.style = 0
            c.add(.oval(CGRect(x: pt(0) - r, y: pt(1) - r, width: r * 2, height: r * 2), ps))
            return .void
        case "drawText":
            var text = ""
            var xi = 1
            if p.first == "[C" {
                let units = (a[0].o?.native as? JArray)?.utf16 ?? []
                text = String(decoding: units.dropFirst(Int(max(0, a[1].i))).prefix(Int(max(0, a[2].i))), as: UTF16.self)
                xi = 3
            } else {
                text = try vm.stringOf(a[0].o)
                if p.count == 6 {
                    let u = Array(text.utf16)
                    let s = max(0, min(Int(a[1].i), u.count)), e = max(s, min(Int(a[2].i), u.count))
                    text = String(decoding: u[s..<e], as: UTF16.self)
                    xi = 3
                }
            }
            c.add(.text(text, CGPoint(x: pt(xi), y: pt(xi + 1)), paint(a[xi + 2])))
            return .void
        case "drawPath":
            if let pb = a[0].o?.native as? PathBox { c.add(.path(pb.ops, pb.evenOdd, paint(a[1]))) }
            return .void
        case "drawBitmap":
            guard let b = a[0].o?.native as? BitmapBox else { return .void }
            let size = CGSize(width: CGFloat(b.width), height: CGFloat(b.height))
            if p.count == 4, p[1] == "F" {
                c.add(.bitmap(b.content, size, nil, CGRect(x: pt(1), y: pt(2), width: size.width, height: size.height), 255))
            } else if p.count == 4 {
                let src: CGRect? = a[1].o == nil ? nil : rect(a[1].o)
                c.add(.bitmap(b.content, size, src, rect(a[2].o), 255))
            } else if p.count == 3, p[1] == "Landroid/graphics/Matrix;" {
                c.add(.bitmap(b.content, size, nil, CGRect(origin: .zero, size: size), 255))
            }
            return .void
        case "save", "saveLayer", "saveLayerAlpha":
            c.add(.save)
            c.saveCount += 1
            return I(c.saveCount)
        case "restore":
            if c.saveCount > 1 { c.add(.restore); c.saveCount -= 1 }
            return .void
        case "restoreToCount":
            while c.saveCount > max(1, a[0].i) { c.add(.restore); c.saveCount -= 1 }
            return .void
        case "getSaveCount": return I(c.saveCount)
        case "translate": c.add(.translate(pt(0), pt(1))); return .void
        case "scale":
            if p.count == 4 {
                c.add(.translate(pt(2), pt(3))); c.add(.scale(pt(0), pt(1))); c.add(.translate(-pt(2), -pt(3)))
            } else {
                c.add(.scale(pt(0), pt(1)))
            }
            return .void
        case "rotate":
            if p.count == 3 {
                c.add(.translate(pt(1), pt(2))); c.add(.rotate(pt(0))); c.add(.translate(-pt(1), -pt(2)))
            } else {
                c.add(.rotate(pt(0)))
            }
            return .void
        case "clipRect":
            if p.first == "F" { c.add(.clip(CGRect(x: pt(0), y: pt(1), width: pt(2) - pt(0), height: pt(3) - pt(1)))) }
            else if p.first == "I" { c.add(.clip(CGRect(x: CGFloat(a[0].i), y: CGFloat(a[1].i), width: CGFloat(a[2].i - a[0].i), height: CGFloat(a[3].i - a[1].i)))) }
            else { c.add(.clip(rect(a[0].o))) }
            return B(true)
        case "getClipBounds":
            let r = CGRect(x: 0, y: 0, width: CGFloat(c.width), height: CGFloat(c.height))
            if let o = a.first?.o { setRect(o, r.minX, r.minY, r.maxX, r.maxY); return B(true) }
            return O(newRect(vm, r, float: false))
        case "concat":
            if let m = a.first?.o?.native as? MatrixBox, !m.m.isIdentity {
                let t = m.m
                c.add(.concat(t.a, t.b, t.c, t.d, t.tx, t.ty))
            }
            return .void
        case "clipOutRect", "clipOutPath", "clipPath":
            // Clipping away a region isn't recorded; drawing continues unclipped.
            return B(true)
        case "setBitmap", "setDensity", "setDrawFilter", "setMatrix", "drawFilter":
            return .void
        default:
            return nil
        }
    }

    // MARK: - Paint

    static func paintMethod(_ vm: VM, _ t: JObject, _ pb: PaintBox, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        var s = pb.state
        defer { pb.state = s }
        switch ref.name {
        case "setColor":
            if ref.params.first == "I" { s.color = UInt32(bitPattern: a[0].i) }
            return .void
        case "getColor": return I(Int32(bitPattern: s.color))
        case "setAlpha":
            s.color = (s.color & 0x00ffffff) | (UInt32(a[0].i & 0xff) << 24)
            return .void
        case "getAlpha": return I(Int32(s.color >> 24))
        case "setARGB":
            s.color = (UInt32(a[0].i & 0xff) << 24) | (UInt32(a[1].i & 0xff) << 16) | (UInt32(a[2].i & 0xff) << 8) | UInt32(a[3].i & 0xff)
            return .void
        case "setStyle":
            switch enumName(a[0]) {
            case "STROKE": s.style = 1
            case "FILL_AND_STROKE": s.style = 2
            default: s.style = 0
            }
            return .void
        case "setStrokeWidth": s.strokeWidth = CGFloat(a[0].f); return .void
        case "getStrokeWidth": return .val(.float(Float(s.strokeWidth)))
        case "setTextSize": s.textSize = CGFloat(a[0].f); return .void
        case "getTextSize": return .val(.float(Float(s.textSize)))
        case "setTextAlign":
            switch enumName(a[0]) {
            case "CENTER": s.align = 1
            case "RIGHT": s.align = 2
            default: s.align = 0
            }
            return .void
        case "setStrokeCap":
            switch enumName(a[0]) {
            case "ROUND": s.cap = 1
            case "SQUARE": s.cap = 2
            default: s.cap = 0
            }
            return .void
        case "setFakeBoldText": s.bold = a[0].i != 0; return .void
        case "setTypeface":
            s.bold = enumName(a[0]).contains("BOLD")
            return O(a[0].o)
        case "set":
            if let src = a[0].o?.native as? PaintBox { s = src.state }
            return .void
        case "reset": s = PaintState(); return .void
        case "measureText":
            var text = ""
            if ref.params.first == "[C" {
                let u = (a[0].o?.native as? JArray)?.utf16 ?? []
                text = String(decoding: u.dropFirst(Int(max(0, a[1].i))).prefix(Int(max(0, a[2].i))), as: UTF16.self)
            } else {
                text = try vm.stringOf(a[0].o)
                if ref.params.count == 3 {
                    let u = Array(text.utf16)
                    let b = max(0, min(Int(a[1].i), u.count)), e = max(b, min(Int(a[2].i), u.count))
                    text = String(decoding: u[b..<e], as: UTF16.self)
                }
            }
            return .val(.float(Float(Graphics.textWidth(text, size: s.textSize, bold: s.bold))))
        case "getTextBounds":
            var text = try vm.stringOf(a[0].o)
            let u = Array(text.utf16)
            let b = max(0, min(Int(a[1].i), u.count)), e = max(b, min(Int(a[2].i), u.count))
            text = String(decoding: u[b..<e], as: UTF16.self)
            if let r = a[3].o {
                let w = Graphics.textWidth(text, size: s.textSize, bold: s.bold)
                setRect(r, 0, -s.textSize * 0.72, w, s.textSize * 0.02)
            }
            return .void
        case "getTextWidths":
            // getTextWidths(String, float[]) / (String, int, int, float[]) / (char[], int, int, float[])
            var text = ""
            if ref.params.first == "[C" {
                let u = (a[0].o?.native as? JArray)?.utf16 ?? []
                text = String(decoding: u.dropFirst(Int(max(0, a[1].i))).prefix(Int(max(0, a[2].i))), as: UTF16.self)
            } else {
                text = try vm.stringOf(a[0].o)
                if ref.params.count == 4 {
                    let u = Array(text.utf16)
                    let b = max(0, min(Int(a[1].i), u.count)), e = max(b, min(Int(a[2].i), u.count))
                    text = String(decoding: u[b..<e], as: UTF16.self)
                }
            }
            guard let out = a.last?.o?.native as? JArray else { throw vm.npe("getTextWidths") }
            var k = 0
            for ch in text {
                let w = Float(Graphics.textWidth(String(ch), size: s.textSize, bold: s.bold))
                let units = String(ch).utf16.count
                for j in 0..<units where k + j < out.count { out[k + j] = .float(j == 0 ? w : 0) }
                k += units
            }
            return I(Int32(text.utf16.count))
        case "ascent": return .val(.float(Float(-s.textSize * 0.93)))
        case "descent": return .val(.float(Float(s.textSize * 0.24)))
        case "getFontSpacing": return .val(.float(Float(s.textSize * 1.17)))
        case "getFontMetrics", "getFontMetricsInt":
            let isInt = ref.name == "getFontMetricsInt"
            let o = (a.first?.o) ?? vm.newObject(isInt ? "Landroid/graphics/Paint$FontMetricsInt;" : "Landroid/graphics/Paint$FontMetrics;")
            let vals: [(String, CGFloat)] = [("top", -s.textSize * 1.06), ("ascent", -s.textSize * 0.93),
                                             ("descent", s.textSize * 0.24), ("bottom", s.textSize * 0.27), ("leading", 0)]
            for (k, v) in vals { o.fields[k] = isInt ? .int(Int32(v.rounded())) : .float(Float(v)) }
            if ref.params.isEmpty { return O(o) }
            return isInt ? I(Int32((s.textSize * 1.17).rounded())) : .val(.float(Float(s.textSize * 1.17)))
        case "setAntiAlias", "setDither", "setFilterBitmap", "setShader", "setColorFilter", "setXfermode",
             "setShadowLayer", "clearShadowLayer", "setStrokeJoin", "setStrokeMiter", "setPathEffect", "setMaskFilter",
             "setLetterSpacing", "setFlags", "setSubpixelText", "setLinearText", "setUnderlineText", "setStrikeThruText",
             "setTextSkewX", "setTextScaleX", "setHinting", "setElegantTextHeight":
            return ref.ret == "V" ? .void : O(nil)
        case "isAntiAlias": return B(true)
        case "getStyle", "getTextAlign", "getTypeface", "getShader": return O(nil)
        default:
            return nil
        }
    }

    // MARK: - Path

    static func pathMethod(_ vm: VM, _ t: JObject, _ pb: PathBox, _ ref: DexMethodRef, _ a: [Value]) -> Ret? {
        func f(_ i: Int) -> CGFloat { return CGFloat(a[i].f) }
        func dirRect(_ r: CGRect) -> CGRect { return r }
        switch ref.name {
        case "moveTo": pb.last = CGPoint(x: f(0), y: f(1)); pb.ops.append(.move(pb.last)); return .void
        case "rMoveTo": pb.last = CGPoint(x: pb.last.x + f(0), y: pb.last.y + f(1)); pb.ops.append(.move(pb.last)); return .void
        case "lineTo": pb.last = CGPoint(x: f(0), y: f(1)); pb.ops.append(.line(pb.last)); return .void
        case "rLineTo": pb.last = CGPoint(x: pb.last.x + f(0), y: pb.last.y + f(1)); pb.ops.append(.line(pb.last)); return .void
        case "quadTo":
            pb.last = CGPoint(x: f(2), y: f(3))
            pb.ops.append(.quad(CGPoint(x: f(0), y: f(1)), pb.last))
            return .void
        case "cubicTo":
            pb.last = CGPoint(x: f(4), y: f(5))
            pb.ops.append(.cubic(CGPoint(x: f(0), y: f(1)), CGPoint(x: f(2), y: f(3)), pb.last))
            return .void
        case "close": pb.ops.append(.close); return .void
        case "reset", "rewind": pb.ops.removeAll(); pb.last = .zero; return .void
        case "addCircle":
            let r = f(2)
            pb.ops.append(.oval(CGRect(x: f(0) - r, y: f(1) - r, width: r * 2, height: r * 2)))
            return .void
        case "addRect":
            if ref.params.first == "F" { pb.ops.append(.rect(CGRect(x: f(0), y: f(1), width: f(2) - f(0), height: f(3) - f(1)))) }
            else { pb.ops.append(.rect(rect(a[0].o))) }
            return .void
        case "addOval":
            if ref.params.first == "F" { pb.ops.append(.oval(CGRect(x: f(0), y: f(1), width: f(2) - f(0), height: f(3) - f(1)))) }
            else { pb.ops.append(.oval(rect(a[0].o))) }
            return .void
        case "addRoundRect":
            if ref.params.first == "F" { pb.ops.append(.roundRect(CGRect(x: f(0), y: f(1), width: f(2) - f(0), height: f(3) - f(1)), f(4), f(5))) }
            else if ref.params.count >= 3, ref.params[1] == "F" { pb.ops.append(.roundRect(rect(a[0].o), f(1), f(2))) }
            else { pb.ops.append(.rect(rect(a[0].o))) }
            return .void
        case "arcTo", "addArc":
            if ref.params.first == "F" { pb.ops.append(.arc(CGRect(x: f(0), y: f(1), width: f(2) - f(0), height: f(3) - f(1)), f(4), f(5))) }
            else { pb.ops.append(.arc(rect(a[0].o), f(1), f(2))) }
            return .void
        case "addPath":
            if let other = a[0].o?.native as? PathBox { pb.ops += other.ops }
            return .void
        case "setFillType":
            pb.evenOdd = enumName(a[0]).contains("EVEN_ODD")
            return .void
        case "isEmpty": return B(pb.ops.isEmpty)
        case "offset":
            let dx = f(0), dy = f(1)
            pb.ops = pb.ops.map { op in
                func m(_ p: CGPoint) -> CGPoint { return CGPoint(x: p.x + dx, y: p.y + dy) }
                switch op {
                case .move(let p): return .move(m(p))
                case .line(let p): return .line(m(p))
                case .quad(let c, let p): return .quad(m(c), m(p))
                case .cubic(let c1, let c2, let p): return .cubic(m(c1), m(c2), m(p))
                case .close: return .close
                case .oval(let r): return .oval(r.offsetBy(dx: dx, dy: dy))
                case .rect(let r): return .rect(r.offsetBy(dx: dx, dy: dy))
                case .roundRect(let r, let x, let y): return .roundRect(r.offsetBy(dx: dx, dy: dy), x, y)
                case .arc(let r, let s, let w): return .arc(r.offsetBy(dx: dx, dy: dy), s, w)
                }
            }
            return .void
        case "computeBounds", "setLastPoint", "incReserve", "transform", "toggleInverseFillType":
            return .void
        default:
            return nil
        }
    }

    // MARK: - Rect / RectF / Point

    static func rectMethod(_ vm: VM, _ t: JObject, _ ref: DexMethodRef, _ a: [Value]) -> Ret? {
        let isF = t.cls.name == "Landroid/graphics/RectF;"
        let r = rect(t)
        func num(_ v: CGFloat) -> Ret { return isF ? .val(.float(Float(v))) : I(Int32(v.rounded(.down))) }
        func arg(_ i: Int) -> CGFloat { return ref.params[i] == "F" ? CGFloat(a[i].f) : CGFloat(a[i].i) }
        switch ref.name {
        case "width": return num(r.width)
        case "height": return num(r.height)
        case "centerX": return isF ? .val(.float(Float(r.midX))) : I(Int32((r.minX + r.maxX) / 2))
        case "centerY": return isF ? .val(.float(Float(r.midY))) : I(Int32((r.minY + r.maxY) / 2))
        case "exactCenterX": return .val(.float(Float(r.midX)))
        case "exactCenterY": return .val(.float(Float(r.midY)))
        case "isEmpty": return B(r.width <= 0 || r.height <= 0)
        case "set":
            if ref.params.count == 4 { setRect(t, arg(0), arg(1), arg(2), arg(3)) }
            else { let o = rect(a[0].o); setRect(t, o.minX, o.minY, o.maxX, o.maxY) }
            return .void
        case "setEmpty": setRect(t, 0, 0, 0, 0); return .void
        case "offset": setRect(t, r.minX + arg(0), r.minY + arg(1), r.maxX + arg(0), r.maxY + arg(1)); return .void
        case "offsetTo": setRect(t, arg(0), arg(1), arg(0) + r.width, arg(1) + r.height); return .void
        case "inset":
            if ref.params.count == 2 { setRect(t, r.minX + arg(0), r.minY + arg(1), r.maxX - arg(0), r.maxY - arg(1)) }
            return .void
        case "contains":
            if ref.params.count == 2 {
                let x = arg(0), y = arg(1)
                return B(r.width > 0 && r.height > 0 && x >= r.minX && x < r.maxX && y >= r.minY && y < r.maxY)
            }
            if ref.params.count == 4 { return B(r.contains(CGRect(x: arg(0), y: arg(1), width: arg(2) - arg(0), height: arg(3) - arg(1)))) }
            return B(r.contains(rect(a[0].o)))
        case "intersects":
            if ref.params.count == 4 { return B(r.intersects(CGRect(x: arg(0), y: arg(1), width: arg(2) - arg(0), height: arg(3) - arg(1)))) }
            return B(r.intersects(rect(a[0].o)))
        case "intersect":
            let o = ref.params.count == 4 ? CGRect(x: arg(0), y: arg(1), width: arg(2) - arg(0), height: arg(3) - arg(1)) : rect(a[0].o)
            guard r.intersects(o) else { return B(false) }
            let i = r.intersection(o)
            setRect(t, i.minX, i.minY, i.maxX, i.maxY)
            return B(true)
        case "union":
            let o = ref.params.count == 4 ? CGRect(x: arg(0), y: arg(1), width: arg(2) - arg(0), height: arg(3) - arg(1)) : rect(a[0].o)
            let u = r.union(o)
            setRect(t, u.minX, u.minY, u.maxX, u.maxY)
            return .void
        case "sort": let s = r.standardized; setRect(t, s.minX, s.minY, s.maxX, s.maxY); return .void
        case "round", "roundOut":
            if let o = a.first?.o { setRect(o, r.minX.rounded(), r.minY.rounded(), r.maxX.rounded(), r.maxY.rounded()) }
            return .void
        case "equals":
            guard let o = a.first?.o, o.cls.name == t.cls.name else { return B(false) }
            return B(rect(o) == r)
        case "toString", "toShortString":
            return S(vm, "\(isF ? "RectF" : "Rect")(\(r.minX), \(r.minY) - \(r.maxX), \(r.maxY))")
        case "hashCode": return I(Int32(truncatingIfNeeded: Int(r.minX) &* 31 &+ Int(r.minY) &* 17 &+ Int(r.maxX) &* 7 &+ Int(r.maxY)))
        default: return nil
        }
    }

    static func pointMethod(_ vm: VM, _ t: JObject, _ ref: DexMethodRef, _ a: [Value]) -> Ret? {
        switch ref.name {
        case "set": t.fields["x"] = a[0]; t.fields["y"] = a[1]; return .void
        case "offset":
            let isF = t.cls.name.hasSuffix("PointF;")
            let x = t.fields["x"] ?? .int(0), y = t.fields["y"] ?? .int(0)
            if isF { t.fields["x"] = .float(x.f + a[0].f); t.fields["y"] = .float(y.f + a[1].f) }
            else { t.fields["x"] = .int(x.i &+ a[0].i); t.fields["y"] = .int(y.i &+ a[1].i) }
            return .void
        case "equals":
            guard ref.params.count == 1, let o = a[0].o else { return B(false) }
            return B(vm.sameValue(o.fields["x"] ?? .int(0), t.fields["x"] ?? .int(0)) && vm.sameValue(o.fields["y"] ?? .int(0), t.fields["y"] ?? .int(0)))
        case "length":
            let x = t.fields["x"]?.f ?? 0, y = t.fields["y"]?.f ?? 0
            return .val(.float((x * x + y * y).squareRoot()))
        default: return nil
        }
    }

    // MARK: - Bitmap, Drawable, MotionEvent

    static func bitmapMethod(_ vm: VM, _ t: JObject, _ b: BitmapBox, _ ref: DexMethodRef, _ a: [Value]) -> Ret? {
        switch ref.name {
        case "getWidth", "getScaledWidth": return I(b.width)
        case "getHeight", "getScaledHeight": return I(b.height)
        case "getByteCount", "getAllocationByteCount": return I(b.width &* b.height &* 4)
        case "isRecycled", "isPremultiplied": return B(ref.name == "isPremultiplied")
        case "isMutable": return B(b.content.image == nil)
        case "hasAlpha": return B(true)
        case "recycle", "prepareToDraw", "setDensity", "setHasAlpha", "setPremultiplied": return .void
        case "eraseColor":
            b.content.ops = [.fill(UInt32(bitPattern: a[0].i))]
            return .void
        case "getPixel": return I(0)
        case "copy":
            return O(vm.newObject("Landroid/graphics/Bitmap;", native: BitmapBox(content: b.content, width: b.width, height: b.height)))
        case "getConfig": return O(nil)
        case "getDensity": return I(320)
        default: return nil
        }
    }

    static func drawableMethod(_ vm: VM, _ t: JObject, _ d: DrawableBox, _ ref: DexMethodRef, _ a: [Value]) -> Ret? {
        switch ref.name {
        case "setBounds":
            if ref.params.count == 4 { d.bounds = CGRect(x: CGFloat(a[0].i), y: CGFloat(a[1].i), width: CGFloat(a[2].i - a[0].i), height: CGFloat(a[3].i - a[1].i)) }
            else { d.bounds = rect(a[0].o) }
            return .void
        case "getBounds", "copyBounds": return O(newRect(vm, d.bounds, float: false))
        case "getIntrinsicWidth": return I(d.bitmap?.width ?? -1)
        case "getIntrinsicHeight": return I(d.bitmap?.height ?? -1)
        case "setAlpha": d.alpha = UInt8(truncatingIfNeeded: a[0].i); return .void
        case "draw":
            guard let c = a.first?.o?.native as? CanvasBox else { return .void }
            if let b = d.bitmap {
                c.add(.bitmap(b.content, CGSize(width: CGFloat(b.width), height: CGFloat(b.height)), nil, d.bounds, d.alpha))
            } else if let col = d.color {
                var ps = PaintState()
                ps.color = col
                c.add(.rect(d.bounds, ps))
            }
            c.target?.ops = c.ops
            return .void
        case "getBitmap": return O(d.bitmap.map { vm.newObject("Landroid/graphics/Bitmap;", native: $0) })
        case "setColor": d.color = UInt32(bitPattern: a[0].i); return .void
        case "mutate": return O(t)
        case "setColorFilter", "setTint", "setTintList", "setCallback", "invalidateSelf", "setFilterBitmap", "setLevel", "setState":
            return ref.ret == "V" ? .void : B(false)
        default: return nil
        }
    }

    static func motionEventMethod(_ vm: VM, _ e: MotionEventBox, _ ref: DexMethodRef, _ a: [Value]) -> Ret? {
        switch ref.name {
        case "getAction", "getActionMasked": return I(e.action)
        case "getActionIndex", "getPointerId", "findPointerIndex", "getMetaState", "getEdgeFlags", "getHistorySize", "getFlags":
            return I(0)
        case "getX", "getRawX": return .val(.float(e.x))
        case "getY", "getRawY": return .val(.float(e.y))
        case "getPointerCount": return I(1)
        case "getEventTime": return .val(.wide(e.eventTime))
        case "getDownTime": return .val(.wide(e.downTime))
        case "getPressure", "getSize": return .val(.float(1))
        case "getToolType": return I(1)
        case "getSource": return I(0x1002)
        case "setAction": e.action = a[0].i; return .void
        case "setLocation": e.x = a[0].f; e.y = a[1].f; return .void
        case "offsetLocation": e.x += a[0].f; e.y += a[1].f; return .void
        case "recycle": return .void
        default: return nil
        }
    }
}

extension Framework {
    /// A Drawable for a resource: a bitmap, or a solid colour.
    static func drawable(_ vm: VM, _ id: Int) -> JObject? {
        let d = DrawableBox()
        if let b = resourceBitmap(vm, id)?.native as? BitmapBox {
            d.bitmap = b
            d.bounds = CGRect(x: 0, y: 0, width: CGFloat(b.width), height: CGFloat(b.height))
            return vm.newObject("Landroid/graphics/drawable/BitmapDrawable;", native: d)
        }
        if let res = vm.apk.resources, let raw = res.value(id) {
            let v = res.resolve(raw)
            if v.isColor {
                d.color = UInt32(truncatingIfNeeded: v.data)
                return vm.newObject("Landroid/graphics/drawable/ColorDrawable;", native: d)
            }
        }
        vm.warnOnce("drawable 0x\(String(id, radix: 16)) can't be drawn (vector or XML drawable)")
        return vm.newObject("Landroid/graphics/drawable/Drawable;", native: d)
    }

    /// Context.getWindowManager / getDrawable / getDisplay.
    static func contextGraphics(_ vm: VM, _ ref: DexMethodRef, _ a: [Value]) -> Ret? {
        switch ref.name {
        case "getWindowManager": return O(vm.newObject("Landroid/view/WindowManager;", native: WindowManagerBox()))
        case "getDisplay": return O(vm.newObject("Landroid/view/Display;", native: DisplayBox()))
        case "getDrawable": return ref.params.first == "I" ? O(drawable(vm, resId(a[0]))) : nil
        default: return nil
        }
    }

    static func displayMethod(_ vm: VM, _ ref: DexMethodRef, _ a: [Value]) -> Ret? {
        let dm = vm.newObject("Landroid/util/DisplayMetrics;")
        fillDisplayMetrics(dm)
        let w = dm.fields["widthPixels"] ?? .int(750), h = dm.fields["heightPixels"] ?? .int(1334)
        switch ref.name {
        case "getMetrics", "getRealMetrics":
            if let o = a.first?.o { fillDisplayMetrics(o) }
            return .void
        case "getSize", "getRealSize":
            if let o = a.first?.o { o.fields["x"] = w; o.fields["y"] = h }
            return .void
        case "getWidth": return .val(w)
        case "getHeight": return .val(h)
        case "getRotation", "getOrientation", "getDisplayId": return I(0)
        case "getRefreshRate": return .val(.float(60))
        case "getName": return S(vm, "Built-in Screen")
        case "getBounds":
            return O(newRect(vm, CGRect(x: 0, y: 0, width: CGFloat(w.i), height: CGFloat(h.i)), float: false))
        default: return nil
        }
    }
}

extension VM {
    /// The view got its size (in points) from UIKit.
    func canvasSizeChanged(_ box: ViewBox, _ o: JObject, width: CGFloat, height: CGFloat) throws {
        let w = Int32(width * Graphics.density), h = Int32(height * Graphics.density)
        guard w > 0, h > 0, w != box.pxWidth || h != box.pxHeight else { return }
        let oldW = box.pxWidth, oldH = box.pxHeight
        box.pxWidth = w
        box.pxHeight = h
        if o.cls.isApp, findVirtual(o.cls, "onSizeChanged(IIII)V") != nil {
            try call(o, "onSizeChanged", params: ["I", "I", "I", "I"], args: [.int(w), .int(h), .int(oldW), .int(oldH)])
        }
        try drawCanvas(box)
    }

    /// view.invalidate(): redraw on the next frame (at most ~40 per second).
    func invalidate(_ box: ViewBox) {
        guard box.isCanvas else { return }
        if !dirtyCanvases.contains(where: { $0 === box }) { dirtyCanvases.append(box) }
        scheduleFrame(after: 0.025)
    }

    func scheduleFrame(after delay: Double) {
        guard !frameScheduled else { return }
        frameScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let vm = self else { return }
            vm.post("frame") { [weak vm] in
                guard let vm = vm else { return }
                vm.frameScheduled = false
                let boxes = vm.dirtyCanvases
                vm.dirtyCanvases.removeAll()
                for b in boxes { try vm.drawCanvas(b) }
            }
        }
    }

    /// Runs the view's draw(Canvas) / onDraw(Canvas) and shows the result.
    func drawCanvas(_ box: ViewBox) throws {
        guard box.isCanvas, let o = box.jobj, o.cls.isApp || box.drawable != nil, box.pxWidth > 0, box.pxHeight > 0 else { return }
        let cb = CanvasBox(width: box.pxWidth, height: box.pxHeight)
        let canvas = newObject("Landroid/graphics/Canvas;", native: cb)
        let params = ["Landroid/graphics/Canvas;"]
        if let d = box.drawable {
            // ImageView with an app Drawable: it fills the view (no intrinsic size).
            try Framework.fitDrawable(self, d, width: box.pxWidth, height: box.pxHeight)
            try call(d, "draw", params: params, args: [.obj(canvas)])
        } else if findVirtual(o.cls, "draw(Landroid/graphics/Canvas;)V") != nil {
            try call(o, "draw", params: params, args: [.obj(canvas)])
        } else {
            try call(o, "onDraw", params: params, args: [.obj(canvas)])
        }
        if box.drawable == nil, findVirtual(o.cls, "dispatchDraw(Landroid/graphics/Canvas;)V") != nil {
            try call(o, "dispatchDraw", params: params, args: [.obj(canvas)])
        }
        framesDrawn += 1
        let ops = cb.ops
        DispatchQueue.main.async { box.canvasView?.show(ops) }
    }

    /// A touch on a drawing view: OnTouchListener first, then onTouchEvent.
    func dispatchTouch(_ box: ViewBox, _ o: JObject, action: Int32, x: CGFloat, y: CGFloat) throws {
        let now = Int64(ProcessInfo.processInfo.systemUptime * 1000)
        if action == 0 { box.touchDownTime = now }
        let e = MotionEventBox(action: action, x: Float(x * Graphics.density), y: Float(y * Graphics.density),
                               downTime: box.touchDownTime, eventTime: now)
        let event = newObject("Landroid/view/MotionEvent;", native: e)
        if let l = box.touchListener {
            let r = try call(l, "onTouch", params: ["Landroid/view/View;", "Landroid/view/MotionEvent;"], ret: "Z",
                             args: [.obj(o), .obj(event)])
            if (r?.i ?? 0) != 0 { return }
        }
        if o.cls.isApp, findVirtual(o.cls, "onTouchEvent(Landroid/view/MotionEvent;)Z") != nil {
            _ = try call(o, "onTouchEvent", params: ["Landroid/view/MotionEvent;"], ret: "Z", args: [.obj(event)])
        }
    }

    /// Does the app's view class handle touches itself?
    func wantsTouches(_ o: JObject) -> Bool {
        return o.cls.isApp && findVirtual(o.cls, "onTouchEvent(Landroid/view/MotionEvent;)Z") != nil
    }
}
