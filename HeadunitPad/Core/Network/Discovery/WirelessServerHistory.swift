//
//  WirelessServerHistory.swift
//  HeadunitPad
//
//  1:1 port of open-headunit WirelessServerHistory.kt
//  Rebuild bookkeeping for WirelessServerRestartPolicy to prevent rebuild loops.
//

import Foundation

public final class WirelessServerHistory {
    public private(set) var lastRebuildAtMs: Int64
    public private(set) var rebuildsInWindow: Int
    public private(set) var rebuildWindowStartedAtMs: Int64

    public init(
        lastRebuildAtMs: Int64 = 0,
        rebuildsInWindow: Int = 0,
        windowStartedAtMs: Int64 = 0
    ) {
        self.lastRebuildAtMs = lastRebuildAtMs
        self.rebuildsInWindow = rebuildsInWindow
        self.rebuildWindowStartedAtMs = windowStartedAtMs
    }

    public func reset() {
        lastRebuildAtMs = 0
        rebuildsInWindow = 0
        rebuildWindowStartedAtMs = 0
    }

    public func attempt(nowMs: Int64? = nil) {
        let now = nowMs ?? Int64(Date().timeIntervalSince1970 * 1000)
        rebuildsInWindow = WirelessServerRestartPolicy.nextRebuildCount(
            nowMs: now,
            rebuildWindowStartedAtMs: rebuildWindowStartedAtMs,
            rebuildsInWindow: rebuildsInWindow
        )
        rebuildWindowStartedAtMs = WirelessServerRestartPolicy.nextWindowStart(
            nowMs: now,
            rebuildWindowStartedAtMs: rebuildWindowStartedAtMs
        )
        lastRebuildAtMs = now
    }
}
