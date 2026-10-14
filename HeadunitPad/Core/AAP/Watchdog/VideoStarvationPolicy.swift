//
//  VideoStarvationPolicy.swift
//  HeadunitPad
//
//  1:1 Port of open-headunit VideoStarvationPolicy.kt
//

import Foundation

/// When to advise the user that the wireless link cannot carry the requested video stream,
/// and when to cap the video profile down.
public enum VideoStarvationPolicy {

    /// How many sessions in a row must end without a frame before advice is worth giving.
    public static let adviseAfterStarvedSessions: Int = 3

    /// Whether the session that just ended should produce the advice.
    public static func shouldAdvise(consecutiveStarvedSessions: Int) -> Bool {
        return consecutiveStarvedSessions == adviseAfterStarvedSessions
    }

    /// Whether the next session should be offered a lower profile than the user requested.
    public static func shouldCap(consecutiveStarvedSessions: Int) -> Bool {
        return consecutiveStarvedSessions >= adviseAfterStarvedSessions
    }

    /// The streak after a session that reached handshake and rendered frames or not.
    public static func nextStreak(current: Int, reachedHandshake: Bool, renderedAnyFrame: Bool) -> Int {
        if !reachedHandshake {
            return current
        } else if renderedAnyFrame {
            return 0
        } else {
            return current + 1
        }
    }
}
