//
//  MixerDuckingEnvelope.swift
//  HeadunitPad
//
//  1:1 port of open-headunit MixerDuckingEnvelope.kt
//

import Foundation

/// Sample-clock ducking: buffered prompts and overlapping speech channels share one envelope.
/// No transport/main-thread timers can restore media while a prompt is still being rendered.
public final class MixerDuckingEnvelope {
    public let sampleRate: Int
    public var duckedGain: Float

    public var currentGain: Float {
        return gain
    }

    public var attackMs: Int = 10
    public var releaseMs: Int = 120

    public init(sampleRate: Int = 48000, attackMs: Int = 10, releaseMs: Int = 120, duckedGain: Float = 0.3) {
        self.sampleRate = sampleRate
        self.attackMs = attackMs
        self.releaseMs = releaseMs
        self.duckedGain = duckedGain
    }

    public func setSpeechActive(_ active: Bool) {
        let next: Float = active ? duckedGain : 1.0
        if next == target { return }
        target = next
        let ms = active ? attackMs : releaseMs
        remaining = sampleRate * ms / 1000
        if remaining > 0 {
            step = (target - gain) / Float(remaining)
        } else {
            gain = target
            step = 0
        }
    }

    public func process(samples: [Float], channels: Int = 1) -> [Float] {
        var output = [Float](repeating: 0, count: samples.count)
        let ch = max(1, channels)
        let frameCount = samples.count / ch
        for i in 0..<frameCount {
            let g = nextGain()
            for c in 0..<ch {
                output[i * ch + c] = samples[i * ch + c] * g
            }
        }
        return output
    }

    public func nextGain() -> Float {
        if remaining > 0 {
            remaining -= 1
            gain = (remaining == 0) ? target : (gain + step)
        }
        return gain
    }

    public func reset() {
        gain = 1.0
        target = 1.0
        step = 0.0
        remaining = 0
    }
}
