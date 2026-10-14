//
//  MixerOutputLifecycle.swift
//  HeadunitPad
//
//  Ported 1:1 from open-headunit MixerOutputLifecycle.kt
//

import Foundation

final class MixerOutputLifecycle {
    enum Action {
        case wait
        case start
        case write
        case pause
    }

    private let keepOutputActive: Bool
    private var started = false
    private var idleSinceMs: Int64 = -1

    init(keepOutputActive: Bool) {
        self.keepOutputActive = keepOutputActive
    }

    func outputProgress(nowMs: Int64) {
        idleSinceMs = nowMs
    }

    func update(nowMs: Int64, idle: Bool, warming: Bool, receivedAudio: Bool, drainMs: Int64) -> Action {
        if !started {
            idleSinceMs = -1
            if idle && !warming {
                return .wait
            }
            started = true
            return .start
        }

        if idle && !warming && (!keepOutputActive || !receivedAudio) {
            if idleSinceMs < 0 {
                idleSinceMs = nowMs
            }
            if nowMs - idleSinceMs >= drainMs {
                started = false
                idleSinceMs = -1
                return .pause
            }
        } else {
            idleSinceMs = -1
        }

        return .write
    }
}
