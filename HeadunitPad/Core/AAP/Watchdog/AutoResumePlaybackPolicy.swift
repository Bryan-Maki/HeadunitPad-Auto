//
//  AutoResumePlaybackPolicy.swift
//  HeadunitPad
//
//  1:1 Port of open-headunit AutoResumePlaybackPolicy.kt
//

import Foundation

/// Pure decision policy for auto-resuming media playback on reconnect.
///
/// Prevents unwanted playback if music was stopped/paused before disconnect,
/// if the feature is disabled in settings, or if the reconnect occurred after
/// a long delay (> 60 seconds).
public enum AutoResumePlaybackPolicy {

    /// Maximum elapsed time (in ms) since disconnect to be considered a quick reconnect.
    public static let maxReconnectWindowMs: Int64 = 60_000

    /// Determines whether Open Headunit / HeadunitPad should send a playback start command upon reconnection.
    public static func shouldResume(
        enabled: Bool,
        wasPlayingBeforeDisconnect: Bool,
        elapsedSinceDisconnectMs: Int64
    ) -> Bool {
        guard enabled else { return false }
        guard wasPlayingBeforeDisconnect else { return false }
        return elapsedSinceDisconnectMs >= 1 && elapsedSinceDisconnectMs <= maxReconnectWindowMs
    }
}
