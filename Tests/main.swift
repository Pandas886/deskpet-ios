import Foundation
import CoreGraphics

func centeredFace(_ x: CGFloat, _ y: CGFloat) -> CGRect {
    CGRect(x: x - 0.1, y: y - 0.1, width: 0.2, height: 0.2)
}

func near(_ x: CGFloat, _ y: CGFloat) -> Bool { abs(x - y) < 0.0001 }

let center = Gaze.target(for: centeredFace(0.5, 0.5))
assert(near(center.x, 0) && near(center.y, 0), "居中的脸应该直视")
assert(Gaze.target(for: centeredFace(0.2, 0.5)).x < 0, "画面左侧的脸应使眼睛向左")
assert(Gaze.target(for: centeredFace(0.8, 0.5)).x > 0, "画面右侧的脸应使眼睛向右")
assert(Gaze.target(for: centeredFace(0.5, 0.8)).y < 0, "Vision 上方的脸应使屏幕眼睛向上")
assert(Gaze.target(for: centeredFace(0.5, 0.2)).y > 0, "Vision 下方的脸应使屏幕眼睛向下")
let outside = Gaze.target(for: centeredFace(2, -2))
assert(near(outside.x, 1) && near(outside.y, 1), "超出范围的观测不能把眼睛推出边界")
let preview = Gaze.previewRect(for: CGRect(x: 0.1, y: 0.6, width: 0.2, height: 0.2),
                               imageSize: CGSize(width: 640, height: 480),
                               bounds: CGRect(x: 0, y: 0, width: 192, height: 108))
assert(near(preview.minX, 38.4), "同帧预览的人脸框不应再次左右镜像")
assert(near(preview.minY, 21.6), "人脸框应正确转换底部原点并考虑留边")
assert(near(preview.width, 28.8) && near(preview.height, 21.6), "人脸框尺寸应与等比预览一致")
print("通过：眼神方向、范围、同帧预览坐标与留边，共 9 项")

func soundCount(_ effects: [PetEffect]) -> Int {
    effects.filter { if case .sound = $0 { return true }; return false }.count
}

let pet = PetBehavior(now: 0)
let visitor = centeredFace(0.8, 0.5)
pet.observe(visitor, now: 0)
assert(soundCount(pet.takeEffects()) == 0, "路过一下不应立即发声")
pet.observe(visitor, now: 0.8)
assert(soundCount(pet.takeEffects()) == 1, "停留后应该欢迎一次")
pet.observe(visitor, now: 1)
assert(soundCount(pet.takeEffects()) == 0, "持续可见不能重复欢迎")
pet.observe(nil, now: 1.5)
pet.observe(visitor, now: 1.9)
assert(soundCount(pet.takeEffects()) == 0, "短暂漏检不能触发新一轮欢迎")
pet.observe(visitor, now: 5)
pet.observe(visitor, now: 5.8)
assert(soundCount(pet.takeEffects()) == 0, "短时间回来也应遵守欢迎间隔")
assert(pet.gaze(now: 7).x > 0, "离开后应短暂目送原来的方向")
assert(pet.mood(now: 42) == .sleepy, "无人互动足够久才打瞌睡")
pet.soothe(now: 43)
assert(pet.mood(now: 43.1) == .curious, "从睡眠被摸醒应先睁眼")
assert(pet.mood(now: 43.4) == .relaxed, "醒来后进入安抚状态")
_ = pet.takeEffects()
pet.stroke(now: 47)
assert(pet.mood(now: 47.1) == .happy, "抚摸应该开心")
assert(soundCount(pet.takeEffects()) == 1, "抚摸应有一次反馈")
pet.stroke(now: 47.2)
assert(soundCount(pet.takeEffects()) == 0, "连续手势不能疯狂触发音效")
pet.poke(now: 50)
assert(pet.mood(now: 50.1) == .curious, "第一次戳是好奇")
pet.poke(now: 50.5)
assert(pet.mood(now: 50.6) == .startled, "第二次戳变惊讶")
pet.poke(now: 51)
assert(pet.mood(now: 51.1) == .shy, "连续第三次戳会躲闪")
pet.stroke(now: 52)
assert(pet.mood(now: 52.1) == .happy, "抚摸可以安慰躲闪的小宠")
pet.movement(began: true, now: 55)
assert(pet.mood(now: 57) == .held, "移动持续时应保持被抱起反应")
pet.movement(began: false, now: 58)
assert(pet.mood(now: 58.1) == .settling, "放稳后缓和")
pet.resetPresence(now: 59)
assert(pet.mood(now: 59.1) == .calm && pet.takeEffects().isEmpty, "退出前台后不应残留声音或移动状态")
var motion = PetMotionFilter()
assert(motion.update(acceleration: 0.3, rotation: 0, now: 0) == nil, "单次撞击不能当作拿起")
assert(motion.update(acceleration: 0, rotation: 0, now: 0.1) == nil, "短暂震动应被过滤")
assert(motion.update(acceleration: 0.2, rotation: 0, now: 1) == nil)
assert(motion.update(acceleration: 0.2, rotation: 0, now: 1.3) == true, "持续移动应有一次拿起事件")
assert(motion.update(acceleration: 0.2, rotation: 0, now: 1.5) == nil, "移动中不能反复触发拿起")
assert(motion.update(acceleration: 0, rotation: 0, now: 2) == nil)
assert(motion.update(acceleration: 0, rotation: 0, now: 3.6) == false, "稳定一段时间再触发放稳")
print("通过：欢迎防抖与冷却、睡眠唤醒、抚摸安抚、连续戳、前后台重置、运动过滤")
let greetedWhileTouched = PetBehavior(now: 0)
greetedWhileTouched.observe(visitor, now: 0)
greetedWhileTouched.soothe(now: 0.5)
_ = greetedWhileTouched.takeEffects()
greetedWhileTouched.observe(visitor, now: 0.8)
assert(greetedWhileTouched.mood(now: 0.9) == .relaxed && greetedWhileTouched.takeEffects().isEmpty,
       "欢迎不能打断正在进行的安抚")
print("通过：欢迎与抚摸反应的优先级")

var turns = TurnGate()
let oldTurn = turns.next()
assert(turns.accepts(oldTurn))
let newTurn = turns.next()
assert(!turns.accepts(oldTurn) && turns.accepts(newTurn), "打断后必须丢弃旧回答")
var speech = SpeechEndpoint(now: 0)
assert(!speech.ready(now: 10), "没有语音文本不能提交空请求")
speech.update("你好", now: 1)
speech.lastVoice = 1.4
assert(!speech.ready(now: 2), "短暂停顿不应截断话语")
assert(speech.ready(now: 2.5), "语音和文本都稳定后可以提交")
speech.update("你好小瓦", now: 2.5)
assert(!speech.ready(now: 2.8), "转写仍在变化时不能提前发送")
let goodReply = try PetReply.parse(Data(#"{"speech":" 我在呢。 ","mood":"happy"}"#.utf8))
assert(goodReply.speech == "我在呢。" && goodReply.mood == "happy")
let unknownMood = try PetReply.parse(Data(#"{"speech":"我在","mood":"run_shell"}"#.utf8))
assert(unknownMood.mood == "calm", "未知情绪不能成为控制指令")
for invalid in [#"{"speech":"","mood":"calm"}"#, #"{"speech":"没有结束""#, #"{"mood":"happy"}"#] {
    do { _ = try PetReply.parse(Data(invalid.utf8)); assertionFailure("无效回答应被拒绝") }
    catch { }
}
let apiEndpoint = try DeepSeekChat.endpoint("https://api.deepseek.com")
assert(apiEndpoint.absoluteString == "https://api.deepseek.com/chat/completions")
for invalid in ["http://api.deepseek.com", "https://name:secret@example.com", "https://api.deepseek.com?key=bad"] {
    do { _ = try DeepSeekChat.endpoint(invalid); assertionFailure("不应接受不安全或混入凭据的地址") }
    catch { }
}
print("通过：对话取消、静音断句、回复校验、情绪白名单、HTTPS 地址约束")

assert(VoiceCommands.endsConversation(" 不聊了。 "), "自然口令应结束连续聊天")
assert(VoiceCommands.endsConversation("别说了！"), "结束口令应兼容标点")
assert(!VoiceCommands.endsConversation("为什么雨停止了？"), "普通句子不能被停止口令误拦")
assert(!VoiceCommands.endsConversation(""), "空白不能触发停止口令")
print("通过：连续聊天结束口令与普通语句区分，共 4 项")

assert(SpeechRecovery.shouldRetryOnline(onDevice: true, onlineAllowed: true), "本机失败含201，应在已获授权时回退联网")
assert(!SpeechRecovery.shouldRetryOnline(onDevice: true, onlineAllowed: false), "未允许联网时不能上传录音")
assert(!SpeechRecovery.shouldRetryOnline(onDevice: false, onlineAllowed: true), "联网请求失败不能无限重试")
print("通过：本机识别失败回退、联网授权与重试上限，共 3 项")

assert(ChatFailure.classify(URLError(.timedOut)) == .timeout)
assert(ChatFailure.classify(URLError(.notConnectedToInternet)) == .offline)
assert(ChatFailure.classify(URLError(.cannotFindHost)) == .dns)
assert(ChatFailure.classify(URLError(.serverCertificateUntrusted)) == .secureConnection)
assert(ChatFailure.classify(NSError(domain: "Test", code: 1)) == .unexpected)
for data in [Data("not json".utf8), Data(#"{"choices":[{"finish_reason":"stop","message":{"content":"{\"speech\":123,\"mood\":\"happy\"}"}}]}"#.utf8)] {
    do { _ = try DeepSeekChat.decodeResponse(data, statusCode: 200); assertionFailure("无效回答应被拒绝") }
    catch { assert((error as? ChatFailure) == .invalidReply, "解析错误不能误报网络失败") }
}

final class MockChatProtocol: URLProtocol {
    static var calls = 0
    static var handler: ((Int) -> Result<(Int, Data), Error>)!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.calls += 1
        switch Self.handler(Self.calls) {
        case .success(let (status, data)):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error): client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() { }
}

let mockConfiguration = URLSessionConfiguration.ephemeral
mockConfiguration.protocolClasses = [MockChatProtocol.self]
let mockSession = URLSession(configuration: mockConfiguration)
let mockGood = Data(#"{"choices":[{"finish_reason":"stop","message":{"content":"{\"speech\":\"我在\",\"mood\":\"happy\"}"}}]}"#.utf8)
func testReply() async throws -> PetReply {
    try await DeepSeekChat.reply(text: "你好", context: "测试", history: [], key: "test-key",
                                base: "https://unit.invalid", model: "test", session: mockSession)
}
MockChatProtocol.calls = 0
MockChatProtocol.handler = { attempt in
    attempt == 1 ? .failure(URLError(.networkConnectionLost)) : .success((200, mockGood))
}
let retriedReply = try await testReply()
assert(retriedReply.speech == "我在" && MockChatProtocol.calls == 2, "断连应在一次重试后得到有效回答")
MockChatProtocol.calls = 0
MockChatProtocol.handler = { _ in .failure(URLError(.networkConnectionLost)) }
do { _ = try await testReply(); assertionFailure("重复断连应报错") }
catch { assert((error as? ChatFailure) == .network && MockChatProtocol.calls == 2, "最多重试一次") }
MockChatProtocol.calls = 0
MockChatProtocol.handler = { _ in .failure(URLError(.timedOut)) }
do { _ = try await testReply(); assertionFailure("超时应单独报告") }
catch { assert((error as? ChatFailure) == .timeout && MockChatProtocol.calls == 1, "超时不应再次长时间等待") }
MockChatProtocol.calls = 0
MockChatProtocol.handler = { _ in .success((500, Data())) }
do { _ = try await testReply(); assertionFailure("服务错误应单独报告") }
catch { assert((error as? ChatFailure) == .server && MockChatProtocol.calls == 1, "HTTP错误不能作为传输断连重试") }
mockSession.invalidateAndCancel()
print("通过：URLSession 模拟传输的断连恢复、重试上限、超时与服务错误分类，解析异常不误报网络")

let emptyEnvelope = Data(#"{"choices":[{"finish_reason":"stop","message":{"content":""}}]}"#.utf8)
MockChatProtocol.calls = 0
MockChatProtocol.handler = { attempt in .success((200, attempt == 1 ? emptyEnvelope : mockGood)) }
let emptyConfiguration = URLSessionConfiguration.ephemeral
emptyConfiguration.protocolClasses = [MockChatProtocol.self]
let emptySession = URLSession(configuration: emptyConfiguration)
let recoveredEmpty = try await DeepSeekChat.reply(text: "再说一个", context: "测试", history: [], key: "test-key",
                                                base: "https://unit.invalid", model: "test", session: emptySession)
assert(recoveredEmpty.speech == "我在" && MockChatProtocol.calls == 2, "HTTP200空内容应只重试一次并恢复")
MockChatProtocol.calls = 0
MockChatProtocol.handler = { _ in .success((200, emptyEnvelope)) }
do {
    _ = try await DeepSeekChat.reply(text: "你好", context: "测试", history: [], key: "test-key",
                                    base: "https://unit.invalid", model: "test", session: emptySession)
    assertionFailure("持续空内容应报错")
} catch { assert((error as? ChatFailure) == .emptyReply && MockChatProtocol.calls == 2, "持续空内容不能误报网络或无限重试") }
emptySession.invalidateAndCancel()
print("通过：JSON模式空内容恢复与重试上限")

var wakeGain = WakeAudioGain()
let quietWave = (0..<1024).map { Float(sin(Double($0) * 0.2)) * 0.0005 }
var amplified = quietWave
for _ in 0..<20 { amplified = wakeGain.process(quietWave, sampleRate: 16000) }
assert(wakeGain.gain > 10 && wakeGain.gain <= 16, "轻声收音应有受限增益，不靠降低唤醒阈值")
assert(abs(amplified[10]) > abs(quietWave[10]) * 10, "轻声波形应实际得到补偿")
let suddenLoud = wakeGain.process([0.9, -0.9, 0.2, -0.2], sampleRate: 16000)
assert(suddenLoud.allSatisfy { abs($0) <= 0.951 }, "突然靠近麦克风不能导致削波")
assert(suddenLoud[0] > 0 && suddenLoud[1] < 0, "限幅不能改变波形极性")
assert(wakeGain.process([Float](repeating: 0, count: 1024), sampleRate: 16000).allSatisfy { $0 == 0 }, "静音不能凭空产生声音")
assert(wakeGain.process([], sampleRate: 16000).isEmpty, "空缓冲不应引发除零")
print("通过：唤醒轻声增益、增益上限、突然大声不削波、静音和空缓冲")

var duplexGate = DuplexGate()
duplexGate.startReply("今天阳光很好，我们来聊聊你的桌面小宠吧。")
for i in 0..<8 { _ = duplexGate.observe(0.03, now: Double(i) * 0.03, playing: true) }
assert(duplexGate.candidate("今", now: 0.24, requireVoice: true) == nil, "回声的第一个字也不能抢先触发插话")
assert(duplexGate.candidate("今天阳光很好", now: 0.25, requireVoice: true) == nil, "持续回声即使有能量也不能触发插话")
assert(duplexGate.candidate("今天阳光很好，等等换个话题", now: 0.3, requireVoice: true) == "等等换个话题", "识别累计的回声前缀应去掉，保留插话开头")
duplexGate.finishReply(now: 0.35)
assert(duplexGate.candidate("今天阳光很好", now: 0.7, requireVoice: false) == nil, "播完后的回声尾音不能成为新问题")
assert(duplexGate.candidate("今天天气怎么样", now: 1.5, requireVoice: false) == "今天天气怎么样", "正常接话应保留完整文字")

var noiseGate = DuplexGate()
noiseGate.startReply("我会继续讲这个故事")
assert(!noiseGate.observe(0.08, now: 0, playing: true), "单次敲击不能降低朗读音量")
_ = noiseGate.observe(0.0001, now: 0.04, playing: true)
assert(noiseGate.candidate("等等", now: 0.1, requireVoice: true) == nil, "没有持续语音证据不能取消回复")
for i in 0..<10 { _ = noiseGate.observe(0.015, now: 0.2 + Double(i) * 0.03, playing: true) }
assert(noiseGate.observe(0.015, now: 0.5, playing: true), "正常近端语音应先降低播放音量")
assert(noiseGate.candidate("别说了", now: 1, requireVoice: true) == "别说了", "短句结束后的识别延迟不能清除插话证据")
assert(!noiseGate.observe(0.0001, now: 1.2, playing: true), "未确认的短噪声应恢复音量")
assert(noiseGate.candidate("错误转写", now: 2, requireVoice: true) == nil, "旧语音证据不能无限触发新插话")
for i in 0..<70 { _ = noiseGate.observe(0.03, now: 3 + Double(i) * 0.03, playing: true) }
assert(!noiseGate.observe(0.03, now: 5.2, playing: true), "持续无文字噪声不能永久压低朗读音量")
print("通过：回声过滤、回声尾音、插话首字保留、短噪声、延迟转写和音量恢复")

var quietDuplex = DuplexGate()
quietDuplex.startReply("我继续说，你可以插话")
for i in 0..<24 {
    let rms: Float = i % 6 == 5 ? 0.0001 : 0.002
    _ = quietDuplex.observe(rms, now: Double(i) * 0.02, playing: true)
}
assert(quietDuplex.candidate("等等换个话题", now: 0.5, requireVoice: true) == "等等换个话题", "XR 实测音量的正常插话不能因音节间隙或旧固定门槛被丢弃")
print("通过：低音量插话与音节短暂停顿的回归样本")
