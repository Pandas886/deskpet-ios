import UIKit
import AVFoundation
import Vision
import CoreImage
import CoreMotion

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = PetController()
        window?.makeKeyAndVisible()
        return true
    }
}

final class FaceView: UIView {
    let behavior = PetBehavior(now: CACurrentMediaTime())
    var onEffect: ((PetEffect) -> Void)?
    var onContact: (() -> Void)?
    var tilt: CGFloat = 0
    var voiceState: PetVoice.State = .idle
    private var gaze = CGPoint.zero
    private var pose = PetFacePose()
    private let renderer = PetFaceRenderer()
    private var lastTick: CFTimeInterval = 0
    private var nextIdleLook: CFTimeInterval = 0
    private var idleLook = CGPoint.zero
    private var nextBlink: CFTimeInterval = 0
    private var blinkStart: CFTimeInterval = -100
    private var clock: CADisplayLink?
    private var touchPoint: CGPoint?
    private var touchStarted: CFTimeInterval = 0
    private var lastTouchPoint = CGPoint.zero
    private var lastTouchTime: CFTimeInterval = 0
    private var travel: CGFloat = 0
    private var stroked = false
    private var heldTouch = false
    private var lastCaress: CFTimeInterval = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isAccessibilityElement = true
        accessibilityLabel = "桌面小宠"
        accessibilityHint = "轻点逗它，缓慢滑动抚摸，长按安抚"
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        clock = link
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    func saw(_ box: CGRect?) {
        behavior.observe(box, now: CACurrentMediaTime())
    }

    func suspend() {
        touchPoint = nil
        tilt = 0
        behavior.resetPresence(now: CACurrentMediaTime())
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        guard UIApplication.shared.applicationState == .active else { return }
        let dt = min(0.05, max(0, now - (lastTick == 0 ? now - 1 / 30 : lastTick)))
        lastTick = now
        if now > nextBlink {
            blinkStart = now
            nextBlink = now + Double.random(in: 2.5...6)
        }
        if touchPoint != nil && now - touchStarted > 0.7 && !stroked && now - lastCaress > 1.8 {
            heldTouch = true
            lastCaress = now
            behavior.soothe(now: now)
        }
        var target = behavior.gaze(now: now)
        if now - behavior.lastSeen > 4 {
            if now > nextIdleLook {
                idleLook = CGPoint(x: CGFloat.random(in: -0.38...0.38), y: CGFloat.random(in: -0.16...0.16))
                nextIdleLook = now + Double.random(in: 3...7)
            }
            target = idleLook
        }
        if voiceState == .waiting && now - behavior.lastInteraction > 3 {
            target = CGPoint(x: -0.24, y: -0.20)
        }
        if let point = touchPoint {
            target = CGPoint(x: max(-1, min(1, (point.x / max(1, bounds.width) - 0.5) * 2)),
                             y: max(-1, min(1, (point.y / max(1, bounds.height) - 0.5) * 2)))
        }
        let gazeAmount = CGFloat(1 - exp(-dt / 0.11))
        gaze.x += (target.x - gaze.x) * gazeAmount
        gaze.y += (target.y - gaze.y) * gazeAmount
        let mood = behavior.mood(now: now)
        var wanted = PetFacePose.target(mood)
        wanted.lean += tilt
        if touchPoint != nil { wanted.lean += gaze.x * 0.04 }
        if mood == .calm && voiceState == .listening { wanted.asymmetry = 0.035 }
        let time = wanted.smile > pose.smile ? 0.20 : 0.42
        pose.approach(wanted, amount: CGFloat(1 - exp(-dt / time)))
        for effect in behavior.takeEffects() { onEffect?(effect) }
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        let now = CACurrentMediaTime()
        guard let context = UIGraphicsGetCurrentContext() else { return }
        renderer.draw(in: context, bounds: bounds, gaze: gaze, pose: pose,
                      closure: PetFaceRenderer.blinkClosure(elapsed: now - blinkStart), now: now)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard touchPoint == nil, let point = touches.first?.location(in: self) else { return }
        onContact?()
        let now = CACurrentMediaTime()
        touchPoint = point
        blinkStart = now
        lastTouchPoint = point
        touchStarted = now
        lastTouchTime = now
        lastCaress = now - 2
        travel = 0
        stroked = false
        heldTouch = false
        behavior.wake(now: now)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard touchPoint != nil, let point = touches.first?.location(in: self) else { return }
        let now = CACurrentMediaTime()
        let distance = hypot(point.x - lastTouchPoint.x, point.y - lastTouchPoint.y)
        let speed = distance / max(0.001, now - lastTouchTime)
        travel += distance
        touchPoint = point
        lastTouchPoint = point
        lastTouchTime = now
        if travel >= 60 && now - touchStarted > 0.25 && speed < 1100 && now - lastCaress > 0.7 {
            stroked = true
            lastCaress = now
            travel = 0
            behavior.stroke(now: now)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard touchPoint != nil else { return }
        let now = CACurrentMediaTime()
        if !stroked && !heldTouch {
            if now - touchStarted >= 0.7 { behavior.soothe(now: now) }
            else if travel < 35 { behavior.poke(now: now) }
        }
        touchPoint = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchPoint = nil
    }
}

final class PetController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let face = FaceView()
    private let audio = PetAudio()
    private let voice = PetVoice()
    private var voiceOwnsAudio = false
    private let microphoneButton = UIButton(type: .system)
    private let voiceLabel = UILabel()
    private let motion = CMMotionManager()
    private var motionFilter = PetMotionFilter()
    private var ignoreMotionUntil: CFTimeInterval = 0
    private var motionEnabled = UserDefaults.standard.object(forKey: "petMotionEnabled") as? Bool ?? true
    private let menuButton = UIButton(type: .system)
    private let status = UILabel()
    private let detail = UILabel()
    private let preview = UIImageView()
    private let faceBox = CAShapeLayer()
    private let session = AVCaptureSession()
    private let cameraQueue = DispatchQueue(label: "deskpet.camera")
    private let frameQueue = DispatchQueue(label: "deskpet.vision")
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private var imageSize = CGSize(width: 640, height: 480)
    private var diagnostic = false
    private var configured = false
    private var cameraDevice: AVCaptureDevice?
    private var wantsPreview = false
    private var processedFPS = 0.0
    private var rateWindow: CFTimeInterval = 0
    private var rateFrames = 0
    private var lastFrame: CFTimeInterval = 0
    private var frameCount = 0
    private var detections = 0
    private var lastLog: CFTimeInterval = 0
    private var logLines = "time,frames,faces,vision_ms,thermal\n"
    private var lastFace: CGRect?
    private var sampleMilliseconds = 0.0
    private let started = Date()
    private var performedVoiceSelfTest = false

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscapeRight }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .landscapeRight }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--camera-diagnostic") && !diagnostic {
            toggleDiagnostic()
        }
        if ProcessInfo.processInfo.arguments.contains("--face-preview") {
            PetFaceRenderer().exportPreview()
        }
        if ProcessInfo.processInfo.arguments.contains("--voice-api-test"), !performedVoiceSelfTest {
            performedVoiceSelfTest = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, UIApplication.shared.applicationState == .active else { return }
                self.voice.stop(message: "正在检查 AI 连接")
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    var history: [ChatMessage] = []
                    for (index, question) in ["请只用一句话问好。", "给我讲个简短笑话。", "再讲一个。"].enumerated() {
                        guard UIApplication.shared.applicationState == .active else { return }
                        do {
                            let reply = try await DeepSeekChat.reply(text: question, context: "连接检查", history: history,
                                                                   key: VoiceKeychain.read(), base: self.voice.base, model: self.voice.model)
                            history.append(ChatMessage(role: "user", content: question))
                            history.append(ChatMessage(role: "assistant", content: reply.speech))
                            print("DeskPet API probe \(index + 1): valid reply")
                        } catch {
                            print("DeskPet API probe \(index + 1): \(ChatFailure.classify(error))")
                        }
                    }
                    self.voice.resumeHandsFreeIfAuthorized()
                }
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--voice-mic-test"), !performedVoiceSelfTest {
            performedVoiceSelfTest = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard UIApplication.shared.applicationState == .active else { return }
                self?.voice.microphone()
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--duplex-self-test"), !performedVoiceSelfTest {
            performedVoiceSelfTest = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard UIApplication.shared.applicationState == .active else { return }
                self?.voice.testDuplex()
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--voice-self-test"),
           !performedVoiceSelfTest,
           let sound = voice.defaultChineseVoice {
            performedVoiceSelfTest = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard UIApplication.shared.applicationState == .active else { return }
                self?.voice.previewVoice(sound.identifier)
            }
        }
        #endif
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        face.frame = view.bounds
        face.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        face.onEffect = { [weak self] effect in
            guard let self else { return }
            let now = CACurrentMediaTime()
            switch effect {
            case .sound(let kind):
                if !self.voice.active { self.audio.play(kind, now: now) }
            case .touch:
                self.ignoreMotionUntil = now + 0.8
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.45)
            }
        }
        view.addSubview(face)
        face.onContact = { [weak self] in
            guard let self, self.voice.state == .speaking else { return }
            self.voice.microphone()
        }
        voice.onOwnership = { [weak self] owned, completion in
            guard let self else { return }
            self.voiceOwnsAudio = owned
            self.audio.setActive(!owned && UIApplication.shared.applicationState == .active, completion: completion)
        }
        voice.context = { [weak self] in
            guard let self else { return "安静陪伴" }
            return "当前状态：\(self.face.behavior.mood(now: CACurrentMediaTime()).rawValue)；用户是否在镜头前：\(self.lastFace != nil ? "是" : "未检测到")。没有画面内容或身份信息。"
        }
        voice.onMood = { [weak self] mood in self?.face.behavior.express(mood, now: CACurrentMediaTime()) }
        voice.onUpdate = { [weak self] state, text in
            guard let self else { return }
            self.face.voiceState = state
            self.voiceLabel.text = text
            self.voiceLabel.isHidden = text.isEmpty
            self.microphoneButton.setImage(UIImage(systemName: state == .listening ? "paperplane.fill" : "mic.fill"), for: .normal)
            self.microphoneButton.tintColor = state == .listening ? .systemRed : .systemYellow
            self.microphoneButton.accessibilityLabel = state == .listening ? "发送识别内容" : "开始说话"
        }
        voiceLabel.textColor = .white
        voiceLabel.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        voiceLabel.font = .systemFont(ofSize: 14)
        voiceLabel.textAlignment = .center
        voiceLabel.numberOfLines = 3
        voiceLabel.isHidden = true
        view.addSubview(voiceLabel)
        microphoneButton.setImage(UIImage(systemName: "mic.fill"), for: .normal)
        microphoneButton.tintColor = .systemYellow
        microphoneButton.accessibilityLabel = "开始说话"
        microphoneButton.addTarget(self, action: #selector(chatMicrophone), for: .touchUpInside)
        view.addSubview(microphoneButton)

        status.text = "准备见面…"
        status.textColor = UIColor(white: 0.65, alpha: 1)
        status.font = .systemFont(ofSize: 14)
        status.textAlignment = .center
        status.isHidden = true
        view.addSubview(status)
        detail.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        detail.textColor = .lightGray
        detail.numberOfLines = 0
        detail.isHidden = true
        view.addSubview(detail)

        preview.isHidden = true
        preview.clipsToBounds = true
        preview.contentMode = .scaleAspectFit
        preview.layer.cornerRadius = 10
        view.addSubview(preview)
        faceBox.strokeColor = UIColor.systemGreen.cgColor
        faceBox.fillColor = UIColor.clear.cgColor
        faceBox.lineWidth = 2
        preview.layer.addSublayer(faceBox)

        menuButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        menuButton.tintColor = UIColor(white: 0.55, alpha: 1)
        menuButton.accessibilityLabel = "宠物设置"
        menuButton.showsMenuAsPrimaryAction = true
        updateMenu()
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(menuButton)
        NSLayoutConstraint.activate([
            menuButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            menuButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            menuButton.widthAnchor.constraint(equalToConstant: 44),
            menuButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(activate), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(deactivate), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted), name: AVCaptureSession.wasInterruptedNotification, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(activate), name: AVCaptureSession.interruptionEndedNotification, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(cameraError), name: AVCaptureSession.runtimeErrorNotification, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(thermalChanged), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        activate()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        status.frame = CGRect(x: 24, y: view.bounds.height - 42, width: view.bounds.width - 48, height: 24)
        microphoneButton.frame = CGRect(x: view.bounds.width - view.safeAreaInsets.right - 60, y: view.bounds.height - 70, width: 48, height: 48)
        voiceLabel.frame = CGRect(x: view.safeAreaInsets.left + 20, y: view.bounds.height - 84,
                                 width: view.bounds.width - view.safeAreaInsets.left - view.safeAreaInsets.right - 100, height: 62)
        detail.frame = CGRect(x: view.safeAreaInsets.left + 16, y: 15, width: 340, height: 65)
        preview.frame = CGRect(x: view.safeAreaInsets.left + 16, y: view.bounds.height - 155, width: 192, height: 108)
        drawBox()
    }

    private func orient(_ connection: AVCaptureConnection?) {
        guard let connection else { return }
        // The XR front sensor needs 180 degrees for the locked landscape interface.
        if connection.isVideoRotationAngleSupported(180) { connection.videoRotationAngle = 180 }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
    }

    @objc private func activate() {
        guard UIApplication.shared.applicationState == .active else { return }
        UIApplication.shared.isIdleTimerDisabled = true
        if !voice.active && !voiceOwnsAudio { audio.setActive(true) }
        voice.resumeHandsFreeIfAuthorized()
        startMotion()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraQueue.async { self.startCamera() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.activate() }
                    else {
                        self.status.text = "相机未授权 · 仍可摸摸我"
                        self.status.isHidden = false
                    }
                }
            }
        default:
            status.text = "请在系统设置中允许相机 · 仍可摸摸我"
            status.isHidden = false
        }
    }

    @objc private func deactivate() {
        UIApplication.shared.isIdleTimerDisabled = false
        face.suspend()
        voice.stop(message: "")
        stopMotion()
        audio.setActive(false)
        cameraQueue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    @objc private func interrupted() {
        DispatchQueue.main.async {
            self.face.saw(nil)
            self.status.text = "相机暂时中断 · 返回后继续"
            self.status.isHidden = false
        }
    }

    @objc private func cameraError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
        showError(error?.localizedDescription ?? "相机运行错误")
    }

    private func startCamera() {
        do {
            if !configured {
                session.beginConfiguration()
                defer { session.commitConfiguration() }
                session.sessionPreset = .vga640x480
                guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                    throw NSError(domain: "DeskPet", code: 1, userInfo: [NSLocalizedDescriptionKey: "没有找到前置摄像头"])
                }
                let input = try AVCaptureDeviceInput(device: camera)
                guard session.canAddInput(input) else { throw cameraSetupError() }
                session.addInput(input)
                cameraDevice = camera
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
                output.setSampleBufferDelegate(self, queue: frameQueue)
                guard session.canAddOutput(output) else { throw cameraSetupError() }
                session.addOutput(output)
                orient(output.connection(with: .video))
                configured = true
            }
            configureCameraRate()
            if !session.isRunning { session.startRunning() }
            DispatchQueue.main.async { self.status.text = "在找你 · 摸摸屏幕试试" }
        } catch { showError(error.localizedDescription) }
    }

    private func cameraSetupError() -> NSError {
        NSError(domain: "DeskPet", code: 2, userInfo: [NSLocalizedDescriptionKey: "相机配置失败"])
    }

    @objc private func thermalChanged() {
        cameraQueue.async { self.configureCameraRate() }
    }

    private func configureCameraRate() {
        guard let camera = cameraDevice else { return }
        let fps = CaptureCadence.framesPerSecond(thermal: ProcessInfo.processInfo.thermalState.rawValue)
        guard camera.activeFormat.videoSupportedFrameRateRanges.contains(where: {
            $0.minFrameRate <= Double(fps) && $0.maxFrameRate >= Double(fps)
        }) else { print("DeskPet camera: requested rate unsupported"); return }
        do {
            try camera.lockForConfiguration()
            defer { camera.unlockForConfiguration() }
            let duration = CMTime(value: 1, timescale: Int32(fps))
            camera.activeVideoMinFrameDuration = duration
            camera.activeVideoMaxFrameDuration = duration
            print("DeskPet camera: captureFPS=\(fps)")
        } catch { print("DeskPet camera: rate configuration failed") }
    }

    private func showError(_ message: String) {
        DispatchQueue.main.async {
            self.face.saw(nil)
            self.status.text = message
            self.status.isHidden = false
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard now - lastFrame >= 0.04,
              let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = now
        // Mirror exactly once, then use the identical pixels for Vision and the preview.
        let image = CIImage(cvPixelBuffer: pixel).oriented(.upMirrored)
        let request = VNDetectFaceRectanglesRequest()
        let start = CACurrentMediaTime()
        do {
            try VNImageRequestHandler(ciImage: image, orientation: .up).perform([request])
            let faces = (request.results ?? []).filter { $0.confidence >= 0.5 }
            let chosen = faces.max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }
            let milliseconds = (CACurrentMediaTime() - start) * 1000
            let cameraFrame = wantsPreview ? imageContext.createCGImage(image, from: image.extent) : nil
            let size = image.extent.size
            DispatchQueue.main.async {
                guard UIApplication.shared.applicationState == .active else { return }
                self.lastFace = chosen?.boundingBox
                self.imageSize = size
                if self.diagnostic, let cameraFrame { self.preview.image = UIImage(cgImage: cameraFrame) }
                self.face.saw(self.lastFace)
                self.frameCount += 1
                self.detections += chosen == nil ? 0 : 1
                self.sampleMilliseconds = milliseconds
                self.rateFrames += 1
                if self.rateWindow == 0 { self.rateWindow = now }
                if now - self.rateWindow >= 2 {
                    self.processedFPS = Double(self.rateFrames - 1) / (now - self.rateWindow)
                    self.rateFrames = 1
                    self.rateWindow = now
                }
                self.status.text = chosen == nil ? "在找你 · 摸摸屏幕试试" : "看到你啦"
                self.updateDiagnostics(faceCount: faces.count)
            }
        } catch { showError("检测失败：\(error.localizedDescription)") }
    }

    private var thermal: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "正常"
        case .fair: return "温热"
        case .serious: return "较热·已降频"
        case .critical: return "过热·请暂停"
        @unknown default: return "未知"
        }
    }

    private func updateDiagnostics(faceCount: Int) {
        detail.text = String(format: "v0.7.0 · %.1f 帧/秒 · 检测 %.1f ms\n样本 %d / 命中 %d · 温度状态 %@\n状态 %@ · 同帧检测，本地处理", processedFPS, sampleMilliseconds, frameCount, detections, thermal, face.behavior.mood(now: CACurrentMediaTime()).rawValue)
        drawBox()
        let now = CACurrentMediaTime()
        if now - lastLog >= 10 {
            lastLog = now
            let line = String(format: "%.1f,%d,%d,%.2f,%d\n", Date().timeIntervalSince(started), frameCount, detections, sampleMilliseconds, ProcessInfo.processInfo.thermalState.rawValue)
            logLines += line
            print("DeskPet metrics: \(line.trimmingCharacters(in: .whitespacesAndNewlines))")
            print("DeskPet camera: processedFPS=\(self.processedFPS)")
            try? logLines.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }

    private func drawBox() {
        guard diagnostic, let box = lastFace else { faceBox.path = nil; return }
        faceBox.path = UIBezierPath(rect: Gaze.previewRect(for: box, imageSize: imageSize,
                                                         bounds: preview.bounds)).cgPath
    }

    @objc private func toggleDiagnostic() {
        diagnostic.toggle()
        let showPreview = diagnostic
        frameQueue.async { self.wantsPreview = showPreview }
        preview.isHidden = !diagnostic
        detail.isHidden = !diagnostic
        status.isHidden = !diagnostic
        updateMenu()
        drawBox()
    }

    private func updateMenu() {
        menuButton.menu = UIMenu(children: [
            UIAction(title: audio.muted ? "开启声音" : "静音", image: UIImage(systemName: audio.muted ? "speaker.wave.2" : "speaker.slash")) { [weak self] _ in
                guard let self else { return }
                self.audio.muted.toggle()
                if self.audio.muted { self.voice.stop(message: "已静音") }
                self.updateMenu()
                if !self.audio.muted && !self.voice.active { self.audio.play(.hello, now: CACurrentMediaTime()) }
            },
            UIAction(title: "AI 与 API Key 设置", image: UIImage(systemName: "key")) { [weak self] _ in self?.showVoiceSettings() },
            UIMenu(title: "中文音色试听", children: voice.chineseVoices.prefix(24).map { sound in
                UIAction(title: "\(sound.name) · \(sound.language)\(sound.quality.rawValue > 1 ? " · 增强" : "")") { [weak self] _ in self?.voice.previewVoice(sound.identifier) }
            }),
            UIAction(title: "本地唤醒：瓦力瓦力", state: voice.localWake ? .on : .off) { [weak self] _ in
                guard let self else { return }
                self.voice.localWake.toggle()
                if self.voice.localWake { self.voice.standby() }
                else { self.voice.stop(message: "本地唤醒已关闭，点麦克风聊天") }
                self.updateMenu()
            },
            UIAction(title: "全双工插话（测试版）", state: voice.duplex ? .on : .off) { [weak self] _ in
                guard let self else { return }
                self.voice.stop()
                self.voice.duplex.toggle()
                self.voice.resumeHandsFreeIfAuthorized()
                self.updateMenu()
            },
            UIAction(title: "苹果联网语音识别", state: voice.onlineRecognition ? .on : .off) { [weak self] _ in
                guard let self else { return }
                if self.voice.onlineRecognition {
                    self.voice.stop(message: "苹果联网识别已关闭")
                    self.voice.onlineRecognition = false
                    self.voice.resumeHandsFreeIfAuthorized()
                    self.updateMenu()
                    return
                }
                let prompt = UIAlertController(title: "允许联网识别？", message: "仅在本机中文识别不可用时，录音可能由苹果服务器识别。聊天文字会发送给你设置的 AI 服务；默认不上传相机画面。", preferredStyle: .alert)
                prompt.addAction(UIAlertAction(title: "取消", style: .cancel))
                prompt.addAction(UIAlertAction(title: "允许", style: .default) { _ in self.voice.onlineRecognition = true; self.updateMenu() })
                self.present(prompt, animated: true)
            },
            UIAction(title: "结束聊天", image: UIImage(systemName: "stop.circle")) { [weak self] _ in self?.voice.endConversation() },
            UIAction(title: "清除本次对话") { [weak self] _ in self?.voice.clearConversation() },
            UIAction(title: "拿起与倾斜感知", state: motionEnabled ? .on : .off) { [weak self] _ in
                guard let self else { return }
                self.motionEnabled.toggle()
                UserDefaults.standard.set(self.motionEnabled, forKey: "petMotionEnabled")
                if self.motionEnabled { self.startMotion() }
                else {
                    if self.motionFilter.moving { self.face.behavior.movement(began: false, now: CACurrentMediaTime()) }
                    self.stopMotion()
                }
                self.updateMenu()
            },
            UIAction(title: "怎么玩", image: UIImage(systemName: "hand.draw")) { [weak self] _ in
                let help = UIAlertController(title: "和小宠相处", message: "轻点：看向手指\n慢慢滑动：抚摸\n长按：安抚\n连续戳：害羞躲闪\n拿起、倾斜、放稳：动作回应\n离开一会儿：它会自己发呆、打瞌睡\n\n声音遵循手机静音开关，不会打断音乐。所有互动都可离线使用。", preferredStyle: .alert)
                help.addAction(UIAlertAction(title: "知道啦", style: .default))
                self?.present(help, animated: true)
            },
            UIAction(title: diagnostic ? "关闭诊断" : "打开诊断", image: UIImage(systemName: "viewfinder")) { [weak self] _ in self?.toggleDiagnostic() },
            UIAction(title: "导出运行记录", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                guard let self else { return }
                self.exportLog(self.menuButton)
            }
        ])
    }

    @objc private func chatMicrophone() {
        if VoiceKeychain.read().isEmpty { showVoiceSettings(); return }
        voice.microphone()
    }

    private func showVoiceSettings() {
        voice.stop(message: "")
        let saved = !VoiceKeychain.read().isEmpty
        let sheet = UIAlertController(title: "语音聊天设置", message: "\(saved ? "已保存 Key；留空保留原值。" : "填写你自己的 DeepSeek API Key。")\nKey 只存系统钥匙串。识别后的文字与最近对话将发送到下面的 HTTPS 服务。", preferredStyle: .alert)
        sheet.addTextField { field in
            field.placeholder = saved ? "API Key（留空保留）" : "API Key"
            field.isSecureTextEntry = true
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        sheet.addTextField { field in field.text = self.voice.base; field.placeholder = "HTTPS API 地址"; field.autocapitalizationType = .none; field.autocorrectionType = .no }
        sheet.addTextField { field in field.text = self.voice.model; field.placeholder = "模型名称"; field.autocapitalizationType = .none; field.autocorrectionType = .no }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        sheet.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak sheet] _ in
            guard let self, let fields = sheet?.textFields else { return }
            do {
                let address = fields[1].text ?? ""
                _ = try DeepSeekChat.endpoint(address)
                let model = (fields[2].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !model.isEmpty else { throw ChatFailure.invalidReply }
                try VoiceKeychain.save((fields[0].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                UserDefaults.standard.set(address, forKey: "petAPIBase")
                UserDefaults.standard.set(model, forKey: "petAPIModel")
                self.voiceLabel.text = "设置已保存 · 点右下角麦克风开始说话"
            } catch { self.voiceLabel.text = error.localizedDescription }
            self.voiceLabel.isHidden = false
        })
        if saved {
            sheet.addAction(UIAlertAction(title: "移除已保存的 Key", style: .destructive) { _ in VoiceKeychain.remove() })
        }
        present(sheet, animated: true)
    }

    private func startMotion() {
        guard motionEnabled, motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 0.1
        motion.startDeviceMotionUpdates(to: .main) { [weak self] sample, _ in
            guard let self, let sample, UIApplication.shared.applicationState == .active else { return }
            let now = CACurrentMediaTime()
            guard now >= self.ignoreMotionUntil else { return }
            let a = sample.userAcceleration
            let r = sample.rotationRate
            if let moving = self.motionFilter.update(acceleration: sqrt(a.x * a.x + a.y * a.y + a.z * a.z),
                                                    rotation: sqrt(r.x * r.x + r.y * r.y + r.z * r.z), now: now) {
                self.face.behavior.movement(began: moving, now: now)
            }
            self.face.tilt = CGFloat(max(-0.18, min(0.18, sample.gravity.y * 0.25)))
        }
    }

    private func stopMotion() {
        motion.stopDeviceMotionUpdates()
        motionFilter = PetMotionFilter()
        face.tilt = 0
    }

    private var logURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("deskpet-metrics.csv")
    }

    @objc private func exportLog(_ sender: UIButton) {
        do {
            try logLines.write(to: logURL, atomically: true, encoding: .utf8)
            let sheet = UIActivityViewController(activityItems: [logURL], applicationActivities: nil)
            sheet.popoverPresentationController?.sourceView = sender
            present(sheet, animated: true)
        } catch { status.text = "记录导出失败：\(error.localizedDescription)" }
    }
}
