//
//  VideoRecoveryPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit VideoRecoveryPolicy.kt
//  Paces stream recovery requests to prevent stream rebuild storms.
//

import Foundation

public enum VideoRecoveryPolicy {

    public static let keyframeRequestThrottleMs: Int64 = 1000

    public static func canRequestKeyframe(nowMs: Int64, lastRequestMs: Int64) -> Bool {
        return nowMs - lastRequestMs > keyframeRequestThrottleMs
    }

    public static func shouldRequestOnDroppedFrame(hasRendered: Bool, nowMs: Int64, lastRequestMs: Int64) -> Bool {
        return hasRendered && canRequestKeyframe(nowMs: nowMs, lastRequestMs: lastRequestMs)
    }
}
