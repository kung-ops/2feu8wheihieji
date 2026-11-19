import UIKit
import AVFoundation

/// Optional local PC media bridge. No sensor is enabled remotely or automatically.
/// The Files APK picker and original Dalvik interpreter remain unchanged.
final class PCBridgeViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let addressField = UITextField()
    private let keyField = UITextField()
    private let statusLabel = UILabel()
    private let recordButton = UIButton(type: .system)
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var player: AVAudioPlayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "PC Bridge"
        view.backgroundColor = .white
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
        ])

        stack.addArrangedSubview(label("On the PC, run PCBridge/START-PC-BRIDGE.bat. Enter the PC address and pairing key from the black server window. Use the same trusted Wi-Fi."))
        addressField.borderStyle = .roundedRect
        addressField.placeholder = "http://192.168.x.x:8765"
        addressField.text = UserDefaults.standard.string(forKey: "pc-bridge-address")
        addressField.keyboardType = .URL
        addressField.autocapitalizationType = .none
        addressField.autocorrectionType = .no
        stack.addArrangedSubview(addressField)
        keyField.borderStyle = .roundedRect
        keyField.placeholder = "Pairing key shown on PC"
        keyField.isSecureTextEntry = true
        keyField.autocapitalizationType = .none
        keyField.autocorrectionType = .no
        stack.addArrangedSubview(keyField)
        stack.addArrangedSubview(button("Connect to PC", #selector(connect)))
        statusLabel.numberOfLines = 0
        statusLabel.textColor = .gray
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.text = "Not connected"
        stack.addArrangedSubview(statusLabel)

        stack.addArrangedSubview(label("Camera and microphone on this iPhone (you control when):"))
        stack.addArrangedSubview(button("Take Photo with Camera", #selector(takePhoto)))
        recordButton.setTitle("Record Microphone", for: .normal)
        recordButton.titleLabel?.font = .boldSystemFont(ofSize: 17)
        recordButton.addTarget(self, action: #selector(toggleRecording), for: .touchUpInside)
        stack.addArrangedSubview(recordButton)
        stack.addArrangedSubview(label("Audio from PC to iPhone:"))
        stack.addArrangedSubview(button("Play PC Audio", #selector(playPCAudio)))
        stack.addArrangedSubview(label("Copy MP3, M4A or WAV to PCBridge/pc-audio. Files are sent to the PC only after you confirm. The APK picker and Run button still work normally. Unsupported Android camera/audio APIs inside imported APKs are not implemented by this bridge."))
    }

    private func label(_ text: String) -> UILabel {
        let v = UILabel()
        v.numberOfLines = 0
        v.text = text
        v.font = .systemFont(ofSize: 15)
        return v
    }
    private func button(_ text: String, _ action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(text, for: .normal)
        b.titleLabel?.font = .boldSystemFont(ofSize: 17)
        b.contentEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }
    private func message(_ text: String) { statusLabel.text = text }
    private func alert(_ title: String, _ message: String) {
        let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        present(a, animated: true)
    }
    private func endpoint(_ route: String) -> URL? {
        let raw = (addressField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: raw), u.scheme == "http", u.host != nil,
              u.port != nil, u.user == nil, u.password == nil else { return nil }
        return u.appendingPathComponent(route)
    }
    private func request(_ method: String, route: String, body: Data? = nil, mime: String? = nil,
                         done: @escaping (Result<Data, Error>) -> Void) {
        guard let url = endpoint(route), let key = keyField.text, !key.isEmpty else {
            alert("PC address and key required", "Start the PC BAT server. Enter its local http:// URL and pairing key.")
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 25
        req.setValue(key, forHTTPHeaderField: "X-Bridge-Key")
        if let mime = mime { req.setValue(mime, forHTTPHeaderField: "Content-Type") }
        req.httpBody = body
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { done(.failure(error)); return }
                guard let code = (response as? HTTPURLResponse)?.statusCode,
                      (200...299).contains(code) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    done(.failure(NSError(domain: "PC Bridge", code: code,
                        userInfo: [NSLocalizedDescriptionKey: "PC server error \(code). Check address and pairing key."])))
                    return
                }
                done(.success(data ?? Data()))
            }
        }.resume()
    }

    @objc private func connect() {
        request("GET", route: "health") { [weak self] result in
            switch result {
            case .success:
                self?.message("Connected to PC. Camera, microphone and PC audio are ready.")
                if let value = self?.addressField.text {
                    UserDefaults.standard.set(value, forKey: "pc-bridge-address")
                }
            case .failure(let error):
                self?.message("Connection failed: \(error.localizedDescription)")
            }
        }
    }

    @objc private func takePhoto() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            alert("Camera unavailable", "This iPhone has no available camera.")
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        present(picker, animated: true)
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
    func imagePickerController(_ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage,
              let jpeg = image.jpegData(compressionQuality: 0.72) else {
            message("Could not convert camera image to JPEG.")
            return
        }
        offerUpload("Upload photo to PC?", data: jpeg, route: "photo", mime: "image/jpeg")
    }

    @objc private func toggleRecording() {
        if recorder != nil { finishRecording(); return }
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if !granted {
                    self.alert("Microphone denied", "Allow microphone access in iPhone Settings to record.")
                    return
                }
                self.beginRecording()
            }
        }
    }
    private func beginRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 22050,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]
            let r = try AVAudioRecorder(url: url, settings: settings)
            guard r.record(forDuration: 60) else {
                throw NSError(domain: "Microphone", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Recording could not start."])
            }
            recorder = r
            recordingURL = url
            recordButton.setTitle("Stop Recording (max 60s)", for: .normal)
            message("Recording locally on iPhone. Tap Stop to choose whether to send to PC.")
        } catch { alert("Microphone failed", error.localizedDescription) }
    }
    private func finishRecording() {
        recorder?.stop()
        recorder = nil
        recordButton.setTitle("Record Microphone", for: .normal)
        guard let url = recordingURL else { return }
        recordingURL = nil
        defer { try? FileManager.default.removeItem(at: url) }
        guard let bytes = try? Data(contentsOf: url), !bytes.isEmpty else {
            message("Recording is empty.")
            return
        }
        offerUpload("Send recording to PC?", data: bytes, route: "recording", mime: "audio/mp4")
    }
    private func offerUpload(_ title: String, data: Data, route: String, mime: String) {
        let a = UIAlertController(title: title,
            message: "Only this file will be sent over your Wi-Fi to the PC. Do not use on public Wi-Fi.",
            preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Discard", style: .cancel))
        a.addAction(UIAlertAction(title: "Send to PC", style: .default) { [weak self] _ in
            self?.message("Uploading \(data.count / 1024) KB...")
            self?.request("POST", route: route, body: data, mime: mime) { result in
                switch result {
                case .success: self?.message("Sent. Check PCBridge/received on your PC.")
                case .failure(let error): self?.message("Upload failed: \(error.localizedDescription)")
                }
            }
        })
        present(a, animated: true)
    }

    @objc private func playPCAudio() {
        request("GET", route: "audio") { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                self.message("Cannot list PC audio: \(error.localizedDescription)")
            case .success(let data):
                let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let files = obj?["files"] as? [String] ?? []
                guard !files.isEmpty else {
                    self.alert("No PC audio", "Put an MP3, M4A or WAV in PCBridge/pc-audio on your PC.")
                    return
                }
                let a = UIAlertController(title: "Play audio from PC", message: "Select a file", preferredStyle: .actionSheet)
                for file in files.prefix(30) {
                    a.addAction(UIAlertAction(title: file, style: .default) { [weak self] _ in
                        self?.downloadAndPlay(file)
                    })
                }
                a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                if let pop = a.popoverPresentationController {
                    pop.sourceView = self.view
                    pop.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 1, height: 1)
                }
                self.present(a, animated: true)
            }
        }
    }
    private func downloadAndPlay(_ name: String) {
        request("GET", route: "audio/" + name) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                self.message("Audio download failed: \(error.localizedDescription)")
            case .success(let data):
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playback, mode: .default)
                    try session.setActive(true)
                    self.player = try AVAudioPlayer(data: data)
                    self.player?.prepareToPlay()
                    guard self.player?.play() == true else {
                        throw NSError(domain: "Audio", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Cannot decode this audio format."])
                    }
                    self.message("Playing PC audio: \(name) through iPhone speakers.")
                } catch { self.message("Audio could not play: \(error.localizedDescription)") }
            }
        }
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // If user leaves while recording, discard rather than capturing in background.
        if recorder != nil {
            recorder?.stop()
            recorder = nil
            if let url = recordingURL { try? FileManager.default.removeItem(at: url) }
            recordingURL = nil
            recordButton.setTitle("Record Microphone", for: .normal)
        }
    }
}
