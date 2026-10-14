//
//  AacDecoderRecovery.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AacDecoderRecovery.kt
//

import Foundation

/// Codec callbacks request recovery; only the decode thread consumes it.
public final class AacDecoderRecovery {
    public enum Action: Equatable, Sendable {
        case none
        case wait
        case rebuild
        case stop
    }

    private let lock = NSLock()
    public private(set) var pending = false
    public private(set) var attempts = 0
    private var lastAttemptMs: Int64 = 0
    private var exhausted = false
    private var playbackVersion: Int64 = 0
    private var attemptedPlaybackVersion: Int64 = 0

    public init() {}

    public func isExhausted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return exhausted
    }

    public func request() {
        lock.lock()
        defer { lock.unlock() }
        if !exhausted {
            pending = true
        }
    }

    /// Remember Start even if it races the final failed rebuild, before STOP is consumed.
    public func retryIfExhausted() {
        lock.lock()
        defer { lock.unlock() }
        playbackVersion += 1
        if !exhausted { return }
        resetBudget()
        pending = true
    }

    public func next(nowMs: Int64) -> Action {
        lock.lock()
        defer { lock.unlock() }
        if !pending { return .none }
        if attempts >= AacDecoderRecoveryPolicy.maxRebuilds {
            if playbackVersion != attemptedPlaybackVersion {
                resetBudget()
            } else {
                pending = false
                exhausted = true
                return .stop
            }
        }
        if !AacDecoderRecoveryPolicy.allowsRebuild(rebuildsSoFar: attempts, sinceLastRebuildMs: nowMs - lastAttemptMs) {
            return .wait
        }
        pending = false
        attempts += 1
        attemptedPlaybackVersion = playbackVersion
        lastAttemptMs = nowMs
        return .rebuild
    }

    /// A new configuration or explicit playback request may retry a terminal decoder.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        pending = false
        playbackVersion = 0
        attemptedPlaybackVersion = 0
        resetBudget()
    }

    private func resetBudget() {
        attempts = 0
        lastAttemptMs = 0
        exhausted = false
    }
}
