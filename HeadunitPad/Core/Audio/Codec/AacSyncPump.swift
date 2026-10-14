//
//  AacSyncPump.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AacSyncPump.kt
//

import Foundation

/// Output buffers must be released while waiting for an input slot on synchronous codecs.
public enum AacSyncPump {
    public static let inputTimeoutMs: Int64 = 200
    public static let pollMs: Int64 = 5

    public static func awaitInput(
        nowMs: () -> Int64,
        isRunning: () -> Bool,
        drainOutput: () -> Void,
        dequeueInput: (Int64) -> Int
    ) -> Int {
        let deadline = nowMs() + inputTimeoutMs
        while isRunning() {
            drainOutput()
            if !isRunning() { return -1 }
            let remainingMs = max(0, deadline - nowMs())
            let timeoutUs = min(pollMs, remainingMs) * 1000
            let index = dequeueInput(timeoutUs)
            if index >= 0 { return index }
            if nowMs() >= deadline { return -1 }
        }
        return -1
    }
}
