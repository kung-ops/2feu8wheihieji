import UIKit

/// android.widget.ArrayAdapter's state. `list` is the very ListBox the app
/// passed in (like Android, changing that list and calling
/// notifyDataSetChanged() updates the screen).
final class AdapterBox {
    var list: ListBox
    let resource: Int
    let textViewId: Int
    var notifyOnChange = true
    init(list: ListBox, resource: Int, textViewId: Int) {
        self.list = list
        self.resource = resource
        self.textViewId = textViewId
    }
}

/// ListView / GridView with ArrayAdapter or the app's own BaseAdapter: rows
/// come from adapter.getView() and are drawn as a plain vertical list.
extension Framework {

    /// Most rows we build for one list (memory on 1 GB iPhones).
    static let maxListRows = 400

    static func adapterConstruct(_ vm: VM, _ t: JObject, _ ref: DexMethodRef, _ a: [Value]) -> Ret? {
        switch ref.classDesc {
        case "Landroid/widget/ArrayAdapter;":
            let p = ref.params
            let resource = p.count > 1 && p[1] == "I" ? resId(a[1]) : 0
            let tvId = p.count > 2 && p[2] == "I" ? resId(a[2]) : 0
            var list = ListBox()
            if let last = p.last, last.hasPrefix("[") || last == "Ljava/util/List;" {
                if let lb = a.last?.o?.native as? ListBox { list = lb }
                else if let arr = a.last?.o?.native as? JArray { list = ListBox(items: arr.items) }
            }
            t.native = AdapterBox(list: list, resource: resource, textViewId: tvId)
            return .void
        case "Landroid/widget/BaseAdapter;", "Landroid/widget/ListAdapter;", "Landroid/widget/Adapter;":
            return .void
        default:
            return nil
        }
    }

    static func adapterMethod(_ vm: VM, _ t: JObject, _ ab: AdapterBox, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        let items = ab.list
        func changed() throws {
            if ab.notifyOnChange { try vm.notifyAdapterChanged(t) }
        }
        switch ref.name {
        case "getCount": return I(Int32(items.items.count))
        case "isEmpty": return B(items.items.isEmpty)
        case "getItem":
            let i = Int(a[0].i)
            guard i >= 0 && i < items.items.count else {
                throw vm.throwable("Ljava/lang/IndexOutOfBoundsException;", "Index: \(i), Size: \(items.items.count)")
            }
            return .val(items.items[i])
        case "getItemId": return .val(.wide(Int64(a[0].i)))
        case "getPosition":
            for (k, x) in items.items.enumerated() where try vm.javaEquals(x.o, a[0].o) { return I(Int32(k)) }
            return I(-1)
        case "add":
            items.items.append(a[0])
            try changed()
            return .void
        case "addAll":
            if let lb = a.first?.o?.native as? ListBox { items.items += lb.items }
            else if let arr = a.first?.o?.native as? JArray { items.items += arr.items }
            else { items.items += a }
            try changed()
            return .void
        case "insert":
            let i = max(0, min(Int(a[1].i), items.items.count))
            items.items.insert(a[0], at: i)
            try changed()
            return .void
        case "remove":
            if let k = try items.items.firstIndex(where: { try vm.javaEquals($0.o, a[0].o) }) { items.items.remove(at: k) }
            try changed()
            return .void
        case "clear":
            items.items.removeAll()
            try changed()
            return .void
        case "sort":
            try sortValues(vm, &items.items, comparator: a.first?.o)
            try changed()
            return .void
        case "notifyDataSetChanged", "notifyDataSetInvalidated":
            try vm.notifyAdapterChanged(t)
            return .void
        case "setNotifyOnChange": ab.notifyOnChange = a[0].i != 0; return .void
        case "getContext": return O(vm.currentActivity?.activity)
        case "setDropDownViewResource", "setDropDownViewTheme", "registerDataSetObserver", "unregisterDataSetObserver":
            return .void
        case "hasStableIds", "areAllItemsEnabled": return B(ref.name == "areAllItemsEnabled")
        case "isEnabled": return B(true)
        case "getViewTypeCount": return I(1)
        case "getItemViewType": return I(0)
        case "getView", "getDropDownView":
            let pos = Int(a[0].i)
            let item: Value = pos >= 0 && pos < items.items.count ? items.items[pos] : .null
            let text = try vm.stringOf(item.o)
            return O(vm.adapterRow(ab, text: text))
        default:
            return nil
        }
    }

    /// ListView / GridView / AdapterView methods.
    static func listViewMethod(_ vm: VM, _ t: JObject, _ box: ViewBox, _ ref: DexMethodRef, _ a: [Value]) throws -> Ret? {
        switch ref.name {
        case "setAdapter":
            box.adapter = a.first?.o
            if !vm.listViews.contains(where: { $0 === box }) { vm.listViews.append(box) }
            try vm.renderList(box)
            return .void
        case "getAdapter": return O(box.adapter)
        case "setOnItemClickListener":
            box.itemClickListener = a.first?.o
            return .void
        case "setOnItemLongClickListener", "setOnItemSelectedListener", "setOnScrollListener":
            if ref.name == "setOnItemLongClickListener" { box.itemLongClickListener = a.first?.o }
            return .void
        case "getItemAtPosition":
            guard let ad = box.adapter else { return O(nil) }
            return try vm.call(ad, "getItem", params: ["I"], ret: "Ljava/lang/Object;", args: [a[0]]).map { .val($0) } ?? O(nil)
        case "getCount":
            guard let ad = box.adapter else { return I(0) }
            return I(try vm.call(ad, "getCount", ret: "I")?.i ?? 0)
        case "setEmptyView":
            box.emptyView = a.first?.o?.native as? ViewBox
            try vm.renderList(box)
            return .void
        case "smoothScrollToPosition", "setSelectionFromTop", "setChoiceMode", "setDivider", "setDividerHeight",
             "setItemChecked", "setFastScrollEnabled", "setTextFilterEnabled", "setStackFromBottom",
             "setTranscriptMode", "setNumColumns", "setHeaderDividersEnabled", "setFooterDividersEnabled":
            return .void
        case "setSelection":
            return box.isList ? .void : nil
        case "getFirstVisiblePosition": return I(0)
        case "getLastVisiblePosition": return I(Int32(max(0, box.children.count - 1)))
        case "getCheckedItemPosition": return I(-1)
        default:
            return nil
        }
    }
}

extension VM {
    /// A row for ArrayAdapter.getView: the app's row layout if it has one
    /// (with the text put in its TextView), otherwise a simple TextView.
    func adapterRow(_ ab: AdapterBox, text: String) -> JObject {
        if ab.resource >= 0x7f00_0000, let row = inflateLayout(ab.resource, host: currentActivity),
           let rb = row.native as? ViewBox {
            var target: ViewBox? = nil
            if ab.textViewId != 0 { target = rb.find(id: ab.textViewId) }
            if target == nil { target = rb.kind == .label ? rb : firstLabel(rb) }
            if let t = target { onMain { t.text = text } }
            return row
        }
        let o = newObject("Landroid/widget/TextView;")
        createView("Landroid/widget/TextView;", for: o, context: nil)
        if let b = o.native as? ViewBox {
            onMain {
                b.text = text
                b.setFontSize(17)
            }
        }
        return o
    }

    private func firstLabel(_ b: ViewBox) -> ViewBox? {
        for c in b.children {
            if c.kind == .label { return c }
            if let f = firstLabel(c) { return f }
        }
        return nil
    }

    /// adapter.notifyDataSetChanged(): rebuild every list showing it.
    func notifyAdapterChanged(_ adapter: JObject) throws {
        listViews.removeAll { $0.jobj == nil }
        for box in listViews where box.adapter === adapter { try renderList(box) }
    }

    /// Builds a list's rows with adapter.getCount() / getView().
    func renderList(_ box: ViewBox) throws {
        guard box.isList else { return }
        var rows: [ViewBox] = []
        if let adapter = box.adapter {
            let total = Int(try call(adapter, "getCount", ret: "I")?.i ?? 0)
            let count = min(max(0, total), Framework.maxListRows)
            if total > count { warnOnce("list shows the first \(count) of \(total) rows") }
            let params = ["I", "Landroid/view/View;", "Landroid/view/ViewGroup;"]
            for i in 0..<count {
                let v = try call(adapter, "getView", params: params, ret: "Landroid/view/View;",
                                 args: [.int(Int32(i)), .null, .obj(box.jobj)])
                guard let vo = v?.o, let rb = vo.native as? ViewBox else { continue }
                if rb.jobj == nil { rb.jobj = vo }
                rb.listPosition = i
                rows.append(rb)
            }
        }
        let empty = box.emptyView
        let hasRows = !rows.isEmpty
        onMain {
            box.removeAllChildren()
            for r in rows {
                box.addChild(r)
                r.decorateAsListRow()
            }
            empty?.setVisibility(hasRows ? 8 : 0)
        }
    }

    /// A tap on a list row: AdapterView.OnItemClickListener.onItemClick.
    func listItemClicked(_ tapped: ViewBox) throws -> Bool {
        // The tap may land on a view inside the row; find the row itself.
        var cur: ViewBox? = tapped
        while let c = cur, !(c.listPosition >= 0 && c.parent?.isList == true) { cur = c.parent }
        guard let row = cur, let list = row.parent, let l = list.itemClickListener else { return false }
        let pos = Int32(row.listPosition)
        try call(l, "onItemClick", params: ["Landroid/widget/AdapterView;", "Landroid/view/View;", "I", "J"],
                 args: [.obj(list.jobj), .obj(row.jobj), .int(pos), .wide(Int64(pos)), .int(0)])
        return true
    }
}
