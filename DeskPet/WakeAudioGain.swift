import Foundation

/// Wake-only level compensation; it never decides whether speech or a keyword is present.
struct WakeAudioGain {
    private(set) var gain: Float = 1

    mutating func process(_ samples: [Float], sampleRate: Double) -> [Float] {
        guard !samples.isEmpty, sampleRate > 0 else { return samples }
        var sum: Float = 0
        var peak: Float = 0
        for value in samples {
            sum += value * value
            peak = max(peak, abs(value))
        }
        let rms = sqrt(sum / Float(samples.count))
        let desired = min(16, max(1, 0.04 / max(rms, 0.000001)))
        let seconds = Double(samples.count) / sampleRate
        let timeConstant = desired > gain ? 0.2 : 0.02
        let smoothing = Float(1 - exp(-seconds / timeConstant))
        gain += (desired - gain) * smoothing
        // Limit immediately on a sudden loud input instead of clipping the waveform.
        gain = min(gain, 0.95 / max(peak, 0.000001))
        return samples.map { $0 * gain }
    }
}
