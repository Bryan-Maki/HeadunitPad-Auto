//
//  CallbackBufferSizing.swift
//  HeadunitPad
//
//  Ported 1:1 from open-headunit CallbackBufferSizing.kt
//

import Foundation

enum CallbackBufferSizing {
    private static func minimumQueueFrames(burst: Int, callbackFrames: Int) -> Int {
        precondition(burst > 0)
        let callback = max(burst, callbackFrames)
        let needed = max(480 + Int64(callback), Int64(callback) * 2)
        return Int((needed + Int64(burst) - 1) / Int64(burst) * Int64(burst))
    }

    static func minimumFrames(burst: Int, callbackFrames: Int) -> Int {
        return burst * 2 + queueFrames(totalFrames: 0, grantedDeviceFrames: 0, burst: burst, callbackFrames: callbackFrames)
    }

    static func deviceFrames(totalFrames: Int, burst: Int, callbackFrames: Int? = nil, preferredDeviceFrames: Int? = nil) -> Int {
        precondition(burst > 0)
        let cbFrames = callbackFrames ?? burst
        let prefFrames = preferredDeviceFrames ?? (burst * 2)
        let bursts = (Int64(totalFrames) + Int64(burst) - 1) / Int64(burst)
        let queueBursts = Int64(minimumQueueFrames(burst: burst, callbackFrames: cbFrames)) / Int64(burst)
        let preferredBursts = (Int64(prefFrames) + Int64(burst) - 1) / Int64(burst)
        let count = max(2, min(preferredBursts, bursts - queueBursts))
        return Int(count * Int64(burst))
    }

    static func queueFrames(totalFrames: Int, grantedDeviceFrames: Int, burst: Int, callbackFrames: Int? = nil) -> Int {
        precondition(burst > 0)
        let cbFrames = callbackFrames ?? burst
        let remainder = max(totalFrames - grantedDeviceFrames, minimumQueueFrames(burst: burst, callbackFrames: cbFrames))
        return Int((Int64(remainder) + Int64(burst) - 1) / Int64(burst) * Int64(burst))
    }
}

final class CallbackDeviceBufferPolicy {
    private let burst: Int
    private var preferredFrames: Int
    private var previousXruns = -1

    init(burst: Int) {
        self.burst = burst
        self.preferredFrames = burst * 2
    }

    func request(totalFrames: Int, callbackFrames: Int, hardwareXruns: Int) -> Int {
        if previousXruns >= 0 && hardwareXruns > previousXruns {
            preferredFrames += burst
        }
        previousXruns = hardwareXruns
        preferredFrames = CallbackBufferSizing.deviceFrames(
            totalFrames: totalFrames,
            burst: burst,
            callbackFrames: callbackFrames,
            preferredDeviceFrames: preferredFrames
        )
        return preferredFrames
    }
}
