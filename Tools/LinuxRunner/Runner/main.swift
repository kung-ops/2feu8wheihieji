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
    var out = line + "\n"
    for c in b.children { out += dump(c, indent + "  ") }
    return out
}

func findBox(_ b: ViewBox, _ text: String) -> ViewBox? {
    if b.text == text || (b.id != -1 && ("0x" + String(b.id, radix: 16) == text || apk.resources?.name(b.id) == "id/" + text)) { return b }
    for c in b.children { if let f = findBox(c, text) { return f } }
    return nil
}

func pump(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
}

let args = CommandLine.arguments
guard args.count > 1 else { print("usage: runner <apk> [tap:text]..."); exit(2) }
let t0 = Date()
let apk = try ApkPackage(url: URL(fileURLWithPath: args[1]), scanCode: true)
print("📦 \(apk.label) \(apk.packageName) v\(apk.versionName)  dex=\(apk.dexNames.count) classes=\(apk.classCount) launcher=\(apk.launcherActivity ?? "-")")
apk.loadCode()
print(String(format: "⏱  loaded in %.2fs", Date().timeIntervalSince(t0)))

let host = TextHost()
let vm = VM(apk: apk)
vm.host = host
vm.log = { print("  log: " + $0) }
let desc = VMClass.descriptor(apk.launcherActivity ?? "")
vm.post("launch") { try vm.launchActivity(desc, intent: nil) }
pump(3)

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
        b.tap()
        pump(1)
        screen()
    } else if a.hasPrefix("wait:") {
        pump((Double(a.dropFirst(5)) ?? 1000) / 1000)
    }
}
print(String(format: "⏱  total %.2fs, steps=%d", Date().timeIntervalSince(t0), vm.steps))
exit(0)
