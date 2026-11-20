import UIKit

// Things that move: android.graphics.Matrix and PathMeasure, TimeAnimator
// (a callback every frame), the support/AndroidX spring animations
// (SpringAnimation, SpringForce, FloatValueHolder) and the app's own
// Drawable subclasses shown in an ImageView. LineageOS's Easter Egg (the
// Android 9 octopus) uses all of them.

/// A 2-D affine transform in Android's Matrix terms:
///   | a c tx |      x' = a·x + c·y + tx
///   | b d ty |      y' = b·x + d·y + ty
struct Affine {
    var a: CGFloat = 1, b: CGFloat = 0, c: CGFloat = 0, d: CGFloat = 1, tx: CGFloat = 0, ty: CGFloat = 0

    static let identity = Affine()
    var isIdentity: Bool { return a == 1 && b == 0 && c == 0 && d == 1 && tx == 0 && ty == 0 }

    /// self, then other (other ∘ self).
    func then(_ o: Affine) -> Affine {
        return Affine(a: a * o.a + b * o.c, b: a * o.b + b * o.d,
                      c: c * o.a + d * o.c, d: c * o.b + d * o.d,
                      tx: tx * o.a + ty * o.c + o.tx, ty: tx * o.b + ty * o.d + o.ty)
    }
    func apply(_ x: CGFloat, _ y: CGFloat) -> (CGFloat, CGFloat) {
        return (a * x + c * y + tx, b * x + d * y + ty)
    }
    var inverted: Affine? {
        let det = a * d - b * c
        guard det != 0, det.isFinite else { return nil }
        return Affine(a: d / det, b: -b / det, c: -c / det, d: a / det,
                      tx: (c * ty - d * tx) / det, ty: (b * tx - a * ty) / det)
    }
    static func scale(_ sx: CGFloat, _ sy: CGFloat, _ px: CGFloat = 0, _ py: CGFloat = 0) -> Affine {
        return Affine(a: sx, b: 0, c: 0, d: sy, tx: px - sx * px, ty: py - sy * py)
    }
    static func translate(_ x: CGFloat, _ y: CGFloat) -> Affine { return Affine(tx: x, ty: y) }
    static func rotate(_ deg: CGFloat, _ px: CGFloat = 0, _ py: CGFloat = 0) -> Affine {
        let r = deg * .pi / 180
        let cs = cos(r), sn = sin(r)
        return Affine(a: cs, b: sn, c: -sn, d: cs, tx: px - cs * px + sn * py, ty: py - sn * px - cs * py)
    }
    static func skew(_ kx: CGFloat, _ ky: CGFloat, _ px: CGFloat = 0, _ py: CGFloat = 0) -> Affine {
        return Affine(a: 1, b: ky, c: kx, d: 1, tx: -kx * py, ty: -ky * px)
    }
}

final class MatrixBox {
    var m = Affine.identity
}

final class PathMeasureBox {
    /// Flattened contours: points and the running length at each.
    var points: [CGPoint] = []
    var lengths: [CGFloat] = []
    var total: CGFloat { return lengths.last ?? 0 }
}

/// Something that runs every frame while the app is open.
protocol FrameTicker: AnyObject {
    /// Returns false when it has finished.
    func tick(_ vm: VM, now: Double) throws -> Bool
}

final class TimeAnimatorBox: FrameTicker {
    weak var owner: JObject?
    var listener: JObject?
    var running = false
    var start: Double = 0
    var last: Double = 0

    func tick(_ vm: VM, now: Double) throws -> Bool {
        guard running, let o = owner else { return false }
        let total = Int64((now - start) * 1000), delta = Int64((now - last) * 1000)
        last = now
        if let l = listener {
            try vm.call(l, "onTimeUpdate", params: ["Landroid/animation/TimeAnimator;", "J", "J"],
                        args: [.obj(o), .wide(total), .wide(delta)])
        }
        return running
    }
}

final class FloatHolderBox {
    var value: Float = 0
}

final class SpringForceBox {
    var stiffness: Float = 1500        // STIFFNESS_MEDIUM
    var damping: Float = 0.5           // DAMPING_RATIO_MEDIUM_BOUNCY
    var finalPosition: Float = .nan    // UNSET
}

final class SpringAnimBox: FrameTicker {
    weak var owner: JObject?
    var holder: JObject?               // FloatValueHolder, or the object a FloatPropertyCompat changes
    var property: JObject?
    var spring: JObject?
    var value: Float = 0
    var velocity: Float = 0
    var startValueSet = false
    var running = false
    var minChange: Float = 1
    var minValue: Float = -.greatestFiniteMagnitude
    var maxValue: Float = .greatestFiniteMagnitude
    var updateListeners: [JObject] = []
    var endListeners: [JObject] = []
    var last: Double = 0
    var pendingFinal: Float?

    var force: SpringForceBox? { return spring?.native as? SpringForceBox }

    func read(_ vm: VM) throws -> Float {
        if let h = holder?.native as? FloatHolderBox { return h.value }
        if let p = property, let target = holder {
            if let name = p.fields["__name"]?.o?.native as? String, let vb = target.native as? ViewBox, name == "ALPHA" {
                return Float(onMain { vb.view.alpha })
            }
            if p.cls.isApp {
                return try vm.call(p, "getValue", params: ["Ljava/lang/Object;"], ret: "F", args: [.obj(target)])?.f ?? 0
            }
        }
        return value
    }

    func write(_ vm: VM, _ v: Float) throws {
        value = v
        if let h = holder?.native as? FloatHolderBox { h.value = v; return }
        if let p = property, let target = holder {
            if let name = p.fields["__name"]?.o?.native as? String, let vb = target.native as? ViewBox {
                if name == "ALPHA" { onMain { vb.view.alpha = CGFloat(v) } }
                return
            }
            if p.cls.isApp {
                try vm.call(p, "setValue", params: ["Ljava/lang/Object;", "F"], args: [.obj(target), .float(v)])
            }
        }
    }

    func startIfNeeded(_ vm: VM) throws {
        guard !running else { return }
        if !startValueSet { value = try read(vm) }
        startValueSet = false
        running = true
        last = ProcessInfo.processInfo.systemUptime
        vm.addTicker(self)
    }

    func tick(_ vm: VM, now: Double) throws -> Bool {
        guard running, let o = owner, let f = force else { return false }
        if let p = pendingFinal { f.finalPosition = p; pendingFinal = nil }
        let target = f.finalPosition.isNaN ? value : f.finalPosition
        var dt = min(now - last, 0.064)
        last = now
        // Damped spring (mass 1) in small steps: a = -k·(x - x₁) - 2ζ√k·v
        let k = Double(max(f.stiffness, 0.0001)), c = 2 * Double(f.damping) * k.squareRoot()
        var x = Double(value), v = Double(velocity)
        while dt > 0 {
            let h = min(dt, 0.002)
            let acc = -k * (x - Double(target)) - c * v
            v += acc * h
            x += v * h
            dt -= h
        }
        x = min(max(x, Double(minValue)), Double(maxValue))
        let threshold = Double(minChange) * 0.75
        let done = abs(v) < threshold * 62.5 && abs(x - Double(target)) < threshold
        if done { x = Double(target); v = 0 }
        velocity = Float(v)
        try write(vm, Float(x))
        let anim = ["Landroid/support/animation/DynamicAnimation;", "F", "F"]
        for l in updateListeners {
            try vm.call(l, "onAnimationUpdate", params: anim, args: [.obj(o), .float(value), .float(velocity)])
        }
        if done { try finish(vm, canceled: false) }
        return running
    }

    func finish(_ vm: VM, canceled: Bool) throws {
        guard running, let o = owner else { return }
        running = false
        for l in endListeners {
            try vm.call(l, "onAnimationEnd", params: ["Landroid/support/animation/DynamicAnimation;", "Z", "F", "F"],
                        args: [.obj(o), .int(canceled ? 1 : 0), .float(value), .float(velocity)])
        }
    }
}

/// android.graphics.drawable.Drawable as the base of the app's own drawables.
final class AppDrawableBox {
    var bounds: JObject?
    weak var view: ViewBox?
    var callback: JObject?
    var level: Int32 = 0
    var visible = true
    var fitted: (Int32, Int32) = (0, 0)
}

extension VM {
    /// Starts calling `t` every frame (about 30 times a second, gentle on a 1 GB iPhone).
    func addTicker(_ t: FrameTicker) {
        if !tickers.contains(where: { $0 === t }) { tickers.append(t) }
        scheduleTick()
    }

    func scheduleTick() {
        guard !tickScheduled, !tickers.isEmpty else { return }
        tickScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.033) { [weak self] in
            self?.post("tick") { [weak self] in
                guard let vm = self else { return }
                vm.tickScheduled = false
                let now = ProcessInfo.processInfo.systemUptime
                for t in vm.tickers where !(try t.tick(vm, now: now)) {
                    vm.tickers.removeAll { $0 === t }
                }
                vm.scheduleTick()
            }
        }
    }
}

extension Framework {

    static let springClasses: Set<String> = [
        "Landroid/support/animation/SpringAnimation;", "Landroidx/dynamicanimation/animation/SpringAnimation;"
    ]
    static let springForceClasses: Set<String> = [
        "Landroid/support/animation/SpringForce;", "Landroidx/dynamicanimation/animation/SpringForce;"
    ]
    static let floatHolderClasses: Set<String> = [
        "Landroid/support/animation/FloatValueHolder;", "Landroidx/dynamicanimation/animation/FloatValueHolder;"
    ]

    // MARK: - Constructors

    static func motionConstruct(_ vm: VM, _ t: JObject, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        let c = ref.classDesc
        switch c {
        case "Landroid/graphics/Matrix;":
            let m = MatrixBox()
            if let src = a.first?.o?.native as? MatrixBox { m.m = src.m }
            t.native = m
            return .void
        case "Landroid/graphics/PathMeasure;":
            let pm = PathMeasureBox()
            if let path = a.first?.o?.native as? PathBox { measure(pm, path, closed: a.count > 1 && a[1].i != 0) }
            t.native = pm
            return .void
        case "Landroid/animation/TimeAnimator;":
            let ta = TimeAnimatorBox()
            ta.owner = t
            t.native = ta
            return .void
        case "Landroid/graphics/drawable/Drawable;":
            // The app's own Drawable subclass.
            t.native = AppDrawableBox()
            return .void
        case "Landroid/graphics/DashPathEffect;", "Landroid/graphics/CornerPathEffect;", "Landroid/graphics/PathEffect;",
             "Landroid/support/animation/FloatPropertyCompat;", "Landroidx/dynamicanimation/animation/FloatPropertyCompat;":
            return .void
        default:
            break
        }
        if floatHolderClasses.contains(c) {
            let h = FloatHolderBox()
            if let f = a.first, ref.params.first == "F" { h.value = f.f }
            t.native = h
            return .void
        }
        if springForceClasses.contains(c) {
            let f = SpringForceBox()
            if ref.params.first == "F" { f.finalPosition = a[0].f }
            t.native = f
            return .void
        }
        if springClasses.contains(c) {
            // (FloatValueHolder) | (object, FloatPropertyCompat[, finalPosition])
            let s = SpringAnimBox()
            s.owner = t
            s.holder = a.first?.o
            if ref.params.count >= 2 { s.property = a[1].o }
            if ref.params.count >= 3 {
                let f = SpringForceBox()
                f.finalPosition = a[2].f
                s.spring = vm.newObject("Landroid/support/animation/SpringForce;", native: f)
            }
            if s.property?.fields["__name"]?.o?.native as? String == "ALPHA" { s.minChange = 1 / 256 }
            t.native = s
            return .void
        }
        return nil
    }

    // MARK: - Statics

    static func motionStatic(_ vm: VM, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        return nil
    }

    // MARK: - Instances

    static func motionInstance(_ vm: VM, _ t: JObject, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        switch t.native {
        case let m as MatrixBox: return try matrixMethod(vm, t, m, ref, a)
        case let pm as PathMeasureBox: return try pathMeasureMethod(vm, pm, ref, a)
        case let ta as TimeAnimatorBox: return try timeAnimatorMethod(vm, t, ta, ref, a)
        case let h as FloatHolderBox:
            switch ref.name {
            case "getValue": return .val(.float(h.value))
            case "setValue": h.value = a[0].f; return .void
            default: return nil
            }
        case let f as SpringForceBox:
            switch ref.name {
            case "setStiffness": f.stiffness = a[0].f; return O(t)
            case "getStiffness": return .val(.float(f.stiffness))
            case "setDampingRatio": f.damping = a[0].f; return O(t)
            case "getDampingRatio": return .val(.float(f.damping))
            case "setFinalPosition": f.finalPosition = a[0].f; return O(t)
            case "getFinalPosition": return .val(.float(f.finalPosition))
            default: return nil
            }
        case let s as SpringAnimBox: return try springMethod(vm, t, s, ref, a)
        case let d as AppDrawableBox: return try appDrawableMethod(vm, t, d, ref, a)
        default: return nil
        }
    }

    static func matrixMethod(_ vm: VM, _ t: JObject, _ mb: MatrixBox, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        let p = ref.params
        func f(_ i: Int) -> CGFloat { return CGFloat(a[i].f) }
        func other(_ i: Int) -> Affine { return (a[i].o?.native as? MatrixBox)?.m ?? .identity }
        func op() -> Affine? {
            let n = ref.name
            let kind = n.hasPrefix("set") ? String(n.dropFirst(3)) : n.hasPrefix("pre") ? String(n.dropFirst(3)) : String(n.dropFirst(4))
            switch kind {
            case "Scale": return p.count == 4 ? .scale(f(0), f(1), f(2), f(3)) : .scale(f(0), f(1))
            case "Translate": return .translate(f(0), f(1))
            case "Rotate": return p.count == 3 ? .rotate(f(0), f(1), f(2)) : .rotate(f(0))
            case "Skew": return p.count == 4 ? .skew(f(0), f(1), f(2), f(3)) : .skew(f(0), f(1))
            case "Concat": return p.count == 2 ? other(0).then(other(1)) : other(0)
            case "SinCos":
                let sn = f(0), cs = f(1)
                let px = p.count == 4 ? f(2) : 0, py = p.count == 4 ? f(3) : 0
                return Affine(a: cs, b: sn, c: -sn, d: cs, tx: px - cs * px + sn * py, ty: py - sn * px - cs * py)
            default: return nil
            }
        }
        let n = ref.name
        switch n {
        case "reset": mb.m = .identity; return .void
        case "set": mb.m = other(0); return .void
        case "isIdentity": return B(mb.m.isIdentity)
        case "isAffine": return B(true)
        case "invert":
            guard let inv = mb.m.inverted else { return B(false) }
            (a.first?.o?.native as? MatrixBox)?.m = inv
            return B(true)
        case "mapPoints":
            // mapPoints(pts) | mapPoints(dst, src) | mapPoints(dst, dstIndex, src, srcIndex, count)
            guard let dst = a[0].o?.native as? JArray else { throw vm.npe("mapPoints") }
            var src = dst, di = 0, si = 0, count = dst.count / 2
            if p.count == 2, let s = a[1].o?.native as? JArray { src = s; count = s.count / 2 }
            if p.count == 5, let s = a[2].o?.native as? JArray { di = Int(a[1].i); src = s; si = Int(a[3].i); count = Int(a[4].i) }
            var out: [(Int, Float)] = []
            for k in 0..<max(0, count) where si + 2 * k + 1 < src.count && di + 2 * k + 1 < dst.count {
                let (x, y) = mb.m.apply(CGFloat(src[si + 2 * k].f), CGFloat(src[si + 2 * k + 1].f))
                out.append((di + 2 * k, Float(x)))
                out.append((di + 2 * k + 1, Float(y)))
            }
            for (i, v) in out { dst[i] = .float(v) }
            return .void
        case "mapVectors":
            guard let dst = a[0].o?.native as? JArray else { throw vm.npe("mapVectors") }
            let src = p.count == 2 ? (a[1].o?.native as? JArray ?? dst) : dst
            var lin = mb.m
            lin.tx = 0; lin.ty = 0
            var out: [Float] = []
            for k in 0..<(src.count / 2) {
                let (x, y) = lin.apply(CGFloat(src[2 * k].f), CGFloat(src[2 * k + 1].f))
                out += [Float(x), Float(y)]
            }
            for (i, v) in out.enumerated() where i < dst.count { dst[i] = .float(v) }
            return .void
        case "mapRect":
            // mapRect(rect) | mapRect(dst, src): the bounds of the mapped corners.
            guard let dstO = a[0].o else { throw vm.npe("mapRect") }
            let r = rect(p.count == 2 ? a[1].o : dstO)
            let corners = [(r.minX, r.minY), (r.maxX, r.minY), (r.minX, r.maxY), (r.maxX, r.maxY)].map { mb.m.apply($0.0, $0.1) }
            let xs = corners.map { $0.0 }, ys = corners.map { $0.1 }
            setRect(dstO, xs.min() ?? 0, ys.min() ?? 0, xs.max() ?? 0, ys.max() ?? 0)
            return B(mb.m.b == 0 && mb.m.c == 0)
        case "mapRadius":
            let s = sqrt(abs(mb.m.a * mb.m.d - mb.m.b * mb.m.c))
            return .val(.float(Float(CGFloat(a[0].f) * s)))
        case "getValues":
            guard let arr = a[0].o?.native as? JArray, arr.count >= 9 else { return .void }
            let v: [CGFloat] = [mb.m.a, mb.m.c, mb.m.tx, mb.m.b, mb.m.d, mb.m.ty, 0, 0, 1]
            for (i, x) in v.enumerated() { arr[i] = .float(Float(x)) }
            return .void
        case "setValues":
            guard let arr = a[0].o?.native as? JArray, arr.count >= 6 else { return .void }
            mb.m = Affine(a: CGFloat(arr[0].f), b: CGFloat(arr[3].f), c: CGFloat(arr[1].f), d: CGFloat(arr[4].f),
                          tx: CGFloat(arr[2].f), ty: CGFloat(arr[5].f))
            return .void
        case "equals": return B((a[0].o?.native as? MatrixBox).map { $0.m.a == mb.m.a && $0.m.b == mb.m.b && $0.m.c == mb.m.c && $0.m.d == mb.m.d && $0.m.tx == mb.m.tx && $0.m.ty == mb.m.ty } ?? false)
        case "hashCode": return I(Int32(truncatingIfNeeded: Int(mb.m.a * 1000 + mb.m.tx)))
        case "toString", "toShortString":
            return S(vm, "Matrix{[\(mb.m.a), \(mb.m.c), \(mb.m.tx)][\(mb.m.b), \(mb.m.d), \(mb.m.ty)][0.0, 0.0, 1.0]}")
        case "setRectToRect":
            let s = rect(a[0].o), d = rect(a[1].o)
            guard s.width != 0, s.height != 0 else { mb.m = .identity; return B(false) }
            var sx = d.width / s.width, sy = d.height / s.height
            let fill = enumName(a[2]) == "FILL"
            if !fill { sx = min(sx, sy); sy = sx }
            var tx = d.minX - s.minX * sx, ty = d.minY - s.minY * sy
            if !fill {
                let name = enumName(a[2])
                let dx = d.width - s.width * sx, dy = d.height - s.height * sy
                if name == "CENTER" { tx += dx / 2; ty += dy / 2 } else if name == "END" { tx += dx; ty += dy }
            }
            mb.m = Affine(a: sx, b: 0, c: 0, d: sy, tx: tx, ty: ty)
            return B(true)
        default:
            guard let o = op() else { return nil }
            if n.hasPrefix("set") { mb.m = o } else if n.hasPrefix("pre") { mb.m = o.then(mb.m) } else { mb.m = mb.m.then(o) }
            return ref.ret == "V" ? .void : B(true)
        }
    }

    // MARK: - PathMeasure

    static func measure(_ pm: PathMeasureBox, _ path: PathBox, closed: Bool) {
        var pts: [CGPoint] = []
        var start = CGPoint.zero
        var cur = CGPoint.zero
        func add(_ p: CGPoint) { pts.append(p); cur = p }
        contours: for op in path.ops {
            switch op {
            case .move(let p):
                // PathMeasure starts on the first contour; nextContour() isn't followed.
                if pts.count > 1 { break contours }
                pts.removeAll()
                start = p; add(p)
            case .line(let p):
                if pts.isEmpty { add(cur) }
                add(p)
            case .quad(let c1, let p):
                if pts.isEmpty { add(cur) }
                let p0 = cur
                for k in 1...16 {
                    let u = CGFloat(k) / 16, v = 1 - u
                    add(CGPoint(x: v * v * p0.x + 2 * v * u * c1.x + u * u * p.x, y: v * v * p0.y + 2 * v * u * c1.y + u * u * p.y))
                }
            case .cubic(let c1, let c2, let p):
                if pts.isEmpty { add(cur) }
                let p0 = cur
                for k in 1...24 {
                    let u = CGFloat(k) / 24, v = 1 - u
                    let x = v * v * v * p0.x + 3 * v * v * u * c1.x + 3 * v * u * u * c2.x + u * u * u * p.x
                    let y = v * v * v * p0.y + 3 * v * v * u * c1.y + 3 * v * u * u * c2.y + u * u * u * p.y
                    add(CGPoint(x: x, y: y))
                }
            case .close:
                add(start)
            case .rect(let r):
                if pts.isEmpty {
                    for p in [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY),
                              CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.minY)] { add(p) }
                }
            case .oval(let r), .roundRect(let r, _, _), .arc(let r, _, _):
                if pts.isEmpty {
                    for k in 0...32 {
                        let ang = CGFloat(k) / 32 * 2 * .pi
                        add(CGPoint(x: r.midX + r.width / 2 * cos(ang), y: r.midY + r.height / 2 * sin(ang)))
                    }
                }
            }
        }
        if closed, let f = pts.first, let l = pts.last, f != l { pts.append(f) }
        var lens: [CGFloat] = []
        var total: CGFloat = 0
        for (i, p) in pts.enumerated() {
            if i > 0 { total += hypot(p.x - pts[i - 1].x, p.y - pts[i - 1].y) }
            lens.append(total)
        }
        pm.points = pts
        pm.lengths = lens
    }

    static func pathMeasureMethod(_ vm: VM, _ pm: PathMeasureBox, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        switch ref.name {
        case "setPath":
            if let path = a[0].o?.native as? PathBox { measure(pm, path, closed: a.count > 1 && a[1].i != 0) }
            else { pm.points = []; pm.lengths = [] }
            return .void
        case "getLength": return .val(.float(Float(pm.total)))
        case "isClosed":
            guard let f = pm.points.first, let l = pm.points.last else { return B(false) }
            return B(pm.points.count > 2 && f == l)
        case "nextContour": return B(false)
        case "getPosTan":
            guard pm.points.count >= 2 else { return B(false) }
            let dist = max(0, min(CGFloat(a[0].f), pm.total))
            var i = 1
            while i < pm.lengths.count - 1 && pm.lengths[i] < dist { i += 1 }
            let p0 = pm.points[i - 1], p1 = pm.points[i]
            let seg = pm.lengths[i] - pm.lengths[i - 1]
            let u = seg > 0 ? (dist - pm.lengths[i - 1]) / seg : 0
            let pos = CGPoint(x: p0.x + (p1.x - p0.x) * u, y: p0.y + (p1.y - p0.y) * u)
            let len = hypot(p1.x - p0.x, p1.y - p0.y)
            let tan = len > 0 ? CGPoint(x: (p1.x - p0.x) / len, y: (p1.y - p0.y) / len) : CGPoint(x: 1, y: 0)
            if a.count > 1, let pa = a[1].o?.native as? JArray, pa.count >= 2 { pa[0] = .float(Float(pos.x)); pa[1] = .float(Float(pos.y)) }
            if a.count > 2, let ta = a[2].o?.native as? JArray, ta.count >= 2 { ta[0] = .float(Float(tan.x)); ta[1] = .float(Float(tan.y)) }
            return B(true)
        case "getSegment":
            // getSegment(start, stop, dst, startWithMoveTo)
            guard let dst = a[2].o?.native as? PathBox, pm.points.count >= 2 else { return B(false) }
            let s = max(0, CGFloat(a[0].f)), e = min(pm.total, CGFloat(a[1].f))
            guard e > s else { return B(false) }
            var first = true
            for (i, p) in pm.points.enumerated() where pm.lengths[i] >= s && pm.lengths[i] <= e {
                if first && a[3].i != 0 { dst.ops.append(.move(p)) } else { dst.ops.append(.line(p)) }
                first = false
                dst.last = p
            }
            return B(!first)
        default: return nil
        }
    }

    // MARK: - TimeAnimator

    static func timeAnimatorMethod(_ vm: VM, _ t: JObject, _ ta: TimeAnimatorBox, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        switch ref.name {
        case "setTimeListener": ta.listener = a.first?.o; return .void
        case "start":
            guard !ta.running else { return .void }
            ta.running = true
            ta.start = ProcessInfo.processInfo.systemUptime
            ta.last = ta.start
            vm.addTicker(ta)
            return .void
        case "cancel", "end", "pause":
            ta.running = false
            return .void
        case "resume":
            if !ta.running { ta.running = true; ta.last = ProcessInfo.processInfo.systemUptime; vm.addTicker(ta) }
            return .void
        case "isRunning", "isStarted": return B(ta.running)
        case "isPaused": return B(false)
        case "setCurrentPlayTime":
            ta.start = ProcessInfo.processInfo.systemUptime - Double(a[0].j) / 1000
            return .void
        case "getCurrentPlayTime":
            return .val(.wide(ta.running ? Int64((ProcessInfo.processInfo.systemUptime - ta.start) * 1000) : 0))
        case "setDuration": return O(t)
        case "getDuration": return .val(.wide(-1))
        case "addListener", "removeListener", "removeAllListeners", "setInterpolator", "setStartDelay",
             "addUpdateListener", "removeAllUpdateListeners", "setRepeatCount", "setRepeatMode":
            return ref.ret == "V" ? .void : O(t)
        default: return nil
        }
    }

    // MARK: - SpringAnimation

    static func springMethod(_ vm: VM, _ t: JObject, _ s: SpringAnimBox, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        switch ref.name {
        case "setSpring": s.spring = a[0].o; return O(t)
        case "getSpring":
            if s.spring == nil { s.spring = vm.newObject("Landroid/support/animation/SpringForce;", native: SpringForceBox()) }
            return O(s.spring)
        case "addUpdateListener": if let l = a[0].o { s.updateListeners.append(l) }; return O(t)
        case "removeUpdateListener": s.updateListeners.removeAll { $0 === a[0].o }; return .void
        case "addEndListener": if let l = a[0].o { s.endListeners.append(l) }; return O(t)
        case "removeEndListener": s.endListeners.removeAll { $0 === a[0].o }; return .void
        case "setStartValue": s.value = a[0].f; s.startValueSet = true; return O(t)
        case "setStartVelocity": s.velocity = a[0].f; return O(t)
        case "setMinValue": s.minValue = a[0].f; return O(t)
        case "setMaxValue": s.maxValue = a[0].f; return O(t)
        case "setMinimumVisibleChange": s.minChange = max(a[0].f, 0.0001); return O(t)
        case "getMinimumVisibleChange": return .val(.float(s.minChange))
        case "animateToFinalPosition":
            if s.spring == nil { s.spring = vm.newObject("Landroid/support/animation/SpringForce;", native: SpringForceBox()) }
            if s.running { s.pendingFinal = a[0].f } else { s.force?.finalPosition = a[0].f }
            try s.startIfNeeded(vm)
            return .void
        case "start":
            if s.spring == nil { throw vm.throwable("Ljava/lang/UnsupportedOperationException;", "Incomplete SpringAnimation: Either final position or a spring force needs to be set.") }
            try s.startIfNeeded(vm)
            return .void
        case "cancel": try s.finish(vm, canceled: true); return .void
        case "skipToEnd":
            if let f = s.force, !f.finalPosition.isNaN { try s.write(vm, f.finalPosition) }
            s.velocity = 0
            try s.finish(vm, canceled: false)
            return .void
        case "isRunning": return B(s.running)
        case "canSkipToEnd": return B(true)
        default: return nil
        }
    }

    // MARK: - The app's Drawable subclasses

    static func drawableBounds(_ vm: VM, _ d: AppDrawableBox) -> JObject {
        if let b = d.bounds { return b }
        let r = vm.newObject("Landroid/graphics/Rect;")
        setRect(r, 0, 0, 0, 0)
        d.bounds = r
        return r
    }

    /// ImageView layout for a drawable without its own size: it fills the view.
    static func fitDrawable(_ vm: VM, _ o: JObject, width: Int32, height: Int32) throws {
        guard let d = o.native as? AppDrawableBox, d.fitted != (width, height) else { return }
        d.fitted = (width, height)
        try vm.call(o, "setBounds", params: ["I", "I", "I", "I"], args: [.zero, .zero, .int(width), .int(height)])
    }

    static func appDrawableMethod(_ vm: VM, _ t: JObject, _ d: AppDrawableBox, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        let p = ref.params
        switch ref.name {
        case "getBounds", "getDirtyBounds": return O(drawableBounds(vm, d))
        case "copyBounds":
            let b = rect(drawableBounds(vm, d))
            if let dst = a.first?.o { setRect(dst, b.minX, b.minY, b.maxX, b.maxY); return .void }
            return O(newRect(vm, b, float: false))
        case "setBounds":
            var r: CGRect
            if p.count == 4 {
                r = CGRect(x: CGFloat(a[0].i), y: CGFloat(a[1].i), width: CGFloat(a[2].i - a[0].i), height: CGFloat(a[3].i - a[1].i))
            } else {
                r = rect(a[0].o)
            }
            let bo = drawableBounds(vm, d)
            guard rect(bo) != r else { return .void }
            setRect(bo, r.minX, r.minY, r.maxX, r.maxY)
            try vm.call(t, "onBoundsChange", params: ["Landroid/graphics/Rect;"], args: [.obj(bo)])
            return .void
        case "invalidateSelf":
            if let v = d.view { vm.invalidate(v) }
            else if let cb = d.callback, cb.cls.isApp {
                try vm.call(cb, "invalidateDrawable", params: ["Landroid/graphics/drawable/Drawable;"], args: [.obj(t)])
            }
            return .void
        case "setCallback": d.callback = a.first?.o; return .void
        case "getCallback": return O(d.callback ?? d.view?.jobj)
        case "scheduleSelf", "unscheduleSelf", "onBoundsChange", "setTint", "setTintList", "setTintMode",
             "setFilterBitmap", "setDither", "setAutoMirrored", "setHotspot", "setHotspotBounds", "jumpToCurrentState",
             "setLayoutDirection", "applyTheme", "clearColorFilter", "setColorFilter", "setAlpha":
            return ref.ret == "V" ? .void : B(false)
        case "getIntrinsicWidth", "getIntrinsicHeight": return I(-1)
        case "getMinimumWidth", "getMinimumHeight", "getChangingConfigurations", "getLayoutDirection": return I(0)
        case "getAlpha": return I(255)
        case "getOpacity": return I(-3)   // PixelFormat.TRANSLUCENT
        case "setLevel":
            guard d.level != a[0].i else { return B(false) }
            d.level = a[0].i
            return .val(try vm.call(t, "onLevelChange", params: ["I"], ret: "Z", args: [a[0]]) ?? .zero)
        case "getLevel": return I(d.level)
        case "onLevelChange", "onStateChange", "isStateful", "isAutoMirrored", "isFilterBitmap", "canApplyTheme",
             "getPadding", "hasFocusStateSpecified":
            return B(false)
        case "setVisible":
            let changed = d.visible != (a[0].i != 0)
            d.visible = a[0].i != 0
            return B(changed)
        case "isVisible": return B(d.visible)
        case "setState": return B(false)
        case "getState": return O(vm.newObject("[I", native: JArray(type: "[I", items: [])))
        case "getCurrent", "mutate": return O(t)
        case "getConstantState", "getColorFilter", "getTransparentRegion", "getOutline": return O(nil)
        default: return nil
        }
    }

    /// ImageView.setImageDrawable with the app's own Drawable: the view draws it.
    /// When that view is all the screen holds, it fills the screen like a game.
    static func showAppDrawable(_ vm: VM, _ t: JObject, _ box: ViewBox, _ d: JObject) {
        guard let db = d.native as? AppDrawableBox else { return }
        db.view = box
        box.drawable = d
        let already = box.isCanvas
        let touches = box.touchListener != nil
        onMain {
            box.addOverlayCanvas()
            if touches { box.canvasView?.acceptsTouches = true }
        }
        if !already { vm.installCanvasHandlers(box, t) }
        if let host = vm.currentActivity, onlyView(host.rootBox, box) {
            onMain { host.fillScreen() }
        }
        vm.invalidate(box)
    }

    /// Is `target` the only thing inside `root` (through single-child containers)?
    static func onlyView(_ root: ViewBox?, _ target: ViewBox) -> Bool {
        var cur = root
        while let c = cur {
            if c === target { return true }
            guard c.children.count == 1 else { return false }
            cur = c.children.first
        }
        return false
    }

    /// Window.setBackgroundDrawableResource: a color, or the main color of a
    /// <shape> (solid, or the gradient's start and end colors mixed).
    static func backgroundColor(_ vm: VM, _ id: Int) -> UInt32? {
        if let res = vm.apk.resources, let raw = res.value(id) {
            let v = res.resolve(raw)
            if v.isColor { return UInt32(truncatingIfNeeded: v.data) }
        }
        guard let node = vm.apk.layout(id) else { return nil }
        func color(_ v: ResValue?) -> UInt32? {
            guard var r = v else { return nil }
            if r.type == ResValue.typeReference, let res = vm.apk.resources { r = res.resolve(r) }
            return r.isColor ? UInt32(truncatingIfNeeded: r.data) : nil
        }
        let shape = node.name == "shape" ? node : node.all("shape").first
        if let solid = shape?.children.first(where: { $0.name == "solid" }), let c = color(solid.attr("color")) { return c }
        if let g = shape?.children.first(where: { $0.name == "gradient" }),
           let c1 = color(g.attr("startColor")), let c2 = color(g.attr("endColor")) {
            var out: UInt32 = 0
            for sh in stride(from: 0, to: 32, by: 8) {
                let a = (c1 >> UInt32(sh)) & 0xff, b = (c2 >> UInt32(sh)) & 0xff
                out |= ((a + b) / 2) << UInt32(sh)
            }
            return out
        }
        return nil
    }
}
