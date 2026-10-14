//
//  PhoneExitQuietPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit PhoneExitQuietPolicy.kt
//  Enforces quiet cooldown when phone disconnects deliberately (e.g. user tapped exit on car screen).
//

import Foundation

public enum PhoneExitQuietPolicy {
    /// How long the wireless stack stays quiet after a phone exits (10 seconds).
    public static let quietWindowMs: Int64 = 10_000

    public static func shouldQuiet(deliberateExit: Bool, nowMs: Int64, exitAtMs: Int64) -> Bool {
        guard deliberateExit else { return false }
        return (nowMs - exitAtMs) < quietWindowMs
    }
}
