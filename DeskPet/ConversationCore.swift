import Foundation

struct PetReply: Decodable {
    let speech: String
    let mood: String

    static func parse(_ data: Data) throws -> PetReply {
        guard !String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("DeskPet reply schema: empty content")
            throw ChatFailure.emptyReply
        }
        let reply: PetReply
        do { reply = try JSONDecoder().decode(PetReply.self, from: data) }
        catch {
            if case DecodingError.keyNotFound(let key, _) = error {
                print("DeskPet reply schema: missing field=\(key.stringValue)")
            } else if case DecodingError.typeMismatch(_, let context) = error {
                print("DeskPet reply schema: wrong type at=\(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            } else { print("DeskPet reply schema: invalid JSON or null field") }
            throw ChatFailure.invalidReply
        }
        let speech = reply.speech.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !speech.isEmpty, speech.count <= 500 else {
            print("DeskPet reply schema: speech length=\(speech.count)")
            throw ChatFailure.invalidReply
        }
        let allowed = ["calm", "curious", "happy", "relaxed", "sleepy"]
        return PetReply(speech: speech, mood: allowed.contains(reply.mood) ? reply.mood : "calm")
    }
}

struct TurnGate {
    private(set) var id = UUID()
    mutating func next() -> UUID { id = UUID(); return id }
    func accepts(_ ticket: UUID) -> Bool { id == ticket }
}

struct SpeechEndpoint {
    var text = ""
    var started: TimeInterval
    var changed: TimeInterval
    var lastVoice: TimeInterval

    init(now: TimeInterval) { started = now; changed = now; lastVoice = now }

    mutating func update(_ value: String, now: TimeInterval) {
        if value != text { text = value; changed = now }
    }

    func ready(now: TimeInterval) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        now - changed > 0.8 && now - lastVoice > 0.9
    }
}

enum ChatFailure: LocalizedError, Equatable {
    case missingKey, invalidAddress, invalidReply, invalidRequest, unauthorized, limited, server, network
    case timeout, offline, dns, secureConnection, unexpected, emptyReply
    var errorDescription: String? {
        switch self {
        case .missingKey: return "请先在语音设置里填写 DeepSeek API Key"
        case .invalidAddress: return "API 地址需要是没有账号密码的 HTTPS 地址"
        case .invalidReply: return "这次回答没有接完整，请再试一次"
        case .unauthorized: return "API Key 无效或没有权限，请检查语音设置"
        case .limited: return "额度不足或请求太频繁，请稍后重试"
        case .server: return "AI 服务暂时不可用，请稍后重试"
        case .network: return "连接 AI 服务时中断，请稍后再试"
        case .invalidRequest: return "AI 服务未接受请求，请检查模型和地址设置"
        case .timeout: return "AI 回应超时，请稍后再试"
        case .offline: return "手机当前无法联网，请检查 Wi-Fi 或蜂窝网络"
        case .dns: return "手机无法找到 AI 服务地址，请检查网络或 API 地址"
        case .secureConnection: return "无法与 AI 服务建立安全连接"
        case .emptyReply: return "AI 这次没有返回内容，请再试一次"
        case .unexpected: return "处理 AI 回答时发生异常，请再试一次"
        }
    }
}

extension ChatFailure {
    static func classify(_ error: Error) -> ChatFailure {
        if let failure = error as? ChatFailure { return failure }
        if error is DecodingError { return .invalidReply }
        let failure = error as NSError
        guard failure.domain == NSURLErrorDomain else { return .unexpected }
        switch URLError.Code(rawValue: failure.code) {
        case .timedOut: return .timeout
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff: return .offline
        case .cannotFindHost, .dnsLookupFailed: return .dns
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
             .clientCertificateRejected, .clientCertificateRequired: return .secureConnection
        case .cannotDecodeRawData, .cannotDecodeContentData, .badServerResponse: return .invalidReply
        case .networkConnectionLost, .cannotConnectToHost: return .network
        default: return .unexpected
        }
    }
}

struct ChatMessage: Codable {
    let role: String
    let content: String
}

enum DeepSeekChat {
    static func endpoint(_ base: String) throws -> URL {
        guard let url = URL(string: base.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { throw ChatFailure.invalidAddress }
        return url.appendingPathComponent("chat/completions")
    }

    static func reply(text: String, context: String, history: [ChatMessage], key: String,
                      base: String, model: String, session: URLSession = .shared) async throws -> PetReply {
        guard !key.isEmpty else { throw ChatFailure.missingKey }
        var request = URLRequest(url: try endpoint(base))
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let personality = """
        你是住在桌面上的机械小宠，温和、好奇、稍微俏皮。说自然中文，通常一两句话。
        不用列表，不输出Markdown，不每句卖萌，不总反问，不声称能执行尚未实现的功能。
        不编造共同经历、身份或用户情绪。知道的只有本次对话和下方真实状态。
        用户要详细解释时可以多说一点，但总长度不超过200个汉字。
        每次都必须返回非空JSON对象，仅包含speech（非空字符串）和mood（calm/curious/happy/relaxed/sleepy）。
        格式示例：{"speech":"我在呢。","mood":"calm"}。后续追问也必须保持这个结构。
        """
        let prior = try history.suffix(12).map { message -> ChatMessage in
            guard message.role == "assistant" else { return message }
            // Keep prior assistant turns in the same format requested for the next reply.
            let data = try JSONSerialization.data(withJSONObject: ["speech": message.content, "mood": "calm"])
            return ChatMessage(role: "assistant", content: String(decoding: data, as: UTF8.self))
        }
        let messages = [ChatMessage(role: "system", content: personality)] + prior +
            [ChatMessage(role: "user", content: "本地状态：\(context)\n用户说：\(text)")]
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "thinking": ["type": "disabled"], "max_tokens": 512,
            "response_format": ["type": "json_object"]
        ])
        let requestID = String(UUID().uuidString.prefix(8))
        let started = Date()
        for attempt in 0...1 {
            do {
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse else { throw ChatFailure.invalidReply }
                print("DeskPet AI \(requestID): attempt=\(attempt + 1), HTTP=\(http.statusCode), bytes=\(data.count), elapsed=\(Date().timeIntervalSince(started))s")
                return try decodeResponse(data, statusCode: http.statusCode)
            } catch {
                try Task.checkCancellation()
                let failure = error as NSError
                print("DeskPet AI \(requestID): attempt=\(attempt + 1), domain=\(failure.domain), code=\(failure.code), elapsed=\(Date().timeIntervalSince(started))s")
                let droppedConnection = failure.domain == NSURLErrorDomain &&
                    failure.code == URLError.networkConnectionLost.rawValue
                // JSON mode can return empty content with HTTP 200; retry that or a dropped connection once.
                if attempt == 0 && (droppedConnection || (error as? ChatFailure) == .emptyReply) {
                    try await Task.sleep(nanoseconds: 350_000_000)
                    continue
                }
                throw ChatFailure.classify(error)
            }
        }
        throw ChatFailure.network
    }

    static func decodeResponse(_ data: Data, statusCode: Int) throws -> PetReply {
        switch statusCode {
        case 200: break
        case 400, 404, 422: throw ChatFailure.invalidRequest
        case 401, 403: throw ChatFailure.unauthorized
        case 402, 429: throw ChatFailure.limited
        case 408, 504: throw ChatFailure.timeout
        default: throw ChatFailure.server
        }
        if let envelope = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let choice = (envelope["choices"] as? [[String: Any]])?.first {
            let reason = choice["finish_reason"] as? String ?? "missing"
            let knownReasons = ["stop", "length", "tool_calls", "content_filter", "insufficient_system_resource", "missing"]
            print("DeskPet reply envelope: finish=\(knownReasons.contains(reason) ? reason : "other")")
        }
        guard data.count < 100_000,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]], let first = choices.first,
              first["finish_reason"] as? String == "stop",
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String, let body = content.data(using: .utf8)
        else { throw ChatFailure.invalidReply }
        print("DeskPet reply envelope: contentBytes=\(body.count)")
        return try PetReply.parse(body)
    }
}

// Match complete commands so ordinary questions containing “停止” still reach the conversation.
enum VoiceCommands {
    static func endsConversation(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return ["停止", "安静", "别说了", "不聊了", "先这样", "结束聊天"].contains(cleaned)
    }
}

enum SpeechRecovery {
    // Retry only from the local request, including error 201; a failed online retry must stop.
    static func shouldRetryOnline(onDevice: Bool, onlineAllowed: Bool) -> Bool {
        onDevice && onlineAllowed
    }
}
