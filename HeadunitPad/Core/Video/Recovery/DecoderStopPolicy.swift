//
//  DecoderStopPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit DecoderStopPolicy.kt
//  Differentiates teardowns that end the AAP projection session from
//  internal decoder restarts and surface lifecycle changes.
//

import Foundation

public enum DecoderStopPolicy {

    public static let reasonSurfaceDestroyed = "surfaceDestroyed"
    public static let reasonDetachedFromWindow = "onDetachedFromWindow"
    public static let reasonProjectionViewRecreate = "projectionViewRecreate"
    public static let reasonNewSurface = "New surface"
    public static let reasonScreenOffSleep = "screen_off_sleep"
    public static let reasonActivityStopped = "activity_stopped"

    private static let restartPrefix = "restart"

    private static let surfaceLifecycleReasons: Set<String> = [
        reasonSurfaceDestroyed,
        reasonDetachedFromWindow,
        reasonProjectionViewRecreate,
        reasonNewSurface,
        reasonScreenOffSleep,
        reasonActivityStopped,
    ]

    public static func isDecoderRestart(reason: String) -> Bool {
        return reason.hasPrefix(restartPrefix)
    }

    public static func endsSession(reason: String) -> Bool {
        return !isDecoderRestart(reason: reason) && !surfaceLifecycleReasons.contains(reason)
    }
}
