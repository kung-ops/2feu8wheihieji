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
    if let cv = b.view as? CanvasView, !cv.ops.isEmpty {
        let texts = cv.ops.filter { if case .text = $0 { return true }; return false }.map { $0.summary }
        line += " [canvas \(b.pxWidth)x\(b.pxHeight) px, \(cv.ops.count) ops: \(Set(cv.ops.map { $0.summary.split(separator: " ").first.map(String.init) ?? "" }).sorted().joined(separator: ","))\(texts.isEmpty ? "" : "; " + texts.joined(separator: "; "))]"
    }
    var out = line + "\n"
    for c in b.children { out += dump(c, indent + "  ") }
    return out
}

func findBox(_ b: ViewBox, _ text: String) -> ViewBox? {
    if b.text == text || (b.id != -1 && ("0x" + String(b.id, radix: 16) == text || apk.resources?.name(b.id) == "id/" + text)) { return b }
    for c in b.children { if let f = findBox(c, text) { return f } }
    return nil
}

/// Gives every drawing view a phone-sized frame (360 x 640 pt), like UIKit layout would.
func layoutCanvases(_ b: ViewBox) {
    if b.isCanvas, let o = b.jobj, o.cls.isApp {
        b.view.bounds = CGRect(x: 0, y: 0, width: 360, height: 640)
        b.sizeHandler?(b, 360, 640)
    }
    for c in b.children { layoutCanvases(c) }
}

func firstTouchable(_ b: ViewBox) -> ViewBox? {
    if b.isCanvas, b.touchHandler != nil, (b.view as? CanvasView)?.acceptsTouches == true { return b }
    for c in b.children { if let f = firstTouchable(c) { return f } }
    return nil
}

func pump(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
}

var args = CommandLine.arguments
guard args.count > 1 else {
    print("""
    usage: runner <apk> [tap:text]... [wait:ms]...
           runner install <apk>            install into the virtual Android
           runner run <package> [tap:...]  run an installed app (memory-mapped dex)
           runner list | uninstall <package> | clear <package>
           runner backup <package> <out.zip> | restore <package> <backup.zip>
    """)
    exit(2)
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
    }
}
print(String(format: "⏱  total %.2fs, steps=%d, frames drawn=%d", Date().timeIntervalSince(t0), vm.steps, vm.framesDrawn))
let heapBefore = HeapBudget.shared.usedBytes
vm.shutdown()
pump(0.5)
print("🧹 app stopped: Java arrays \(ProcessMemory.megabytes(heapBefore)) → \(ProcessMemory.megabytes(HeapBudget.shared.usedBytes))")
print("🧠 Java arrays now \(ProcessMemory.megabytes(HeapBudget.shared.usedBytes)), peak \(ProcessMemory.megabytes(HeapBudget.shared.peakBytes)), limit \(ProcessMemory.megabytes(HeapBudget.shared.limit)); process \(ProcessMemory.megabytes(ProcessMemory.footprint()))")
exit(0)
