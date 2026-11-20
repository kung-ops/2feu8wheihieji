import UIKit

/// "Download from a link" (like Husk's Add Download): asks for the address
/// of an .apk / .apks / .xapk / .apkm, downloads it into Downloads with a
/// progress alert, then hands the file back.
final class LinkDownloader: NSObject, URLSessionDownloadDelegate {
    /// The download in progress (kept alive here until it ends).
    private static var current: LinkDownloader?

    private var session: URLSession?
    private let alert: UIAlertController
    private let done: (URL) -> Void
    private weak var presenter: UIViewController?
    private var savedFile: URL?
    private var failure: String?

    /// Asks for a link, then downloads it.
    static func ask(from presenter: UIViewController, done: @escaping (URL) -> Void) {
        let a = UIAlertController(title: "Download from a link",
                                  message: "The address of an APK or an app bundle (.apks, .xapk, .apkm).",
                                  preferredStyle: .alert)
        a.addTextField { tf in
            tf.placeholder = "https://…"
            tf.keyboardType = .URL
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
            tf.clearButtonMode = .whileEditing
        }
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        a.addAction(UIAlertAction(title: "Download", style: .default) { [weak presenter] _ in
            guard let presenter = presenter else { return }
            var text = (a.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty, !text.contains("://") { text = "https://" + text }
            guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                presenter.showMessage("That isn't a web address", "Paste a link that starts with https:// or http://.")
                return
            }
            let d = LinkDownloader(presenter: presenter, done: done)
            current = d
            d.start(url)
        })
        presenter.present(a, animated: true)
    }

    private init(presenter: UIViewController, done: @escaping (URL) -> Void) {
        self.presenter = presenter
        self.done = done
        alert = UIAlertController(title: "Downloading…", message: "Starting", preferredStyle: .alert)
        super.init()
    }

    private func start(_ url: URL) {
        let s = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue.main)
        session = s
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.session?.invalidateAndCancel()
            LinkDownloader.current = nil
        })
        presenter?.present(alert, animated: true)
        s.downloadTask(with: url).resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let pct = Int(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) * 100)
            alert.message = "\(pct)% of \(Theme.bytes(totalBytesExpectedToWrite))"
        } else {
            alert.message = Theme.bytes(totalBytesWritten)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temporary file disappears after this call: move it now.
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            failure = "The server answered \(http.statusCode)."
            return
        }
        var name = downloadTask.response?.suggestedFilename ?? downloadTask.originalRequest?.url?.lastPathComponent ?? "download.apk"
        if !ApkBundle.extensions.contains((name as NSString).pathExtension.lowercased()) { name += ".apk" }
        let fm = FileManager.default
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var dest = ApkStore.documents.appendingPathComponent(name)
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = ApkStore.documents.appendingPathComponent("\(base) \(n).\(ext)")
            n += 1
        }
        do {
            try fm.moveItem(at: location, to: dest)
            savedFile = dest
        } catch {
            failure = error.localizedDescription
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        session.finishTasksAndInvalidate()
        LinkDownloader.current = nil
        let file = savedFile
        let why = failure ?? error?.localizedDescription
        let done = self.done
        let presenter = self.presenter
        alert.dismiss(animated: true) {
            if let f = file {
                done(f)
            } else if let p = presenter {
                p.showMessage("Download failed", why ?? "Unknown error")
            }
        }
    }
}
