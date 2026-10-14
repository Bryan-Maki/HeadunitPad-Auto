//
//  KeyframeCycleEscalationPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit KeyframeCycleEscalationPolicy.kt
//  Controls escalation from gain-only keyframe nudges to full video-focus
//  release/regain cycles, protected by budget caps, cooldowns, and wire-quiet gates.
//

import Foundation

public enum KeyframeCycleEscalationPolicy {

    public static let escalateAfterUnrepairedMs: Int64 = 2500
    public static let cycleCooldownMs: Int64 = 30_000
    public static let maxCyclesPerSession: Int = 3
    public static let corruptionQuietMs: Int64 = 3000
    public static let deferForQuietLimitMs: Int64 = 15_000
    public static let cycleRefundAfterQuietMs: Int64 = 300_000
    public static let maxCyclesPerDrive: Int = 8

    public enum Action: Equatable {
        /// Send the unsolicited focus gain.
        case nudge
        /// Release video focus and take it back, so phone rebuilds the stream.
        case cycleFocus
        /// Picture is broken, budget available, but wire is still losing frames. Wait for quiet.
        case waitForQuiet
    }

    public static func cyclesToRefund(
        nowMs: Int64,
        cyclesUsedThisSession: Int,
        cyclesSpentThisSession: Int,
        lastBudgetChangeMs: Int64,
        lastWireCorruptionMs: Int64,
        pictureUnrepaired: Bool
    ) -> Int {
        if pictureUnrepaired && cyclesUsedThisSession < maxCyclesPerSession {
            return 0
        }
        if cyclesUsedThisSession <= 0 { return 0 }
        if lastBudgetChangeMs == 0 { return 0 }

        let quietSince = max(lastBudgetChangeMs, lastWireCorruptionMs)
        let windows = Int((nowMs - quietSince) / cycleRefundAfterQuietMs)
        if windows <= 0 { return 0 }

        let remainingDriveAllowance = maxCyclesPerDrive - cyclesSpentThisSession - (maxCyclesPerSession - cyclesUsedThisSession)
        return max(0, min(windows, min(cyclesUsedThisSession, remainingDriveAllowance)))
    }

    public static func decide(
        nowMs: Int64,
        unrepairedSinceMs: Int64,
        cyclesUsedThisSession: Int,
        lastCycleMs: Int64,
        lastWireCorruptionMs: Int64
    ) -> Action {
        if unrepairedSinceMs == 0 { return .nudge }
        if nowMs - unrepairedSinceMs < escalateAfterUnrepairedMs { return .nudge }
        if cyclesUsedThisSession >= maxCyclesPerSession { return .nudge }
        if lastCycleMs != 0 && (nowMs - lastCycleMs < cycleCooldownMs) { return .nudge }

        let wireQuiet = (lastWireCorruptionMs == 0) || (nowMs - lastWireCorruptionMs >= corruptionQuietMs)
        if !wireQuiet {
            let corruptionSinceArm = (lastWireCorruptionMs - unrepairedSinceMs) >= escalateAfterUnrepairedMs
            if corruptionSinceArm {
                if cyclesUsedThisSession == maxCyclesPerSession - 1 {
                    return .waitForQuiet
                }
                if nowMs - unrepairedSinceMs < deferForQuietLimitMs {
                    return .waitForQuiet
                }
            }
        }
        return .cycleFocus
    }
}
