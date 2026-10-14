//
//  OutputBufferPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit OutputBufferPolicy.kt
//

import Foundation

/// Output scheduling jitter only; network jitter is handled before samples reach this buffer.
public final class OutputBufferPolicy {
    public let sampleRate: Int
    private let burstFrames: Int
    private let floorFrames: Int
    public let maximumFrames: Int

    public private(set) var stableFloorFrames: Int
    public private(set) var targetFrames: Int

    private var previousXruns: Int = 0
    private var lastChangeMs: Int64 = -1
    private var reducedFromFrames: Int = 0
    private var reducedAtMs: Int64 = -1

    public init(sampleRate: Int, burstFrames: Int, minimumFrames: Int? = nil) {
        guard sampleRate > 0, burstFrames > 0 else {
            fatalError("sampleRate and burstFrames must be > 0")
        }
        self.sampleRate = sampleRate
        self.burstFrames = burstFrames
        let minFrames = minimumFrames ?? (sampleRate * 20 / 1000)
        self.floorFrames = Int((Int64(minFrames) + Int64(burstFrames) - 1) / Int64(burstFrames) * Int64(burstFrames))
        self.maximumFrames = max(floorFrames + 2 * burstFrames, sampleRate * 60 / 1000 / burstFrames * burstFrames)
        self.stableFloorFrames = floorFrames
        self.targetFrames = floorFrames
    }

    @discardableResult
    public func update(nowMs: Int64, xruns: Int) -> Int {
        if lastChangeMs < 0 {
            lastChangeMs = nowMs
            previousXruns = xruns
        }
        if xruns > previousXruns {
            if reducedFromFrames > 0 && (0...30_000).contains(nowMs - reducedAtMs) {
                stableFloorFrames = max(stableFloorFrames, reducedFromFrames)
            }
            reducedFromFrames = 0
            targetFrames = min(maximumFrames, max(targetFrames + burstFrames, stableFloorFrames))
            lastChangeMs = nowMs
        } else if xruns < previousXruns {
            lastChangeMs = nowMs
            reducedFromFrames = 0
        } else if nowMs - lastChangeMs >= 10_000 {
            let smaller = max(stableFloorFrames, targetFrames - burstFrames)
            if smaller < targetFrames {
                reducedFromFrames = targetFrames
                reducedAtMs = nowMs
                targetFrames = smaller
            }
            lastChangeMs = nowMs
        }
        previousXruns = xruns
        return targetFrames
    }
}
