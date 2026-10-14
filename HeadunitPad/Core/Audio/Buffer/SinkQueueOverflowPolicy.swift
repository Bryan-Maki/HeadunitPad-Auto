//
//  SinkQueueOverflowPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit SinkQueueOverflowPolicy.kt
//

import Foundation

/// How deep the hand-off queue in front of a sink may get, and what to shed when it fills.
public enum SinkQueueOverflowPolicy {
    /// Depth the queue must reach whatever the setting says.
    public static let minQueueMs: Int64 = 1_000

    /// The wireless unacked window AapControl advertises for audio; a legal burst must fit.
    public static let unackedWindowChunks = 30

    /// Chunks to allow. configuredChunks of zero means no limit.
    public static func capacityChunks(configuredChunks: Int, chunkDurationMs: Int) -> Int {
        if configuredChunks <= 0 { return 0 }
        let byTime = chunkDurationMs > 0 ? Int((minQueueMs + Int64(chunkDurationMs) - 1) / Int64(chunkDurationMs)) : 0
        return max(configuredChunks, byTime, unackedWindowChunks)
    }

    /// How far behind the queue is in milliseconds.
    public static func backlogMs(queuedChunks: Int, chunkDurationMs: Int) -> Int64 {
        if chunkDurationMs <= 0 || queuedChunks < 0 { return -1 }
        return Int64(queuedChunks) * Int64(chunkDurationMs)
    }

    public static let unboundedBacklogWarnMs: Int64 = 2_000

    public static func chunkDurationMs(chunkFrames: Int, sampleRateInHz: Int) -> Int {
        if sampleRateInHz <= 0 || chunkFrames <= 0 { return 0 }
        return Int(Int64(chunkFrames) * 1000 / Int64(sampleRateInHz))
    }
}
