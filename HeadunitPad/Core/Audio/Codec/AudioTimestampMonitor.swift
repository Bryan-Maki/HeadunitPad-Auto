//
//  AudioTimestampMonitor.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AudioTimestampMonitor.kt
//

import Foundation

/// Compare PCM source and delivery intervals without assuming synchronized device clocks.
/// These are diagnostic observations, not one-way latency or proof of packet loss.
public final class AudioTimestampMonitor {
    public static let maxIntervalUs: Int64 = 1_000_000 // 1 second

    private let lock = NSLock()
    private let windowUs: Int64
    private var windowStartUs: Int64 = -1
    private var previousSourceUs: Int64 = -1
    private var previousArrivalUs: Int64 = -1
    private var previousDurationUs: Int64 = 0
    private var packets = 0
    private var durationChanges = 0
    private var discontinuities = 0
    private var missingTimestamps = 0
    private var maxArrivalGapUs: Int64 = 0
    private var maxArrivalExcessUs: Int64 = 0

    public struct Report: Equatable, Sendable {
        public let windowUs: Int64
        public let packets: Int
        public let discontinuities: Int
        public let maxArrivalGapUs: Int64
        public let maxArrivalExcessUs: Int64
    }

    public init(windowUs: Int64 = 10_000_000) {
        self.windowUs = windowUs
    }

    public func onPacket(sourceUs: Int64, arrivalUs: Int64, durationUs: Int64) -> Report? {
        guard arrivalUs >= 0, durationUs > 0 else { return nil }

        lock.lock()
        defer { lock.unlock() }

        if previousArrivalUs > arrivalUs {
            resetInternal()
        }
        if windowStartUs < 0 {
            windowStartUs = arrivalUs
        }
        packets += 1
        if sourceUs <= 0 {
            missingTimestamps += 1
        }
        if previousArrivalUs >= 0 {
            let arrivalGap = arrivalUs - previousArrivalUs
            if arrivalGap > AudioTimestampMonitor.maxIntervalUs {
                discontinuities += 1
            } else {
                maxArrivalGapUs = max(maxArrivalGapUs, arrivalGap)
                if durationUs != previousDurationUs {
                    durationChanges += 1
                }
                let arrivalExcess = arrivalGap - max(previousDurationUs, durationUs)
                if arrivalExcess > maxArrivalExcessUs {
                    maxArrivalExcessUs = arrivalExcess
                }
            }
        }
        previousSourceUs = sourceUs
        previousArrivalUs = arrivalUs
        previousDurationUs = durationUs

        if arrivalUs - windowStartUs >= windowUs {
            let report = Report(
                windowUs: arrivalUs - windowStartUs,
                packets: packets,
                discontinuities: discontinuities,
                maxArrivalGapUs: maxArrivalGapUs,
                maxArrivalExcessUs: maxArrivalExcessUs
            )
            resetInternal()
            windowStartUs = arrivalUs
            return report
        }
        return nil
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        resetInternal()
    }

    private func resetInternal() {
        windowStartUs = -1
        previousSourceUs = -1
        previousArrivalUs = -1
        previousDurationUs = 0
        packets = 0
        durationChanges = 0
        discontinuities = 0
        missingTimestamps = 0
        maxArrivalGapUs = 0
        maxArrivalExcessUs = 0
    }
}
