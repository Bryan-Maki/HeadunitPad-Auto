//
//  ReconnectPlaybackSnapshot.swift
//  HeadunitPad
//
//  1:1 Port of open-headunit ReconnectPlaybackSnapshot.kt
//

import Foundation

/// Playback belongs to the last reporting session, not to attempts that never carried media.
public final class ReconnectPlaybackSnapshot: @unchecked Sendable {
    public struct Resume: Sendable, Equatable {
        public let wasPlaying: Bool
        public let elapsedMs: Int64

        public init(wasPlaying: Bool, elapsedMs: Int64) {
            self.wasPlaying = wasPlaying
            self.elapsedMs = elapsedMs
        }
    }

    private let lock = NSLock()
    private var wasPlaying: Bool = false
    private var disconnectedAt: Int64 = 0

    public init() {}

    public func onDisconnected(lastPlaying: Bool?, now: Int64, deliberate: Bool) {
        lock.lock()
        defer { lock.unlock() }

        if deliberate {
            wasPlaying = false
        } else if let last = lastPlaying {
            wasPlaying = last
            disconnectedAt = now
        }
        // A failed handshake has no playback report. Preserve both the intent and its original
        // age, so retries cannot erase a playing session or extend the auto-resume window.
    }

    public func consume(now: Int64) -> Resume {
        lock.lock()
        defer { lock.unlock() }

        let result = Resume(wasPlaying: wasPlaying, elapsedMs: now - disconnectedAt)
        wasPlaying = false
        return result
    }
}
