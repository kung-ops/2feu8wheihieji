import UIKit
import AVFoundation

/// PC features are separate from the normal APK picker and interpreter.
final class PCLinkViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let address = UITextField()
    let token = UITextField()
    let status = UILabel()
    let recordButton = UIButton(type: .system)
    var player: AVPlayer?
    var recorder: AVAudioRecorder?
    var recording: URL?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "PC Link"
        view.backgroundColor = .white
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 13
        stack.translatesAutoresizingMaskIntoConstraints = false
        let heading = UILabel()
        heading.text = "PC audio, camera and microphone"
        heading.numberOfLines = 0
        heading.font = .boldSystemFont(ofSize: 18)
        stack.addArrangedSubview(heading)
        address.placeholder = "http://192.168.1.10:8765"
        address.keyboardType = .URL
        address.autocapitalizationType = .none
        address.autocorrectionType = .no
        address.borderStyle = .roundedRect
        address.text = UserDefaults.standard.string(forKey: "PCLinkAddress")
        stack.addArrangedSubview(address)
        token.placeholder = "Pairing token printed on PC"
        token.borderStyle = .roundedRect
        token.autocapitalizationType = .none
        token.autocorrectionType = .no
        token.isSecureTextEntry = true
        token.text = UserDefaults.standard.string(forKey: "PCLinkToken")
        stack.addArrangedSubview(token)
        button("Test connection", #selector(check), stack)
        button("Play PC audio file", #selector(play), stack)
        button("Stop audio", #selector(stop), stack)
        button("Take photo & send to PC", #selector(photo), stack)
        recordButton.setTitle("Start microphone recording", for: .normal)
        recordButton.addTarget(self, action: #selector(mic), for: .touchUpInside)
        stack.addArrangedSubview(recordButton)
        status.numberOfLines = 0
        status.font = .systemFont(ofSize: 13)
        status.text = "Trusted Wi-Fi only. LAN HTTP is unencrypted. Recording is always initiated on your iPhone."
        stack.addArrangedSubview(status)
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }

    func button(_ name: String, _ action: Selector, _ stack: UIStackView) {
        let b = UIButton(type: .system)
        b.setTitle(name, for: .normal)
        b.contentHorizontalAlignment = .left
        b.addTarget(self, action: action, for: .touchUpInside)
        stack.addArrangedSubview(b)
    }
    func message(_ text: String) {
        DispatchQueue.main.async { [weak self] in self?.status.text = text }
    }
    func configuration() -> (URL, String)? {
        guard let addressText = address.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: addressText), url.scheme == "http", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil,
              url.fragment == nil, (url.path.isEmpty || url.path == "/"),
              let key = token.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              key.range(of: "^[a-f0-9]{36}$", options: .regularExpression) != nil else {
            message("Enter the PC http://IP:8765 address and 36-character pairing token.")
            return nil
        }
        UserDefaults.standard.set(addressText, forKey: "PCLinkAddress")
        UserDefaults.standard.set(key, forKey: "PCLinkToken")
        return (url, key)
    }
    func endpoint(_ url: URL, _ path: String) -> URL { return url.appendingPathComponent(path) }
    func upload(_ root: URL, _ key: String, path: String, body: Data, type: String) {
        var req = URLRequest(url: endpoint(root, path))
        req.httpMethod = "POST"
        req.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        req.setValue(type, forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 45
        URLSession.shared.uploadTask(with: req, from: body) { [weak self] _, response, error in
            if let error = error { self?.message(error.localizedDescription); return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            self?.message(code == 201 ? "Sent to the PC uploads folder." : "Upload failed, HTTP \(code).")
        }.resume()
    }

    @objc func check() {
        guard let (root, key) = configuration() else { return }
        var req = URLRequest(url: endpoint(root, "status"))
        req.timeoutInterval = 10
        req.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { [weak self] _, response, error in
            if let error = error { self?.message(error.localizedDescription); return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            self?.message(code == 200 ? "Connected to your PC." : "Could not connect: HTTP \(code)")
        }.resume()
    }

    @objc func play() {
        guard let (root, key) = configuration() else { return }
        var parts = URLComponents(url: endpoint(root, "audio"), resolvingAgainstBaseURL: false)
        parts?.queryItems = [URLQueryItem(name: "token", value: key)]
        guard let url = parts?.url else { return }
        player?.pause()
        player = AVPlayer(url: url)
        player?.play()
        message("Playing PC audio file. Put pc-audio.mp3 or .m4a beside server.js.")
    }
    @objc func stop() {
        player?.pause()
        player = nil
        message("PC audio stopped.")
    }
    @objc func photo() {
        guard configuration() != nil else { return }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            message("Camera unavailable on this device."); return
        }
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard granted else { self.message("Camera access denied in Settings."); return }
                let picker = UIImagePickerController()
                picker.sourceType = .camera
                picker.delegate = self
                self.present(picker, animated: true)
            }
        }
    }
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage,
              let jpeg = image.jpegData(compressionQuality: 0.75),
              let (root, key) = configuration() else { return }
        upload(root, key, path: "upload/photo", body: jpeg, type: "image/jpeg")
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
    @objc func mic() {
        if let recorder = recorder, recorder.isRecording {
            recorder.stop()
            recordButton.setTitle("Start microphone recording", for: .normal)
            guard let file = recording, let (root, key) = configuration() else { return }
            do {
                let bytes = try Data(contentsOf: file)
                upload(root, key, path: "upload/microphone", body: bytes, type: "audio/mp4")
                try? FileManager.default.removeItem(at: file)
            } catch { message(error.localizedDescription) }
            return
        }
        guard configuration() != nil else { return }
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                if granted { self?.startMic() }
                else { self?.message("Microphone permission denied in Settings.") }
            }
        }
    }
    func startMic() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
            let opts: [String: Any] = [AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 22050, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64000]
            let rec = try AVAudioRecorder(url: file, settings: opts)
            guard rec.record() else { message("Could not start microphone."); return }
            recorder = rec
            recording = file
            recordButton.setTitle("Stop & send microphone recording", for: .normal)
            message("Recording. Tap Stop & send to upload the clip.")
        } catch { message(error.localizedDescription) }
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent || isBeingDismissed {
            player?.pause()
            recorder?.stop()
            if let file = recording { try? FileManager.default.removeItem(at: file) }
            recorder = nil
        }
    }
}
