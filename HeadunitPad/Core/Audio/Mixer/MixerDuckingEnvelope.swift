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

    private var gain: Float = 1.0
    private var target: Float = 1.0
    private var step: Float = 0.0
    private var remaining: Int = 0

    public init(sampleRate: Int = 48000, duckedGain: Float = 0.3) {
        self.sampleRate = sampleRate
        self.duckedGain = duckedGain
    }

    public func setSpeechActive(_ active: Bool) {
        let next: Float = active ? duckedGain : 1.0
        if next == target { return }
        target = next
        remaining = sampleRate * (active ? 10 : 120) / 1000
        if remaining > 0 {
            step = (target - gain) / Float(remaining)
        } else {
            gain = target
            step = 0
        }
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
