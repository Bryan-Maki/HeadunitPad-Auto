//
//  AuditRecoveryPolicy.swift
//  HeadunitPad
//
//  1:1 Port of open-headunit AuditRecoveryPolicy.kt
//

import Foundation

/// Turns framing findings into video recovery, rather than only describing corruption in a log.
public enum AuditRecoveryPolicy {

    public static func shouldRequestKeyframe(outcome: FragmentedMessageAudit.Outcome, channel: Int) -> Bool {
        guard UInt8(channel) == Channel.ID_VID else { return false }
        switch outcome {
        case .deltaChanged, .orphanedFragment, .truncatedRun:
            return true
        }
    }

    /// DELTA_CHANGED describes the unit about to complete. Discard it to avoid feeding holed frames.
    public static func shouldDiscardAssembledUnit(result: FragmentedMessageAudit.AuditResult) -> Bool {
        return UInt8(result.channel) == Channel.ID_VID && result.outcome == .deltaChanged
    }
}
