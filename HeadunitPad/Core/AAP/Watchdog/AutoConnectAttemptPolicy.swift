//
//  AutoConnectAttemptPolicy.swift
//  HeadunitPad
//
//  1:1 Port of open-headunit AutoConnectAttemptPolicy.kt
//

import Foundation

public enum ConnectionUiMode: Sendable, Equatable {
    case overlay
    case pill
    case pillThenOverlay
}

/// How long an auto-connect attempt may run without the connection advancing,
/// and what its failure is allowed to do to the status UI.
public enum AutoConnectAttemptPolicy {

    public static let overlayWatchdogMs: Int64 = 30_000
    public static let pillWatchdogMs: Int64 = 150_000

    public static func watchdogMs(mode: ConnectionUiMode) -> Int64 {
        switch mode {
        case .overlay:
            return overlayWatchdogMs
        case .pill, .pillThenOverlay:
            return pillWatchdogMs
        }
    }

    public static func deadlineAt(mode: ConnectionUiMode, startedAtElapsedMs: Int64) -> Int64 {
        return startedAtElapsedMs + watchdogMs(mode: mode)
    }

    public static func remainingMs(deadlineElapsedMs: Int64, nowElapsedMs: Int64) -> Int64 {
        return max(0, deadlineElapsedMs - nowElapsedMs)
    }

    public static func hasExpired(deadlineElapsedMs: Int64, nowElapsedMs: Int64) -> Bool {
        return remainingMs(deadlineElapsedMs: deadlineElapsedMs, nowElapsedMs: nowElapsedMs) == 0
    }

    public static func resetsStageOnFailure(mode: ConnectionUiMode) -> Bool {
        return mode == .overlay
    }
}
