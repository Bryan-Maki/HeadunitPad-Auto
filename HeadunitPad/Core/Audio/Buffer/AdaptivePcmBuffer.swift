//
//  AdaptivePcmBuffer.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AdaptivePcmBuffer.kt
//

import Foundation

/// A bounded network bank, independent of the device output buffer. One producer and one reader;
/// short synchronized copies make reset safe during sink stop. All samples are interleaved.
public final class AdaptivePcmBuffer {
    public let sampleRate: Int
    public let channels: Int
    public let isMediaSink: Bool

    private let lock = NSLock()
    private let mediaPrerollDeadlineMs: Int64 = 1500
    private let cycleFrames: Int
    private let cycleSamples: Int
    private let capacityFrames: Int
    private var ring: [Int16]
    private var lastGood: [Int16]
    private var previousOutput: [Int16]
    private var endingSample: [Int16]
    private var endingFrames: Int = 0

    private let policy: AdaptiveJitterPolicy
    private let recovery: LatencyRecoveryPolicy
    private let overlap = PcmOverlap()
    private var recoveryDeferrals = 0
    private let prerollDeadlineMs: Int64

    private var startupFramesPlayed: Int64 = 0
    private var head = 0
    private var count = 0
    private var inputFrames: Int64 = 0
    private var offeredFrames: Int64 = 0
    private var resetDiscardedFrames: Int64 = 0
    private var started = false
    private var rebanking = false
    private var firstDataMs: Int64 = -1
    private var gapFrames = 0
    private var needsFade = true
    private var ended = false
    private var lastReadMs: Int64 = -1

    public struct Overflow: Equatable, Sendable {
        public let atMs: Int64
        public let incomingFrames: Int
        public let depthBeforeFrames: Int
        public let capacityFrames: Int
        public let oldFramesDropped: Int
        public let incomingFramesDropped: Int
        public let offeredBeforeFrames: Int64
        public let consumedFrames: Int64
        public let compressedFrames: Int64
        public let overflowBeforeFrames: Int64
        public let resetDiscardedFrames: Int64
        public let targetFrames: Int
        public let lastReadMs: Int64
        public let started: Bool
        public let rebanking: Bool
        public let ended: Bool
    }

    public private(set) var pendingOverflow: Overflow?
    public private(set) var silentCycles: Int64 = 0
    public private(set) var rebanks: Int64 = 0
    public private(set) var concealedFrames: Int64 = 0
    public private(set) var droppedFrames: Int64 = 0
    public private(set) var compressedFrames: Int64 = 0

    public init(
        sampleRate: Int = 48000,
        channels: Int = 2,
        latencyMultiplier: Int = AudioJitterBufferPolicy.defaultMultiplier,
        isMediaSink: Bool = false
    ) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.isMediaSink = isMediaSink

        self.cycleFrames = sampleRate / 100 // 10ms
        self.cycleSamples = cycleFrames * channels
        self.capacityFrames = sampleRate * 3 / 2 // 1.5s
        self.ring = [Int16](repeating: 0, count: capacityFrames * channels)
        self.lastGood = [Int16](repeating: 0, count: cycleSamples)
        self.previousOutput = [Int16](repeating: 0, count: cycleSamples)
        self.endingSample = [Int16](repeating: 0, count: channels)

        self.policy = AdaptiveJitterPolicy(sampleRate: sampleRate, latencyMultiplier: latencyMultiplier)
        self.recovery = LatencyRecoveryPolicy(sampleRate: sampleRate)
        let targetMs = AudioJitterBufferPolicy.targetMs(for: latencyMultiplier)
        self.prerollDeadlineMs = max(100, targetMs + 50)
    }

    public convenience init(sampleRate: Int = 48000, channels: Int = 2, targetLatencyMs: Int) {
        let mult = max(1, targetLatencyMs * AudioJitterBufferPolicy.anchorMultiplier / Int(AudioJitterBufferPolicy.targetMs))
        self.init(sampleRate: sampleRate, channels: channels, latencyMultiplier: mult, isMediaSink: false)
    }

    public var availableFrames: Int {
        return depthFrames()
    }

    public func write(samples: [Int16]) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        write(data: samples, length: samples.count, nowMs: now)
    }

    public func read(frames: Int) -> [Int16] {
        lock.lock()
        defer { lock.unlock() }

        let requestedSamples = frames * channels
        var output = [Int16](repeating: 0, count: requestedSamples)
        let available = min(frames, count / channels)
        let samplesToCopy = available * channels

        for i in 0..<samplesToCopy {
            let idx = (head + i) % ring.count
            output[i] = ring[idx]
        }
        if samplesToCopy > 0 {
            head = (head + samplesToCopy) % ring.count
            count -= samplesToCopy
            for c in 0..<channels {
                endingSample[c] = output[samplesToCopy - channels + c]
            }
        }

        // If buffer was empty or underrun, perform PLC decay on remaining frames
        if available < frames {
            let startFrame = available
            var prev = endingSample
            for f in startFrame..<frames {
                for c in 0..<channels {
                    let decayed = Int16(Float(prev[c]) * 0.8)
                    output[f * channels + c] = decayed
                    prev[c] = decayed
                }
            }
            endingSample = prev
        }

        return output
    }

    public func noteArrival(nowMs: Int64, frames: Int) {
        lock.lock()
        defer { lock.unlock() }
        if ended { policy.resetArrival() }
        ended = false
        policy.onArrival(nowMs: nowMs, chunkFrames: frames)
    }

    public func finish() {
        lock.lock()
        defer { lock.unlock() }
        ended = true
    }

    public func targetFrames() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return playbackTargetFrames()
    }

    public func maxArrivalGapMs() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        return policy.largestArrivalGapMs
    }

    public func maxPcmGapMs() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        return policy.largestPcmGapMs
    }

    public func depthFrames() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return count / channels
    }

    public func takeOverflow() -> Overflow? {
        lock.lock()
        defer { lock.unlock() }
        let overflow = pendingOverflow
        pendingOverflow = nil
        return overflow
    }

    public func isIdle() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return count == 0 && endingFrames == 0 && (ended || (firstDataMs < 0 && !rebanking)) && !started
    }

    public func write(data: [Int16], length: Int, nowMs: Int64) {
        lock.lock()
        defer { lock.unlock() }

        let aligned = min(length, data.count) / channels * channels
        if aligned == 0 { return }

        if !ended { policy.onPcmDelivery(nowMs: nowMs, chunkFrames: aligned / channels) }
        if firstDataMs < 0 { firstDataMs = nowMs }

        let keep = min(aligned, ring.count)
        let skip = aligned - keep
        let oldDrop = max(0, count + keep - ring.count)

        if (oldDrop > 0 || skip > 0) && pendingOverflow == nil {
            pendingOverflow = Overflow(
                atMs: nowMs,
                incomingFrames: aligned / channels,
                depthBeforeFrames: count / channels,
                capacityFrames: capacityFrames,
                oldFramesDropped: oldDrop / channels,
                incomingFramesDropped: skip / channels,
                offeredBeforeFrames: offeredFrames,
                consumedFrames: startupFramesPlayed,
                compressedFrames: compressedFrames,
                overflowBeforeFrames: droppedFrames,
                resetDiscardedFrames: resetDiscardedFrames,
                targetFrames: playbackTargetFrames(),
                lastReadMs: lastReadMs,
                started: started,
                rebanking: rebanking,
                ended: ended
            )
        }

        if oldDrop > 0 { discard(samples: oldDrop) }
        if skip > 0 {
            droppedFrames += Int64(skip / channels)
            needsFade = true
            recovery.reset()
        }

        let tail = (head + count) % ring.count
        let first = min(keep, ring.count - tail)

        for i in 0..<first {
            ring[tail + i] = data[skip + i]
        }
        for i in 0..<(keep - first) {
            ring[i] = data[skip + first + i]
        }

        count += keep
        offeredFrames += Int64(aligned / channels)
        inputFrames += Int64(keep / channels)
    }

    /// Renders one 10ms block. Returns true when there is real or concealed audio.
    public func render(out: inout [Int16], nowMs: Int64, outputBurstFrames: Int? = nil) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard out.count >= cycleSamples else { return false }
        for i in 0..<cycleSamples { out[i] = 0 }

        let target = playbackTargetFrames()
        if !started {
            let waitMs: Int64
            if outputBurstFrames != nil {
                waitMs = 0
            } else if isMediaSink && startupFramesPlayed == 0 {
                waitMs = max(prerollDeadlineMs, mediaPrerollDeadlineMs)
            } else if isMediaSink || rebanking {
                waitMs = max(prerollDeadlineMs, Int64(target) * 1000 / Int64(sampleRate) + 50)
            } else {
                waitMs = prerollDeadlineMs
            }

            if count == 0 || (!ended && (count / channels < target) && (nowMs - firstDataMs < waitMs)) {
                if endingFrames == 0 { return false }
                _ = renderEnding(out: &out, offsetFrames: 0)
                for i in 0..<cycleSamples { previousOutput[i] = out[i] }
                return true
            }

            endingFrames = 0
            started = true
            rebanking = false
            needsFade = true
        }

        let burst = outputBurstFrames ?? cycleFrames
        let outputSlack = max(0, burst - cycleFrames)
        let slack = max(sampleRate * 30 / 1000, policy.largestChunkFrames - cycleFrames + outputSlack)
        let canRecover = !ended && gapFrames == 0 && !needsFade
        recovery.observe(
            nowMs: nowMs,
            target: target,
            packetFrames: policy.largestChunkFrames,
            slack: slack,
            depth: count / channels,
            inputFrames: inputFrames,
            canRecover: canRecover
        )

        let proposal = canRecover ? recovery.correction(nowMs: nowMs, depth: count / channels) : 0
        var catchUp = overlap.shift(
            ring: ring,
            head: head,
            channels: channels,
            overlapFrames: cycleFrames / 2,
            maximum: min(proposal, max(0, count / channels - cycleFrames))
        )

        if catchUp > 0 && overlap.protectAttack && recoveryDeferrals < 3 {
            recoveryDeferrals += 1
            catchUp = 0
        } else if catchUp > 0 || proposal == 0 {
            recoveryDeferrals = 0
        }

        let skipped = catchUp * channels
        let real = min(count, cycleSamples)
        let readHead = (head + skipped) % ring.count
        let first = min(real, ring.count - readHead)

        for i in 0..<first {
            out[i] = ring[readHead + i]
        }
        for i in 0..<(real - first) {
            out[first + i] = ring[i]
        }

        if catchUp > 0 {
            let fadeFrames = cycleFrames / 2
            for frame in 0..<fadeFrames {
                let mix = Float(frame + 1) / Float(fadeFrames)
                for ch in 0..<channels {
                    let index = frame * channels + ch
                    let origIndex = (head + index) % ring.count
                    let original = Float(ring[origIndex])
                    let blended = original * (1.0 - mix) + Float(out[index]) * mix
                    out[index] = Int16(clamping: Int(blended))
                }
            }
            compressedFrames += Int64(catchUp)
        }

        head = (head + real + skipped) % ring.count
        count -= (real + skipped)
        recovery.consumed(nowMs: nowMs, frames: catchUp, pacingFrames: overlap.matched ? catchUp : (sampleRate / 1000))
        startupFramesPlayed += Int64(real / channels)
        if real > 0 { lastReadMs = nowMs }

        let recovering = gapFrames > 0
        if real == cycleSamples {
            for i in 0..<cycleSamples { lastGood[i] = out[i] }
            gapFrames = 0
        } else if ended {
            gapFrames = 0
            for i in 0..<cycleSamples { lastGood[i] = 0 }
            recovery.reset()
        } else {
            recovery.reset()
            if gapFrames == 0 {
                policy.onUnderrun(nowMs: nowMs)
                rebanks += 1
            }
            silentCycles += 1

            for frame in (real / channels)..<cycleFrames {
                let missingFrame = gapFrames + frame - real / channels
                let block = missingFrame / cycleFrames
                var gain: Float = {
                    switch block {
                    case 0: return 0.7
                    case 1: return 0.4
                    case 2: return 0.15
                    default: return 0.0
                    }
                }()

                if block == 2 {
                    let tail = missingFrame % cycleFrames - cycleFrames / 2 + 1
                    if tail > 0 {
                        gain *= (1.0 - Float(tail) / Float(cycleFrames / 2))
                    }
                }

                for ch in 0..<channels {
                    let sampleIndex = frame * channels + ch
                    let goodIndex = (missingFrame % cycleFrames) * channels + ch
                    out[sampleIndex] = Int16(clamping: Int(Float(lastGood[goodIndex]) * gain))
                }
                if block < 3 {
                    concealedFrames += 1
                }
            }

            gapFrames += (cycleFrames - real / channels)
            if gapFrames >= cycleFrames * 3 {
                started = false
                rebanking = true
                firstDataMs = (count > 0) ? nowMs : -1
                gapFrames = 0
                needsFade = true
                for i in 0..<cycleSamples { lastGood[i] = 0 }
            }
        }

        if needsFade || recovering || (real < cycleSamples && !ended) {
            let fadeFrames = cycleFrames / 2
            let liveFrames = ended ? min(fadeFrames, real / channels) : fadeFrames
            for frame in 0..<liveFrames {
                let mix = Float(frame + 1) / Float(fadeFrames)
                for ch in 0..<channels {
                    let index = frame * channels + ch
                    let old = Float(previousOutput[cycleSamples - channels + ch])
                    let blended = old * (1.0 - mix) + Float(out[index]) * mix
                    out[index] = Int16(clamping: Int(blended))
                }
            }
            needsFade = false
        }

        var endingRendered = false
        if ended && count == 0 {
            for ch in 0..<channels {
                endingSample[ch] = (real > 0) ? out[real - channels + ch] : previousOutput[cycleSamples - channels + ch]
            }
            endingFrames = endingSample.contains(where: { $0 != 0 }) ? (cycleFrames / 2) : 0
            started = false
            firstDataMs = -1
            endingRendered = renderEnding(out: &out, offsetFrames: real / channels) > 0
            for i in 0..<cycleSamples { lastGood[i] = 0 }
        }

        for i in 0..<cycleSamples { previousOutput[i] = out[i] }
        return real > 0 || endingRendered || (!ended && real < cycleSamples)
    }

    private func renderEnding(out: inout [Int16], offsetFrames: Int) -> Int {
        let frames = min(endingFrames, cycleFrames - offsetFrames)
        let halfCycle = cycleFrames / 2
        for frame in 0..<frames {
            endingFrames -= 1
            for ch in 0..<channels {
                let s = Int(endingSample[ch]) * endingFrames / max(1, halfCycle)
                out[(offsetFrames + frame) * channels + ch] = Int16(clamping: s)
            }
        }
        return frames
    }

    private func playbackTargetFrames() -> Int {
        let releaseSteps = max(0, startupFramesPlayed / Int64(sampleRate) - 10)
        let startupMs: Int64 = isMediaSink ? max(0, 120 - releaseSteps * 5) : 0
        return max(policy.targetFrames, Int(startupMs * Int64(sampleRate) / 1000))
    }

    private func discard(samples: Int) {
        let drop = min(samples, count) / channels * channels
        head = (head + drop) % ring.count
        count -= drop
        droppedFrames += Int64(drop / channels)
        needsFade = true
        recovery.reset()
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }

        resetDiscardedFrames += Int64(count / channels)
        head = 0
        count = 0
        started = false
        firstDataMs = -1
        gapFrames = 0
        rebanking = false
        lastReadMs = -1
        needsFade = true
        ended = false
        endingFrames = 0
        recoveryDeferrals = 0
        for i in 0..<cycleSamples {
            lastGood[i] = 0
            previousOutput[i] = 0
        }
        policy.resetArrival()
        recovery.reset()
    }
}
