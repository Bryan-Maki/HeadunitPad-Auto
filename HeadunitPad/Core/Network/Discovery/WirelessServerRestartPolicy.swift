//
//  WirelessServerRestartPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit WirelessServerRestartPolicy.kt
//  Decides whether the TCP server should be started, left alone, or rebuilt.
//

import Foundation

public enum WirelessServerRestartPolicy {
    /// How long to wait before another rebuild after one has been attempted (10s).
    public static let rebuildCooldownMs: Int64 = 10_000

    /// Rebuilds allowed in one window before backoff engages (3).
    public static let maxRebuildsPerWindow: Int = 3

    /// The window those rebuilds are counted in (60s).
    public static let rebuildWindowMs: Int64 = 60_000

    public enum Action: Equatable {
        /// Already bound and accepting. Do nothing.
        case noOp
        /// Nothing has been created yet. Create it.
        case start
        /// An instance exists and its bind task is in progress. Await.
        case await
        /// An instance exists, its task has ended, and it never bound. Replace it.
        case rebuild
        /// A rebuild is due but too soon, or too many have been tried. Back off.
        case backoff
    }

    public static func decide(
        assigned: Bool,
        alive: Bool,
        listening: Bool,
        nowMs: Int64,
        sessionBusy: Bool = false,
        history: WirelessServerHistory
    ) -> Action {
        if assigned && listening { return .noOp }
        if !assigned { return .start }
        if alive { return .await }
        if sessionBusy { return .noOp }

        // Assigned, not listening, and its task has ended: dead.
        if history.lastRebuildAtMs > 0 && (nowMs - history.lastRebuildAtMs) < rebuildCooldownMs {
            return .backoff
        }
        if windowIsOpen(nowMs: nowMs, windowStartedAtMs: history.rebuildWindowStartedAtMs) && history.rebuildsInWindow >= maxRebuildsPerWindow {
            return .backoff
        }
        return .rebuild
    }

    public static func windowIsOpen(nowMs: Int64, windowStartedAtMs: Int64) -> Bool {
        return windowStartedAtMs > 0 && (nowMs - windowStartedAtMs) < rebuildWindowMs
    }

    public static func nextRebuildCount(nowMs: Int64, rebuildWindowStartedAtMs: Int64, rebuildsInWindow: Int) -> Int {
        if windowIsOpen(nowMs: nowMs, windowStartedAtMs: rebuildWindowStartedAtMs) {
            return rebuildsInWindow + 1
        } else {
            return 1
        }
    }

    public static func nextWindowStart(nowMs: Int64, rebuildWindowStartedAtMs: Int64) -> Int64 {
        if windowIsOpen(nowMs: nowMs, windowStartedAtMs: rebuildWindowStartedAtMs) {
            return rebuildWindowStartedAtMs
        } else {
            return nowMs
        }
    }
}
