//
//  KeyframeRepairTracker.swift
//  HeadunitPad
//
//  1:1 port of open-headunit KeyframeRepairTracker.kt
//  Separates a keyframe that was handed to the codec from one that produced a picture.
//  Protects against holed keyframes causing infinite stall/rebuild loops.
//

import Foundation

public final class KeyframeRepairTracker {

    public static let rendersBeforeTimestampsDisbelieved = 30
    private static let none: Int64 = -1

    private let lock = NSLock()
    private var pendingPtsUs: Int64 = none
    private var decoded = false
    private var rendersWhilePending = 0
    private var disbelievedTimestamps = false

    public init() {}

    public var keyframeDecoded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return decoded
    }

    public var awaitingOutput: Bool {
        lock.lock()
        defer { lock.unlock() }
        return pendingPtsUs != Self.none
    }

    public var timestampsUnusable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return disbelievedTimestamps
    }

    public func onKeyframeFed(ptsUs: Int64) {
        lock.lock()
        defer { lock.unlock() }
        pendingPtsUs = ptsUs
        rendersWhilePending = 0
    }

    /// Returns true exactly once per pending keyframe on the first frame at or past its timestamp.
    public func onFrameRendered(ptsUs: Int64) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if pendingPtsUs == Self.none { return false }
        if ptsUs < pendingPtsUs {
            rendersWhilePending += 1
            if rendersWhilePending < Self.rendersBeforeTimestampsDisbelieved {
                return false
            }
            disbelievedTimestamps = true
        }

        pendingPtsUs = Self.none
        rendersWhilePending = 0
        decoded = true
        return true
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        pendingPtsUs = Self.none
        rendersWhilePending = 0
        decoded = false
    }
}
