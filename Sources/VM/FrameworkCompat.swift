import UIKit

/// Smaller Android APIs that real apps (such as LineageOS's own Calculator,
/// Clock and Easter Egg) use: TypedArray, AsyncTask, ViewConfiguration,
/// GestureDetector, PreferenceManager, Class.forName…
final class TypedArrayBox {}
final class ViewConfigurationBox {}
final class GestureDetectorBox {
    var listener: JObject?
}
/// android.widget.OverScroller / Scroller: scrolls and flings jump straight
/// to where they would stop.
final class ScrollerBox {
    var x: Int32 = 0, y: Int32 = 0
    var finalX: Int32 = 0, finalY: Int32 = 0
    var finished = true
}
/// The activity's android.view.Window.
final class WindowBox {
    weak var host: ActivityHost?
    var flags: Int32 = 0
    var attributes: JObject?
    init(host: ActivityHost?) { self.host = host }
}
/// View.getViewTreeObserver(): layout / pre-draw listeners hear once, after
/// the current work, that the screen has been laid out.
final class ViewTreeObserverBox {}
/// View.getOverlay(): views added there (reveal effects) aren't shown.
final class ViewOverlayBox {}
/// TtsSpan.*Builder (how screen readers speak a number): built but unused.
final class TtsBuilderBox {}
/// AccessibilityManager: VoiceOver isn't bridged, so Android's
/// accessibility services are reported as off.
final class AccessibilityManagerBox {}
/// android.transition.*: changes are applied at once, without animation.
final class TransitionBox {}
/// androidx ViewDragHelper (drag-to-reveal panels): dragging is not
/// tracked, so panels stay where the app puts them.
final class ViewDragHelperBox {}

extension Framework {

    /// Methods that change nothing visible here; ignoring them is correct
    /// for the sandbox (they tune drawing order, scrolling, IME, haptics…).
    static let viewNoOps: Set<String> = [
        "setChildrenDrawingOrderEnabled", "setIncludeFontPadding", "setPageMargin", "setPageTransformer",
        "addOnPageChangeListener", "removeOnPageChangeListener", "setOffscreenPageLimit", "setLineSpacing",
        "setBreakStrategy", "setHyphenationFrequency", "setAutoSizeTextTypeUniformWithConfiguration",
        "setAutoSizeTextTypeWithDefaults", "setHighlightColor", "setShadowLayer", "setFadingEdgeLength",
        "setHorizontalFadingEdgeEnabled", "setVerticalFadingEdgeEnabled", "setScrollContainer", "setClipChildren",
        "setClipToPadding", "setClipToOutline", "setOutlineProvider", "setForeground", "setAccessibilityLiveRegion",
        "setAccessibilityTraversalBefore", "setAccessibilityTraversalAfter", "setAccessibilityHeading",
        "announceForAccessibility", "sendAccessibilityEvent", "setNestedScrollingEnabled", "setFitsSystemWindows",
        "setSaveEnabled", "setSaveFromParentEnabled", "setDuplicateParentStateEnabled", "setAddStatesFromChildren",
        "setDescendantFocusability", "setMotionEventSplittingEnabled", "setLayoutTransition", "setLayoutAnimation",
        "setPivotX", "setPivotY", "setCameraDistance", "setTranslationZ", "setZ", "setRotationX", "setRotationY",
        "setTextLocale", "setTextLocales", "setEllipsize", "setMarqueeRepeatLimit", "setHorizontallyScrolling",
        "setPrivateImeOptions", "setImeOptions", "setRawInputType", "setCustomSelectionActionModeCallback",
        "setCustomInsertionActionModeCallback", "cancelLongPress", "setHapticFeedbackEnabled", "performHapticFeedback",
        "playSoundEffect", "setSoundEffectsEnabled", "setOverScrollMode", "setScrollBarStyle", "setWillNotDraw",
        "setActionBar", "setDisplayOptions", "addOnMenuVisibilityListener", "setElevation", "setStateListAnimator",
        "setFocusedByDefault", "setKeyboardNavigationCluster", "setDefaultFocusHighlightEnabled", "setTooltipText",
        "setImportantForAutofill", "setAutofillHints", "setLayoutMode", "setCompoundDrawablePadding",
        "setCompoundDrawablesRelativeWithIntrinsicBounds", "setLines", "setMinLines", "setMaxLines", "setEms",
        "setMinEms", "setMaxEms", "setMinWidth", "setMaxWidth", "setMinHeight", "setMaxHeight", "setRawTextSize"
    ]

    static func compatStatic(_ vm: VM, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        let n = ref.name
        switch ref.classDesc {
        case "Landroid/preference/PreferenceManager;", "Landroidx/preference/PreferenceManager;",
             "Landroid/support/v7/preference/PreferenceManager;":
            if n == "getDefaultSharedPreferences" {
                let key = "apk.prefs.\(vm.apk.packageName).\(vm.apk.packageName)_preferences"
                return O(vm.newObject("Landroid/content/SharedPreferences;", native: PrefsBox(key: key)))
            }
            if n == "getDefaultSharedPreferencesName" { return S(vm, "\(vm.apk.packageName)_preferences") }
            if n == "setDefaultValues" { return .void }
            return nil
        case "Landroid/view/ViewConfiguration;":
            switch n {
            case "get": return O(vm.newObject("Landroid/view/ViewConfiguration;", native: ViewConfigurationBox()))
            case "getLongPressTimeout": return I(500)
            case "getTapTimeout": return I(100)
            case "getDoubleTapTimeout": return I(300)
            case "getJumpTapTimeout": return I(500)
            case "getKeyRepeatTimeout": return I(500)
            case "getKeyRepeatDelay": return I(50)
            case "getPressedStateDuration": return I(64)
            case "getScrollBarFadeDuration", "getScrollDefaultDelay": return I(300)
            case "getZoomControlsTimeout", "getGlobalActionKeyTimeout": return .val(.wide(3000))
            case "getScrollFriction": return .val(.float(0.015))
            default: return nil
            }
        case "Landroid/view/View$MeasureSpec;":
            let mask = Int32(bitPattern: 0xc0000000)
            switch n {
            case "getSize": return I(a[0].i & ~mask)
            case "getMode": return I(a[0].i & mask)
            case "makeMeasureSpec", "makeSafeMeasureSpec": return I((a[0].i & ~mask) | (a[1].i & mask))
            case "toString": return S(vm, "MeasureSpec: \(a[0].i & ~mask)")
            default: return nil
            }
        case "Landroid/view/ViewGroup;":
            if n == "getChildMeasureSpec" {
                // getChildMeasureSpec(spec, padding, childDimension)
                let mask = Int32(bitPattern: 0xc0000000)
                let size = max(0, (a[0].i & ~mask) - a[1].i)
                if a[2].i >= 0 { return I(a[2].i | Int32(1 << 30)) }
                if a[2].i == -1 { return I(size | (a[0].i & mask)) }
                return I(size | Int32(bitPattern: 0x80000000))
            }
            return nil
        case "Landroid/view/View;":
            switch n {
            case "resolveSize", "resolveSizeAndState":
                let mask = Int32(bitPattern: 0xc0000000)
                let mode = a[1].i & mask, size = a[1].i & ~mask
                if mode == Int32(1 << 30) { return I(size) }
                if mode == mask & ~Int32(1 << 30) /* AT_MOST */ { return I(min(a[0].i, size)) }
                return I(a[0].i)
            case "getDefaultSize": return I(a[1].i & ~Int32(bitPattern: 0xc0000000) == 0 ? a[0].i : a[1].i & ~Int32(bitPattern: 0xc0000000))
            case "combineMeasuredStates": return I(a[0].i | a[1].i)
            default: return nil
            }
        case "Landroid/text/Layout;", "Landroid/text/StaticLayout;", "Landroid/text/BoringLayout;":
            switch n {
            case "getDesiredWidth":
                // getDesiredWidth(CharSequence, TextPaint) / (CharSequence, int, int, TextPaint)
                var text = try vm.stringOf(a[0].o)
                if ref.params.count == 4 {
                    let u = Array(text.utf16)
                    let b = max(0, min(Int(a[1].i), u.count)), e = max(b, min(Int(a[2].i), u.count))
                    text = String(decoding: u[b..<e], as: UTF16.self)
                }
                let st = (a.last?.o?.native as? PaintBox)?.state ?? PaintState()
                return .val(.float(Float(Graphics.textWidth(text, size: st.textSize, bold: st.bold))))
            default: return nil
            }
        case "Landroid/view/ViewAnimationUtils;":
            if n == "createCircularReveal" {
                let (o, box) = newAnimator(vm, "Landroid/animation/Animator;")
                box.target = a.first?.o
                return O(o)
            }
            return nil
        case "Landroid/transition/TransitionManager;":
            switch n {
            case "beginDelayedTransition", "go", "endTransitions": return .void
            default: return nil
            }
        case "Landroidx/customview/widget/ViewDragHelper;", "Landroid/support/v4/widget/ViewDragHelper;":
            if n == "create" { return O(vm.newObject(ref.classDesc, native: ViewDragHelperBox())) }
            return nil
        case "Landroid/transition/TransitionInflater;":
            switch n {
            case "from": return O(vm.newObject(ref.classDesc))
            default: return nil
            }
        case "Landroid/os/AsyncTask;":
            if n == "execute", let r = a.first?.o {
                vm.post("async") { [weak vm] in try vm?.call(r, "run") }
                return .void
            }
            return nil
        case "Ljava/lang/Class;":
            if n == "forName" {
                let name = try vm.stringOf(a[0].o)
                let desc = VMClass.descriptor(name)
                guard vm.hasAppClass(desc) || vm.isFrameworkName(desc) else {
                    throw vm.throwable("Ljava/lang/ClassNotFoundException;", name)
                }
                return O(vm.newObject("Ljava/lang/Class;", native: ClassRef(name: desc)))
            }
            return nil
        default:
            return nil
        }
    }

    /// Class.newInstance(): a new app object made with its no-argument constructor.
    static func newInstance(_ vm: VM, _ desc: String) throws -> JObject {
        let c = vm.classFor(desc)
        guard c.isApp else {
            throw vm.throwable("Ljava/lang/InstantiationException;", VMClass.javaName(desc))
        }
        try vm.ensureInit(c)
        let o = JObject(cls: c)
        let initRef = DexMethodRef(classDesc: desc, name: "<init>", params: [], ret: "V", sig: "<init>()V")
        _ = try vm.invoke(kind: 2, ref: initRef, args: [.obj(o)])
        return o
    }

    static func windowMethod(_ vm: VM, _ t: JObject, _ w: WindowBox, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        let host = w.host ?? vm.currentActivity
        switch ref.name {
        case "getDecorView", "peekDecorView":
            if let root = host?.rootBox?.jobj { return O(root) }
            // Before setContentView: an empty frame stands in for the decor view.
            let box: ViewBox = onMain { AndroidLayoutInflater(apk: vm.apk).make("FrameLayout", hasChildren: true) }
            return O(vm.wrap(box, in: host))
        case "findViewById", "requireViewById":
            return O(host?.findView(id: resId(a[0])))
        case "getContext": return O(host?.activity)
        case "getAttributes":
            if w.attributes == nil {
                let lp = vm.newObject("Landroid/view/WindowManager$LayoutParams;")
                _ = compatConstruct(vm, lp, DexMethodRef(classDesc: "Landroid/view/WindowManager$LayoutParams;", name: "<init>",
                                                          params: [], ret: "V", sig: "<init>()V"), [])
                lp.fields["flags"] = .int(w.flags)
                w.attributes = lp
            }
            return O(w.attributes)
        case "setAttributes":
            w.attributes = a[0].o
            if let f = a[0].o?.fields["flags"]?.i { w.flags = f }
            return .void
        case "addFlags", "clearFlags", "setFlags":
            switch ref.name {
            case "addFlags": w.flags |= a[0].i
            case "clearFlags": w.flags &= ~a[0].i
            default: w.flags = (w.flags & ~a[1].i) | (a[0].i & a[1].i)
            }
            let keepOn = w.flags & 0x80 != 0   // FLAG_KEEP_SCREEN_ON
            #if !APKSANDBOX_RUNNER
            DispatchQueue.main.async { UIApplication.shared.isIdleTimerDisabled = keepOn }
            #else
            _ = keepOn
            #endif
            return .void
        case "getWindowManager": return O(vm.newObject("Landroid/view/WindowManager;", native: WindowManagerBox()))
        case "setBackgroundDrawableResource", "setBackgroundDrawable":
            var argb: UInt32? = nil
            if ref.name == "setBackgroundDrawableResource" { argb = backgroundColor(vm, resId(a[0])) }
            else if let d = a.first?.o?.native as? DrawableBox { argb = d.color }
            if let c = argb, let h = host {
                let col = AndroidLayoutInflater.color(Int(c))
                onMain { h.setBackground(col) }
            }
            return .void
        case "requestFeature", "hasFeature": return B(true)
        case "getCurrentFocus": return O(nil)
        case "isActive", "isFloating", "hasChildren": return B(ref.name == "isActive")
        case "getStatusBarColor", "getNavigationBarColor": return I(Int32(bitPattern: 0xff000000))
        case "getInsetsController", "getCallback", "getContainer", "getEnterTransition", "getExitTransition":
            return O(nil)
        case "superDispatchTouchEvent", "superDispatchKeyEvent": return B(false)
        default:
            if ref.name.hasPrefix("set") || ref.name.hasPrefix("add") || ref.name.hasPrefix("clear")
                || ref.name.hasPrefix("remove") || ref.name.hasPrefix("take") || ref.name.hasPrefix("invalidate") {
                return ref.ret == "V" ? .void : (ref.ret == "Z" ? B(false) : nil)
            }
            return nil
        }
    }

    /// TextView methods for measuring and drawing text that custom text views
    /// (the Calculator's display) use.
    static func textViewExtra(_ vm: VM, _ t: JObject, _ box: ViewBox, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        func fontPx() -> CGFloat {
            return onMain {
                if let l = box.control as? UILabel { return l.font.pointSize * Graphics.density }
                if let b = box.control as? UIButton { return (b.titleLabel?.font.pointSize ?? 15) * Graphics.density }
                if let f = box.control as? UITextField { return (f.font?.pointSize ?? 15) * Graphics.density }
                return 15 * Graphics.density
            }
        }
        switch ref.name {
        case "getOverlay":
            return O(vm.newObject("Landroid/view/ViewGroupOverlay;", native: ViewOverlayBox()))
        case "setImageDrawable":
            if let d = a.first?.o, d.native is AppDrawableBox { showAppDrawable(vm, t, box, d) }
            return .void
        case "getViewTreeObserver":
            return O(vm.newObject("Landroid/view/ViewTreeObserver;", native: ViewTreeObserverBox()))
        case "getLayoutParams":
            if let lp = t.fields["__lp"]?.o { return O(lp) }
            let lp = vm.newObject("Landroid/view/ViewGroup$MarginLayoutParams;")
            lp.fields["width"] = .int(-1); lp.fields["height"] = .int(-2)
            for k in ["leftMargin", "topMargin", "rightMargin", "bottomMargin", "gravity"] { lp.fields[k] = .int(0) }
            lp.fields["weight"] = .float(0)
            t.fields["__lp"] = .obj(lp)
            return O(lp)
        case "setLayoutParams":
            t.fields["__lp"] = a[0]
            return .void
        case "getTranslationX", "getTranslationY", "getTranslationZ", "getElevation", "getZ", "getRotation",
             "getRotationX", "getRotationY", "getX", "getY", "getPivotX", "getPivotY":
            return .val(.float(0))
        case "getScaleX", "getScaleY": return .val(.float(1))
        case "getAlpha": return .val(.float(Float(onMain { box.view.alpha })))
        case "getSuggestedMinimumWidth", "getSuggestedMinimumHeight", "getLayerType", "getLayoutDirection",
             "getImportantForAccessibility", "getImportantForAutofill", "getScrollBarSize", "getVerticalScrollbarWidth",
             "getHorizontalScrollbarHeight", "getPaddingStart", "getPaddingEnd", "getPaddingBottom", "getLayoutMode",
             "getAccessibilityLiveRegion", "getDescendantFocusability", "getScrollIndicators", "getTextAlignment",
             "getTextDirection":
            return I(0)
        case "getLocationOnScreen", "getLocationInWindow", "getLocationInSurface":
            if let arr = a.first?.o?.native as? JArray, arr.count >= 2 { arr[0] = .int(0); arr[1] = .int(0) }
            return .void
        case "getMatrix", "getAnimationMatrix":
            return O(vm.newObject("Landroid/graphics/Matrix;"))
        case "hasOverlappingRendering": return B(true)
        case "isOpaque", "hasTransientState", "isTransitionGroup", "isAccessibilityFocused", "getFitsSystemWindows",
             "canScrollHorizontally", "canScrollVertically", "hasFocusable", "isFocusable", "isFocusableInTouchMode",
             "isSelected", "isActivated", "isPressed", "isHovered", "isHapticFeedbackEnabled", "isSoundEffectsEnabled",
             "requestChildRectangleOnScreen", "verifyDrawable", "dispatchPopulateAccessibilityEvent",
             "isScrollContainer", "isNestedScrollingEnabled", "isTemporarilyDetached", "isShowingLayoutBounds",
             "isLongClickable", "isContextClickable", "isHorizontalScrollBarEnabled", "isVerticalScrollBarEnabled":
            return B(false)
        case "isClickable": return B(true)
        case "requestFocus", "requestFocusFromTouch": return B(true)
        case "getTransitionName", "getAnimation", "getFocusedChild", "focusSearch", "findFocus", "getBackground",
             "getForeground", "getOnFocusChangeListener", "getContentDescription", "getAccessibilityDelegate",
             "getHandler", "getApplicationWindowToken", "getKeyListener", "getMovementMethod", "getTransformationMethod",
             "getOutlineProvider", "getStateListAnimator", "getTouchDelegate":
            return O(nil)
        case "getWindowToken": return O(vm.newObject("Landroid/os/IBinder;"))
        case "getDisplay": return O(vm.newObject("Landroid/view/Display;", native: DisplayBox()))
        case "getChildDrawingOrder": return I(a.last?.i ?? 0)
        case "indexOfChild":
            guard let child = a.first?.o?.native as? ViewBox else { return I(-1) }
            return I(Int32(box.children.firstIndex { $0 === child } ?? -1))
        case "setBottom", "setTop", "setLeft", "setRight", "setLeftTopRightBottom", "offsetLeftAndRight",
             "offsetTopAndBottom", "setLayerPaint", "setTransitionName", "setImportantForAccessibility",
             "setAccessibilityDelegate", "sendAccessibilityEventUnchecked", "requestApplyInsets", "requestFitSystemWindows",
             "setOnApplyWindowInsetsListener", "setOnHoverListener", "setOnGenericMotionListener", "setOnDragListener",
             "addOnAttachStateChangeListener", "removeOnAttachStateChangeListener", "addOnLayoutChangeListener",
             "removeOnLayoutChangeListener", "startViewTransition", "endViewTransition", "removeDetachedView",
             "requestDisallowInterceptTouchEvent", "stopNestedScroll", "saveHierarchyState", "restoreHierarchyState",
             "drawableStateChanged", "addFocusables", "addTouchables", "setOnFocusChangeListener", "setFocusable",
             "setFocusableInTouchMode", "clearFocus", "setLongClickable", "setOnKeyListener", "setOnCreateContextMenuListener",
             "setOnSystemUiVisibilityChangeListener", "setSystemUiVisibility", "setOnScrollChangeListener",
             "setVerticalScrollBarEnabled", "setHorizontalScrollBarEnabled", "setScrollbarFadingEnabled",
             "jumpDrawablesToCurrentState", "refreshDrawableState", "setBackground", "setBackgroundDrawable",
             "setBackgroundResource", "setBackgroundTintList", "setForegroundGravity", "setOutlineAmbientShadowColor",
             "setOutlineSpotShadowColor", "setAnimationMatrix", "setLayoutDirection", "setTextDirection",
             "setTextAlignment", "setKeyListener", "setMovementMethod", "setTransformationMethod", "setLinkTextColor",
             "setLinksClickable", "setCursorVisible", "setShowSoftInputOnFocus", "setFilters", "setTypeface",
             "setAllCaps", "setSingleLine", "setTouchDelegate", "bringToFront", "scrollTo", "scrollBy",
             "setScrollX", "setScrollY", "smoothScrollTo", "smoothScrollBy", "fullScroll", "pageScroll",
             "setSmoothScrollingEnabled", "setFillViewport", "dispatchSetPressed", "dispatchSetSelected",
             "setDrawingCacheEnabled", "buildDrawingCache", "destroyDrawingCache", "setAccessibilityPaneTitle",
             "setScreenReaderFocusable", "setLabelFor", "setNextFocusDownId", "setNextFocusUpId",
             "setNextFocusLeftId", "setNextFocusRightId", "setNextFocusForwardId", "onInitializeAccessibilityNodeInfo",
             "onInitializeAccessibilityEvent", "onPopulateAccessibilityEvent", "onRestoreInstanceState",
             "onAttachedToWindow", "onDetachedFromWindow", "onWindowFocusChanged", "onVisibilityChanged",
             "onFocusChanged", "onScrollChanged", "onOverScrolled", "onTextChanged", "onSelectionChanged",
             "onConfigurationChanged", "onRtlPropertiesChanged", "onWindowVisibilityChanged", "dispatchWindowVisibilityChanged":
            return ref.ret == "V" ? .void : (ref.ret == "Z" ? B(false) : nil)
        case "onSaveInstanceState": return O(nil)
        case "dispatchApplyWindowInsets", "onApplyWindowInsets", "computeSystemWindowInsets": return O(a.first?.o)
        case "onTouchEvent", "onInterceptTouchEvent", "dispatchTouchEvent", "onHoverEvent", "dispatchGenericMotionEvent",
             "onGenericMotionEvent", "onKeyDown", "onKeyUp", "dispatchKeyEvent", "onKeyPreIme", "onKeyLongPress",
             "onRequestFocusInDescendants", "performLongClick", "showContextMenu", "onCheckIsTextEditor":
            return B(false)
        case "getPaint":
            let pb = PaintBox()
            pb.state.textSize = fontPx()
            pb.state.color = box.textARGB
            return O(vm.newObject("Landroid/text/TextPaint;", native: pb))
        case "getCurrentTextColor": return I(Int32(bitPattern: box.textARGB))
        case "getTextColors": return O(vm.newObject("Landroid/content/res/ColorStateList;"))
        case "getLineHeight": return I(Int32((fontPx() * 1.17).rounded()))
        case "getLineCount": return I(1)
        case "getBaseline": return I(Int32((fontPx() * 0.93).rounded()))
        case "getMinimumWidth", "getMinimumHeight", "getMinWidth", "getMinHeight",
             "getCompoundPaddingTop", "getCompoundPaddingBottom", "getCompoundPaddingLeft", "getCompoundPaddingRight",
             "getCompoundPaddingStart", "getCompoundPaddingEnd", "getTotalPaddingTop", "getTotalPaddingBottom",
             "getTotalPaddingLeft", "getTotalPaddingRight", "getTotalPaddingStart", "getTotalPaddingEnd",
             "getExtendedPaddingTop", "getExtendedPaddingBottom", "getMeasuredState":
            return I(0)
        case "getMaxLines": return I(Int32.max)
        case "getLineSpacingExtra": return .val(.float(0))
        case "getLineSpacingMultiplier": return .val(.float(1))
        case "getGravity": return I(0x800033)
        case "measureChildren", "measureChild", "measureChildWithMargins", "requestLayout", "forceLayout",
             "addTextChangedListener", "removeTextChangedListener", "setMinimumWidth", "setMinimumHeight":
            return .void
        case "getMeasuredWidthAndState":
            return I(box.pxWidth > 0 ? box.pxWidth : onMain { Int32(box.view.bounds.width * Graphics.density) })
        case "getMeasuredHeightAndState":
            return I(box.pxHeight > 0 ? box.pxHeight : onMain { Int32(box.view.bounds.height * Graphics.density) })
        default:
            return nil
        }
    }

    static func compatConstruct(_ vm: VM, _ t: JObject, _ ref: DexMethodRef, _ a: [Value]) -> Ret? {
        switch ref.classDesc {
        case "Landroid/view/GestureDetector;", "Landroidx/core/view/GestureDetectorCompat;",
             "Landroid/support/v4/view/GestureDetectorCompat;":
            let g = GestureDetectorBox()
            g.listener = a.first(where: { $0.o != nil && !($0.o?.native is ActivityBox) })?.o
            t.native = g
            return .void
        case "Landroid/os/AsyncTask;":
            return .void
        case "Landroid/widget/OverScroller;", "Landroid/widget/Scroller;":
            t.native = ScrollerBox()
            return .void
        case "Landroid/view/WindowManager$LayoutParams;":
            t.fields["width"] = .int(-1); t.fields["height"] = .int(-1)
            t.fields["screenBrightness"] = .float(-1); t.fields["buttonBrightness"] = .float(-1)
            t.fields["alpha"] = .float(1); t.fields["dimAmount"] = .float(1)
            return .void
        default:
            if ref.classDesc.hasPrefix("Landroid/transition/") {
                t.native = TransitionBox()
                return .void
            }
            if ref.classDesc.hasPrefix("Landroid/text/style/TtsSpan$") && ref.classDesc.hasSuffix("Builder;") {
                t.native = TtsBuilderBox()
                return .void
            }
            return nil
        }
    }

    /// Calls on objects with no Swift state: app subclasses of AsyncTask, etc.
    static func compatInstance(_ vm: VM, _ t: JObject, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        let n = ref.name
        switch t.native {
        case is TypedArrayBox:
            // Styled attributes aren't read from the layout: every getter
            // returns the default the app passes in.
            switch n {
            case "recycle", "close": return .void
            case "hasValue", "hasValueOrEmpty": return B(false)
            case "getIndexCount", "length", "getChangingConfigurations": return I(0)
            case "getString", "getText", "getNonResourceString", "getDrawable", "getColorStateList", "getTextArray",
                 "getFont", "peekValue":
                return O(nil)
            default:
                if n.hasPrefix("get"), a.count >= 2 { return .val(a[1]) }
                return nil
            }
        case is AccessibilityManagerBox:
            switch n {
            case "isEnabled", "isTouchExplorationEnabled", "isHighTextContrastEnabled": return B(false)
            case "addAccessibilityStateChangeListener", "removeAccessibilityStateChangeListener",
                 "addTouchExplorationStateChangeListener", "removeTouchExplorationStateChangeListener":
                return B(true)
            case "getRecommendedTimeoutMillis": return I(a.first?.i ?? 0)
            case "getEnabledAccessibilityServiceList", "getInstalledAccessibilityServiceList":
                return O(vm.newObject("Ljava/util/ArrayList;", native: ListBox()))
            case "sendAccessibilityEvent", "interrupt": return .void
            default: return nil
            }
        case let sc as ScrollerBox:
            func clamp(_ v: Int32, _ lo: Int32, _ hi: Int32) -> Int32 { return lo > hi ? v : max(lo, min(hi, v)) }
            switch n {
            case "isFinished": return B(sc.finished)
            case "computeScrollOffset":
                // One step: arrive at the end.
                let moving = !sc.finished
                sc.x = sc.finalX; sc.y = sc.finalY; sc.finished = true
                return B(moving)
            case "getCurrX", "getStartX": return I(sc.x)
            case "getCurrY", "getStartY": return I(sc.y)
            case "getFinalX": return I(sc.finalX)
            case "getFinalY": return I(sc.finalY)
            case "getCurrVelocity": return .val(.float(0))
            case "startScroll":
                sc.x = a[0].i; sc.y = a[1].i
                sc.finalX = a[0].i &+ a[2].i; sc.finalY = a[1].i &+ a[3].i
                sc.finished = false
                return .void
            case "fling":
                // fling(startX, startY, velX, velY, minX, maxX, minY, maxY[, overX, overY])
                sc.x = a[0].i; sc.y = a[1].i
                sc.finalX = clamp(a[0].i &+ a[2].i / 4, a[4].i, a[5].i)
                sc.finalY = clamp(a[1].i &+ a[3].i / 4, a[6].i, a[7].i)
                sc.finished = false
                return .void
            case "springBack":
                sc.finalX = clamp(a[0].i, a[2].i, a[3].i); sc.finalY = clamp(a[1].i, a[4].i, a[5].i)
                sc.finished = sc.finalX == a[0].i && sc.finalY == a[1].i
                return B(!sc.finished)
            case "forceFinished": sc.finished = a[0].i != 0; return .void
            case "abortAnimation": sc.x = sc.finalX; sc.y = sc.finalY; sc.finished = true; return .void
            case "setFinalX": sc.finalX = a[0].i; sc.finished = false; return .void
            case "setFinalY": sc.finalY = a[0].i; sc.finished = false; return .void
            case "isOverScrolled": return B(false)
            case "setFriction", "notifyHorizontalEdgeReached", "notifyVerticalEdgeReached", "extendDuration":
                return .void
            case "timePassed", "getDuration": return I(0)
            default: return nil
            }
        case is ViewTreeObserverBox:
            switch n {
            case "addOnGlobalLayoutListener", "addOnPreDrawListener", "addOnDrawListener", "addOnWindowAttachListener",
                 "addOnGlobalFocusChangeListener", "addOnScrollChangedListener", "addOnTouchModeChangeListener",
                 "addOnWindowFocusChangeListener":
                guard let l = a.first?.o else { return .void }
                let callback: (String, String)? = [
                    "addOnGlobalLayoutListener": ("onGlobalLayout", "V"),
                    "addOnPreDrawListener": ("onPreDraw", "Z"),
                    "addOnDrawListener": ("onDraw", "V"),
                    "addOnWindowAttachListener": ("onWindowAttached", "V")
                ][n]
                if let (name, ret) = callback {
                    vm.post("layout-listener") { [weak vm] in _ = try vm?.call(l, name, ret: ret) }
                }
                return .void
            case "removeOnGlobalLayoutListener", "removeGlobalOnLayoutListener", "removeOnPreDrawListener",
                 "removeOnDrawListener", "removeOnWindowAttachListener", "removeOnGlobalFocusChangeListener",
                 "removeOnScrollChangedListener", "removeOnTouchModeChangeListener", "removeOnWindowFocusChangeListener",
                 "dispatchOnGlobalLayout":
                return .void
            case "isAlive": return B(true)
            case "dispatchOnPreDraw": return B(false)
            default: return nil
            }
        case is ViewOverlayBox:
            switch n {
            case "add", "remove", "clear": return .void
            default: return nil
            }
        case is TtsBuilderBox:
            if n == "build" { return O(vm.newObject("Landroid/text/style/TtsSpan;")) }
            if ref.ret.hasPrefix("Landroid/text/style/TtsSpan$") { return O(t) }
            return ref.ret == "V" ? .void : nil
        case let w as WindowBox:
            return try windowMethod(vm, t, w, ref, a)
        case is TransitionBox:
            if ref.ret.hasPrefix("Landroid/transition/") { return O(t) }
            switch n {
            case "getDuration", "getStartDelay": return .val(.wide(0))
            case "getTransitionCount": return I(0)
            default: return ref.ret == "V" ? .void : nil
            }
        case is ViewDragHelperBox:
            switch n {
            case "shouldInterceptTouchEvent", "continueSettling", "smoothSlideViewTo", "settleCapturedViewAt",
                 "isViewUnder", "isCapturedViewUnder", "isEdgeTouched", "checkTouchSlop":
                return B(false)
            case "getViewDragState", "getEdgeSize", "getTouchSlop", "getActivePointerId": return I(0)
            case "getMinVelocity": return .val(.float(100))
            case "getCapturedView": return O(nil)
            default: return ref.ret == "V" ? .void : nil
            }
        case is ViewConfigurationBox:
            switch n {
            case "getScaledTouchSlop", "getScaledPagingTouchSlop", "getScaledDoubleTapSlop", "getScaledWindowTouchSlop":
                return I(16)
            case "getScaledMinimumFlingVelocity": return I(100)
            case "getScaledMaximumFlingVelocity": return I(16000)
            case "getScaledOverscrollDistance", "getScaledOverflingDistance": return I(12)
            case "getScaledEdgeSlop", "getScaledScrollBarSize", "getScaledFadingEdgeLength": return I(24)
            case "hasPermanentMenuKey": return B(false)
            case "getScaledHorizontalScrollFactor", "getScaledVerticalScrollFactor": return .val(.float(64))
            default: return nil
            }
        case let g as GestureDetectorBox:
            switch n {
            case "setIsLongpressEnabled", "setOnDoubleTapListener", "setContextClickListener", "setIsDoubleTapEnabled":
                if n == "setOnDoubleTapListener", g.listener == nil { g.listener = a.first?.o }
                return .void
            case "onTouchEvent", "onGenericMotionEvent":
                // A finger lifted quickly counts as a single tap.
                if let e = a.first?.o?.native as? MotionEventBox, e.action == 1, let l = g.listener,
                   e.eventTime - e.downTime < 400 {
                    let ev = a[0]
                    _ = try? vm.call(l, "onSingleTapUp", params: ["Landroid/view/MotionEvent;"], ret: "Z", args: [ev])
                    _ = try? vm.call(l, "onSingleTapConfirmed", params: ["Landroid/view/MotionEvent;"], ret: "Z", args: [ev])
                }
                if let e = a.first?.o?.native as? MotionEventBox, e.action == 0, let l = g.listener {
                    _ = try? vm.call(l, "onDown", params: ["Landroid/view/MotionEvent;"], ret: "Z", args: [a[0]])
                }
                return B(true)
            case "isLongpressEnabled": return B(false)
            default: return nil
            }
        case nil:
            if vm.isSubclass(t.cls, of: "Landroid/os/AsyncTask;") { return try asyncTaskMethod(vm, t, ref, a) }
            return nil
        default:
            return nil
        }
    }

    /// AsyncTask runs its steps one after another on the VM thread:
    /// onPreExecute, doInBackground, onPostExecute.
    static func asyncTaskMethod(_ vm: VM, _ t: JObject, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        switch ref.name {
        case "execute", "executeOnExecutor":
            let params: Value = ref.name == "execute" ? (a.first ?? .null) : (a.count > 1 ? a[1] : .null)
            t.fields["__status"] = .int(1)
            vm.post("asynctask") { [weak vm] in
                guard let vm = vm else { return }
                _ = try vm.call(t, "onPreExecute")
                let result = try vm.call(t, "doInBackground", params: ["[Ljava/lang/Object;"], ret: "Ljava/lang/Object;",
                                         args: [params]) ?? .null
                t.fields["__result"] = result
                t.fields["__status"] = .int(2)
                if (t.fields["__cancelled"]?.i ?? 0) != 0 {
                    _ = try vm.call(t, "onCancelled", params: ["Ljava/lang/Object;"], args: [result])
                } else {
                    _ = try vm.call(t, "onPostExecute", params: ["Ljava/lang/Object;"], args: [result])
                }
            }
            return O(t)
        case "publishProgress":
            let values = a.first ?? .null
            vm.post("progress") { [weak vm] in
                _ = try vm?.call(t, "onProgressUpdate", params: ["[Ljava/lang/Object;"], args: [values])
            }
            return .void
        case "cancel":
            t.fields["__cancelled"] = .int(1)
            return B(true)
        case "isCancelled": return B((t.fields["__cancelled"]?.i ?? 0) != 0)
        case "get": return .val(t.fields["__result"] ?? .null)
        case "getStatus":
            let o = vm.newObject("Landroid/os/AsyncTask$Status;")
            let s = t.fields["__status"]?.i ?? 0
            o.fields["__name"] = .obj(vm.str(s == 0 ? "PENDING" : (s == 1 ? "RUNNING" : "FINISHED")))
            return O(o)
        case "onPreExecute", "onPostExecute", "onProgressUpdate", "onCancelled":
            return .void
        default:
            return nil
        }
    }
}
