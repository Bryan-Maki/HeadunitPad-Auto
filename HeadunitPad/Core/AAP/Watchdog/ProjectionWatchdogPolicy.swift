//
//  ProjectionWatchdogPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit ProjectionWatchdogPolicy.kt
//  Decides when video starvation or link silence warrants reconnect overlays or video recovery requests.
//

import Foundation

public enum ProjectionWatchdogPolicy {
    /// How long without a rendered frame before the picture stopping is worth reacting to (10s).
    public static let frameGapMs: Int64 = 10_000

    /// How long the display consumer may draw nothing with video still arriving before view rebuild (5s).
    public static let displayFreezeMs: Int64 = 5_000

    /// Watchdog evaluation tick frequency (2s).
    public static let watchdogTickMs: Int64 = 2_000

    /// How long the whole AAP link must have been silent before a stopped picture is called lost connection (10s).
    public static let linkQuietMs: Int64 = 10_000

    /// Minimum interval between consecutive video recovery / focus requests (1.5s).
    public static let minRecoveryIntervalMs: Int64 = 1_500

    public static func isSessionLive(isConnected: Bool) -> Bool {
        return isConnected
    }

    /// Whether a stopped picture should be shown to the user as a lost connection overlay.
    public static func shouldShowReconnecting(frameGapMs: Int64, linkQuietMs: Int64) -> Bool {
        return frameGapMs > Self.frameGapMs && linkQuietMs > Self.linkQuietMs
    }

    /// Whether a black mid-session picture warrants asking the phone for video focus again.
    public static func shouldRequestVideoFocus(
        pictureStopped: Bool,
        nowMs: Int64,
        lastRequestMs: Int64
    ) -> Bool {
        guard pictureStopped else { return false }
        return (nowMs - lastRequestMs) >= minRecoveryIntervalMs
    }
}
