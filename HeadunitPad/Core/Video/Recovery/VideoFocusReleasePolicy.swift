//
//  VideoFocusReleasePolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit VideoFocusReleasePolicy.kt
//  Protects phone keyboard from premature teardown when input fields are tapped,
//  while ensuring proper sink release on genuine surface loss.
//

import Foundation

public enum VideoFocusReleasePolicy {

    public static let touchWindowMs: Int64 = 3000

    public static func coverFollowsTouch(lastTouchAtMs: Int64, coveredAtMs: Int64) -> Bool {
        return lastTouchAtMs > 0 && (coveredAtMs - lastTouchAtMs <= touchWindowMs)
    }

    public static func shouldReleaseOnSurfaceLost(
        coverFollowsTouch: Bool,
        sessionConnected: Bool,
        activityEnding: Bool,
        pipActive: Bool,
        focusCycleInFlight: Bool
    ) -> Bool {
        if !coverFollowsTouch { return true }
        if !sessionConnected || activityEnding || pipActive || focusCycleInFlight { return true }
        return false
    }
}
