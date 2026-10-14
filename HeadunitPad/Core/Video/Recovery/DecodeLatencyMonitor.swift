//
//  DecodeLatencyMonitor.swift
//  HeadunitPad
//
//  1:1 port of open-headunit DecodeLatencyMonitor.kt
//  Measures end-to-end hardware decoding latency (median & 95th percentile).
//

import Foundation

public final class DecodeLatencyMonitor {

    public static let capacity = 640
    public static let maxPlausibleUs: Int64 = 1_000_000

    public struct Report: Equatable, CustomStringConvertible {
        public let medianUs: Int64
        public let p95Us: Int64
        public let frames: Int
        public let unusable: Int

        public init(medianUs: Int64, p95Us: Int64, frames: Int, unusable: Int) {
            self.medianUs = medianUs
            self.p95Us = p95Us
            self.frames = frames
            self.unusable = unusable
        }

        public var description: String {
            if frames == 0 { return "decodeLatency=unreadable (\(unusable) frames)" }
            let suffix = unusable == 0 ? "" : ", \(unusable) unreadable"
            return "decodeLatency=\(medianUs / 1000)ms p95=\(p95Us / 1000)ms (\(frames) frames\(suffix))"
        }
    }

    private var samples = [Int64](repeating: 0, count: capacity)
    private var count = 0
    private var next = 0
    private var implausible = 0

    public init() {}

    public func onFrameDecoded(latencyUs: Int64) {
        if latencyUs < 0 || latencyUs > Self.maxPlausibleUs {
            implausible += 1
            return
        }
        samples[next] = latencyUs
        next = (next + 1) % Self.capacity
        if count < Self.capacity {
            count += 1
        }
    }

    public func report() -> Report? {
        if count == 0 && implausible == 0 { return nil }
        var valid = Array(samples[0..<count])
        valid.sort()

        let rep = Report(
            medianUs: Self.percentile(sorted: valid, percentile: 50),
            p95Us: Self.percentile(sorted: valid, percentile: 95),
            frames: count,
            unusable: implausible
        )
        count = 0
        next = 0
        implausible = 0
        return rep
    }

    public func reset() {
        count = 0
        next = 0
        implausible = 0
    }

    private static func percentile(sorted: [Int64], percentile: Int) -> Int64 {
        if sorted.isEmpty { return 0 }
        let rank = (sorted.count * percentile + 99) / 100
        let index = max(0, min(rank - 1, sorted.count - 1))
        return sorted[index]
    }
}
