import UIKit

extension Framework {

    static func newAnimator(_ vm: VM, _ type: String) -> (JObject, AnimatorBox) {
        let box = AnimatorBox()
        return (vm.newObject(type, native: box), box)
    }

    static func animationStatic(_ vm: VM, _ ref: DexMethodRef, _ a: [Value]) -> Ret? {
        let n = ref.name
        switch ref.classDesc {
        case "Landroid/animation/ValueAnimator;", "Landroid/animation/ObjectAnimator;":
            guard n.hasPrefix("of") else {
                if n == "areAnimatorsEnabled" { return B(false) }
                if n == "getFrameDelay" { return .val(.wide(10)) }
                return nil
            }
            let (o, box) = newAnimator(vm, ref.classDesc)
            var values = a
            if ref.classDesc == "Landroid/animation/ObjectAnimator;", a.count >= 2 {
                box.target = a[0].o
                box.property = a[1].o?.string
                values = Array(a.dropFirst(2))
            }
            if n == "ofObject" { values = Array(values.dropFirst()) } // skip TypeEvaluator
            if let arr = values.last?.o?.native as? JArray, let last = arr.items.last {
                let et = arr.elementType
                switch et {
                case "F": box.endValue = .obj(vm.box(last, type: "F"))
                case "I": box.endValue = .obj(vm.box(last, type: "I"))
                default: box.endValue = last
                }
                if box.property == "alpha", et == "F" { box.alpha = last.f }
            }
            return O(o)
        case "Landroid/animation/AnimatorInflater;":
            if n == "loadAnimator" { return O(newAnimator(vm, "Landroid/animation/AnimatorSet;").0) }
            if n == "loadStateListAnimator" { return O(nil) }
            return nil
        case "Landroid/view/animation/AnimationUtils;":
            if n == "loadAnimation" || n == "loadLayoutAnimation" { return O(newAnimator(vm, "Landroid/view/animation/Animation;").0) }
            if n == "currentAnimationTimeMillis" { return .val(.wide(Int64(ProcessInfo.processInfo.systemUptime * 1000))) }
            return nil
        default:
            return nil
        }
    }

    static func animationConstruct(_ t: JObject, _ ref: DexMethodRef) -> Ret? {
        switch ref.classDesc {
        case "Landroid/animation/AnimatorSet;", "Landroid/animation/ValueAnimator;", "Landroid/animation/ObjectAnimator;",
             "Landroid/view/animation/AlphaAnimation;", "Landroid/view/animation/TranslateAnimation;",
             "Landroid/view/animation/ScaleAnimation;", "Landroid/view/animation/AnimationSet;",
             "Landroid/view/animation/RotateAnimation;":
            t.native = AnimatorBox()
            return .void
        default:
            return nil
        }
    }

    /// Jumps to the end of an animation and tells the app's listeners, after a short delay.
    static func runAnimation(_ vm: VM, _ t: JObject, _ box: AnimatorBox) {
        guard !box.started else { return }
        box.started = true
        let delay = Int(max(0, min(box.duration, 250)))
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay)) { [weak vm] in
            vm?.post("animation") { [weak vm] in
                guard let vm = vm else { return }
                try finishAnimation(vm, t, box)
            }
        }
    }

    static func finishAnimation(_ vm: VM, _ t: JObject, _ box: AnimatorBox) throws {
        guard !box.finished else { return }
        box.finished = true
        let anim: [String] = ["Landroid/animation/Animator;"]
        for r in box.startActions { try vm.call(r, "run") }
        for l in box.listeners { try vm.call(l, "onAnimationStart", params: anim, args: [.obj(t)]) }
        for c in box.children {
            if let cb = c.native as? AnimatorBox { cb.started = true; try finishAnimation(vm, c, cb) }
        }
        for u in box.updateListeners {
            try vm.call(u, "onAnimationUpdate", params: box.isViewAnimator ? anim : ["Landroid/animation/ValueAnimator;"], args: [.obj(t)])
        }
        if let alpha = box.alpha, let v = box.target?.native as? ViewBox {
            onMain { v.view.alpha = CGFloat(alpha) }
        }
        for l in box.listeners {
            if l.cls.isApp, vm.findVirtual(l.cls, "onAnimationEnd(Landroid/animation/Animator;Z)V") != nil {
                try vm.call(l, "onAnimationEnd", params: anim + ["Z"], args: [.obj(t), .zero])
            } else {
                try vm.call(l, "onAnimationEnd", params: anim, args: [.obj(t)])
            }
        }
        for r in box.endActions { try vm.call(r, "run") }
    }

    static func animatorMethod(_ vm: VM, _ t: JObject, _ box: AnimatorBox, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        let n = ref.name
        func this() -> Ret { return ref.ret == "V" ? .void : O(t) }
        switch n {
        case "start": runAnimation(vm, t, box); return .void
        case "end": box.started = true; try finishAnimation(vm, t, box); return .void
        case "cancel":
            for l in box.listeners { try vm.call(l, "onAnimationCancel", params: ["Landroid/animation/Animator;"], args: [.obj(t)]) }
            box.started = true
            try finishAnimation(vm, t, box)
            return .void
        case "addListener", "setListener", "setAnimationListener":
            if let l = a.first?.o { box.listeners.append(l) }
            return this()
        case "removeListener", "removeAllListeners":
            if let l = a.first?.o { box.listeners.removeAll { $0 === l } } else { box.listeners.removeAll() }
            return .void
        case "addUpdateListener", "setUpdateListener":
            if let l = a.first?.o { box.updateListeners.append(l) }
            return this()
        case "removeAllUpdateListeners", "removeUpdateListener": box.updateListeners.removeAll(); return .void
        case "playTogether", "playSequentially":
            if let arr = a.first?.o?.native as? JArray { box.children += arr.items.compactMap { $0.o } }
            else if let l = a.first?.o?.native as? ListBox { box.children += l.items.compactMap { $0.o } }
            return .void
        case "play", "with", "before", "after":
            if let c = a.first?.o { box.children.append(c) }
            return O(t)
        case "withEndAction": if let r = a.first?.o { box.endActions.append(r) }; return O(t)
        case "withStartAction": if let r = a.first?.o { box.startActions.append(r) }; return O(t)
        case "setDuration":
            box.duration = ref.params.first == "J" ? a[0].j : Int64(a[0].i)
            return this()
        case "getDuration": return .val(.wide(box.duration))
        case "getAnimatedValue": return .val(box.endValue)
        case "getAnimatedFraction", "getInterpolation": return .val(.float(1))
        case "isRunning", "isStarted", "hasStarted", "hasEnded":
            return B(n == "hasEnded" ? box.finished : (box.started && !box.finished))
        case "setTarget": box.target = a.first?.o; return .void
        case "getTarget": return O(box.target)
        case "alpha":
            box.alpha = a[0].f
            return O(t)
        case "setInterpolator", "setStartDelay", "setRepeatCount", "setRepeatMode", "setEvaluator",
             "setFloatValues", "setIntValues", "setObjectValues", "setPropertyName", "setCurrentPlayTime",
             "setCurrentFraction", "setFillAfter", "setFillEnabled", "setAutoCancel", "setupStartValues",
             "setupEndValues", "translationX", "translationY", "translationZ", "scaleX", "scaleY", "rotation",
             "x", "y", "z", "alphaBy", "translationXBy", "translationYBy", "scaleXBy", "scaleYBy", "rotationBy",
             "withLayer", "setUpdateListenerSet", "pause", "resume", "reverse", "setDurationScale":
            if ref.params.first == "[F", let arr = a.first?.o?.native as? JArray, let last = arr.items.last {
                box.endValue = .obj(vm.box(last, type: "F"))
            }
            return this()
        default:
            return nil
        }
    }
}
