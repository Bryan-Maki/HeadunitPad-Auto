//
//  ProjectionRaiseDeadlinePolicy.swift
//  HeadunitPad
//
//  1:1 Port of open-headunit ProjectionRaiseDeadlinePolicy.kt
//

import Foundation

/// Decides what to do when a handshake has completed and the projection screen has still not come up.
public enum ProjectionRaiseDeadlinePolicy {

    /// Long enough for a slow unit to inflate the view, short enough to beat a phone's own patience.
    public static let deadlineMs: Int64 = 8_000

    /// One retry, then the session is ended so the phone can start a fresh one.
    public static let maxRaises: Int = 2

    /// Sessions in a row that may end for a missing screen and still let a reconnect follow.
    public static let maxRecoveredEnds: Int = 1

    public enum Action: Sendable, Equatable {
        case retryRaise
        case endAndRecover
        case endAndHold
    }

    /// Armed only when a raise was actually attempted.
    public static func arms(raiseAttempted: BooleanLiteralType) -> Bool {
        return raiseAttempted
    }

    /// Action calculation for session raise failures.
    public static func actionFor(raisesMade: Int, unprojectedEndsInARow: Int) -> Action {
        if raisesMade < maxRaises {
            return .retryRaise
        } else if unprojectedEndsInARow < maxRecoveredEnds {
            return .endAndRecover
        } else {
            return .endAndHold
        }
    }

    /// A projected session, or one the user asked for, starts the count again.
    public static func endsInARowAfter(previous: Int, projected: Bool, userRequested: Bool) -> Int {
        return (projected || userRequested) ? 0 : previous
    }
}
