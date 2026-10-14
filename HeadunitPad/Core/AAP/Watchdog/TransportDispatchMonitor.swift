//
//  TransportDispatchMonitor.swift
//  HeadunitPad
//
//  1:1 port of open-headunit TransportDispatchMonitor.kt
//  Measures how long the transport receive loop spends in dispatch vs reading socket.
//

import Foundation

public final class TransportDispatchMonitor {
    public static let windowMs: Int64 = 30_000
    public static let blockingThresholdMs: Int64 = 50

    public struct Report: Equatable {
        public let windowMs: Int64
        public let videoMs: Int64
        public let audioMs: Int64
        public let otherMs: Int64
        public let worstMs: Int64
        public let worstChannel: Int
        public let blocks: Int
        public let maxVideoQueue: Int
        public let videoShed: Int64
    }

    private var started: Bool = false
    private var windowStartMs: Int64 = 0
    private var videoMs: Int64 = 0
    private var audioMs: Int64 = 0
    private var otherMs: Int64 = 0
    private var worstMs: Int64 = 0
    private var worstChannel: Int = -1
    private var blocks: Int = 0
    private var maxVideoQueue: Int = 0
    private var shedAtWindowStart: Int64 = -1
    private var videoShed: Int64 = 0

    public init() {}

    public func onDispatch(
        channel: Int,
        tookMs: Int64,
        nowMs: Int64,
        videoQueueDepth: Int = 0,
        videoShedTotal: Int64 = 0
    ) -> Report? {
        if !started {
            started = true
            windowStartMs = nowMs
        }

        if videoQueueDepth > maxVideoQueue { maxVideoQueue = videoQueueDepth }
        if shedAtWindowStart < 0 { shedAtWindowStart = videoShedTotal }
        videoShed = max(videoShedTotal - shedAtWindowStart, 0)
        let took = max(tookMs, 0)

        if UInt8(channel) == Channel.ID_VID {
            videoMs += took
        } else if UInt8(channel) == Channel.ID_MED || UInt8(channel) == Channel.ID_GUD || UInt8(channel) == Channel.ID_SYS {
            audioMs += took
        } else {
            otherMs += took
        }

        if took >= Self.blockingThresholdMs { blocks += 1 }
        if took > worstMs {
            worstMs = took
            worstChannel = channel
        }

        let elapsedMs = nowMs - windowStartMs
        if elapsedMs < Self.windowMs {
            return nil
        }

        let report = Report(
            windowMs: elapsedMs,
            videoMs: videoMs,
            audioMs: audioMs,
            otherMs: otherMs,
            worstMs: worstMs,
            worstChannel: worstChannel,
            blocks: blocks,
            maxVideoQueue: maxVideoQueue,
            videoShed: videoShed
        )

        windowStartMs = nowMs
        shedAtWindowStart = videoShedTotal
        videoShed = 0
        videoMs = 0
        audioMs = 0
        otherMs = 0
        worstMs = 0
        worstChannel = -1
        blocks = 0
        maxVideoQueue = 0

        return report
    }

    public func reset() {
        started = false
        windowStartMs = 0
        videoMs = 0
        audioMs = 0
        otherMs = 0
        worstMs = 0
        worstChannel = -1
        blocks = 0
        maxVideoQueue = 0
        shedAtWindowStart = -1
        videoShed = 0
    }
}
