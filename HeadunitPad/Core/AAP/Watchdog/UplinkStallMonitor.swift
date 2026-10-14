//
//  UplinkStallMonitor.swift
//  HeadunitPad
//
//  1:1 port of open-headunit UplinkStallMonitor.kt
//  Measures how long the outbound write path spends blocked on a socket.
//

import Foundation

public final class UplinkStallMonitor {
    public static let stallThresholdMs: Int64 = 200
    public static let windowMs: Int64 = 30_000

    public struct Report: Equatable {
        public let stalls: Int
        public let writes: Int
        public let windowMs: Int64
        public let blockedMs: Int64
        public let longestMs: Int64

        public var blockedPercent: Int {
            return windowMs > 0 ? Int((blockedMs * 100) / windowMs) : 0
        }
    }

    private var started: Bool = false
    private var windowStartMs: Int64 = 0
    private var stallCount: Int = 0
    private var blockedMs: Int64 = 0
    private var longestMs: Int64 = 0
    private var writes: Int = 0
    private var writeStartMs: Int64 = 0

    public init() {}

    public func onWriteStarted(nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        writeStartMs = nowMs
    }

    public func onWriteCompleted(nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> Report? {
        let duration = max(0, nowMs - writeStartMs)
        return onWrite(durationMs: duration, nowMs: nowMs)
    }

    public func onWrite(durationMs: Int64, nowMs: Int64) -> Report? {
        if !started {
            started = true
            windowStartMs = nowMs
        }

        writes += 1
        if durationMs > Self.stallThresholdMs {
            stallCount += 1
            blockedMs += durationMs
            if durationMs > longestMs { longestMs = durationMs }
        }

        let elapsedMs = nowMs - windowStartMs
        if elapsedMs < Self.windowMs {
            return nil
        }

        let report: Report? = (stallCount == 0) ? nil : Report(
            stalls: stallCount,
            writes: writes,
            windowMs: elapsedMs,
            blockedMs: blockedMs,
            longestMs: longestMs
        )

        windowStartMs = nowMs
        stallCount = 0
        blockedMs = 0
        longestMs = 0
        writes = 0

        return report
    }

    public func reset() {
        started = false
        windowStartMs = 0
        stallCount = 0
        blockedMs = 0
        longestMs = 0
        writes = 0
    }
}
