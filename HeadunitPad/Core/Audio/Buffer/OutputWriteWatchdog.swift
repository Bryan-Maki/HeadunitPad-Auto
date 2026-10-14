//
//  OutputWriteWatchdog.swift
//  HeadunitPad
//
//  Ported 1:1 from open-headunit OutputWriteWatchdog.kt
//

import Foundation

final class OutputWriteWatchdog {
    enum Action {
        case wait
        case reopen
        case stop
    }

    private let stableProgressUnits: Int
    private var blockedSinceMs: Int64 = -1
    private var recoveryAttempts = 0
    private var progressUnits: Int64 = 0

    init(stableProgressUnits: Int = 1) {
        self.stableProgressUnits = stableProgressUnits
    }

    func onProgress(units: Int = 1) {
        blockedSinceMs = -1
        progressUnits = min(progressUnits + Int64(units), Int64(stableProgressUnits))
        if progressUnits >= Int64(stableProgressUnits) {
            recoveryAttempts = 0
        }
    }

    func onBlocked(nowMs: Int64) -> Action {
        if blockedSinceMs < 0 {
            blockedSinceMs = nowMs
        }
        if nowMs - blockedSinceMs < 500 {
            return .wait
        }
        return onFailure()
    }

    func onFailure() -> Action {
        blockedSinceMs = -1
        progressUnits = 0
        if recoveryAttempts < 2 {
            recoveryAttempts += 1
            return .reopen
        } else {
            return .stop
        }
    }
}
