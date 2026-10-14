//
//  AdaptiveJitterPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AdaptiveJitterPolicy.kt
//

import Foundation

/// Independent ingress and decoded-PCM clocks share a bounded reserve.
public final class AdaptiveJitterPolicy {
    public let sampleRate: Int

    private let floorMs: Int64
    private let initialCeilingMs: Int64
    private var ceilingMs: Int64
    private let maximumMs: Int64
    private var marginMs: Int64 = 15

    private let arrivals: SupplyClock
    private let pcm: SupplyClock

    public private(set) var largestPcmGapMs: Int64 = 0
    public private(set) var largestArrivalGapMs: Int64 = 0
    public private(set) var largestChunkFrames: Int = 0

    private var lastAdjustmentMs: Int64 = -1
    private var lastDisturbanceMs: Int64 = -1

    private var chunkEpochs = [Int64](repeating: -1, count: 10)
    private var chunkMaxima = [Int](repeating: 0, count: 10)

    public var targetFrames: Int {
        let invariant = largestChunkFrames + frames(10)
        return max(invariant, min(frames(ceilingMs), max(frames(floorMs), invariant + frames(marginMs))))
    }

    public init(sampleRate: Int, latencyMultiplier: Int = AudioJitterBufferPolicy.defaultMultiplier) {
        self.sampleRate = sampleRate
        let targetMs = AudioJitterBufferPolicy.targetMs(for: latencyMultiplier)
        self.floorMs = max(60, targetMs)
        self.initialCeilingMs = max(150, self.floorMs)
        self.ceilingMs = self.initialCeilingMs
        self.maximumMs = max(AudioJitterBufferPolicy.maxTargetMs, self.floorMs)

        self.arrivals = SupplyClock(sampleRate: sampleRate, maximumMs: self.maximumMs)
        self.pcm = SupplyClock(sampleRate: sampleRate, maximumMs: self.maximumMs)
    }

    private final class SupplyClock {
        let sampleRate: Int
        let maximumMs: Int64

        var lastMs: Int64 = -1
        var gapMs: Int64 = 0
        var excessMs: Int64 = 0
        var position: Int64 = 0
        var envelopeFrameMillis: Int64 = 0
        var conservedFrameMillis: Int64 = 0
        var coveredGapFrames: Int64 = 0
        var epoch: Int64 = -1
        var currentMinimum: Int64 = Int64.max
        var previousMinimum: Int64 = Int64.max
        var learningMinimum: Int64 = Int64.max
        var currentMaximum: Int64 = Int64.min
        var previousMaximum: Int64 = Int64.min
        var completedFrames: Int64 = 0
        var peakFrameMillis: Int64 = 0
        var peakStartedMs: Int64 = -1

        init(sampleRate: Int, maximumMs: Int64) {
            self.sampleRate = sampleRate
            self.maximumMs = maximumMs
        }

        func observe(nowMs: Int64, suppliedFrames: Int) {
            gapMs = (lastMs < 0) ? 0 : max(0, nowMs - lastMs)
            let elapsedFrameMillis = gapMs * Int64(sampleRate)

            let complete = gapMs > 0 && ((elapsedFrameMillis + 5 * Int64(sampleRate) >= envelopeFrameMillis) ||
                (nowMs - peakStartedMs >= 1000))
            completedFrames = complete ? ((peakFrameMillis + 999) / 1000) : 0
            if complete || peakStartedMs < 0 {
                peakFrameMillis = 0
                peakStartedMs = nowMs
            }

            coveredGapFrames = min(elapsedFrameMillis, conservedFrameMillis) / 1000
            excessMs = max(0, elapsedFrameMillis - conservedFrameMillis) / Int64(sampleRate)
            conservedFrameMillis = min(maximumMs * Int64(sampleRate),
                                      max(0, conservedFrameMillis - elapsedFrameMillis) + Int64(suppliedFrames) * 1000)
            position -= elapsedFrameMillis

            if position <= min(currentMinimum, previousMinimum) {
                learningMinimum = position
            }
            let nextEpoch = nowMs / 1000
            if nextEpoch != epoch {
                if nextEpoch != epoch + 1 {
                    learningMinimum = position
                } else if currentMaximum <= previousMaximum && currentMinimum >= previousMinimum {
                    learningMinimum = min(currentMinimum, previousMinimum)
                }
                previousMaximum = (nextEpoch == epoch + 1) ? currentMaximum : Int64.min
                currentMaximum = Int64.min
                previousMinimum = (nextEpoch == epoch + 1) ? currentMinimum : Int64.max
                currentMinimum = Int64.max
                epoch = nextEpoch
            }

            currentMinimum = min(currentMinimum, position)
            learningMinimum = min(learningMinimum, position)
            position += Int64(suppliedFrames) * 1000
            currentMaximum = max(currentMaximum, position)
            envelopeFrameMillis = position - learningMinimum
            peakFrameMillis = max(peakFrameMillis, envelopeFrameMillis)
            lastMs = nowMs
        }

        func reset() {
            lastMs = -1
            gapMs = 0
            excessMs = 0
            position = 0
            envelopeFrameMillis = 0
            conservedFrameMillis = 0
            coveredGapFrames = 0
            completedFrames = 0
            peakFrameMillis = 0
            peakStartedMs = -1
            epoch = -1
            currentMinimum = Int64.max
            previousMinimum = Int64.max
            learningMinimum = Int64.max
            currentMaximum = Int64.min
            previousMaximum = Int64.min
        }
    }

    public func onArrival(nowMs: Int64, chunkFrames: Int) {
        guard chunkFrames > 0 else { return }
        arrivals.observe(nowMs: nowMs, suppliedFrames: chunkFrames)
        largestArrivalGapMs = max(largestArrivalGapMs, arrivals.gapMs)
        observeSupply(nowMs: nowMs, clock: arrivals, ingressFrames: chunkFrames)
    }

    public func onPcmDelivery(nowMs: Int64, chunkFrames: Int) {
        guard chunkFrames > 0 else { return }
        pcm.observe(nowMs: nowMs, suppliedFrames: chunkFrames)
        largestPcmGapMs = max(largestPcmGapMs, pcm.gapMs)
        observeSupply(nowMs: nowMs, clock: pcm, ingressFrames: 0)
    }

    private func observeSupply(nowMs: Int64, clock: SupplyClock, ingressFrames: Int) {
        let maxFramesAllowed = Int64(frames(maximumMs - 10))
        let completed = Int(min(maxFramesAllowed, max(clock.completedFrames, clock.coveredGapFrames)))
        recordSupplySize(nowMs: nowMs, size: max(ingressFrames, completed))

        if clock.gapMs > 0 {
            let excess = min(maximumMs, clock.excessMs)
            if excess > 5 {
                lastDisturbanceMs = nowMs
            }
            let observedNeedMs = Int64(largestChunkFrames) * 1000 / Int64(sampleRate) + 20 + excess
            ceilingMs = max(ceilingMs, min(maximumMs, observedNeedMs))
            if excess + 10 > marginMs {
                marginMs = min(maxMarginMs(), max(marginMs + 20, excess + 10))
                lastAdjustmentMs = nowMs
            }
        }
        recover(nowMs: nowMs)
    }

    private func recordSupplySize(nowMs: Int64, size: Int) {
        let epoch = nowMs / 1000
        let slot = Int(epoch % Int64(chunkEpochs.count))
        if chunkEpochs[slot] != epoch {
            chunkEpochs[slot] = epoch
            chunkMaxima[slot] = 0
        }
        chunkMaxima[slot] = max(chunkMaxima[slot], size)
        largestChunkFrames = size
        for i in 0..<chunkEpochs.count {
            if (epoch - chunkEpochs[i]) >= 0 && (epoch - chunkEpochs[i]) < Int64(chunkEpochs.count) {
                largestChunkFrames = max(largestChunkFrames, chunkMaxima[i])
            }
        }
    }

    public func onUnderrun(nowMs: Int64) {
        if targetFrames >= frames(ceilingMs) {
            ceilingMs = min(maximumMs, ceilingMs + 20)
        }
        marginMs = min(maxMarginMs(), marginMs + 20)
        lastAdjustmentMs = nowMs
        lastDisturbanceMs = nowMs
    }

    private func recover(nowMs: Int64) {
        if lastAdjustmentMs < 0 { lastAdjustmentMs = nowMs }
        if lastDisturbanceMs < 0 { lastDisturbanceMs = nowMs }
        if nowMs - lastDisturbanceMs >= 10_000 && nowMs - lastAdjustmentMs >= 1000 {
            marginMs = max(15, marginMs - 5)
            ceilingMs = max(initialCeilingMs, ceilingMs - 5)
            lastAdjustmentMs = nowMs
        }
    }

    public func resetArrival() {
        arrivals.reset()
        pcm.reset()
        largestArrivalGapMs = 0
        largestPcmGapMs = 0
        chunkEpochs = [Int64](repeating: -1, count: 10)
        chunkMaxima = [Int](repeating: 0, count: 10)
        largestChunkFrames = 0
    }

    private func maxMarginMs() -> Int64 {
        return max(15, ceilingMs - Int64(largestChunkFrames) * 1000 / Int64(sampleRate) - 10)
    }

    private func frames(_ ms: Int64) -> Int {
        return Int(Int64(sampleRate) * ms / 1000)
    }
}
