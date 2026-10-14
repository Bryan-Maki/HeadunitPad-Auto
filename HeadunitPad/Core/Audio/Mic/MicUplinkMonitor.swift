//
//  MicUplinkMonitor.swift
//  HeadunitPad
//
//  1:1 port of open-headunit MicUplinkMonitor.kt
//

import Foundation

/// What the microphone session claimed for sending and cancelled before sending.
public final class MicUplinkMonitor {
    public static let bytesPerSecond: Int64 = 32000

    private var open = false
    private var startedMs: Int64 = 0
    private var frames = 0
    private var bytes: Int64 = 0
    private var peak = 0
    private var largest = 0
    private var smallest = 0
    private var acks = 0
    private var discarded = 0

    public var isOpen: Bool {
        return open
    }

    public struct Report: Equatable, Sendable {
        public let frames: Int
        public let bytes: Int64
        public let elapsedMs: Int64
        public let peak: Int
        public let largest: Int
        public let smallest: Int
        public let acks: Int
        public let discarded: Int

        public var percentOfExpected: Int {
            let expected = MicUplinkMonitor.bytesPerSecond * elapsedMs / 1000
            return (expected <= 0) ? -1 : Int(bytes * 100 / expected)
        }
    }

    public init() {}

    @discardableResult
    public func onFrame(payloadBytes: Int, framePeak: Int, nowMs: Int64) -> Bool {
        let first = (frames == 0)
        if !open {
            open = true
            startedMs = nowMs
        }
        if first { smallest = payloadBytes }
        frames += 1
        bytes += Int64(payloadBytes)
        if framePeak > peak { peak = framePeak }
        if payloadBytes > largest { largest = payloadBytes }
        if payloadBytes < smallest { smallest = payloadBytes }
        return first
    }

    public func onSessionStart(nowMs: Int64) {
        reset()
        open = true
        startedMs = nowMs
    }

    public func onAck() {
        if open { acks += 1 }
    }

    public func onDiscarded(bytes: Int) {
        if open { discarded += bytes }
    }

    public func onSessionEnd(nowMs: Int64) -> Report? {
        guard open else { return nil }
        let report = Report(
            frames: frames,
            bytes: bytes,
            elapsedMs: nowMs - startedMs,
            peak: peak,
            largest: largest,
            smallest: smallest,
            acks: acks,
            discarded: discarded
        )
        reset()
        return report
    }

    public func reset() {
        open = false
        startedMs = 0
        frames = 0
        bytes = 0
        peak = 0
        largest = 0
        smallest = 0
        acks = 0
        discarded = 0
    }
}
