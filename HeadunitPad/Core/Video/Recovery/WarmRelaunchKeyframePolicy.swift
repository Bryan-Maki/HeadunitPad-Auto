//
//  WarmRelaunchKeyframePolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit WarmRelaunchKeyframePolicy.kt
//  Controls focus cycle escalation when iPad app returns from background
//  or surface changes without tearing down the AAP session.
//

import Foundation

public enum WarmRelaunchKeyframePolicy {

    public static let escalateAfterSurfaceMs: Int64 = 850
    public static let healthyFirstFrameCeilingMs: Int64 = 404
    public static let nudgeThrottleMs: Int64 = VideoRecoveryPolicy.keyframeRequestThrottleMs
    public static let focusCycleGapMs: Int64 = 400

    public enum Action: Equatable {
        case none
        case nudge
        case cycleFocus
    }

    public static func decide(
        sessionHasRendered: Bool,
        crediblePictureOnSurface: Bool,
        transportStarted: Bool,
        msSinceSurfaceSet: Int64,
        msSinceLinkActivity: Int64,
        linkQuietThresholdMs: Int64,
        cycleAlreadySpent: Bool,
        msSinceLastRequest: Int64
    ) -> Action {
        if !transportStarted { return .none }
        if crediblePictureOnSurface { return .none }
        if !sessionHasRendered { return .none }
        if msSinceLinkActivity > linkQuietThresholdMs { return .none }
        if msSinceSurfaceSet < escalateAfterSurfaceMs { return .none }

        if !cycleAlreadySpent { return .cycleFocus }
        if msSinceLastRequest >= nudgeThrottleMs { return .nudge }
        return .none
    }
}
