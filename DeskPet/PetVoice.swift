import UIKit
import AVFoundation
import Speech

final class PetVoice {
    enum State { case idle, armed, listening, waiting, speaking }
    var onUpdate: ((State, String) -> Void)?
    var onMood: ((PetMood) -> Void)?
    var context: (() -> String)?
    var onOwnership: ((Bool, @escaping () -> Void) -> Void)?
    private(set) var state: State = .idle
    var active: Bool { state != .idle || audioRunning }
    var duplex: Bool {
        get { UserDefaults.standard.object(forKey: "petDuplex") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "petDuplex") }
    }
    var onlineRecognition: Bool {
        get { UserDefaults.standard.bool(forKey: "petOnlineRecognition") }
        set { UserDefaults.standard.set(newValue, forKey: "petOnlineRecognition") }
    }
    var localWake: Bool {
        get { UserDefaults.standard.object(forKey: "petLocalWake") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "petLocalWake") }
    }
    var base: String { UserDefaults.standard.string(forKey: "petAPIBase") ?? "https://api.deepseek.com" }
    var model: String { UserDefaults.standard.string(forKey: "petAPIModel") ?? "deepseek-flash" }
    var chineseVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("zh") }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
    }
    var defaultChineseVoice: AVSpeechSynthesisVoice? {
        chineseVoices.first { $0.language == "zh-CN" && $0.name.localizedCaseInsensitiveContains("Rocko") } ??
            chineseVoices.first { $0.language == "zh-CN" } ?? AVSpeechSynthesisVoice(language: "zh-CN")
    }
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let synthesizer = AVSpeechSynthesizer()
    private let renderFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let wake = PetWakeWord()
    private var sessionOpen = false
    private let inputLock = NSLock()
    private var inputRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var recognitionID = UUID()
    private var preferOnlineRecognition = false
    private var timer: Timer?
    private var endpoint = SpeechEndpoint(now: 0)
    private var turn = TurnGate()
    private var task: Task<Void, Never>?
    private var history: [ChatMessage] = []
    private var audioRunning = false
    private var tapInstalled = false
    private var speakingID = UUID()
    private var pendingBuffers = 0
    private var synthesisFinished = false
    private var spokenText = ""
    private var duplexGate = DuplexGate()
    private var recognitionRecoveries = 0
    private var levelLogged: TimeInterval = 0
    private var peakInput: Float = 0
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?

    init() {
        wake.onWake = { [weak self] in
            guard let self, self.state == .armed, UIApplication.shared.applicationState == .active else { return }
            do { try self.startAudio(recording: true) }
            catch { self.stop(message: "聊天麦克风启动失败，请点麦克风重试"); return }
            self.sessionOpen = true
            self.wake.setArmed(false)
            self.spokenText = ""
            self.update(.speaking, "我在，你说")
            self.onMood?(.happy)
            self.speak("我在，你说")
        }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: renderFormat)
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
                                                                       object: nil, queue: .main) { [weak self] note in
            guard let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  type == AVAudioSession.InterruptionType.began.rawValue else { return }
            print("DeskPet voice: audio interrupted")
            self?.stop(message: "声音被系统中断，点麦克风重新开始")
        }
        routeObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification,
                                                               object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            self?.stop(message: "音频设备已断开，点麦克风重新开始")
        }
    }

    func microphone() {
        if state == .listening { sendRecognized(); return }
        guard !VoiceKeychain.read().isEmpty else { stop(message: ChatFailure.missingKey.localizedDescription); return }
        sessionOpen = true
        wake.setArmed(false)
        let ticket = turn.next()
        task?.cancel()
        cancelSpeech()
        authorize { [weak self] error in
            guard let self else { return }
            guard self.turn.accepts(ticket), UIApplication.shared.applicationState == .active else {
                if error == nil { self.update(.idle, "权限已允许 · 点麦克风开始说话") }
                return
            }
            if let error { self.stop(message: error); return }
            self.claimAudio {
                guard self.turn.accepts(ticket) else { return }
                do {
                    try self.startAudio(recording: true)
                    self.listen()
                } catch { self.stop(message: "麦克风启动失败：\(error.localizedDescription)") }
            }
        }
    }

    func sendText(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        if VoiceCommands.endsConversation(cleaned) { endConversation(); return }
        guard !VoiceKeychain.read().isEmpty else { stop(message: ChatFailure.missingKey.localizedDescription); return }
        let ticket = turn.next()
        task?.cancel()
        cancelRecognition()
        cancelSpeech()
        timer?.invalidate()
        update(.waiting, "你：\(cleaned)\n正在想…")
        onMood?(.curious)
        if duplex && sessionOpen && tapInstalled {
            endpoint = SpeechEndpoint(now: CACurrentMediaTime())
            recognitionRecoveries = 0
            beginRecognition()
            startEndpointTimer()
        }
        let savedHistory = history
        history.append(ChatMessage(role: "user", content: cleaned))
        history = Array(history.suffix(12))
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let reply = try await DeepSeekChat.reply(text: cleaned, context: self.context?() ?? "平静陪伴",
                                                        history: savedHistory, key: VoiceKeychain.read(),
                                                        base: self.base, model: self.model)
                guard !Task.isCancelled, self.turn.accepts(ticket), UIApplication.shared.applicationState == .active else { return }
                self.onMood?(PetMood(rawValue: reply.mood) ?? .calm)
                self.update(.speaking, reply.speech)
                self.spokenText = reply.speech
                if UserDefaults.standard.bool(forKey: "petMuted") {
                    self.history.append(ChatMessage(role: "assistant", content: reply.speech))
                    self.continueListening()
                } else {
                    self.claimAudio {
                        guard self.turn.accepts(ticket) else { return }
                        do {
                            if !self.engine.isRunning { try self.startAudio(recording: true) }
                            self.speak(reply.speech)
                        } catch { self.stop(message: "朗读暂不可用，文字回答：\(reply.speech)") }
                    }
                }
            } catch {
                guard !Task.isCancelled, self.turn.accepts(ticket) else { return }
                let message = ChatFailure.classify(error).localizedDescription
                if self.localWake { self.standby(notice: message + "\n叫「瓦力瓦力」可继续") }
                else { self.stop(message: message) }
            }
        }
    }

    func stop(message: String = "已结束聊天") {
        if !message.isEmpty { print("DeskPet voice stop: \(message)") }
        sessionOpen = false
        wake.setArmed(false)
        _ = turn.next()
        task?.cancel()
        task = nil
        timer?.invalidate()
        cancelRecognition()
        cancelSpeech()
        releaseAudio()
        update(.idle, message)
    }

    func resumeHandsFreeIfAuthorized() {
        guard localWake, state == .idle, !audioRunning, !VoiceKeychain.read().isEmpty,
              AVAudioApplication.shared.recordPermission == .granted,
              SFSpeechRecognizer.authorizationStatus() == .authorized else { return }
        standby()
    }

    func endConversation() {
        if localWake { standby() }
        else { stop() }
    }

    func standby(notice: String? = nil) {
        stop(message: "")
        guard localWake, !VoiceKeychain.read().isEmpty,
              UIApplication.shared.applicationState == .active else { return }
        let ticket = turn.id
        update(.waiting, "正在准备本地唤醒…")
        authorize(checkAvailability: false) { [weak self] error in
            guard let self, self.turn.accepts(ticket), UIApplication.shared.applicationState == .active else { return }
            if let error { self.stop(message: error); return }
            self.wake.prepare { [weak self] ready in
                guard let self, self.turn.accepts(ticket), self.localWake,
                      UIApplication.shared.applicationState == .active else { return }
                guard ready else { self.stop(message: "本地唤醒模型不可用，仍可点麦克风聊天"); return }
                self.claimAudio {
                    guard self.turn.accepts(ticket) else { return }
                    do {
                        try self.startAudio(recording: true, wakeOnly: true)
                        self.update(.armed, notice ?? "叫「瓦力瓦力」· 本地待唤醒")
                        self.wake.setArmed(true)
                    } catch {
                        print("DeskPet wake setup failure: \(error as NSError)")
                        self.stop(message: "唤醒麦克风暂不可用，请点麦克风重试")
                    }
                }
            }
        }
    }

    func clearConversation() { stop(message: "本次对话已清除"); history.removeAll() }

    func previewVoice(_ id: String) {
        stop(message: "音色试听")
        UserDefaults.standard.set(id, forKey: "petVoiceID")
        let ticket = turn.id
        claimAudio { [weak self] in
            guard let self, self.turn.accepts(ticket) else { return }
            do {
                try self.startAudio(recording: true)
                self.spokenText = ""
                self.update(.speaking, "正在试听中文音色")
                self.speak("我在这里呀。摸摸我的脑袋，或者和我聊聊今天的事。")
            } catch { self.stop(message: "音色试听失败，请尝试其他声音") }
        }
    }

    #if DEBUG
    func testDuplex() {
        stop(message: "全双工真机测试")
        duplex = true
        sessionOpen = true
        let ticket = turn.id
        authorize { [weak self] error in
            guard let self, self.turn.accepts(ticket) else { return }
            if let error { self.stop(message: error); return }
            self.claimAudio {
                guard self.turn.accepts(ticket) else { return }
                do {
                    try self.startAudio(recording: true)
                    let text = "现在是语音插话测试。我会用平时的声音说一段话。你可以保持安静，看看我会不会被自己的声音打断。也可以在我说话的时候，用正常聊天的音量，直接提出一个新问题。不用再叫唤醒词，也不用按麦克风。"
                    self.spokenText = text
                    self.update(.speaking, "全双工测试 · 可直接插话")
                    self.speak(text)
                } catch { self.stop(message: "全双工测试音频启动失败") }
            }
        }
    }
    #endif

    private func authorize(checkAvailability: Bool = true, _ done: @escaping (String?) -> Void) {
        AVAudioApplication.requestRecordPermission { mic in
            guard mic else { DispatchQueue.main.async { done("请在系统设置中允许麦克风") }; return }
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    guard status == .authorized else { done("请在系统设置中允许语音识别"); return }
                    guard let recognizer = self.recognizer, !checkAvailability || recognizer.isAvailable else { done("中文语音识别目前不可用，请检查系统语言与网络"); return }
                    guard !checkAvailability || recognizer.supportsOnDeviceRecognition || self.onlineRecognition else {
                        done("本机中文识别不可用，请在菜单开启苹果联网识别后再点麦克风")
                        return
                    }
                    done(nil)
                }
            }
        }
    }

    private func claimAudio(_ done: @escaping () -> Void) {
        if audioRunning { done(); return }
        onOwnership?(true, done)
    }

    private func startAudio(recording: Bool, wakeOnly: Bool = false) throws {
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        let session = AVAudioSession.sharedInstance()
        if recording {
            try session.setCategory(.playAndRecord, mode: wakeOnly ? .measurement : .voiceChat, options: [.defaultToSpeaker])
        } else { try session.setCategory(.ambient, mode: .default) }
        try session.setActive(true)
        if engine.inputNode.isVoiceProcessingEnabled != (recording && !wakeOnly) {
            try engine.inputNode.setVoiceProcessingEnabled(recording && !wakeOnly)
        }
        if recording {
            let format = engine.inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw ChatFailure.server }
            if tapInstalled { engine.inputNode.removeTap(onBus: 0) }
            engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let self else { return }
                self.inputLock.lock()
                self.inputRequest?.append(buffer)
                self.inputLock.unlock()
                guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
                self.wake.accept(samples, count: Int(buffer.frameLength), sampleRate: buffer.format.sampleRate)
                var sum: Float = 0
                for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
                let rms = sqrt(sum / Float(buffer.frameLength))
                DispatchQueue.main.async { self.receiveLevel(rms) }
            }
            tapInstalled = true
        }
        engine.prepare()
        try engine.start()
        audioRunning = true
        print("DeskPet audio: engine started, recording=\(recording), wakeOnly=\(wakeOnly), mode=\(session.mode.rawValue), voiceProcessing=\(engine.inputNode.isVoiceProcessingEnabled)")
    }

    private func releaseAudio() {
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        engine.stop()
        audioRunning = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        onOwnership?(false, {})
    }

    private func listen() {
        wake.setArmed(false)
        update(.listening, "我在听 · 说完停顿即可")
        onMood?(.curious)
        endpoint = SpeechEndpoint(now: CACurrentMediaTime())
        duplexGate = DuplexGate()
        recognitionRecoveries = 0
        beginRecognition()
        startEndpointTimer()
    }

    private func startEndpointTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in self?.checkEndpoint() }
    }

    private func beginRecognition(forceOnline: Bool = false) {
        cancelRecognition()
        duplexGate.resetRecognition()
        let ticket = recognitionID
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = !forceOnline && !(preferOnlineRecognition && onlineRecognition) &&
            recognizer?.supportsOnDeviceRecognition == true
        print("DeskPet recognition: onDevice=\(request.requiresOnDeviceRecognition), onlineAllowed=\(onlineRecognition)")
        inputLock.lock(); inputRequest = request; inputLock.unlock()
        recognition = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.recognitionID == ticket else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    print("DeskPet ASR: state=\(self.state), characters=\(text.count), final=\(result.isFinal)")
                    let now = CACurrentMediaTime()
                    let interrupting = self.state == .speaking || self.state == .waiting
                    if (self.state == .listening || (self.duplex && self.sessionOpen && interrupting)),
                       let candidate = self.duplexGate.candidate(text, now: now, requireVoice: interrupting) {
                        if interrupting {
                            _ = self.turn.next()
                            self.task?.cancel()
                            self.task = nil
                            self.cancelSpeech()
                            self.duplexGate.finishReply(now: now)
                            self.spokenText = ""
                            self.endpoint = SpeechEndpoint(now: now)
                            self.onMood?(.curious)
                            print("DeskPet duplex: confirmed interruption")
                        }
                        self.endpoint.update(candidate, now: now)
                        self.update(.listening, "你：\(candidate)")
                        if result.isFinal { self.sendRecognized() }
                    } else if result.isFinal && self.state != .idle && self.state != .armed {
                        self.beginRecognition(forceOnline: !request.requiresOnDeviceRecognition)
                    }
                }
                guard self.recognitionID == ticket else { return }
                if let error, self.sessionOpen && (self.state == .listening || self.state == .speaking || self.state == .waiting) {
                    let failure = error as NSError
                    print("DeskPet recognition failure: \(failure.domain) / \(failure.code), local=\(request.requiresOnDeviceRecognition)")
                    if self.state == .listening && !self.endpoint.text.isEmpty { self.sendRecognized() }
                    else if SpeechRecovery.shouldRetryOnline(onDevice: request.requiresOnDeviceRecognition,
                                                            onlineAllowed: self.onlineRecognition) {
                        // Error 201 can occur for the local service even while Settings shows Dictation enabled.
                        self.preferOnlineRecognition = true
                        if self.state == .listening { self.update(.listening, "我在听 · 使用苹果联网识别") }
                        self.beginRecognition(forceOnline: true)
                    } else if self.recognitionRecoveries < 2 {
                        self.recognitionRecoveries += 1
                        self.cancelRecognition()
                        let recoveryTicket = self.recognitionID
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4 * Double(self.recognitionRecoveries)) { [weak self] in
                            guard let self, self.sessionOpen, self.recognitionID == recoveryTicket,
                                  UIApplication.shared.applicationState == .active else { return }
                            self.beginRecognition(forceOnline: !request.requiresOnDeviceRecognition)
                        }
                    } else if failure.domain == "kLSRErrorDomain" && failure.code == 201 {
                        self.stop(message: "苹果语音识别服务暂不可用（201），当前无法判断系统设置状态。\(self.onlineRecognition ? "请稍后再试" : "可在菜单允许苹果联网识别后重试")")
                    } else {
                        self.stop(message: "语音识别未能启动（\(failure.code)）。\(request.requiresOnDeviceRecognition ? "可在菜单允许苹果联网识别后重试" : "请检查系统语音识别和网络")")
                    }
                }
            }
        }
    }

    private func cancelRecognition() {
        recognitionID = UUID()
        inputLock.lock()
        inputRequest?.endAudio()
        inputRequest = nil
        inputLock.unlock()
        recognition?.cancel()
        recognition = nil
    }

    private func receiveLevel(_ rms: Float) {
        let now = CACurrentMediaTime()
        guard state == .listening || (sessionOpen && duplex && (state == .speaking || state == .waiting)) else { return }
        let duck = duplexGate.observe(rms, now: now, playing: state == .speaking)
        if duplexGate.voiceActive { endpoint.lastVoice = now }
        player.volume = duck ? 0.2 : 1
        peakInput = max(peakInput, rms)
        if now - levelLogged > 2 {
            print("DeskPet duplex input: peak=\(peakInput), threshold=\(duplexGate.threshold), duck=\(duck), state=\(state)")
            peakInput = 0
            levelLogged = now
        }
    }

    private func checkEndpoint() {
        guard state == .listening else { return }
        let now = CACurrentMediaTime()
        if endpoint.ready(now: now) || now - endpoint.started > 20 {
            sendRecognized()
        } else if endpoint.text.isEmpty && now - endpoint.started > 8 {
            endConversation()
        }
    }

    private func sendRecognized() {
        let text = endpoint.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            if CACurrentMediaTime() - endpoint.started < 2 {
                update(.listening, "正在听，请直接说话…")
            } else { endConversation() }
            return
        }
        sendText(text)
    }

    private func speak(_ text: String) {
        cancelSpeech()
        let ticket = speakingID
        pendingBuffers = 0
        synthesisFinished = false
        let utterance = AVSpeechUtterance(string: text)
        if let id = UserDefaults.standard.string(forKey: "petVoiceID"), let voice = AVSpeechSynthesisVoice(identifier: id) {
            utterance.voice = voice
        } else { utterance.voice = defaultChineseVoice }
        #if DEBUG
        print("DeskPet TTS voice: \(utterance.voice?.name ?? "unknown") / \(utterance.voice?.language ?? "unknown")")
        #endif
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.94
        if duplex && tapInstalled && sessionOpen {
            endpoint = SpeechEndpoint(now: CACurrentMediaTime())
            duplexGate.startReply(text)
            beginRecognition()
            startEndpointTimer()
        }
        synthesizer.write(utterance) { [weak self] buffer in
            DispatchQueue.main.async {
                guard let self, ticket == self.speakingID, self.engine.isRunning else { return }
                guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
                    self.synthesisFinished = true
                    self.finishSpeakingIfReady()
                    return
                }
                do {
                    let rendered = try self.convert(pcm)
                    self.pendingBuffers += 1
                    self.player.scheduleBuffer(rendered, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                        DispatchQueue.main.async {
                            guard let self, ticket == self.speakingID else { return }
                            self.pendingBuffers -= 1
                            self.finishSpeakingIfReady()
                        }
                    }
                    if !self.player.isPlaying { self.player.play() }
                } catch { self.stop(message: "朗读转换失败，可换一个中文音色") }
            }
        }
    }

    private func convert(_ input: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard let converter = AVAudioConverter(from: input.format, to: renderFormat),
              let output = AVAudioPCMBuffer(pcmFormat: renderFormat,
                                           frameCapacity: AVAudioFrameCount(Double(input.frameLength) * 48000 / input.format.sampleRate) + 64)
        else { throw ChatFailure.server }
        var provided = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if provided { status.pointee = .endOfStream; return nil }
            provided = true
            status.pointee = .haveData
            return input
        }
        if let error { throw error }
        return output
    }

    private func finishSpeakingIfReady() {
        guard synthesisFinished, pendingBuffers == 0, state == .speaking else { return }
        if !spokenText.isEmpty { history.append(ChatMessage(role: "assistant", content: spokenText)) }
        spokenText = ""
        if duplex && sessionOpen && recognition != nil {
            duplexGate.finishReply(now: CACurrentMediaTime())
            endpoint = SpeechEndpoint(now: CACurrentMediaTime())
            update(.listening, "你接着说，我在听…")
            return
        }
        cancelRecognition()
        timer?.invalidate()
        continueListening()
    }

    private func continueListening() {
        guard sessionOpen, tapInstalled, engine.isRunning else {
            releaseAudio()
            update(.idle, "点麦克风开始聊天")
            resumeHandsFreeIfAuthorized()
            return
        }
        if duplex && recognition != nil {
            endpoint = SpeechEndpoint(now: CACurrentMediaTime())
            update(.listening, "你接着说，我在听…")
            return
        }
        // Let the last loudspeaker samples drain before opening the next recognition request.
        let ticket = turn.id
        update(.waiting, "你接着说，我在听…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.sessionOpen, self.turn.accepts(ticket),
                  UIApplication.shared.applicationState == .active else { return }
            self.listen()
        }
    }

    private func cancelSpeech() {
        speakingID = UUID()
        synthesizer.stopSpeaking(at: .immediate)
        player.stop()
        player.volume = 1
        pendingBuffers = 0
        synthesisFinished = false
    }

    private func update(_ next: State, _ text: String) {
        state = next
        print("DeskPet voice state: \(next)")
        onUpdate?(next, text)
    }
}
