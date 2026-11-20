import Foundation

extension VM {
    /// Swift frees objects by reference counting, not with a garbage
    /// collector, so the cycles every Java app has (an activity and its
    /// click listeners point at each other; views, their listeners and their
    /// screen do too) would keep a closed app's objects, arrays and views in
    /// memory for good. When an app stops, this walks everything reachable
    /// from its roots and cuts those links. VM thread only, after the app has
    /// stopped running.
    func releaseAll() {
        var all: [JObject] = []
        var stack: [JObject] = []
        var seen = Set<ObjectIdentifier>()
        var views: [ViewBox] = []
        var seenViews = Set<ObjectIdentifier>()

        func push(_ o: JObject?) {
            guard let o = o, seen.insert(ObjectIdentifier(o)).inserted else { return }
            stack.append(o)
            all.append(o)
        }
        func push(_ v: Value) {
            if case .obj(let o) = v { push(o) }
        }
        func view(_ b: ViewBox?) {
            guard let b = b, seenViews.insert(ObjectIdentifier(b)).inserted else { return }
            views.append(b)
            push(b.jobj)
            push(b.clickListener); push(b.checkedListener); push(b.seekListener)
            push(b.itemClickListener); push(b.itemLongClickListener); push(b.adapter)
            push(b.tag)
            for c in b.children { view(c) }
            view(b.emptyView)
        }
        /// Generic: any JObject / Value stored in a native helper object.
        func scan(_ any: Any, depth: Int) {
            guard depth < 4 else { return }
            for child in Mirror(reflecting: any).children {
                switch child.value {
                case let o as JObject: push(o)
                case let v as Value: push(v)
                case let vs as [Value]: vs.forEach { push($0) }
                case let d as [String: Value]: d.values.forEach { push($0) }
                case let b as ViewBox: view(b)
                case let os as [JObject]: os.forEach { push($0) }
                default:
                    let m = Mirror(reflecting: child.value)
                    if m.displayStyle == .optional || m.displayStyle == .tuple || m.displayStyle == .collection {
                        scan(child.value, depth: depth + 1)
                    }
                }
            }
        }

        // Roots: static fields, screens, views, lists, interned strings.
        for c in classes.values { for v in c.statics.values { push(v) } }
        for h in activityStack {
            push(h.activity); push(h.intent)
            h.viewObjects.forEach { push($0) }
            view(h.rootBox)
        }
        orphanViews.forEach { push($0) }
        listViews.forEach { view($0) }
        internedStrings.values.forEach { push($0) }
        push(mainLooper)
        push(mainThread)

        while let o = stack.popLast() {
            for v in o.fields.values { push(v) }
            switch o.native {
            case nil, is String, is StringBuilderBox, is Boxed, is DecimalBox: break
            case let a as JArray:
                if case .refs(let items) = a.storage { items.forEach { push($0) } }
            case let l as ListBox: l.items.forEach { push($0) }
            case let m as MapBox: m.keys.forEach { push($0) }; m.values.forEach { push($0) }
            case let ad as AdapterBox: ad.list.items.forEach { push($0) }
            case let b as ViewBox: view(b)
            case let e as EditableBox: view(e.box)
            case let ab as ActivityBox:
                if let h = ab.host {
                    push(h.activity); push(h.intent)
                    h.viewObjects.forEach { push($0) }
                    view(h.rootBox)
                }
            case let n?: scan(n, depth: 0)
            }
        }

        // Cut the links. Views are UIKit objects: tidy them on the main thread.
        for o in all {
            o.fields.removeAll()
            o.native = nil
        }
        for c in classes.values { c.statics.removeAll(); c.vcache.removeAll() }
        let screens = activityStack
        activityStack.removeAll()
        orphanViews.removeAll()
        listViews.removeAll()
        internedStrings.removeAll()
        runnableGeneration.removeAll()
        DispatchQueue.main.async {
            for b in views {
                b.handler = nil
                b.clickListener = nil; b.checkedListener = nil; b.seekListener = nil
                b.itemClickListener = nil; b.itemLongClickListener = nil; b.adapter = nil
                b.emptyView = nil
                b.tag = .null
            }
            for h in screens {
                h.activity = nil
                h.intent = nil
                h.viewObjects.removeAll()
            }
        }
        log("Released \(all.count) Java objects and \(views.count) views.")
    }
}
