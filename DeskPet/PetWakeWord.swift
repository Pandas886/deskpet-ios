import Foundation
import SherpaOnnx

/// The audio thread only copies a bounded chunk. Inference and model lifetime stay on one queue.
final class PetWakeWord {
    var onWake: (() -> Void)?
    private let queue = DispatchQueue(label: "deskpet.wake", qos: .userInitiated)
    private let slots = DispatchSemaphore(value: 4)
    private let lock = NSLock()
    private var generation = 0
    private var armed = false
    private var droppedChunks = 0
    private var receivedSeconds: Double = 0
    private var loudestRMS: Float = 0
    private var reportAt = ProcessInfo.processInfo.systemUptime
    private var spotter: SherpaOnnxKeywordSpotterWrapper?

    func prepare(_ done: @escaping (Bool) -> Void) {
        queue.async {
            if self.spotter == nil {
                func resource(_ name: String, _ ext: String) -> String? {
                    Bundle.main.path(forResource: name, ofType: ext, inDirectory: "WakeModel") ??
                        Bundle.main.path(forResource: name, ofType: ext)
                }
                if let encoder = resource("encoder", "onnx"), let decoder = resource("decoder", "onnx"),
                   let joiner = resource("joiner", "onnx"), let tokens = resource("tokens", "txt"),
                   let keywords = resource("keywords", "txt") {
                    let transducer = sherpaOnnxOnlineTransducerModelConfig(encoder: encoder, decoder: decoder, joiner: joiner)
                    let model = sherpaOnnxOnlineModelConfig(tokens: tokens, transducer: transducer, numThreads: 1)
                    var config = sherpaOnnxKeywordSpotterConfig(
                        featConfig: sherpaOnnxFeatureConfig(sampleRate: 16000, featureDim: 80),
                        modelConfig: model, keywordsFile: keywords)
                    self.spotter = SherpaOnnxKeywordSpotterWrapper(config: &config)
                }
            }
            let ready = self.spotter?.spotter != nil && self.spotter?.stream != nil
            print("DeskPet local wake: model ready=\(ready)")
            DispatchQueue.main.async { done(ready) }
        }
    }

    func setArmed(_ enabled: Bool) {
        lock.lock()
        generation += 1
        armed = enabled
        droppedChunks = 0
        receivedSeconds = 0
        loudestRMS = 0
        reportAt = ProcessInfo.processInfo.systemUptime
        lock.unlock()
        queue.async { self.spotter?.reset() }
    }

    func accept(_ samples: UnsafePointer<Float>, count: Int, sampleRate: Double) {
        lock.lock()
        let enabled = armed
        let ticket = generation
        lock.unlock()
        guard enabled else { return }
        guard slots.wait(timeout: .now()) == .success else {
            lock.lock(); droppedChunks += 1; lock.unlock()
            return
        }
        let copy = Array(UnsafeBufferPointer(start: samples, count: count))
        queue.async {
            defer { self.slots.signal() }
            self.lock.lock()
            let valid = self.armed && self.generation == ticket
            self.lock.unlock()
            guard valid, let spotter = self.spotter else { return }
            var sum: Float = 0
            for value in copy { sum += value * value }
            self.lock.lock()
            self.receivedSeconds += Double(count) / sampleRate
            self.loudestRMS = max(self.loudestRMS, sqrt(sum / Float(max(1, count))))
            let now = ProcessInfo.processInfo.systemUptime
            if now - self.reportAt >= 5 {
                let decibels = 20 * log10(max(self.loudestRMS, 0.000001))
                print(String(format: "DeskPet wake input: audio=%.1fs, loudestRMS=%.1fdBFS, dropped=%d",
                             self.receivedSeconds, decibels, self.droppedChunks))
                self.receivedSeconds = 0
                self.loudestRMS = 0
                self.droppedChunks = 0
                self.reportAt = now
            }
            self.lock.unlock()
            spotter.acceptWaveform(samples: copy, sampleRate: Int(sampleRate))
            while spotter.isReady() {
                spotter.decode()
                if !spotter.getResult().keyword.isEmpty {
                    self.lock.lock()
                    let deliver = self.armed && self.generation == ticket
                    if deliver { self.armed = false }
                    self.lock.unlock()
                    spotter.reset()
                    if deliver {
                        print("DeskPet local wake: detected")
                        DispatchQueue.main.async {
                            self.lock.lock()
                            let current = self.generation == ticket
                            self.lock.unlock()
                            if current { self.onWake?() }
                        }
                    }
                    break
                }
            }
        }
    }
}
