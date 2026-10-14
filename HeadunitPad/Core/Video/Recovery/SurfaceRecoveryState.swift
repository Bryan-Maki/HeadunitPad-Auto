//
//  SurfaceRecoveryState.swift
//  HeadunitPad
//
//  1:1 port of open-headunit SurfaceRecoveryState.kt
//  Recovery state tracked per decoder run and session.
//

import Foundation

public final class SurfaceRecoveryState {
    public var cycleSpent: Bool = false
    public var loggedKeyframelessPicture: Bool = false
    private var observedStopGeneration: Int64 = 0

    public init() {}

    public func resetSession() {
        cycleSpent = false
        loggedKeyframelessPicture = false
    }

    public func onSurfaceChanged(targetChanged: Bool, stopGeneration: Int64) -> Bool {
        let rearm = targetChanged || (stopGeneration != observedStopGeneration)
        observedStopGeneration = stopGeneration
        if rearm {
            resetSession()
        }
        return rearm
    }
}
