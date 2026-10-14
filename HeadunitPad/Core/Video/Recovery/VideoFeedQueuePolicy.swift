//
//  VideoFeedQueuePolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit VideoFeedQueuePolicy.kt
//  Calculates video frame queue capacity based on negotiated/requested FPS
//  to prevent queue shedding during transient decoder hiccups.
//

import Foundation

public enum VideoFeedQueuePolicy {

    public static let inputDequeuePatienceMs: Int64 = 300
    public static let frameQueueMs: Int = 500
    public static let minCapacity: Int = 15
    public static let maxCapacity: Int = 40

    public static func capacityFor(fpsLimit: Int) -> Int {
        let rate = safeRate(fpsLimit)
        let derived = rate * frameQueueMs / 1000
        return min(max(derived, minCapacity), maxCapacity)
    }

    public static func heldMsAt(fpsLimit: Int) -> Int64 {
        let rate = safeRate(fpsLimit)
        return Int64(capacityFor(fpsLimit: fpsLimit)) * 1000 / Int64(rate)
    }

    private static func safeRate(_ fpsLimit: Int) -> Int {
        return fpsLimit > 0 ? fpsLimit : minCapacity
    }
}
