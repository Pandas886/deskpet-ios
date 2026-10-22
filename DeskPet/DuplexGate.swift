import Foundation

// Input is the post-Voice-Processing microphone signal, never the raw wake-word signal.
struct DuplexGate {
    private var noise: Float = 0.0002
    private var voicedSince: TimeInterval?
    private var lastAbove: TimeInterval = -.infinity
    private var voicedDuration: TimeInterval = 0
    private(set) var voiceActive = false
    var threshold: Float { min(0.006, max(0.0008, noise * 3)) }
    private var lastEvidence: TimeInterval = -.infinity
    private var lastLevel: TimeInterval?
    private var echo = ""
    private var echoUntil: TimeInterval = -.infinity
    private var ignoredTranscript = ""

    mutating func startReply(_ text: String) {
        echo = Self.normalized(text)
        echoUntil = .infinity
        resetRecognition()
        voicedSince = nil
        voicedDuration = 0
        lastEvidence = -.infinity
    }

    mutating func finishReply(now: TimeInterval) { echoUntil = now + 1 }

    mutating func resetRecognition() { ignoredTranscript = "" }

    mutating func observe(_ rms: Float, now: TimeInterval, playing: Bool) -> Bool {
        // Learn the quiet floor only; loud playback residue must not raise the threshold indefinitely.
        let dt = min(0.1, max(0, now - (lastLevel ?? now)))
        lastLevel = now
        voiceActive = rms >= threshold
        if rms < threshold {
            noise += (rms - noise) * Float(1 - exp(-dt / 1.5))
            voicedDuration = max(0, voicedDuration - dt * 0.5)
            if now - lastAbove > 0.12 { voicedSince = nil }
        } else {
            if voicedSince == nil { voicedSince = now }
            lastAbove = now
            voicedDuration = min(0.3, voicedDuration + dt)
            if voicedDuration >= 0.12 { lastEvidence = now }
        }
        // Briefly duck on sustained energy; only recognizable non-echo words can stop playback.
        return playing && now - lastEvidence < 0.55 && now - (voicedSince ?? now) < 1.2
    }

    mutating func candidate(_ transcript: String, now: TimeInterval, requireVoice: Bool) -> String? {
        var text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if ignoredTranscript.count >= 2, text.hasPrefix(ignoredTranscript) {
            text = String(text.dropFirst(ignoredTranscript.count)).trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        }
        let normalized = Self.normalized(text)
        guard !normalized.isEmpty else { return nil }
        if now < echoUntil, echo.contains(normalized) {
            ignoredTranscript = transcript
            return nil
        }
        guard !requireVoice || now - lastEvidence < 1.2 else { return nil }
        return text
    }

    private static func normalized(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}
