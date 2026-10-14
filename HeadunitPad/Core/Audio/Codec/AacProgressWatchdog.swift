//
//  AacProgressWatchdog.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AacProgressWatchdog.kt
//

import Foundation

/// Progress belongs to the codec's continuous work interval, never to a packet or Start/Stop.
public final class AacProgressWatchdog {
    private let lock = NSLock()
    private var inputBlockedSince: Int64 = -1
    private var outputWaitingSince: Int64 = -1

    public init() {}

    public func inputWaiting(nowMs: Int64) {
        lock.lock()
        defer { lock.unlock() }
        if inputBlockedSince < 0 {
            inputBlockedSince = nowMs
        }
    }

    public func inputAccepted(nowMs: Int64) {
        lock.lock()
        defer { lock.unlock() }
        inputBlockedSince = -1
        if outputWaitingSince < 0 {
            outputWaitingSince = nowMs
        }
    }

    public func outputCopied() {
        lock.lock()
        defer { lock.unlock() }
        outputWaitingSince = -1
    }

    public func idleClosedTail() {
        lock.lock()
        defer { lock.unlock() }
        outputWaitingSince = -1
    }

    public func stalled(nowMs: Int64, hasUnsubmitted: Bool, inputClosed: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if inputClosed && !hasUnsubmitted {
            outputWaitingSince = -1
        }
        let inputStalled = hasUnsubmitted && inputBlockedSince >= 0 && (nowMs - inputBlockedSince >= 1000)
        let outputStalled = (!inputClosed || hasUnsubmitted) && outputWaitingSince >= 0 && (nowMs - outputWaitingSince >= 1000)
        return inputStalled || outputStalled
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        inputBlockedSince = -1
        outputWaitingSince = -1
    }
}
