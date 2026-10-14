//
//  AudioJitterBufferPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AudioJitterBufferPolicy.kt
//

import Foundation

/// Converts the persisted latency dial to a requested reserve without changing saved preferences.
/// The 8x anchor means 200 ms; it is not the default. An unset preference remains 16x / 400 ms.
public struct AudioJitterBufferPolicy {
    public init() {}

    public static let defaultMultiplier = 16
    public static let targetMs: Int64 = 200
    public static let anchorMultiplier = 8
    public static let minTargetMs: Int64 = 25
    public static let maxTargetMs: Int64 = 400

    public func targetLatencyMs(multiplier: Int) -> Int {
        return Int(Self.targetMs(for: multiplier))
    }

    public static func targetMs(for latencyMultiplier: Int) -> Int64 {
        let m = Int64(max(1, latencyMultiplier))
        let computed = targetMs * m / Int64(anchorMultiplier)
        return max(minTargetMs, min(maxTargetMs, computed))
    }
}
