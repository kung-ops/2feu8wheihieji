import UIKit

extension Framework {

    // MARK: - android.view.View and widgets

    static func viewMethod(_ vm: VM, _ t: JObject, _ box: ViewBox, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        let p = ref.params
        let n = ref.name
        switch n {
        case "setText":
            let s = try text(vm, a[0], p[0])
            onMain { box.text = s }
            return .void
        case "getText", "getEditableText":
            if box.kind == .field {
                return O(vm.newObject("Landroid/text/SpannableStringBuilder;", native: EditableBox(box)))
            }
            let s: String = onMain { box.text }
            return S(vm, s)
        case "length":
            return I(Int32(onMain { box.text }.utf16.count))
        case "getSelectionStart", "getSelectionEnd":
            let count = onMain { box.text }.utf16.count
            let v = n == "getSelectionStart" ? box.selStart : box.selEnd
            return I(Int32(v < 0 || v > count ? count : v))
        case "setSelection":
            box.selStart = Int(a[0].i)
            box.selEnd = p.count > 1 ? Int(a[1].i) : Int(a[0].i)
            return .void
        case "selectAll":
            box.selStart = 0
            box.selEnd = -1
            return .void
        case "hasFocus", "isFocused":
            return B(box.kind == .field)
        case "append":
            let s = try text(vm, a[0], p[0])
            onMain { box.text += s }
            return .void
        case "setTextColor":
            if p.first == "I" {
                box.textARGB = UInt32(bitPattern: a[0].i)
                let c = AndroidLayoutInflater.color(Int(UInt32(bitPattern: a[0].i)))
                onMain { box.setTextColor(c) }
            }
            return .void
        case "setTextSize":
            // setTextSize(unit, size): COMPLEX_UNIT_PX (0) is in pixels, 2 per point here.
            var size = CGFloat(p.count == 2 ? a[1].f : a[0].f)
            if p.count == 2 && a[0].i == 0 { size /= Graphics.density }
            onMain { box.setFontSize(size) }
            return .void
        case "setHint":
            let s = try text(vm, a[0], p[0])
            onMain { (box.control as? UITextField)?.placeholder = s }
            return .void
        case "getHint":
            let s: String = onMain { (box.control as? UITextField)?.placeholder ?? "" }
            return S(vm, s)
        case "setVisibility":
            let v = a[0].i
            onMain { box.setVisibility(v) }
            return .void
        case "getVisibility":
            return I(onMain { box.visibility })
        case "isShown":
            return B(onMain { !box.view.isHidden && box.view.alpha > 0 })
        case "setEnabled":
            let e = a[0].i != 0
            onMain {
                if let c = box.control as? UIControl { c.isEnabled = e } else { box.view.alpha = e ? 1 : 0.5 }
            }
            return .void
        case "isEnabled":
            return B(onMain { (box.control as? UIControl)?.isEnabled ?? true })
        case "setAlpha":
            let v = CGFloat(a[0].f)
            onMain { box.view.alpha = v }
            return .void
        case "setBackgroundColor":
            let c = AndroidLayoutInflater.color(Int(UInt32(bitPattern: a[0].i)))
            onMain {
                if box.kind == .button { box.control.backgroundColor = c } else { box.view.backgroundColor = c }
            }
            return .void
        case "setImageResource":
            let img = vm.apk.image(resource: resId(a[0]))
            onMain {
                if let iv = box.control as? UIImageView { iv.image = img }
                else if let b = box.control as? UIButton { b.setImage(img?.withRenderingMode(.alwaysOriginal), for: .normal) }
            }
            return .void
        case "getId": return I(Int32(truncatingIfNeeded: box.id))
        case "setId": box.id = resId(a[0]); return .void
        case "setTag":
            box.tag = p.count == 2 ? a[1] : a[0]
            return .void
        case "getTag": return .val(box.tag)
        case "setOnClickListener":
            box.clickListener = a[0].o
            if a[0].o != nil { onMain { box.makeTappable() } }
            return .void
        case "setOnCheckedChangeListener":
            box.checkedListener = a[0].o
            return .void
        case "setOnSeekBarChangeListener", "addOnChangeListener":
            box.seekListener = a[0].o
            return .void
        case "isChecked": return B(onMain { box.isChecked })
        case "setChecked":
            let on = a[0].i != 0
            onMain { box.isChecked = on }
            return .void
        case "toggle":
            onMain { box.isChecked = !box.isChecked }
            return .void
        case "getProgress":
            return I(onMain { Int32((box.control as? UISlider)?.value ?? 0) })
        case "setProgress":
            let v = Float(a[0].i)
            onMain { (box.control as? UISlider)?.value = v }
            return .void
        case "setMax":
            let v = a[0].i
            box.maxProgress = v
            onMain { (box.control as? UISlider)?.maximumValue = Float(max(1, v)) }
            return .void
        case "getMax": return I(box.maxProgress)
        case "addView":
            guard let child = a[0].o?.native as? ViewBox else { return .void }
            if child.jobj == nil, let co = a[0].o { child.jobj = co }
            var index: Int? = nil
            if p.count >= 2, p[1] == "I" { index = Int(a[1].i) }
            onMain {
                if let i = index, i >= 0, i <= box.children.count, let st = box.stack {
                    child.parent = box
                    box.children.insert(child, at: i)
                    st.insertArrangedSubview(child.view, at: i)
                } else {
                    box.addChild(child)
                }
            }
            return .void
        case "removeAllViews", "removeAllViewsInLayout":
            onMain { box.removeAllChildren() }
            return .void
        case "removeView":
            guard let child = a[0].o?.native as? ViewBox else { return .void }
            onMain {
                child.view.removeFromSuperview()
                box.children.removeAll { $0 === child }
                child.parent = nil
            }
            return .void
        case "removeViewAt":
            let i = Int(a[0].i)
            onMain {
                if i >= 0 && i < box.children.count {
                    let c = box.children.remove(at: i)
                    c.view.removeFromSuperview()
                    c.parent = nil
                }
            }
            return .void
        case "getChildCount": return I(Int32(box.children.count))
        case "getChildAt":
            let i = Int(a[0].i)
            return O(i >= 0 && i < box.children.count ? box.children[i].jobj : nil)
        case "getParent": return O(box.parent?.jobj)
        case "setOrientation":
            let horizontal = a[0].i == 0
            onMain {
                box.stack?.axis = horizontal ? .horizontal : .vertical
                box.stack?.alignment = horizontal ? .center : .fill
            }
            return .void
        case "setPadding", "setPaddingRelative":
            let l = CGFloat(a[0].i) / 2, tp = CGFloat(a[1].i) / 2, r = CGFloat(a[2].i) / 2, b = CGFloat(a[3].i) / 2
            onMain {
                if let st = box.stack {
                    st.isLayoutMarginsRelativeArrangement = true
                    st.layoutMargins = UIEdgeInsets(top: tp, left: l, bottom: b, right: r)
                }
            }
            return .void
        case "setGravity":
            let g = a[0].i
            onMain {
                if g & 0x11 == 0x11 || g & 0x07 == 0x01 { box.setAlignment(.center) }
                else if g & 0x07 == 0x05 { box.setAlignment(.right) }
            }
            return .void
        case "findViewById", "requireViewById":
            return O(box.find(id: resId(a[0]))?.jobj)
        case "getContext":
            return O(vm.currentActivity?.activity)
        case "getResources":
            return O(vm.newObject("Landroid/content/res/Resources;", native: ResourcesBox()))
        case "getRootView":
            return O(vm.currentActivity?.rootBox?.jobj ?? t)
        case "post":
            if let r = a[0].o { schedule(vm, r, delayMs: 0) }
            return B(true)
        case "postDelayed":
            if let r = a[0].o { schedule(vm, r, delayMs: a[1].j) }
            return B(true)
        case "removeCallbacks":
            cancel(vm, a[0].o)
            return B(true)
        case "performClick", "callOnClick":
            let h = box.handler
            DispatchQueue.main.async { h?(box, "click", 0) }
            return B(true)
        case "getWidth", "getMeasuredWidth", "getRight":
            if box.pxWidth > 0 { return I(box.pxWidth) }
            return I(onMain { Int32(box.view.bounds.width * 2) })
        case "getHeight", "getMeasuredHeight", "getBottom":
            if box.pxHeight > 0 { return I(box.pxHeight) }
            return I(onMain { Int32(box.view.bounds.height * 2) })
        case "getLeft", "getTop", "getScrollX", "getScrollY", "getPaddingLeft", "getPaddingTop", "getPaddingRight",
             "getPaddingBottom", "getPaddingStart", "getPaddingEnd":
            return I(0)
        case "invalidate", "postInvalidate", "postInvalidateOnAnimation", "invalidateDrawable":
            vm.invalidate(box)
            return .void
        case "postInvalidateDelayed":
            let ms = Int(max(0, min(a[0].j, 60_000)))
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) { [weak vm] in
                vm?.post("invalidate") { [weak vm] in vm?.invalidate(box) }
            }
            return .void
        case "setOnTouchListener":
            box.touchListener = a[0].o
            if a[0].o != nil {
                onMain {
                    box.canvasView?.acceptsTouches = true
                    box.view.isUserInteractionEnabled = true
                }
            }
            return .void
        case "getDrawingRect", "getHitRect", "getLocalVisibleRect", "getGlobalVisibleRect":
            let w = box.pxWidth > 0 ? box.pxWidth : onMain { Int32(box.view.bounds.width * 2) }
            let h = box.pxHeight > 0 ? box.pxHeight : onMain { Int32(box.view.bounds.height * 2) }
            if let r = a.first?.o { setRect(r, 0, 0, CGFloat(w), CGFloat(h)) }
            return ref.ret == "Z" ? B(true) : .void
        case "onDraw", "draw", "dispatchDraw", "onMeasure", "onLayout", "onSizeChanged", "setWillNotDraw",
             "setLayerType", "measure", "layout", "setMeasuredDimension", "onFinishInflate", "setDrawingCacheEnabled",
             "setKeepScreenOn", "setSystemUiVisibility", "buildDrawingCache", "destroyDrawingCache":
            return .void
        case "setSelected", "setActivated", "setPressed", "setRotation", "setScaleX", "setScaleY",
             "setTranslationX", "setTranslationY", "setX", "setY", "setTextIsSelectable", "setHorizontallyScrolling",
             "setCompoundDrawablesWithIntrinsicBounds", "setLayoutDirection", "setImageTintList", "setColorFilter",
             "setBackgroundTintList", "setIndeterminate", "setKeyListener", "setFilters", "setCursorVisible",
             "setShowSoftInputOnFocus", "setSoundEffectsEnabled", "setImportantForAccessibility", "setTooltipText",
             "setStateListAnimator", "setNextFocusUpId", "setNextFocusDownId", "setNextFocusLeftId", "setNextFocusRightId",
             "setOnFocusChangeListener", "setOnHoverListener", "setLongClickable", "setHapticFeedbackEnabled",
             "setTextDirection", "setLayoutDirectionMode", "setAccessibilityDelegate", "setHorizontalScrollBarEnabled",
             "setVerticalScrollBarEnabled", "setOverScrollMode", "setFocusableInTouchMode", "setTextSelectHandle":
            return .void
        case "animate":
            // view.animate()... starts by itself on the next frame, like Android.
            let (o, anim) = newAnimator(vm, "Landroid/view/ViewPropertyAnimator;")
            anim.isViewAnimator = true
            anim.target = t
            runAnimation(vm, o, anim)
            return O(o)
        case "startAnimation":
            if let o = a.first?.o, let anim = o.native as? AnimatorBox { runAnimation(vm, o, anim) }
            return .void
        case "clearAnimation":
            return .void
        case "isLaidOut", "isAttachedToWindow": return B(true)
        case "isInLayout", "isInEditMode", "isLayoutRequested", "isDirty": return B(false)
        case "getTextSize":
            let pt: CGFloat = onMain {
                if let l = box.control as? UILabel { return l.font.pointSize }
                if let b = box.control as? UIButton { return b.titleLabel?.font.pointSize ?? 15 }
                if let f = box.control as? UITextField { return f.font?.pointSize ?? 15 }
                return 15
            }
            return .val(.float(Float(pt * Graphics.density)))
        case "getHighlightColor": return I(Int32(bitPattern: 0x6633b5e5))
        case "getCurrentItem": return I(0)
        default:
            if viewNoOps.contains(n) { return ref.ret == "V" ? .void : stubRet(vm, ref) }
            if let r = try textViewExtra(vm, t, box, ref, a) { return r }
            return try listViewMethod(vm, t, box, ref, a)
        }
    }

    // MARK: - android.app.Activity / Context

    static func activityMethod(_ vm: VM, _ t: JObject, _ hostOpt: ActivityHost?, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        let p = ref.params
        let n = ref.name
        guard let host = hostOpt else { return nil }
        switch n {
        case "setContentView":
            if p.first == "I" {
                if let v = vm.inflateLayout(resId(a[0]), host: host) { vm.setContent(host, v) }
            } else if let v = a[0].o {
                if v.native == nil { return .void }
                vm.setContent(host, v)
            }
            return .void
        case "findViewById", "requireViewById":
            return O(host.findView(id: resId(a[0])))
        case "setTitle":
            host.title = try text(vm, a[0], p[0])
            let screen = vm.host
            onMain { screen?.titleChanged(host) }
            return .void
        case "getTitle":
            return S(vm, host.title)
        case "getString", "getText":
            let s = resString(vm, a[0])
            if p.count > 1 { return S(vm, try vm.javaFormat(s, varargs(a[1]))) }
            return S(vm, s)
        case "getColor":
            return I(resColor(vm, a[0]))
        case "getResources":
            return O(vm.newObject("Landroid/content/res/Resources;", native: ResourcesBox()))
        case "getApplicationContext", "getApplication":
            return O(vm.application ?? t)
        case "getBaseContext", "getContext", "requireContext", "requireActivity", "getActivity", "getLifecycle":
            return O(t)
        case "getIntent":
            if host.intent == nil { host.intent = vm.newObject("Landroid/content/Intent;", native: IntentBox()) }
            return O(host.intent)
        case "setIntent":
            host.intent = a[0].o
            return .void
        case "startActivity", "startActivityForResult":
            guard let intent = a[0].o, let ib = intent.native as? IntentBox else { return .void }
            if let target = ib.target {
                vm.post("startActivity") { [weak vm] in try vm?.launchActivity(target, intent: intent) }
            } else {
                vm.warnOnce("startActivity with an implicit intent (\(ib.action ?? "no action")) is not supported")
                let h = vm.host
                let action = ib.action ?? "?"
                DispatchQueue.main.async { h?.showToast("Can't open other apps from the sandbox (\(action))") }
            }
            return .void
        case "finish", "finishAffinity", "finishAndRemoveTask", "onBackPressed":
            vm.finishActivity(host)
            return .void
        case "runOnUiThread":
            if let r = a[0].o { try vm.call(r, "run") }
            return .void
        case "getSupportActionBar", "getActionBar":
            return O(vm.newObject("Landroid/app/ActionBar;", native: ActionBarBox()))
        case "getLayoutInflater":
            return O(vm.newObject("Landroid/view/LayoutInflater;", native: InflaterBox()))
        case "getSystemService":
            return systemService(vm, ref, a)
        case "getSharedPreferences", "getPreferences":
            let name = p.first == "Ljava/lang/String;" ? ((a[0].o?.native as? String) ?? "default") : "activity"
            let key = "apk.prefs.\(vm.apk.packageName).\(name)"
            return O(vm.newObject("Landroid/content/SharedPreferences;", native: PrefsBox(key: key)))
        case "getPackageName":
            return S(vm, vm.apk.packageName)
        case "isFinishing", "isDestroyed", "isChangingConfigurations":
            return B(host.finished)
        case "checkSelfPermission", "checkCallingOrSelfPermission":
            return I(0)
        case "requestPermissions", "recreate", "invalidateOptionsMenu", "supportInvalidateOptionsMenu":
            return .void
        case "getWindow":
            if host.window == nil { host.window = vm.newObject("Landroid/view/Window;", native: WindowBox(host: host)) }
            return O(host.window)
        case "requestWindowFeature", "supportRequestWindowFeature":
            return B(true)
        case "getMainLooper":
            return O(vm.newObject("Landroid/os/Looper;"))
        case "obtainStyledAttributes":
            return O(vm.newObject("Landroid/content/res/TypedArray;", native: TypedArrayBox()))
        case "setActionBar":
            return .void
        case "setRequestedOrientation":
            let o = a[0].i
            host.requestedOrientation = o
            let screen = vm.host
            DispatchQueue.main.async { screen?.requestOrientation(o) }
            return .void
        case "getRequestedOrientation":
            return I(host.requestedOrientation)
        default:
            if let r = contextDir(vm, ref, a) ?? contextGraphics(vm, ref, a) { return r }
            return try contextDatabase(vm, ref, a)
        }
    }
}
