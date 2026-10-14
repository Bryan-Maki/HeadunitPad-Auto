//
//  MixerSoftClipper.swift
//  HeadunitPad
//
//  1:1 port of open-headunit MixerSoftClipper.kt
//

import Foundation

/// Crossfade limiter activation on the sample clock, including silent/muted contributors.
public final class MixerSoftClipper {
    private var wet: Float = 0.0
    private var target: Float = 0.0
    private var step: Float = 0.0
    private var remaining: Int = 0

    public init() {}

    public func setEnabled(_ enabled: Bool) {
        let next: Float = enabled ? 1.0 : 0.0
        if next == target { return }
        target = next
        remaining = enabled ? 480 : 5760
        if remaining > 0 {
            step = (target - wet) / Float(remaining)
        } else {
            wet = target
            step = 0
        }
    }

    public func advance() {
        if remaining > 0 {
            remaining -= 1
            wet = (remaining == 0) ? target : (wet + step)
        }
    }

    public func process(_ sample: Int) -> Int16 {
        if wet == 0.0 {
            return Int16(clamping: sample)
        }
        let s = max(-98304, min(98304, sample))
        let clipped: Int
        if s > 20480 {
            let d = s - 20480
            clipped = 20480 + d * 12287 / (d + 24574)
        } else if s < -20480 {
            let d = -s - 20480
            clipped = -(20480 + d * 12287 / (d + 24574))
        } else {
            clipped = s
        }
        let blended = Float(sample) + Float(clipped - sample) * wet
        return Int16(clamping: Int(blended))
    }

    public func reset() {
        wet = 0.0
        target = 0.0
        step = 0.0
        remaining = 0
    }
}
