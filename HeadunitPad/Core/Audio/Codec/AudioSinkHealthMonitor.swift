//
//  AudioSinkHealthMonitor.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AudioSinkHealthMonitor.kt
//

import Foundation

/// Whether the speaker actually stuttered, and when.
/// Pure and clock-free: the caller passes the time and running totals.
public final class AudioSinkHealthMonitor {
    private let channelName: String
    private let sampleRateInHz: Int

    private var started = false
    private var windowStartMs: Int64 = 0
    private var prev: Sample?
    private var minDepthFrames = Int.max
    private var maxQueuedChunks = 0

    public struct Sample: Equatable, Sendable {
        public let underrunsTotal: Int64
        public let silentCyclesTotal: Int64
        public let rebanksTotal: Int64
        public let droppedChunksTotal: Int64
        public let droppedFramesTotal: Int64
        public let shedFramesTotal: Int64
        public let depthFrames: Int
        public let queuedChunks: Int
        public let chunkDurationMs: Int
        public let queueCapacityChunks: Int
        public let capacityFrames: Int
        public let effectiveFrames: Int
        public let targetFrames: Int

        public init(
            underrunsTotal: Int64 = 0,
            silentCyclesTotal: Int64 = 0,
            rebanksTotal: Int64 = 0,
            droppedChunksTotal: Int64 = 0,
            droppedFramesTotal: Int64 = 0,
            shedFramesTotal: Int64 = 0,
            depthFrames: Int = 0,
            queuedChunks: Int = 0,
            chunkDurationMs: Int = 0,
            queueCapacityChunks: Int = 0,
            capacityFrames: Int = 0,
            effectiveFrames: Int = 0,
            targetFrames: Int = 0
        ) {
            self.underrunsTotal = underrunsTotal
            self.silentCyclesTotal = silentCyclesTotal
            self.rebanksTotal = rebanksTotal
            self.droppedChunksTotal = droppedChunksTotal
            self.droppedFramesTotal = droppedFramesTotal
            self.shedFramesTotal = shedFramesTotal
            self.depthFrames = depthFrames
            self.queuedChunks = queuedChunks
            self.chunkDurationMs = chunkDurationMs
            self.queueCapacityChunks = queueCapacityChunks
            self.capacityFrames = capacityFrames
            self.effectiveFrames = effectiveFrames
            self.targetFrames = targetFrames
        }
    }

    public struct Report: Equatable, Sendable {
        public let channelName: String
        public let sampleRateInHz: Int
        public let windowMs: Int64
        public let underruns: Int64
        public let silentCycles: Int64
        public let rebanks: Int64
        public let droppedChunks: Int64
        public let droppedFrames: Int64
        public let shedFrames: Int64
        public let depthFrames: Int
        public let minDepthFrames: Int
        public let maxQueuedChunks: Int
        public let chunkDurationMs: Int
        public let queueCapacityChunks: Int
        public let capacityFrames: Int
        public let effectiveFrames: Int
        public let targetFrames: Int

        public var healthy: Bool {
            return underruns == 0 && silentCycles == 0 && droppedChunks == 0 &&
                droppedFrames == 0 && shedFrames == 0
        }

        public func ms(frames: Int64) -> Int64 {
            guard sampleRateInHz > 0 else { return 0 }
            return frames * 1000 / Int64(sampleRateInHz)
        }
    }

    public init(channelName: String, sampleRateInHz: Int) {
        self.channelName = channelName
        self.sampleRateInHz = sampleRateInHz
    }

    public func sample(nowMs: Int64, s: Sample) -> Report? {
        if !started {
            started = true
            windowStartMs = nowMs
            prev = s
            return nil
        }

        if s.depthFrames < minDepthFrames { minDepthFrames = s.depthFrames }
        if s.queuedChunks > maxQueuedChunks { maxQueuedChunks = s.queuedChunks }

        let elapsedMs = nowMs - windowStartMs
        if elapsedMs < 10_000 { // 10s window
            return nil
        }

        let before = prev ?? s
        let report = Report(
            channelName: channelName,
            sampleRateInHz: sampleRateInHz,
            windowMs: elapsedMs,
            underruns: max(0, s.underrunsTotal - before.underrunsTotal),
            silentCycles: max(0, s.silentCyclesTotal - before.silentCyclesTotal),
            rebanks: max(0, s.rebanksTotal - before.rebanksTotal),
            droppedChunks: max(0, s.droppedChunksTotal - before.droppedChunksTotal),
            droppedFrames: max(0, s.droppedFramesTotal - before.droppedFramesTotal),
            shedFrames: max(0, s.shedFramesTotal - before.shedFramesTotal),
            depthFrames: s.depthFrames,
            minDepthFrames: minDepthFrames == Int.max ? s.depthFrames : minDepthFrames,
            maxQueuedChunks: maxQueuedChunks,
            chunkDurationMs: s.chunkDurationMs,
            queueCapacityChunks: s.queueCapacityChunks,
            capacityFrames: s.capacityFrames,
            effectiveFrames: s.effectiveFrames,
            targetFrames: s.targetFrames
        )

        windowStartMs = nowMs
        prev = s
        minDepthFrames = Int.max
        maxQueuedChunks = 0
        return report
    }

    public func reset() {
        started = false
        windowStartMs = 0
        prev = nil
        minDepthFrames = Int.max
        maxQueuedChunks = 0
    }
}
