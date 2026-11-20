import UIKit

// Linux test runner for the APK Sandbox engine.
// usage: runner <apk> [tap:<button text>]... [wait:<ms>]...

final class TextHost: RunHost {
    var stack: [ActivityHost] = []
    var errors: [String] = []
    func showError(title: String, message: String) { errors.append(title + ": " + message); print("‼️  " + title + ": " + message) }
    func showToast(_ text: String) { print("🍞 Toast: " + text) }
    func push(_ activity: ActivityHost) { stack.append(activity); print("➡️  push " + activity.className) }
    func finish(_ activity: ActivityHost) { stack.removeAll { $0 === activity }; print("⬅️  finish " + activity.className) }
    func titleChanged(_ activity: ActivityHost) { print("🏷  title: " + activity.title) }
    func showDialog(title: String?, message: String?, items: [String],
                    buttons: [(text: String, style: UIAlertAction.Style, action: () -> Void)],
                    itemTapped: ((Int) -> Void)?) {
        print("💬 Dialog: \(title ?? "") / \(message ?? "") items=\(items) buttons=\(buttons.map { $0.text })")
    }
    func finishAll() { print("⏹ finishAll") }
}

func dump(_ b: ViewBox, _ indent: String = "") -> String {
    var line = indent + "\(b.kind)"
    if b.id != -1 { line += " #" + (apk.resources?.name(b.id) ?? "0x" + String(b.id, radix: 16)) }
    let t = b.text
    if !t.isEmpty { line += " \"\(t)\"" }
    if b.view.isHidden { line += " (gone)" }
    if b.clickListener != nil { line += " [onClick:" + (b.clickListener?.cls.javaName ?? "") + "]" }
    if b.onClickAttr != nil { line += " [android:onClick=" + (b.onClickAttr ?? "") + "]" }
    if let o = b.jobj, o.cls.isApp { line += " <" + o.cls.javaName + ">" }
    if let cv = b.canvasView, !cv.ops.isEmpty {
        let texts = cv.ops.filter { if case .text = $0 { return true }; return false }.map { $0.summary }
        line += " [canvas \(b.pxWidth)x\(b.pxHeight) px, \(cv.ops.count) ops: \(Set(cv.ops.map { $0.summary.split(separator: " ").first.map(String.init) ?? "" }).sorted().joined(separator: ","))\(texts.isEmpty ? "" : "; " + texts.joined(separator: "; "))]"
    }
    var out = line + "\n"
    for c in b.children { out += dump(c, indent + "  ") }
    return out
}

/// Draw commands as SVG (for checking a game's picture without an iPhone).
func svgDocument(_ ops: [DrawOp], width: Int, height: Int) -> String {
    func col(_ c: UInt32) -> String {
        return String(format: "rgba(%d,%d,%d,%.3f)", Int((c >> 16) & 0xff), Int((c >> 8) & 0xff), Int(c & 0xff), Double(c >> 24) / 255)
    }
    func f(_ v: CGFloat) -> String { return String(format: "%.1f", Double(v)) }
    func style(_ p: PaintState) -> String {
        let c = col(p.color)
        switch p.style {
        case 1: return "fill=\"none\" stroke=\"\(c)\" stroke-width=\"\(f(max(p.strokeWidth, 1)))\" stroke-linecap=\"\(p.cap == 1 ? "round" : "butt")\""
        case 2: return "fill=\"\(c)\" stroke=\"\(c)\" stroke-width=\"\(f(max(p.strokeWidth, 1)))\""
        default: return "fill=\"\(c)\""
        }
    }
    func pathData(_ ops: [PathOp]) -> String {
        var d = ""
        for op in ops {
            switch op {
            case .move(let p): d += "M\(f(p.x)) \(f(p.y)) "
            case .line(let p): d += "L\(f(p.x)) \(f(p.y)) "
            case .quad(let c, let p): d += "Q\(f(c.x)) \(f(c.y)) \(f(p.x)) \(f(p.y)) "
            case .cubic(let c1, let c2, let p): d += "C\(f(c1.x)) \(f(c1.y)) \(f(c2.x)) \(f(c2.y)) \(f(p.x)) \(f(p.y)) "
            case .close: d += "Z "
            case .rect(let r), .roundRect(let r, _, _):
                d += "M\(f(r.minX)) \(f(r.minY)) H\(f(r.maxX)) V\(f(r.maxY)) H\(f(r.minX)) Z "
            case .oval(let r), .arc(let r, _, _):
                d += "M\(f(r.minX)) \(f(r.midY)) A\(f(r.width / 2)) \(f(r.height / 2)) 0 1 0 \(f(r.maxX)) \(f(r.midY)) A\(f(r.width / 2)) \(f(r.height / 2)) 0 1 0 \(f(r.minX)) \(f(r.midY)) Z "
            }
        }
        return d
    }
    var out = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(width)\" height=\"\(height)\" viewBox=\"0 0 \(width) \(height)\">\n"
    var open = 0
    var stack: [Int] = []
    for op in ops {
        switch op {
        case .fill(let c): out += "<rect x=\"-10000\" y=\"-10000\" width=\"20000\" height=\"20000\" fill=\"\(col(c))\"/>\n"
        case .rect(let r, let p): out += "<rect x=\"\(f(r.minX))\" y=\"\(f(r.minY))\" width=\"\(f(r.width))\" height=\"\(f(r.height))\" \(style(p))/>\n"
        case .roundRect(let r, let rx, let ry, let p):
            out += "<rect x=\"\(f(r.minX))\" y=\"\(f(r.minY))\" width=\"\(f(r.width))\" height=\"\(f(r.height))\" rx=\"\(f(rx))\" ry=\"\(f(ry))\" \(style(p))/>\n"
        case .oval(let r, let p), .arc(let r, _, _, _, let p):
            out += "<ellipse cx=\"\(f(r.midX))\" cy=\"\(f(r.midY))\" rx=\"\(f(r.width / 2))\" ry=\"\(f(r.height / 2))\" \(style(p))/>\n"
        case .line(let a, let b, var p):
            p.style = 1
            out += "<line x1=\"\(f(a.x))\" y1=\"\(f(a.y))\" x2=\"\(f(b.x))\" y2=\"\(f(b.y))\" \(style(p))/>\n"
        case .text(let s, let pt, let p):
            let esc = s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            out += "<text x=\"\(f(pt.x))\" y=\"\(f(pt.y))\" font-size=\"\(f(p.textSize))\" font-family=\"sans-serif\" fill=\"\(col(p.color))\">\(esc)</text>\n"
        case .path(let pops, let evenOdd, let p):
            out += "<path d=\"\(pathData(pops))\" fill-rule=\"\(evenOdd ? "evenodd" : "nonzero")\" \(style(p))/>\n"
        case .bitmap(_, _, _, let dst, _):
            out += "<rect x=\"\(f(dst.minX))\" y=\"\(f(dst.minY))\" width=\"\(f(dst.width))\" height=\"\(f(dst.height))\" fill=\"#888\"/>\n"
        case .save: stack.append(open)
        case .restore:
            let target = stack.popLast() ?? 0
            while open > target { out += "</g>"; open -= 1 }
            out += "\n"
        case .translate(let x, let y): out += "<g transform=\"translate(\(f(x)) \(f(y)))\">"; open += 1
        case .scale(let x, let y): out += "<g transform=\"scale(\(x) \(y))\">"; open += 1
        case .rotate(let d): out += "<g transform=\"rotate(\(f(d)))\">"; open += 1
        case .concat(let a, let b, let c, let d, let tx, let ty):
            out += "<g transform=\"matrix(\(a) \(b) \(c) \(d) \(tx) \(ty))\">"; open += 1
        case .clip: break
        }
    }
    while open > 0 { out += "</g>"; open -= 1 }
    return out + "</svg>\n"
}

func findBox(_ b: ViewBox, _ text: String) -> ViewBox? {
    if b.text == text || (b.id != -1 && ("0x" + String(b.id, radix: 16) == text || apk.resources?.name(b.id) == "id/" + text)) { return b }
    for c in b.children { if let f = findBox(c, text) { return f } }
    return nil
}

/// Gives every drawing view a phone-sized frame (360 x 640 pt), like UIKit layout would.
func layoutCanvases(_ b: ViewBox) {
    if b.isCanvas, let o = b.jobj, o.cls.isApp || b.drawable != nil {
        b.view.bounds = CGRect(x: 0, y: 0, width: 360, height: 640)
        b.sizeHandler?(b, 360, 640)
    }
    for c in b.children { layoutCanvases(c) }
}

func firstTouchable(_ b: ViewBox) -> ViewBox? {
    if b.isCanvas, b.touchHandler != nil, b.canvasView?.acceptsTouches == true { return b }
    for c in b.children { if let f = firstTouchable(c) { return f } }
    return nil
}

func pump(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
}

var args = CommandLine.arguments
// --lenient: unsupported Android APIs are logged and skipped instead of stopping
// the app (to list everything an APK still needs in one run).
let lenient = args.contains("--lenient")
args.removeAll { $0 == "--lenient" }
guard args.count > 1 else {
    print("""
    usage: runner [--lenient] <apk> [tap:id-or-text]... [touch:x,y]... [wait:ms]... [screen]
                  [expect:id=text]... [svg:out.svg]
           runner install <apk>            install into the virtual Android
           runner install-builtin [--again] install the built-in LineageOS apps
           runner run <package> [tap:...]  run an installed app (memory-mapped dex)
           runner list | uninstall <package> | clear <package>
           runner backup <package> <out.zip> | restore <package> <backup.zip>
    """)
    exit(2)
}
if let env = ProcessInfo.processInfo.environment["APKSANDBOX_FRAMEWORK_RES"] {
    FrameworkResources.packURL = URL(fileURLWithPath: env)
} else {
    // Tools/LinuxRunner/build/runner → Sources/Android/android9-res.zip
    let exe = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let pack = exe.deletingLastPathComponent().appendingPathComponent("../../../Sources/Android/android9-res.zip").standardizedFileURL
    if FileManager.default.fileExists(atPath: pack.path) { FrameworkResources.packURL = pack }
}
// The built-in apps (Sources/Android/Preinstalled), as the iOS app bundles them.
do {
    let exe = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    PackageManager.builtInFolder = exe.deletingLastPathComponent().appendingPathComponent("../../../Sources/Android/Preinstalled").standardizedFileURL
}
if args[1] == "make-framework-pack" {
    // runner make-framework-pack <framework-res.apk> <out.zip>: the trimmed Android resources.
    guard args.count > 3 else { print("usage: runner make-framework-pack <framework-res.apk> <out.zip>"); exit(2) }
    let fw = try ApkPackage(url: URL(fileURLWithPath: args[2]))
    guard let table = fw.resources else { print("✖ no resources.arsc"); exit(3) }
    var values: [String: [Any]] = [:]
    var files: [String: String] = [:]
    var fileData: [String: [UInt8]] = [:]
    func densityRank(_ d: Int) -> Int {
        // Best for a 2x iPhone: xhdpi, then xxhdpi, hdpi, xxxhdpi, mdpi, any.
        switch d { case 320: return 0; case 480: return 1; case 240: return 2; case 640: return 3; case 160: return 4; case 0: return 5; default: return 6 }
    }
    for (id, list) in table.values {
        let key = String(id, radix: 16)
        let typeName = table.name(id)?.split(separator: "/").first.map(String.init) ?? ""
        let paths = list.compactMap { e -> (String, Int)? in
            guard e.isDefault, let s = e.value.string, s.hasPrefix("res/") else { return nil }
            return (s, e.density)
        }
        if !paths.isEmpty {
            let pngs = paths.filter { $0.0.hasSuffix(".png") || $0.0.hasSuffix(".webp") || $0.0.hasSuffix(".jpg") }
            var chosen: String? = nil
            if !pngs.isEmpty, typeName == "drawable" || typeName == "mipmap" {
                chosen = pngs.min { densityRank($0.1) < densityRank($1.1) }?.0
            } else if typeName == "layout" {
                chosen = paths.first { $0.1 == 0 }?.0 ?? paths.first?.0
            }
            if let c = chosen, let bytes = fw.zip.read(c) {
                files[key] = c
                fileData[c] = bytes
            }
            continue
        }
        guard let v = table.ownValue(id) else { continue }
        if v.type == ResValue.typeString, let s = v.string { values[key] = [v.type, v.data, s] }
        else { values[key] = [v.type, v.data] }
    }
    var attrNames: [String: String] = [:]
    for (id, n) in table.names where n.hasPrefix("attr/") { attrNames[String(id, radix: 16)] = String(n.dropFirst(5)) }
    var styles: [String: [Any]] = [:]
    for (id, b) in table.bags {
        let items: [[Any]] = b.items.map { it in
            if it.value.type == ResValue.typeString, let s = it.value.string { return [it.attr, it.value.type, it.value.data, s] }
            return [it.attr, it.value.type, it.value.data]
        }
        styles[String(id, radix: 16)] = [b.parent, items]
    }
    let z = ZipWriter()
    z.add("values.json", try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]))
    z.add("attrs.json", try JSONSerialization.data(withJSONObject: attrNames, options: [.sortedKeys]))
    z.add("styles.json", try JSONSerialization.data(withJSONObject: styles, options: [.sortedKeys]))
    z.add("files.json", try JSONSerialization.data(withJSONObject: files, options: [.sortedKeys]))
    z.add("NOTICE.txt", Data("""
    Android 9 framework resources from LineageOS 16.0 (framework-res.apk),
    trimmed by APK Sandbox. Copyright (C) The Android Open Source Project and
    The LineageOS Project. Licensed under the Apache License, Version 2.0:
    http://www.apache.org/licenses/LICENSE-2.0
    """.utf8))
    for (path, bytes) in fileData.sorted(by: { $0.key < $1.key }) { z.add(path, Data(bytes)) }
    try z.finish().write(to: URL(fileURLWithPath: args[3]))
    let total = fileData.values.reduce(0) { $0 + $1.count }
    let layouts = files.values.filter { $0.hasPrefix("res/layout") }.count
    print("  layouts: \(layouts), pictures: \(files.count - layouts)")
    print("  attributes: \(attrNames.count), styles: \(styles.count)")
    print("✓ \(values.count) values, \(files.count) files (\(total / 1024) KB) → \(args[3])")
    exit(0)
}
let pm = PackageManager.shared
switch args[1] {
case "install":
    guard args.count > 2 else { exit(2) }
    let info = try pm.install(from: URL(fileURLWithPath: args[2])) { step, f in print(String(format: "  [%3.0f%%] ", f * 100) + step) }
    pm.reload()
    print("✓ installed \(info.packageName) \(info.versionName) (\(info.versionCode)) icon=\(info.hasIcon) dex=\(info.dexCount)")
    let oat = (try? FileManager.default.contentsOfDirectory(atPath: pm.oatDir(info.packageName).path)) ?? []
    print("  oat: \(oat.sorted())")
    exit(0)
case "backup":
    guard args.count > 3, let app = pm.app(args[2]) else { print("✖ usage: backup <package> <out.zip>"); exit(2) }
    let tmp = try pm.backup(app.packageName, label: app.label)
    try? FileManager.default.removeItem(atPath: args[3])
    try FileManager.default.moveItem(at: tmp, to: URL(fileURLWithPath: args[3]))
    print("✓ backed up \(app.packageName) to \(args[3])")
    exit(0)
case "restore":
    guard args.count > 3 else { print("✖ usage: restore <package> <backup.zip>"); exit(2) }
    try pm.restore(args[2], from: URL(fileURLWithPath: args[3]))
    print("✓ restored \(args[2])")
    exit(0)
case "android-res":
    // android-res 0x0104000a → the Android 9 value (here "OK"), or a style's items.
    guard args.count > 2, let id = Int(args[2].replacingOccurrences(of: "0x", with: ""), radix: 16),
          let fw = FrameworkResources.shared else { print("✖ usage: android-res <hex id> (pack missing?)"); exit(2) }
    if let v = fw.value(id) {
        print(v.string ?? "type=0x\(String(v.type, radix: 16)) data=0x\(String(UInt32(truncatingIfNeeded: v.data), radix: 16))")
    } else if let b = fw.bag(id) {
        for (attr, v) in b.items { print("\(fw.attrName(attr) ?? String(attr, radix: 16)) = \(v.string ?? "0x" + String(UInt32(truncatingIfNeeded: v.data), radix: 16))") }
    } else if let f = fw.filePath(id) {
        print(f)
    } else {
        print("✖ no Android resource 0x\(String(id, radix: 16))")
        exit(1)
    }
    exit(0)
case "install-builtin":
    // What the iOS app does on its first launch.
    let names = pm.installBuiltInApps(includingRemoved: args.count > 2 && args[2] == "--again")
    pm.reload()
    print("✓ built-in apps installed: \(names.isEmpty ? "none" : names.joined(separator: ", "))")
    exit(0)
case "list":
    for a in pm.apps { print("\(a.packageName)\t\(a.label)\t\(a.versionName)") }
    exit(0)
case "uninstall", "clear":
    guard args.count > 2 else { exit(2) }
    if args[1] == "uninstall" { pm.uninstall(args[2]) } else { pm.clearData(args[2]) }
    print("✓ \(args[1]) \(args[2])")
    exit(0)
default:
    break
}
let t0 = Date()
let apk: ApkPackage
if args[1] == "run" {
    guard args.count > 2, pm.app(args[2]) != nil else { print("✖ not installed"); exit(3) }
    apk = try pm.open(args[2])
    args.remove(at: 1)
    print("📲 running installed app from \(pm.appDir(args[1]).path)")
} else {
    apk = try ApkPackage(url: URL(fileURLWithPath: args[1]), scanCode: true)
}
print("📦 \(apk.label) \(apk.packageName) v\(apk.versionName)  dex=\(apk.dexNames.count) classes=\(apk.classCount) launcher=\(apk.launcherActivity ?? "-")")
apk.loadCode()
for error in apk.codeErrors { print("✖ " + error) }
guard !apk.dexFiles.isEmpty else {
    print("✖ No valid DEX files loaded. Nothing was executed.")
    exit(3)
}
guard let launcher = apk.launcherActivity else {
    print("✖ APK has no launcher activity.")
    exit(3)
}
let desc = VMClass.descriptor(launcher)
guard apk.dexFiles.contains(where: { $0.hasClass(desc) }) else {
    print("✖ Launcher \(launcher) not found in loaded DEX classes.")
    exit(3)
}
print(String(format: "⏱  loaded in %.2fs", Date().timeIntervalSince(t0)))

let host = TextHost()
let vm = VM(apk: apk)
vm.host = host
if lenient { vm.strictRealApkMode = false }
vm.log = { print("  log: " + $0) }
vm.post("launch") { try vm.launchActivity(desc, intent: nil) }
pump(3)
if !host.errors.isEmpty || vm.interpretedMethodCount == 0 {
    print("✖ Launch failed or no real DEX methods were executed.")
    exit(4)
}
print("✓ DEX methods executed: \(vm.interpretedMethodCount); compatibility no-ops: \(vm.stubCallCount)")
if let root = host.stack.last?.rootBox {
    layoutCanvases(root)
    pump(0.5)
}

func screen() {
    guard let top = host.stack.last else { print("(no activity)"); return }
    print("📱 SCREEN \(top.className) — \(top.title)")
    if let root = top.rootBox { print(dump(root), terminator: "") } else { print("   (no content view)") }
}
screen()

for a in args.dropFirst(2) {
    if a.hasPrefix("tap:") {
        let what = String(a.dropFirst(4))
        guard let root = host.stack.last?.rootBox, let b = findBox(root, what) else { print("❓ no view '\(what)'"); continue }
        print("👆 tap \(what)")
        if b.kind == .check {
            b.isChecked = !b.isChecked
            b.toggle()
        } else {
            b.tap()
        }
        pump(1)
        screen()
    } else if a.hasPrefix("touch:") {
        // touch:x,y in Android pixels: a finger down and up there.
        let xy = a.dropFirst(6).split(separator: ",").compactMap { Double($0) }
        guard xy.count == 2, let root = host.stack.last?.rootBox, let b = firstTouchable(root) else { print("❓ nothing takes touches"); continue }
        print("👆 touch \(Int(xy[0])),\(Int(xy[1]))")
        b.touchHandler?(b, 0, CGFloat(xy[0]) / 2, CGFloat(xy[1]) / 2)
        b.touchHandler?(b, 1, CGFloat(xy[0]) / 2, CGFloat(xy[1]) / 2)
        pump(0.3)
        screen()
    } else if a.hasPrefix("wait:") {
        pump((Double(a.dropFirst(5)) ?? 1000) / 1000)
    } else if a == "screen" {
        screen()
    } else if a.hasPrefix("svg:") {
        // svg:file.svg — what the first drawing view shows, as an SVG picture.
        func firstCanvas(_ b: ViewBox) -> ViewBox? {
            if let cv = b.canvasView, !cv.ops.isEmpty { return b }
            for c in b.children { if let f = firstCanvas(c) { return f } }
            return nil
        }
        guard let root = host.stack.last?.rootBox, let b = firstCanvas(root), let cv = b.canvasView else { print("❓ nothing drawn"); continue }
        let path = String(a.dropFirst(4))
        try svgDocument(cv.ops, width: Int(b.pxWidth), height: Int(b.pxHeight)).write(toFile: path, atomically: true, encoding: .utf8)
        print("🖼  \(path) (\(cv.ops.count) ops)")
    } else if a.hasPrefix("expect:") {
        // expect:id=text — fails the run (exit 5) unless that view shows exactly that text.
        let spec = a.dropFirst(7)
        guard let eq = spec.firstIndex(of: "=") else { continue }
        let id = String(spec[..<eq]), want = String(spec[spec.index(after: eq)...])
        func byId(_ b: ViewBox) -> ViewBox? {
            if b.id != -1, apk.resources?.name(b.id) == "id/" + id { return b }
            for c in b.children { if let f = byId(c) { return f } }
            return nil
        }
        let got = host.stack.last?.rootBox.flatMap { byId($0) }?.text
        if got == want { print("✅ \(id) = \"\(want)\"") } else {
            print("❌ \(id) is \"\(got ?? "(missing)")\", expected \"\(want)\"")
            exit(5)
        }
    }
}
print(String(format: "⏱  total %.2fs, steps=%d, frames drawn=%d", Date().timeIntervalSince(t0), vm.steps, vm.framesDrawn))
let heapBefore = HeapBudget.shared.usedBytes
vm.shutdown()
pump(0.5)
print("🧹 app stopped: Java arrays \(ProcessMemory.megabytes(heapBefore)) → \(ProcessMemory.megabytes(HeapBudget.shared.usedBytes))")
print("🧠 Java arrays now \(ProcessMemory.megabytes(HeapBudget.shared.usedBytes)), peak \(ProcessMemory.megabytes(HeapBudget.shared.peakBytes)), limit \(ProcessMemory.megabytes(HeapBudget.shared.limit)); process \(ProcessMemory.megabytes(ProcessMemory.footprint()))")
exit(0)
