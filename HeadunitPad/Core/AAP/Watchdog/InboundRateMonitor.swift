//
//  InboundRateMonitor.swift
//  HeadunitPad
//
//  1:1 port of open-headunit InboundRateMonitor.kt
//  Measures incoming throughput separated by video, audio, and other channels.
//

import Foundation

public final class InboundRateMonitor {
    public static let windowMs: Int64 = 30_000

    public struct Report: Equatable {
        public let windowMs: Int64
        public let videoBytes: Int64
        public let audioBytes: Int64
        public let otherBytes: Int64
        public let videoMessages: Int
        public let audioMessages: Int
        public let otherMessages: Int

        public var videoKbps: Double {
            return windowMs > 0 ? (Double(videoBytes) * 8.0) / Double(windowMs) : 0
        }

        public var audioKbps: Double {
            return windowMs > 0 ? (Double(audioBytes) * 8.0) / Double(windowMs) : 0
        }
    }

    private var started: Bool = false
    private var windowStartMs: Int64 = 0
    private var videoBytes: Int64 = 0
    private var audioBytes: Int64 = 0
    private var otherBytes: Int64 = 0
    private var videoMessages: Int = 0
    private var audioMessages: Int = 0
    private var otherMessages: Int = 0

    public init() {}

    public func onMessage(channel: Int, bytes: Int, nowMs: Int64) -> Report? {
        if !started {
            started = true
            windowStartMs = nowMs
        }

        let size = Int64(max(bytes, 0))
        if UInt8(channel) == Channel.ID_VID {
            videoBytes += size
            videoMessages += 1
        } else if UInt8(channel) == Channel.ID_MED || UInt8(channel) == Channel.ID_GUD || UInt8(channel) == Channel.ID_SYS {
            audioBytes += size
            audioMessages += 1
        } else {
            otherBytes += size
            otherMessages += 1
        }

        let elapsedMs = nowMs - windowStartMs
        if elapsedMs < Self.windowMs {
            return nil
        }

        let report = Report(
            windowMs: elapsedMs,
            videoBytes: videoBytes,
            audioBytes: audioBytes,
            otherBytes: otherBytes,
            videoMessages: videoMessages,
            audioMessages: audioMessages,
            otherMessages: otherMessages
        )

        windowStartMs = nowMs
        videoBytes = 0
        audioBytes = 0
        otherBytes = 0
        videoMessages = 0
        audioMessages = 0
        otherMessages = 0

        return report
    }

    public func reset() {
        started = false
        windowStartMs = 0
        videoBytes = 0
        audioBytes = 0
        otherBytes = 0
        videoMessages = 0
        audioMessages = 0
        otherMessages = 0
    }

    public func currentRxMbps(nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> Double {
        guard started, windowStartMs > 0 else { return 0.0 }
        let elapsedMs = max(nowMs - windowStartMs, 1)
        let totalBytes = videoBytes + audioBytes + otherBytes
        return (Double(totalBytes) * 8.0) / (Double(elapsedMs) * 1000.0)
    }
}
