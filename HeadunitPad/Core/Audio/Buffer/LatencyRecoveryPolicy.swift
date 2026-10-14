//
//  LatencyRecoveryPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit LatencyRecoveryPolicy.kt
//

import Foundation

/// Repay lower targets and sustained backlog with small overlaps.
public final class LatencyRecoveryPolicy {
    public let sampleRate: Int

    private var previousTarget: Int = 0
    private var previousPacket: Int = 0
    private var budget: Int = 0
    private var debt: Int = 0
    private var excess: Int = 0
    private var windowStart: Int64 = -1
    private var windowInput: Int64 = 0
    private var windowCycles: Int = 0
    private var lastObservation: Int64 = -1
    private var minimumDepth: Int = Int.max
    private var maximumDepth: Int = 0
    private var allowance: Int = 0
    private var nextCorrection: Int64 = 0
    private var renderSlack: Int = 0
    private var previousRenderSlack: Int = 0

    public init(sampleRate: Int) {
        self.sampleRate = sampleRate
    }

    public func observe(
        nowMs: Int64,
        target: Int,
        packetFrames: Int,
        slack: Int,
        depth: Int,
        inputFrames: Int64,
        canRecover: Bool = true
    ) {
        let newBudget = max(0, min(sampleRate, target + slack))
        if target > previousTarget {
            debt = 0
        } else {
            debt = min(sampleRate, debt + previousTarget - target)
        }
        if target != previousTarget || packetFrames != previousPacket || newBudget != budget ||
            lastObservation < 0 || (nowMs - lastObservation) < 0 || (nowMs - lastObservation) > 499 {
            resetWindow()
        }
        if lastObservation >= 0 && (0...499).contains(nowMs - lastObservation) {
            let elapsedFrames = Int((nowMs - lastObservation) * Int64(sampleRate) / 1000)
            renderSlack = max(renderSlack, elapsedFrames - sampleRate / 100)
        }
        previousTarget = target
        previousPacket = packetFrames
        budget = newBudget
        lastObservation = nowMs
        if !canRecover {
            debt = 0
            resetWindow()
            return
        }
        if windowStart < 0 {
            windowStart = nowMs
            windowInput = inputFrames
        }
        minimumDepth = min(minimumDepth, depth)
        maximumDepth = max(maximumDepth, depth)
        windowCycles += 1

        if nowMs - windowStart >= 500 {
            if inputFrames > windowInput && windowCycles >= 50 {
                allowance = max(0, minimumDepth - reserve())
                excess = max(0, min(maximumDepth, minimumDepth + packetFrames) - budget)
            } else {
                allowance = 0
                excess = 0
            }
            previousRenderSlack = renderSlack
            renderSlack = 0
            minimumDepth = depth
            maximumDepth = depth
            windowStart = nowMs
            windowInput = inputFrames
            windowCycles = 1
        }
    }

    /// A proposal only; settle it after the ring actually consumes these extra frames.
    public func correction(nowMs: Int64, depth: Int) -> Int {
        if nowMs < nextCorrection { return 0 }
        let liveDebt = min(debt, max(0, depth - previousTarget - max(renderSlack, previousRenderSlack)))
        return min(sampleRate / 1000, max(liveDebt, excess), allowance, max(0, depth - reserve()))
    }

    public func consumed(nowMs: Int64, frames: Int, pacingFrames: Int? = nil) {
        guard frames > 0 else { return }
        let pacing = pacingFrames ?? frames
        debt = max(0, debt - frames)
        excess = max(0, excess - frames)
        allowance = max(0, allowance - frames)
        if minimumDepth != Int.max {
            minimumDepth = max(0, minimumDepth - frames)
        }
        maximumDepth = max(0, maximumDepth - frames)
        let delay = (Int64(max(frames, pacing)) * 100_000 + Int64(sampleRate) - 1) / Int64(sampleRate)
        nextCorrection = nowMs + max(1, delay)
    }

    private func reserve() -> Int {
        return max(sampleRate / 100, previousTarget - previousPacket) + sampleRate / 200
    }

    public func reset() {
        previousTarget = 0
        previousPacket = 0
        budget = 0
        debt = 0
        nextCorrection = 0
        lastObservation = -1
        resetWindow()
    }

    private func resetWindow() {
        renderSlack = 0
        previousRenderSlack = 0
        allowance = 0
        excess = 0
        windowStart = -1
        windowCycles = 0
        minimumDepth = Int.max
        maximumDepth = 0
    }
}
