import Foundation
import AVFoundation

final class PetAudio {
    var muted = UserDefaults.standard.bool(forKey: "petMuted") {
        didSet {
            UserDefaults.standard.set(muted, forKey: "petMuted")
            if muted { stop() }
        }
    }
    private let queue = DispatchQueue(label: "deskpet.audio")
    private var players: [PetSound: AVAudioPlayer] = [:]
    private var lastSound: TimeInterval = -.infinity
    private var active = false

    init() {
        // Prepare short, procedural electronic calls once; no downloads or recordings.
        queue.async {
            for kind in PetSound.allCases {
                do {
                    let player = try AVAudioPlayer(data: Self.wave(kind), fileTypeHint: AVFileType.wav.rawValue)
                    player.volume = kind == .purr ? 0.13 : 0.20
                    player.prepareToPlay()
                    self.players[kind] = player
                } catch { print("DeskPet audio preparation: \(error.localizedDescription)") }
            }
        }
    }

    func setActive(_ enabled: Bool, completion: (() -> Void)? = nil) {
        queue.async {
            self.active = enabled
            do {
                if enabled {
                    try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
                    try AVAudioSession.sharedInstance().setActive(true)
                } else {
                    self.players.values.forEach { $0.stop() }
                    try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                }
            } catch { print("DeskPet audio session: \(error.localizedDescription)") }
            if let completion { DispatchQueue.main.async(execute: completion) }
        }
    }

    func play(_ kind: PetSound, now: TimeInterval) {
        guard !muted else { return }
        queue.async {
            guard self.active, now - self.lastSound >= 1.5 else { return }
            self.lastSound = now
            self.players.values.forEach { $0.stop() }
            self.players[kind]?.currentTime = 0
            self.players[kind]?.play()
        }
    }

    func stop() {
        queue.async { self.players.values.forEach { $0.stop() } }
    }

    private static func wave(_ kind: PetSound) -> Data {
        let notes: [(Double, Double, Double)]
        switch kind {
        case .hello: notes = [(520, 760, 0.14), (720, 980, 0.18)]
        case .curious: notes = [(400, 650, 0.22)]
        case .happy: notes = [(650, 850, 0.12), (850, 1100, 0.14)]
        case .purr: notes = [(105, 115, 0.65)]
        case .surprised: notes = [(700, 360, 0.20)]
        case .settled: notes = [(420, 280, 0.24)]
        }
        let rate = 22050.0
        var samples: [Int16] = []
        for (from, to, duration) in notes {
            var phase = 0.0
            let count = Int(rate * duration)
            for i in 0..<count {
                let t = Double(i) / rate
                let progress = Double(i) / Double(count)
                phase += 2 * .pi * (from + (to - from) * progress) / rate
                let envelope = min(1, t / 0.018) * min(1, (duration - t) / 0.045)
                let tremolo = kind == .purr ? 0.65 + 0.35 * sin(2 * .pi * 24 * t) : 1
                let value = (sin(phase) + 0.16 * sin(phase * 2)) * envelope * tremolo * 0.45
                samples.append(Int16(max(-32767, min(32767, value * 32767))))
            }
            samples.append(contentsOf: repeatElement(0, count: Int(rate * 0.045)))
        }
        var result = Data()
        func text(_ value: String) { result.append(contentsOf: value.utf8) }
        func number<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { result.append(contentsOf: $0) }
        }
        text("RIFF"); number(UInt32(36 + samples.count * 2)); text("WAVEfmt ")
        number(UInt32(16)); number(UInt16(1)); number(UInt16(1))
        number(UInt32(rate)); number(UInt32(rate * 2)); number(UInt16(2)); number(UInt16(16))
        text("data"); number(UInt32(samples.count * 2))
        for sample in samples { number(sample) }
        return result
    }
}
